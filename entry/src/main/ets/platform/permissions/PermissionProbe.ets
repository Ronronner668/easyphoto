import { abilityAccessCtrl, bundleManager, common, Permissions } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { ProbeResult, ProbeStatus } from '../../domain/models/ProbeResult';
import { assessReadPermission } from '../../domain/usecases/AssessReadPermission';
import { probeError } from '../../common/ProbeError';

export class PermissionProbe {
  private readonly readPermission: Permissions = 'ohos.permission.READ_IMAGEVIDEO';

  private hasReadDeclaration(): boolean {
    return this.hasDeclaration(this.readPermission);
  }

  private hasDeclaration(permission: Permissions): boolean {
    const info = bundleManager.getBundleInfoForSelfSync(
      bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_REQUESTED_PERMISSION);
    return info.reqPermissionDetails.some((detail: bundleManager.ReqPermissionDetail) =>
      detail.name === permission);
  }

  canWriteLibrary(): boolean {
    const token = bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION)
      .appInfo.accessTokenId;
    return abilityAccessCtrl.createAtManager().checkAccessTokenSync(token, 'ohos.permission.WRITE_IMAGEVIDEO') ===
      abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED;
  }

  async requestWrite(context: common.UIAbilityContext, settings: boolean = false): Promise<ProbeResult> {
    const permission: Permissions = 'ohos.permission.WRITE_IMAGEVIDEO';
    try {
      if (!this.hasDeclaration(permission)) {
        return new ProbeResult('申请图库写入权限', ProbeStatus.Blocked,
          '当前包未开启图库写入实验。需先运行项目的 configure-write-probes.ps1 -Enable，再更新包含 WRITE_IMAGEVIDEO 的调试 Profile 并重新安装。读取和文件实验可以独立继续。');
      }
      if (this.canWriteLibrary()) {
        return new ProbeResult('申请图库写入权限', ProbeStatus.Observed, '当前已有图库写入授权，不重复弹窗。实验仅操作本页生成的样本。');
      }
      const manager = abilityAccessCtrl.createAtManager();
      if (settings) {
        const results = await manager.requestPermissionOnSetting(context, [permission]);
        return new ProbeResult('图库写入权限设置', this.canWriteLibrary() ? ProbeStatus.Observed : ProbeStatus.Blocked,
          `设置返回值：${results[0]}；当前写入权限：${this.canWriteLibrary() ? '已授权' : '未授权'}。`);
      }
      const response = await manager.requestPermissionsFromUser(context, [permission]);
      const index = response.permissions.indexOf(permission);
      const auth = index < 0 ? undefined : response.authResults[index];
      const dialog = index < 0 ? undefined : response.dialogShownResults?.[index];
      const reason = index < 0 ? undefined : response.errorReasons?.[index];
      const granted = this.canWriteLibrary();
      const result = new ProbeResult('申请图库写入权限', granted ? ProbeStatus.Observed : ProbeStatus.Blocked,
        `当前写入权限：${granted ? '已授权' : '未授权'}；授权结果：${auth === undefined ? '未返回' : auth}；` +
        `弹窗：${dialog === undefined ? '未返回' : (dialog ? '已显示' : '未显示')}；原因码：${reason === undefined ? '未返回' : reason}。` +
        (granted ? '仅对本页生成的样本执行实验。' : '如请求无效请核对包内声明及签名 Profile；被拒绝后可主动进入设置。'));
      result.canOpenPermissionSettings = !granted && auth === -1 && reason !== 2;
      return result;
    } catch (error) { return probeError('申请图库写入权限', error as BusinessError); }
  }

  canReadLibrary(): boolean {
    const token = bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION)
      .appInfo.accessTokenId;
    return abilityAccessCtrl.createAtManager().checkAccessTokenSync(token, 'ohos.permission.READ_IMAGEVIDEO') ===
      abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED;
  }

  inspect(): ProbeResult {
    const token = bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION)
      .appInfo.accessTokenId;
    const manager = abilityAccessCtrl.createAtManager();
    const read = manager.checkAccessTokenSync(token, 'ohos.permission.READ_IMAGEVIDEO');
    const write = manager.checkAccessTokenSync(token, 'ohos.permission.WRITE_IMAGEVIDEO');
    const readText = read === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED ? '已授权' : '未授权';
    const writeText = write === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED ? '已授权' : '未授权';
    const declaration = this.hasReadDeclaration() ? '已声明' : '未声明';
    return new ProbeResult('图库权限检查', ProbeStatus.Observed,
      `批量读取：${readText}；图库修改：${writeText}；读取权限声明：${declaration}。` +
      '此按钮仅检查状态。需要批量访问时，请点击“申请图库读取权限”。选图授权单独生效。');
  }

  async requestRead(context: common.UIAbilityContext): Promise<ProbeResult> {
    try {
      if (!this.hasReadDeclaration()) {
        return new ProbeResult('申请图库读取权限', ProbeStatus.Blocked,
          '当前安装包未声明图库读取权限，请安装包含权限声明的新版本，并更新相应调试签名 Profile。');
      }
      if (this.canReadLibrary()) {
        return new ProbeResult('申请图库读取权限', ProbeStatus.Observed,
          '当前已有批量图库读取权限，无需再次弹窗。可以检查系统相册读取。');
      }
      const response = await abilityAccessCtrl.createAtManager().requestPermissionsFromUser(context,
        [this.readPermission]);
      const index = response.permissions.indexOf(this.readPermission);
      return assessReadPermission(index < 0 ? undefined : response.authResults[index],
        index < 0 ? undefined : response.dialogShownResults?.[index],
        index < 0 ? undefined : response.errorReasons?.[index], this.canReadLibrary());
    } catch (error) {
      const result = probeError('申请图库读取权限', error as BusinessError);
      result.detail += ' 请核对权限声明及普通三方调试 Profile 的受限权限配置。';
      return result;
    }
  }

  async requestReadOnSettings(context: common.UIAbilityContext): Promise<ProbeResult> {
    try {
      if (!this.hasReadDeclaration()) {
        return new ProbeResult('图库读取权限设置', ProbeStatus.Blocked, '当前安装包未声明读取权限，请先更新安装包和签名。');
      }
      if (this.canReadLibrary()) {
        return new ProbeResult('图库读取权限设置', ProbeStatus.Observed, '当前已授权，无需打开设置。');
      }
      const response = await abilityAccessCtrl.createAtManager().requestPermissionOnSetting(context,
        [this.readPermission]);
      const granted = this.canReadLibrary();
      return new ProbeResult('图库读取权限设置', granted ? ProbeStatus.Observed : ProbeStatus.Blocked,
        (granted ? '设置返回后已确认取得批量读取权限。' : '设置返回后仍未取得批量读取权限，可继续使用选图。') +
        ` 设置返回值：${response[0] === undefined ? '未返回' : response[0]}。`);
    } catch (error) {
      const result = probeError('图库读取权限设置', error as BusinessError);
      result.detail += ' 请先完成一次读取权限申请；若仍无法授权，检查调试 Profile 和系统应用权限设置。';
      return result;
    }
  }
}
