// 单机发布版备用代码：Index 已注释账号导入与调用，本文件目前不接入应用入口。
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { AccountProfile, HuaweiAccountService } from '../services/operations/HuaweiAccountService';
import { ExperimentError } from '../domain/models/Experiment';

@Observed
export class HuaweiAccountViewModel {
  profile: AccountProfile | undefined = undefined;
  busy: boolean = false;
  message: string = '';
  private service: HuaweiAccountService | undefined = undefined;
  private generation: number = 0;
  private disposed: boolean = false;
  initialize(context: common.UIAbilityContext): void { this.service = new HuaweiAccountService(context); this.disposed = false; }
  failure(error: BusinessError): void {
    if (this.disposed) { return; }
    this.message = error.code === 1001502012 ? '' :
      error.code === 1001500001 ? '账号配置或签名指纹尚未匹配，请在开发者中心核对。' : `登录未完成（${error.code || -1}），可稍后重试。`;
  }
  async login(): Promise<void> { await this.perform(() => this.service!.login()); }
  async authorize(openID: string): Promise<void> { await this.perform(() => this.service!.authorize(openID)); }
  private async perform(operation: () => Promise<AccountProfile>): Promise<void> {
    if (this.busy || !this.service || this.disposed) { return; }
    this.busy = true; const generation = ++this.generation;
    this.profile = undefined;
    try {
      const profile = await operation();
      if (!this.disposed && generation === this.generation) { this.profile = profile; this.message = ''; }
    } catch (error) {
      if (!this.disposed && generation === this.generation) {
        if (error instanceof ExperimentError) { this.message = error.message; } else { this.failure(error as BusinessError); }
      }
    } finally { if (!this.disposed && generation === this.generation) { this.busy = false; } }
  }
  logout(): void { if (this.busy) { return; } this.generation++; this.profile = undefined; this.message = ''; }
  async revoke(): Promise<void> {
    if (this.busy || !this.service || this.disposed) { return; }
    this.busy = true; const generation = ++this.generation;
    try { await this.service.revoke(); if (!this.disposed && generation === this.generation) { this.profile = undefined; this.message = '已取消授权，请点击登录重新授权头像昵称。'; } }
    catch (_) { if (!this.disposed && generation === this.generation) { this.message = '取消授权未确认，当前资料保留。可在系统账号设置中核对后重试。'; } }
    finally { if (!this.disposed && generation === this.generation) { this.busy = false; } }
  }
  dispose(): void { this.disposed = true; this.generation++; this.profile = undefined; }
}
