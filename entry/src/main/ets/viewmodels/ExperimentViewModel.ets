import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { AlbumAction, AlbumExperiment, AlbumPhase, ExperimentError, LabAlbum } from '../domain/models/Experiment';
import { ExperimentService } from '../services/operations/ExperimentService';

export enum LabCommand {
  LoadAlbums, CreateSample, AddA, AddB, RemoveB, AlbumTrash, AlbumCheck,
  RequestWrite, WriteSettings
}

@Observed
export class ExperimentViewModel {
  busy: boolean = true;
  ready: boolean = false;
  albums: LabAlbum[] = [];
  album: AlbumExperiment = new AlbumExperiment();
  status: string = '';
  writeSettingsAvailable: boolean = false;
  private service: ExperimentService | undefined = undefined;
  private context: common.UIAbilityContext | undefined = undefined;

  async initialize(context: common.UIAbilityContext): Promise<void> {
    this.context = context;
    this.service = new ExperimentService(context);
    try {
      this.album = await this.service.repository.loadAlbum();
      this.ready = true;
      this.status = '已有实验会话已恢复，不自动请求权限或重放任何操作。';
    } catch (_) { this.status = '实验记录读取失败，已禁用实验操作；未覆盖原记录。'; }
    finally { this.busy = false; }
  }

  selectAlbum(index: number, second: boolean): void {
    if (this.busy || !this.ready || this.album.phase !== AlbumPhase.Empty || !this.albums[index]) { return; }
    if (second) { this.album.albumB = this.albums[index]; }
    else { this.album.albumA = this.albums[index]; }
    this.album = JSON.parse(JSON.stringify(this.album)) as AlbumExperiment;
  }

  async finishRound(manuallyChecked: boolean): Promise<void> {
    if (this.busy || !this.ready || !this.service || !manuallyChecked) { return; }
    if (!ExperimentService.tryAcquire()) { this.status = '另一页正在核查或提交，请等待完成后重新打开本页。'; return; }
    this.busy = true;
    try {
      await this.service.repository.archiveAlbum(this.album);
      this.album = new AlbumExperiment();
      this.status = '本轮记录已归档，未删除、恢复或移动任何外部资源。最近 20 轮核查记录保留在应用私有存储。';
    } catch (_) { this.status = '归档未完成，未开启新一轮；请保留现有样本并重查记录。'; }
    finally { this.busy = false; ExperimentService.release(); }
  }

  async run(command: LabCommand, confirmed: boolean): Promise<void> {
    if (this.busy || !this.ready || !this.service || !this.context) { return; }
    const mutates = command === LabCommand.CreateSample || command === LabCommand.AddA || command === LabCommand.AddB ||
      command === LabCommand.RemoveB || command === LabCommand.AlbumTrash;
    if (mutates && !confirmed) { this.status = '请先确认仅使用本页生成的可丢弃样本。'; return; }
    if (!ExperimentService.tryAcquire()) { this.status = '另一页正在核查或提交，请等待完成后重新打开本页。'; return; }
    this.busy = true;
    try {
      switch (command) {
        case LabCommand.LoadAlbums:
          this.albums = await this.service.listAlbums();
          this.status = this.albums.length ? `已读取 ${this.albums.length} 个用户相册（最多展示 100 个），请选择两个专用测试相册。` :
            '未读取到用户相册。请在系统图库创建两个空测试相册后重新加载；本页没有调用未公开的新建相册接口。';
          break;
        case LabCommand.CreateSample: await this.service.createSample(this.album); break;
        case LabCommand.AddA: await this.service.mutateAlbum(this.album, AlbumAction.AddA); break;
        case LabCommand.AddB: await this.service.mutateAlbum(this.album, AlbumAction.AddB); break;
        case LabCommand.RemoveB: await this.service.mutateAlbum(this.album, AlbumAction.RemoveB); break;
        case LabCommand.AlbumTrash: await this.service.mutateAlbum(this.album, AlbumAction.Trash); break;
        case LabCommand.AlbumCheck: await this.service.recheckAlbum(this.album); break;
        case LabCommand.RequestWrite:
        case LabCommand.WriteSettings:
          const result = await this.service.requestWrite(command === LabCommand.WriteSettings);
          this.status = result.detail;
          this.writeSettingsAvailable = result.canOpenPermissionSettings;
          break;
      }
    } catch (error) {
      const message = error instanceof ExperimentError ? error.message :
        `系统调用未完成，错误码：${(error as BusinessError).code || -1}。未自动重试，未据此判断照片已删除或移动。`;
      this.status = message;
      // The service has already persisted every native intent. Never overwrite that journal here:
      // this page may be stale, or a failed final flush may have left a pending transaction on disk.
      if (mutates) {
        this.album.message = message;
      }
    } finally {
      this.album = JSON.parse(JSON.stringify(this.album)) as AlbumExperiment;
      this.busy = false;
      ExperimentService.release();
    }
  }
}
