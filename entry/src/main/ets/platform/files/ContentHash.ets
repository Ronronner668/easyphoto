import { fileIo } from '@kit.CoreFileKit';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { ExperimentError } from '../../domain/models/Experiment';

export async function contentHash(reference: string, limit: number = Number.MAX_SAFE_INTEGER): Promise<string> {
  const digest = cryptoFramework.createMd('SHA256');
  const file = await fileIo.open(reference, fileIo.OpenMode.READ_ONLY);
  try {
    const size = (await fileIo.stat(file.fd)).size;
    if (size <= 0 || size > limit) { throw new ExperimentError('文件为空或超出本次读取范围，未执行写入。'); }
    let total: number = 0;
    while (true) {
      const buffer = new ArrayBuffer(256 * 1024);
      const count = await fileIo.read(file.fd, buffer);
      if (count === 0) { break; }
      total += count;
      if (total > limit || total > size) { throw new ExperimentError('文件在读取期间变化，停止校验。'); }
      await digest.update({ data: new Uint8Array(buffer.slice(0, count)) });
    }
    if (total !== size) { throw new ExperimentError('样本在读取期间发生变化，停止校验。'); }
    const result = await digest.digest();
    if (result.data.length !== 32) { throw new ExperimentError('摘要长度无效，不能把本次读取当作完整内容校验。'); }
    let hex: string = '';
    result.data.forEach((value: number) => { hex += value.toString(16).padStart(2, '0'); });
    return hex;
  } finally { await fileIo.close(file.fd); }
}
