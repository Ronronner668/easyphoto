import { MoveIdentity, MoveJournalPort, VerifiedMove, VerifiedMovePort } from '../models/VerifiedMove';
import { identicalMoveContent } from './ExecuteVerifiedMove';
import { ExperimentError } from '../models/Experiment';
import { isAlbumOnlyMove } from './AlbumOnlyPolicy';

export interface BatchMoveJournal extends MoveJournalPort {
  saveBatch(records: VerifiedMove[]): Promise<void>;
}
export interface FinishMovePort {
  source(uri: string): VerifiedMovePort;
  target(kind: string): VerifiedMovePort;
  trashGallery(uris: string[]): Promise<void>;
}
async function verifyTargets(record: VerifiedMove, port: FinishMovePort): Promise<void> {
  if (!record.copy || !isAlbumOnlyMove(record)) { throw new ExperimentError('仅支持相册分类收尾，历史文件记录保持原状。'); }
  const adapter = port.target('album'); const copy = await adapter.identify(record.copy.uri);
  if (copy.uri !== record.copy.uri || !record.source.hash || copy.hash !== record.source.hash || copy.bytes !== record.source.bytes ||
    copy.taken !== record.source.taken || !(await adapter.members(record.target)).some(item => item.uri === copy.uri)) {
    throw new ExperimentError('目标副本已变化，本次未提交回收。');
  }
}
export async function finishStagedMoves(records: VerifiedMove[], port: FinishMovePort, journal: BatchMoveJournal, keepOriginal: boolean = false,
  confirmed: (identity: MoveIdentity) => void = () => {}): Promise<string> {
  if (records.some(record => !isAlbumOnlyMove(record))) { throw new ExperimentError('历史文件任务保持原状，未提交收尾。'); }
  if (!records.length) { return '没有待收尾的原图。'; }
  if (records.length > 300 || new Set(records.map(item => item.source.uri)).size !== records.length) { throw new ExperimentError('收尾列表不可用。'); }
  const ready: VerifiedMove[] = [];
  let alreadyGone = 0;
  for (const record of records) {
    if (record.phase !== 'awaiting_trash' && record.phase !== 'batch_trashing') { throw new ExperimentError('收尾状态已变化，未重复提交。'); }
    const durable = await journal.active(record.source.uri);
    if (!durable || durable.id !== record.id || durable.phase !== record.phase) { throw new ExperimentError('收尾记录已变化，未操作。'); }
    await verifyTargets(record, port);
    const source = port.source(record.source.uri);
    if (!await source.exists(record.source.uri)) {
      if (record.phase === 'awaiting_trash') { alreadyGone++; }
      record.phase = 'complete'; await journal.save(record); continue;
    }
    if (record.phase === 'batch_trashing' && !record.batchCancelled) { throw new ExperimentError('上次收尾结果尚未确定，不重复发起回收；可以继续浏览。'); }
    const original = await source.identify(record.source.uri);
    if (original.uri !== record.source.uri || !identicalMoveContent(original, record.source)) { throw new ExperimentError('原图已变化，本次未提交回收。'); }
    if (keepOriginal || record.keepOriginal || record.source.retainOriginal) {
      record.keepOriginal = keepOriginal || record.keepOriginal;
      record.phase = 'retained'; await journal.save(record); continue;
    }
    ready.push(record);
  }
  if (!ready.length) { return records.some(item => item.phase === 'retained') ? '已保留原位置照片，分类目标可用。' : alreadyGone ? '来源已不在原位置，目标副本完整，分类记录已收尾。' : '本轮原图已完成统一回收。'; }
  ready.forEach(item => { item.phase = 'batch_trashing'; item.batchCancelled = false; });
  await journal.saveBatch(ready);
  let cancelled = false;
  const attempted = new Set<string>();
  try {
    const gallery = ready.map(item => item.source.uri);
    if (gallery.length) { gallery.forEach(uri => { attempted.add(uri); }); await port.trashGallery(gallery); }
  } catch (error) { cancelled = (error as ErrorWithCode).code === 201; }
  ready.forEach(item => { item.batchCancelled = cancelled || !attempted.has(item.source.uri); });
  if (ready.some(item => item.batchCancelled)) { await journal.saveBatch(ready); }
  let completed = 0;
  for (const record of ready) {
    // No native write is repeated, even after a partial/ambiguous platform result.
    await verifyTargets(record, port);
    const source = port.source(record.source.uri);
    if (!await source.exists(record.source.uri)) { record.phase = 'complete'; completed++; }
    else if (record.batchCancelled) {
      const original = await source.identify(record.source.uri);
      if (original.uri === record.source.uri && identicalMoveContent(original, record.source)) { record.phase = 'awaiting_trash'; }
    }
    await journal.save(record);
    if (record.phase === 'complete' && attempted.has(record.source.uri)) { confirmed(record.source); }
  }
  if (cancelled && completed === 0) { return '已取消统一回收，原图保留，可稍后结束整理。'; }
  const retained = records.filter(item => item.phase === 'retained').length;
  const suffix = (retained ? `另保留 ${retained} 张原图。` : '') + (alreadyGone ? `另有 ${alreadyGone} 张来源已不在原位置。` : '');
  return (completed === ready.length ? `已统一回收 ${completed} 张原图。` : `已回收 ${completed} 张，其余未确认完成；不会重复提交。`) + suffix;
}
interface ErrorWithCode { code: number; }
