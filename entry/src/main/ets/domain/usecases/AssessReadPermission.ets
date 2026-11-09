import { ProbeResult, ProbeStatus } from '../models/ProbeResult';

// Pure interpretation of API output. Never infer authorization from a shown dialog.
export function assessReadPermission(authResult: number | undefined, dialogShown: boolean | undefined,
  errorReason: number | undefined, currentlyGranted: boolean): ProbeResult {
  const dialog = dialogShown === undefined ? '未返回' : (dialogShown ? '已显示' : '未显示');
  const evidence = `授权结果：${authResult === undefined ? '未返回' : authResult}；弹窗：${dialog}；` +
    `原因码：${errorReason === undefined ? '未返回' : errorReason}。`;
  if (currentlyGranted) {
    return new ProbeResult('申请图库读取权限', ProbeStatus.Observed,
      `当前已取得批量图库读取权限，可以继续检查系统相册读取。${evidence}`);
  }
  let detail: string;
  if (authResult === 2 || errorReason === 2) {
    detail = '权限请求无效。请核对安装包的权限声明，以及调试签名 Profile 是否包含图库读取受限权限。';
  } else if (authResult === -1 && dialogShown === true) {
    detail = '本次已显示系统授权弹窗，但未取得批量读取权限。仍可使用选图；如需重新授权，请点击下方设置入口。';
  } else if (authResult === -1) {
    detail = '未取得批量读取权限。系统可能不再显示首次授权弹窗，可主动打开权限设置；仍失败时核对签名 Profile。';
  } else {
    detail = '未确认取得批量读取权限。请检查权限声明、签名 Profile 和系统返回结果，不能按授权成功继续。';
  }
  const result = new ProbeResult('申请图库读取权限', ProbeStatus.Blocked, detail + evidence);
  result.canOpenPermissionSettings = authResult === -1 && errorReason !== 2;
  return result;
}
