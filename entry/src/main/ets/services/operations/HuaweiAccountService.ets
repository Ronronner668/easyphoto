// 单机发布版备用代码：Index 已注释账号导入与调用，本文件目前不接入应用入口。
import { BusinessError } from '@kit.BasicServicesKit';
import { authentication } from '@kit.AccountKit';
import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { ExperimentError } from '../../domain/models/Experiment';

export class AccountProfile {
  openID: string = '';
  nickname: string = '';
  avatar: string = '';
}

// Client-only optional identity. No token, authorization code or profile is persisted or logged.
export class HuaweiAccountService {
  private context: common.UIAbilityContext;
  constructor(context: common.UIAbilityContext) { this.context = context; }
  private nativeError(phase: string, error: BusinessError): ExperimentError {
    const code = error.code || -1;
    if (code === 1001502012) { return new ExperimentError(''); }
    if (code === 1001502003) { return new ExperimentError(`${phase}参数未被系统接受（1001502003）。请核对应用级Client ID、所关联应用和签名Profile；当前仅请求头像昵称。`); }
    if (code === 1001500001) { return new ExperimentError(`${phase}的签名指纹校验失败，请核对开发者中心配置。`); }
    return new ExperimentError(`${phase}未完成（${code}），请稍后重试。`);
  }
  async login(): Promise<AccountProfile> {
    // Explicit ordinary sign-in avoids widget-generated implicit credential requests.
    const request = new authentication.HuaweiIDProvider().createLoginWithHuaweiIDRequest();
    request.forceLogin = true;
    request.state = util.generateRandomUUID().replace(/-/g, '');
    request.nonce = util.generateRandomUUID().replace(/-/g, '');
    let response: authentication.LoginWithHuaweiIDResponse;
    try { response = await new authentication.AuthenticationController(this.context).executeRequest(request) as authentication.LoginWithHuaweiIDResponse; }
    catch (error) { throw this.nativeError('普通登录', error as BusinessError); }
    if (response.state !== request.state || !response.data?.openID) { throw new ExperimentError('普通登录身份校验未通过，请重试。'); }
    return this.authorize(response.data.openID);
  }
  async authorize(openID: string): Promise<AccountProfile> {
    const provider = new authentication.HuaweiIDProvider();
    const request = provider.createAuthorizationWithHuaweiIDRequest();
    request.scopes = ['profile'];
    request.forceAuthorization = true;
    request.permissions = [];
    request.state = util.generateRandomUUID().replace(/-/g, '');
    let response: authentication.AuthorizationWithHuaweiIDResponse;
    try { response = await new authentication.AuthenticationController(this.context).executeRequest(request) as authentication.AuthorizationWithHuaweiIDResponse; }
    catch (error) { throw this.nativeError('头像昵称授权', error as BusinessError); }
    const data = response.data;
    if (response.state !== request.state || !data || !openID || data.openID !== openID) {
      throw new ExperimentError('账号校验未通过，请重新登录。');
    }
    if (!data.authorizedScopes?.includes('profile')) { throw new ExperimentError('未授权头像昵称，可继续使用照片整理。'); }
    const profile = new AccountProfile(); profile.openID = openID; profile.nickname = data.nickName || '华为账号用户';
    // Only the SDK-provided HTTPS avatar URL is rendered; other schemes are not followed.
    profile.avatar = data.avatarUri?.startsWith('https://') ? data.avatarUri : '';
    return profile;
  }
  async revoke(): Promise<void> {
    const request = new authentication.HuaweiIDProvider().createCancelAuthorizationRequest();
    request.state = util.generateRandomUUID().replace(/-/g, '');
    const response = await new authentication.AuthenticationController(this.context).executeRequest(request) as authentication.CancelAuthorizationResponse;
    if (response.state !== request.state) { throw new ExperimentError('取消授权结果未确认，请在系统账号设置中核对。'); }
  }
}
