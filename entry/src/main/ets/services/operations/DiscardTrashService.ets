import { common } from '@kit.AbilityKit';
import { relationalStore } from '@kit.ArkData';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { VerifiedAlbumMoveAdapter } from '../../platform/media/VerifiedAlbumMoveAdapter';
import { PermissionProbe } from '../../platform/permissions/PermissionProbe';
import { DiscardQueueRepository } from '../../data/repositories/DiscardQueueRepository';
import { ExperimentError } from '../../domain/models/Experiment';
import { GalleryReferenceInspector } from '../../platform/media/GalleryReferenceInspector';
import { PhotoAvailability } from '../../domain/models/PhotoAvailability';
import { DiscardMark } from '../../domain/models/DiscardMark';
import { MoveIdentity } from '../../domain/models/VerifiedMove';

export class DiscardTrashService {
  confirmedRemoved: MoveIdentity[] = [];
  private static running: boolean = false;
  private context: common.UIAbilityContext;
  constructor(context: common.UIAbilityContext) { this.context = context; }
  async trash(requested: string[], progress: (message: string) => void = () => {}): Promise<string> {
    if (DiscardTrashService.running) { throw new ExperimentError('正在回收，请稍候。'); }
    DiscardTrashService.running = true;
    this.confirmedRemoved = [];
    try {
      if (requested.some(uri => uri.startsWith('file://docs/'))) { throw new ExperimentError('历史文件标记仅保留记录，请使用系统文件管理器处理。'); }
      if (!requested.length) { return '没有需要回收的图库标记。'; }
      const permissions = new PermissionProbe();
      if (!permissions.canWriteLibrary()) { await permissions.requestWrite(this.context); }
      if (!permissions.canReadLibrary() || !permissions.canWriteLibrary()) { throw new ExperimentError('需要图库授权才能回收。'); }
      const db = await relationalStore.getRdbStore(this.context, { name: 'discard_trash.db', securityLevel: relationalStore.SecurityLevel.S1 });
      await db.executeSql('CREATE TABLE IF NOT EXISTS request (id INTEGER PRIMARY KEY, payload TEXT NOT NULL)');
      const gallery = new VerifiedAlbumMoveAdapter(this.context);
      const repository = new DiscardQueueRepository(this.context);
      const pending = await db.querySql('SELECT payload FROM request WHERE id=1');
      let previous: string[] = [];
      try { if (pending.goToFirstRow()) { previous = JSON.parse(pending.getString(0)) as string[]; } } finally { pending.close(); }
      if (previous.some(uri => uri.startsWith('file://docs/'))) { throw new ExperimentError('历史文件回收请求待人工核对，已保留记录，未重放。'); }
      for (const uri of previous) {
        const exists = await gallery.exists(uri);
        if (exists) { throw new ExperimentError('上次回收结果尚未确定，未重复发送。'); }
        await repository.unmark(uri);
      }
      await db.executeSql('DELETE FROM request WHERE id=1');
      const marks = new Map<string, DiscardMark>();
      (await repository.load()).forEach(mark => { marks.set(mark.reference, mark); });
      const refs = Array.from(new Set(requested)).filter(uri => marks.has(uri));
      if (!refs.length) { return '没有需要回收的标记。'; }
      const active: string[] = [];
      const identities: Map<string, MoveIdentity> = new Map();
      const checks = await new GalleryReferenceInspector(this.context).inspect(refs);
      let skipped = 0;
      for (const check of checks) {
        const mark = marks.get(check.reference);
        if (!mark) { skipped++; continue; }
        if (check.state === PhotoAvailability.Missing) { await repository.removeMissing(mark); continue; }
        if (check.state !== PhotoAvailability.Ready) { skipped++; continue; }
        try {
          const identity = await gallery.identify(check.reference);
          identities.set(check.reference, identity); active.push(check.reference);
        } catch (_) { skipped++; }
      }
      const skippedMessage = skipped ? `已跳过 ${skipped} 张暂不可核验的照片，标记保留。` : '';
      if (!active.length) { return skippedMessage || '已自动更新失效标记，没有需要回收的照片。'; }
      let removed = 0;
      const batchCount = Math.ceil(active.length / 100);
      for (let offset = 0; offset < active.length; offset += 100) {
        if (!permissions.canReadLibrary() || !permissions.canWriteLibrary()) {
          throw new ExperimentError('图库授权已变化，剩余标记保留，未继续回收。');
        }
        const batch = active.slice(offset, offset + 100);
        progress(`第 ${offset / 100 + 1}/${batchCount} 批 · 已确认移入回收站 ${removed} 张`);
        await db.executeSql('INSERT OR REPLACE INTO request (id,payload) VALUES (1,?)', [JSON.stringify(batch)]);
        try {
          await photoAccessHelper.MediaAssetChangeRequest.deleteAssets(this.context, batch);
        } catch (error) {
          if ((error as TrashError).code === 201) {
            await db.executeSql('DELETE FROM request WHERE id=1');
            return removed ? `已回收 ${removed} 张，其余标记保留。` : '已取消，待删除标记保留。';
          }
          throw new ExperimentError('回收结果尚未确认，保留标记且不重复发送。');
        }
        let confirmed = 0;
        for (const uri of batch) {
          if (!await gallery.exists(uri)) {
            await repository.unmark(uri);
            this.confirmedRemoved.push(identities.get(uri)!);
            confirmed++;
          }
        }
        removed += confirmed;
        if (confirmed !== batch.length) {
          throw new ExperimentError(`已回收 ${removed} 张，仍有回收结果待核对，其余标记保留。`);
        }
        await db.executeSql('DELETE FROM request WHERE id=1');
      }
      return `已移入系统回收站 ${removed} 张。${skippedMessage}`;
    } finally { DiscardTrashService.running = false; }
  }
}
interface TrashError { code: number; }
