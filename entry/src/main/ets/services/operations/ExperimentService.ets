import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { AlbumAction, AlbumExperiment, AlbumPhase, ExperimentError, LabAlbum } from '../../domain/models/Experiment';
import { ProbeResult } from '../../domain/models/ProbeResult';
import { albumActionError, isAlbumPending, membershipSummary, reconciledAlbumPhase, sameAlbumObservation, sameAssetContent } from '../../domain/usecases/ExperimentRules';
import { ExperimentRepository } from '../../data/repositories/ExperimentRepository';
import { AlbumExperimentAdapter } from '../../platform/media/AlbumExperimentAdapter';
import { contentHash } from '../../platform/files/ContentHash';
import { PermissionProbe } from '../../platform/permissions/PermissionProbe';

export class ExperimentService {
  private static operationActive: boolean = false;
  static tryAcquire(): boolean {
    if (ExperimentService.operationActive) { return false; }
    ExperimentService.operationActive = true;
    return true;
  }
  static release(): void { ExperimentService.operationActive = false; }
  repository: ExperimentRepository;
  private albums: AlbumExperimentAdapter;
  private context: common.UIAbilityContext;
  constructor(context: common.UIAbilityContext) {
    this.context = context;
    this.repository = new ExperimentRepository(context);
    this.albums = new AlbumExperimentAdapter(context);
  }

  listAlbums(): Promise<LabAlbum[]> { return this.albums.listAlbums(); }
  requestWrite(settings: boolean): Promise<ProbeResult> { return new PermissionProbe().requestWrite(this.context, settings); }

  async createSample(session: AlbumExperiment): Promise<void> {
    if (session.phase !== AlbumPhase.Empty || !session.albumA || !session.albumB || session.albumA.uri === session.albumB.uri) {
      throw new ExperimentError('请先选择两个不同的已有测试相册；一个实验只创建一张样本，不自动重试。');
    }
    if (!new PermissionProbe().canWriteLibrary()) {
      throw new ExperimentError('尚未取得图库写入权限。先完成写入验证配置与系统授权，不创建样本。');
    }
    const stored = await this.repository.loadAlbum();
    if (stored.phase !== AlbumPhase.Empty) { throw new ExperimentError('已有另一页创建的实验记录，请返回并重新打开实验室。'); }
    session.id = Date.now().toString();
    session.fixturePath = await this.albums.generateFixture(session.id);
    session.fixtureHash = await contentHash(session.fixturePath);
    session.phase = AlbumPhase.Creating;
    session.message = '已记录创建意图，正在请求创建一张应用生成的测试图片。';
    await this.repository.saveAlbum(session); // Must persist before any library mutation.
    session.assetUri = await this.albums.createAsset(session.fixturePath);
    session.createdByLab = true;
    await this.repository.saveAlbum(session); // Preserve minted identity before verification.
    const snapshot = await this.albums.snapshot(session);
    if (snapshot.sha256 !== session.fixtureHash || snapshot.inA || snapshot.inB || snapshot.albumACount !== 0 || snapshot.albumBCount !== 0) {
      throw new ExperimentError('新建样本的内容或初始相册状态不符合预期，需人工核对。');
    }
    session.baseline = snapshot;
    session.latest = snapshot;
    session.phase = AlbumPhase.Created;
    session.message = '测试图片已创建并与原始 JPEG 完整摘要核对一致。下一步可加入测试相册 A。';
    await this.repository.saveAlbum(session);
  }

  async mutateAlbum(session: AlbumExperiment, action: AlbumAction): Promise<void> {
    const error = albumActionError(session, action);
    if (error) { throw new ExperimentError(error); }
    if (!new PermissionProbe().canWriteLibrary()) { throw new ExperimentError('图库写入授权已失效，未执行操作。'); }
    const stored = await this.repository.loadAlbum();
    if (stored.id !== session.id || stored.phase !== session.phase || stored.assetUri !== session.assetUri) {
      throw new ExperimentError('页面记录已过期，请重新打开实验室；不重复执行另一页已提交的操作。');
    }
    const before = await this.albums.snapshot(session);
    if (!session.latest || !sameAssetContent(session.latest, before) || !sameAlbumObservation(session.latest, before)) {
      throw new ExperimentError('执行前样本或相册状态发生变化，停止操作并要求重新核对。');
    }
    session.phase = action === AlbumAction.AddA ? AlbumPhase.AddingA : action === AlbumAction.AddB ? AlbumPhase.AddingB :
      action === AlbumAction.RemoveB ? AlbumPhase.RemovingB : AlbumPhase.Trashing;
    session.lastAction = action;
    session.lastNativeReturned = false;
    session.lastErrorCode = 0;
    session.lastError = '';
    session.message = '操作意图已记录；中断后只核查，不自动重放。';
    await this.repository.saveAlbum(session);
    const pendingPhase = session.phase;
    try {
    await this.albums.mutate(session, action);
    session.lastNativeReturned = true;
    if (action === AlbumAction.Trash) {
      session.phase = AlbumPhase.TrashRequested;
      session.message = '系统回收站请求已返回。请在系统图库“最近删除”核对样本；恢复需在系统图库完成，不能把普通查询不可见单独当作删除证据。';
      await this.repository.saveAlbum(session);
      return;
    }
    const after = await this.albums.snapshot(session);
    if (!session.baseline || !sameAssetContent(session.baseline, after)) {
      throw new ExperimentError('原始内容、身份或拍摄时间核对不一致，停止后续操作。');
    }
    session.latest = after;
    if ((action === AlbumAction.AddA && (!after.copyA || after.albumACount !== 1)) ||
      (action === AlbumAction.AddB && (!after.copyB || after.albumBCount !== 1)) ||
      (action === AlbumAction.RemoveB && after.inB)) {
      throw new ExperimentError(membershipSummary(after) + '接口已返回，但目标成员关系未满足预期；保留本次结果，请到系统图库核对，不重复提交。');
    }
    session.latest = after;
    if (action === AlbumAction.AddA) { session.verifiedCopyA = after.copyA; }
    if (action === AlbumAction.AddB) { session.verifiedCopyB = after.copyB; }
    session.phase = action === AlbumAction.AddA ? AlbumPhase.InA : action === AlbumAction.AddB ? AlbumPhase.InB : AlbumPhase.RemovedB;
    session.message = membershipSummary(after) + '身份、完整内容摘要及拍摄时间与基线一致。' +
      (after.ownerAlbum === session.baseline.ownerAlbum ? '归属字段未变。' : '归属字段发生变化。') +
      '原样本与相册副本使用独立引用；添加副本不等于移动。移除 B 副本可能送入回收站，需在系统图库核对。';
    await this.repository.saveAlbum(session);
    } catch (failure) {
      const nativeError = failure as BusinessError;
      const label = action === AlbumAction.Trash ? '图库回收站 · MediaAssetChangeRequest.deleteAssets' :
        `图库相册 · ${action}`;
      session.lastErrorCode = nativeError.code || 0;
      session.lastError = `${label}：` + (failure instanceof ExperimentError ? failure.message :
        `系统调用失败，错误码 ${nativeError.code || '未返回'}。请求结果待核对，不自动重试。`);
      // Persist diagnostics only against this operation's durable intent, never another page's journal.
      const current = await this.repository.loadAlbum();
      if (current.id === session.id && current.assetUri === session.assetUri && current.phase === pendingPhase) {
        current.lastAction = action;
        current.lastNativeReturned = session.lastNativeReturned;
        current.lastErrorCode = session.lastErrorCode;
        current.lastError = session.lastError;
        current.message = session.lastError;
        current.latest = session.latest;
        await this.repository.saveAlbum(current);
        session.phase = pendingPhase;
      }
      throw new ExperimentError(session.lastError);
    }
  }

  async recheckAlbum(session: AlbumExperiment): Promise<void> {
    if (!session.assetUri) { throw new ExperimentError('没有已记录的资源引用；若创建时中断，请在图库核对样本名，不盲目重建。'); }
    const stored = await this.repository.loadAlbum();
    if (stored.id !== session.id || stored.phase !== session.phase || stored.assetUri !== session.assetUri) {
      throw new ExperimentError('该页面与保存记录不一致，请重新打开实验室后核查；不会用旧页面覆盖新记录。');
    }
    const snapshot = await this.albums.snapshot(session);
    if (!session.baseline || !sameAssetContent(session.baseline, snapshot)) {
      throw new ExperimentError('引用、内容或拍摄时间与基线不一致，不能继续写入。');
    }
    session.latest = snapshot;
    if (session.baseline.membershipVersion !== 3) {
      session.message = membershipSummary(snapshot) + '旧轮次仅进行观察，不授予副本写入资格；请核对后归档开启新轮。';
      await this.repository.saveAlbum(session);
      return;
    }
    // Reconcile only observed postconditions, never replay a pending native call.
    const pendingPhase = session.phase;
    session.phase = reconciledAlbumPhase(pendingPhase, snapshot);
    if (pendingPhase === AlbumPhase.AddingA && session.phase === AlbumPhase.InA) { session.verifiedCopyA = snapshot.copyA; }
    if (pendingPhase === AlbumPhase.AddingB && session.phase === AlbumPhase.InB) { session.verifiedCopyB = snapshot.copyB; }
    session.message = membershipSummary(snapshot) + '本次可读、内容和拍摄时间与基线一致；未重放任何写操作。' +
      (isAlbumPending(session.phase) ? '上次操作仍待人工核对。' : '');
    await this.repository.saveAlbum(session);
  }

}
