import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { ProbePhoto, ProbeResult } from '../domain/models/ProbeResult';
import { ProbeUseCase } from '../domain/usecases/ProbeUseCase';
import { ProbeAction } from '../domain/models/ProbeGateway';
import { LocalProbeService } from '../services/operations/LocalProbeService';
import { ProbeRepository } from '../data/repositories/ProbeRepository';
import { probeError } from '../common/ProbeError';

@Observed
export class ProbeViewModel {
  busy: boolean = true;
  results: ProbeResult[] = [];
  photo: ProbePhoto | undefined = undefined;
  notice: string = '';
  permissionSettingsAvailable: boolean = false;
  private repository: ProbeRepository = new ProbeRepository();

  async load(context: common.UIAbilityContext): Promise<void> {
    try { this.results = await this.repository.load(context); }
    catch (_) { this.notice = '历史验证记录读取失败，可继续重新验证。'; }
    finally { this.busy = false; }
  }

  async execute(context: common.UIAbilityContext, action?: ProbeAction): Promise<void> {
    if (this.busy) { return; }
    this.busy = true;
    this.notice = '';
    try {
      const useCase = new ProbeUseCase(new LocalProbeService(context));
      let result: ProbeResult;
      if (action === undefined) {
        this.photo = undefined;
        const selected = await useCase.selectPhoto();
        this.photo = selected.photo;
        result = selected.result;
      } else { result = await useCase.run(action); }
      if (action === ProbeAction.RequestRead || action === ProbeAction.ReadSettings) {
        this.permissionSettingsAvailable = result.canOpenPermissionSettings;
      }
      this.results = [result, ...this.results].slice(0, 30);
      try { await this.repository.save(context, this.results); }
      catch (_) { this.notice = '本次结果已显示，但记录保存失败。'; }
    } catch (error) {
      this.results = [probeError('能力验证', error as BusinessError), ...this.results].slice(0, 30);
    } finally { this.busy = false; }
  }
}
