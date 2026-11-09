import { common } from '@kit.AbilityKit';
import { MoveIdentity, VerifiedMove, VerifiedMovePort } from '../../domain/models/VerifiedMove';
import { TargetKind } from '../../domain/models/Category';
import { ExperimentError } from '../../domain/models/Experiment';
import { executeVerifiedMove } from '../../domain/usecases/ExecuteVerifiedMove';
import { MoveJournal } from '../../data/repositories/MoveJournal';
import { VerifiedAlbumMoveAdapter } from '../../platform/media/VerifiedAlbumMoveAdapter';
import { PermissionProbe } from '../../platform/permissions/PermissionProbe';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { FinishMovePort, finishStagedMoves } from '../../domain/usecases/FinishStagedMoves';
import { AlbumClassificationTargets } from './AlbumClassificationTargets';
import { isAlbumOnlyMove, isLegacyDocument } from '../../domain/usecases/AlbumOnlyPolicy';

class FinishAdapters implements FinishMovePort {
  private context: common.UIAbilityContext;
  constructor(context: common.UIAbilityContext) { this.context = context; }
  source(uri: string): VerifiedMovePort {
    if (isLegacyDocument(uri)) { throw new ExperimentError('历史文件操作仅保留记录。'); }
    return this.target('album');
  }
  target(kind: string): VerifiedMovePort {
    if (kind !== 'album') { throw new ExperimentError('历史文件操作仅保留记录。'); }
    return new VerifiedAlbumMoveAdapter(this.context);
  }
  trashGallery(uris: string[]): Promise<void> { return photoAccessHelper.MediaAssetChangeRequest.deleteAssets(this.context, uris); }
}

export class VerifiedMoveService {
  confirmedRecycled: MoveIdentity[] = [];
  private static running: boolean = false;
  private context: common.UIAbilityContext;
  private currentRecords: Set<string> = new Set();
  constructor(context: common.UIAbilityContext) { this.context = context; }
  completedCount(): Promise<number> { return new MoveJournal(this.context).completedCount(); }
  async staged(): Promise<VerifiedMove[]> { return (await new MoveJournal(this.context).staged()).filter(record => this.currentRecords.has(record.id) && isAlbumOnlyMove(record)); }
  classified(): Promise<VerifiedMove[]> { return new MoveJournal(this.context).classified(); }
  async finish(keepOriginal: boolean = false, protectedSources: string[] = []): Promise<string> {
    if (VerifiedMoveService.running) { throw new ExperimentError('正在保存，请稍后结束整理。'); }
    VerifiedMoveService.running = true;
    this.confirmedRecycled = [];
    try {
      const journal = new MoveJournal(this.context);
      const records = (await this.staged()).filter(record => !protectedSources.includes(record.source.uri)).slice(0, 300);
      if (records.some(item => !item.source.uri.startsWith('file://docs/'))) {
        const permissions = new PermissionProbe();
        if (!keepOriginal && !permissions.canWriteLibrary()) { await permissions.requestWrite(this.context); }
        if ((!keepOriginal && !permissions.canWriteLibrary()) || !permissions.canReadLibrary()) { throw new ExperimentError(keepOriginal ? '需要图库读取授权才能核对并保留原图。' : '需要图库读写授权才能统一回收原图。'); }
      }
      return await finishStagedMoves(records, new FinishAdapters(this.context), journal, keepOriginal,
        (identity: MoveIdentity) => { this.confirmedRecycled.push(identity); });
    } finally { VerifiedMoveService.running = false; }
  }
  async move(source: string, categoryId: string, kind: TargetKind = TargetKind.Album, keepOriginal: boolean = false): Promise<VerifiedMove> {
    if (VerifiedMoveService.running) { throw new ExperimentError('已有分类正在处理。'); }
    VerifiedMoveService.running = true;
    try {
      if (kind !== TargetKind.Album || isLegacyDocument(source)) { throw new ExperimentError('仅支持图库照片的相册分类，历史文件记录未处理。'); }
      const permissions = new PermissionProbe();
      if (!permissions.canWriteLibrary()) { await permissions.requestWrite(this.context); }
      if (!permissions.canWriteLibrary() || !permissions.canReadLibrary()) { throw new ExperimentError('需要图库读写授权，未提交分类。'); }
      const categories = new AlbumClassificationTargets(this.context);
      const snapshot = await categories.load();
      const category = snapshot.categories.find(item => item.id === categoryId);
      const target = category?.album;
      if (!target) { throw new ExperimentError('目标相册已不可用，请刷新相册后重试。'); }
      const record = new VerifiedMove(); record.id = `${Date.now()}`; record.categoryId = categoryId;
      record.revision = snapshot.revision; record.target = target.reference; record.targetKind = TargetKind.Album; record.source.uri = source;
      record.targetName = target.name;
      record.keepOriginal = keepOriginal;
      record.phase = 'planning';
      const adapter = new VerifiedAlbumMoveAdapter(this.context); const journal = new MoveJournal(this.context);
      const bindingCurrent = async (): Promise<boolean> => {
        const current = await categories.load();
        const item = current.categories.find(item => item.id === categoryId);
        return current.revision === record.revision && item?.album?.reference === record.target;
      };
      try {
        const result = await executeVerifiedMove(record, adapter, journal, bindingCurrent, true);
        this.currentRecords.add(result.id);
        return result;
      } catch (error) {
        // Once a copy may have started, keep the durable record active for reconciliation.
        if (record.phase !== 'planning') {
          const reason = error instanceof ExperimentError ? error.message + ' ' : '';
          throw new ExperimentError(reason + '分类结果待核对，原图保留，暂不重复复制。');
        }
        throw error as Error;
      }
    } finally { VerifiedMoveService.running = false; }
  }
}
