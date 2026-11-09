import { BusinessError } from '@kit.BasicServicesKit';
import { ProbeResult, ProbeStatus } from '../domain/models/ProbeResult';

export function probeError(title: string, error: BusinessError): ProbeResult {
  // Platform error messages may include private paths/URIs; expose codes only.
  const code: number = error.code || -1;
  let explanation: string = '调用未完成，请检查设备条件后重试。';
  if (code === 201 || code === 13900012 || code === 13900001) {
    explanation = '访问未获授权或授权已失效，请重新选择并检查权限。';
  } else if (code === 801) {
    explanation = '这台设备未提供所需能力。';
  } else if (code === 13900002 || code === 14000002) {
    explanation = '资源已不可访问，请重新选择测试文件。';
  }
  return new ProbeResult(title, ProbeStatus.Failed, `${explanation} 错误码：${code}`, Date.now(), code);
}
