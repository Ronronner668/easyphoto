import { MoveIdentity, MoveJournalPort, VerifiedMove, VerifiedMovePort } from '../models/VerifiedMove';
import { AlreadyInTargetError, ExperimentError } from '../models/Experiment';
import { isAlbumOnlyMove } from './AlbumOnlyPolicy';

export function identicalMoveContent(a: MoveIdentity, b: MoveIdentity): boolean {
  return !!a.hash && a.hash === b.hash && a.bytes === b.bytes && a.taken === b.taken;
}
function verifiedTarget(record: VerifiedMove, copy: MoveIdentity): boolean {
  return identicalMoveContent(record.source, copy);
}
export async function reconcileVerifiedMove(port: VerifiedMovePort, journal: MoveJournalPort): Promise<string> {
  const record = await journal.active();
  if (!record) { return '没有未完成移动。'; }
  if (!isAlbumOnlyMove(record)) { throw new ExperimentError('历史文件任务仅保留记录，不自动核对或改写阶段。'); }
  if (await port.exists(record.source.uri)) {
    const original = await port.identify(record.source.uri);
    if (!identicalMoveContent(original, record.source)) { throw new ExperimentError('原图已变化，保留日志，请到系统图库核对。'); }
    record.phase = 'cancelled'; await journal.save(record);
    return '已核对并保留原图，结束本次待核对记录。目标中可能存在副本，请到目标位置核对；未重放移动。';
  }
  if (record.phase !== 'trashing' || !record.copy) { throw new ExperimentError('原图不可读取且缺少完成证据，请到系统图库核对。'); }
  const copy = await port.identify(record.copy.uri);
  if (!verifiedTarget(record, copy) || !(await port.members(record.target)).some((item: MoveIdentity) => item.uri === copy.uri)) {
    throw new ExperimentError('目标尚未通过核对，保留日志停止操作。');
  }
  record.phase = 'complete'; await journal.save(record);
  return '已核对：原图已回收，目标副本完整，移动记录已完成。';
}
export async function executeVerifiedMove(record: VerifiedMove, port: VerifiedMovePort, journal: MoveJournalPort,
  bindingCurrent: () => Promise<boolean>, deferTrash: boolean = true): Promise<VerifiedMove> {
  if (!isAlbumOnlyMove(record)) { throw new ExperimentError('仅支持图库照片的相册分类。'); }
  if (await journal.active(record.source.uri)) { throw new ExperimentError('这张照片暂时无法继续整理，已保留原记录，可以浏览其他照片。'); }
  if (!await bindingCurrent()) { throw new ExperimentError('目标绑定已变化，请重新选择。'); }
  const requested = record.source.uri;
  record.source = await port.identify(requested);
  if (record.source.uri !== requested) { throw new ExperimentError('来源引用与请求不一致，未操作。'); }
  const before = await port.members(record.target);
  if (before.some((item: MoveIdentity) => item.uri === record.source.uri)) { throw new AlreadyInTargetError('照片已在目标中，无需移动。'); }
  if (before.some((item: MoveIdentity) => item.name.toLowerCase() === record.source.name.toLowerCase())) {
    throw new ExperimentError('目标存在同名照片，未覆盖。');
  }
  record.before = before.map((item: MoveIdentity) => item.uri);
  record.phase = 'copying'; await journal.save(record);
  await port.copy(record.source.uri, record.target);
  const after = await port.members(record.target);
  const added = after.filter((item: MoveIdentity) => !record.before.includes(item.uri));
  if (after.length !== before.length + 1 || added.length !== 1 ||
    before.some((item: MoveIdentity) => !after.some((next: MoveIdentity) => next.uri === item.uri))) {
    throw new ExperimentError('目标在操作期间发生变化，保留原图并等待核对。');
  }
  const copy = await port.identify(added[0].uri);
  if (copy.uri === record.source.uri || !verifiedTarget(record, copy)) {
    throw new ExperimentError('副本内容或拍摄时间未通过校验，原图保持原状。');
  }
  record.copy = copy; record.phase = 'copied'; await journal.save(record);
  const fresh = await port.identify(record.source.uri);
  if (fresh.uri !== record.source.uri || !identicalMoveContent(fresh, record.source) || !await bindingCurrent()) {
    throw new ExperimentError('原图或目标绑定已变化，不提交来源回收。');
  }
  const verifiedCopy = await port.identify(copy.uri);
  if (!verifiedTarget(record, verifiedCopy) || !(await port.members(record.target)).some((item: MoveIdentity) => item.uri === copy.uri)) {
    throw new ExperimentError('目标副本已变化，原图保持原状。');
  }
  if (record.keepOriginal || deferTrash) { record.phase = record.keepOriginal ? 'retained' : 'awaiting_trash'; await journal.save(record); return record; }
  record.phase = 'trashing'; await journal.save(record);
  await port.trash(record.source.uri);
  if (await port.exists(record.source.uri)) { throw new ExperimentError('原图仍在，移动尚未完成；可能取消了系统确认，请核对记录。'); }
  const finalCopy = await port.identify(copy.uri);
  if (!verifiedTarget(record, finalCopy) || !(await port.members(record.target)).some((item: MoveIdentity) => item.uri === copy.uri)) {
    throw new ExperimentError('来源已回收，目标待核对，请在系统图库检查；不会重放。');
  }
  record.phase = 'complete'; await journal.save(record);
  return record;
}
