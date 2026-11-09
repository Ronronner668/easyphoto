import { common } from '@kit.AbilityKit';
import { fileIo, picker } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

export class SlideshowMusicFile {
  file: string;
  name: string;
  constructor(file: string, name: string) { this.file = file; this.name = name; }
}

export class SlideshowMusicFiles {
  private context: common.UIAbilityContext;
  constructor(context: common.UIAbilityContext) { this.context = context; }
  path(file: string): string {
    if (!/^memory_[A-Za-z0-9]{6}\/track\.audio$/.test(file)) { throw new Error('音乐文件记录不可读取'); }
    return `${this.context.filesDir}/${file}`;
  }
  async choose(): Promise<SlideshowMusicFile | undefined> {
    const options = new picker.AudioSelectOptions(); options.maxSelectNumber = 1;
    const selected = await new picker.AudioViewPicker(this.context).select(options);
    if (!selected.length) { return undefined; }
    const source = await fileIo.open(selected[0], fileIo.OpenMode.READ_ONLY);
    let file = '';
    let directory = '';
    let created = false;
    try {
      const size = (await fileIo.stat(source.fd)).size;
      if (size <= 0 || size > 50 * 1024 * 1024) { throw new Error('请选择大小在 50MB 以内的有效音频'); }
      directory = await fileIo.mkdtemp(`${this.context.filesDir}/memory_XXXXXX`);
      file = `${directory.substring(this.context.filesDir.length + 1)}/track.audio`;
      const target = await fileIo.open(this.path(file), fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY);
      created = true;
      try {
        await fileIo.copyFile(source.fd, target.fd);
        await fileIo.fsync(target.fd);
        if ((await fileIo.stat(target.fd)).size !== size) { throw new Error('音乐导入不完整'); }
      } finally { await fileIo.close(target.fd); }
      // The picker URI is opaque and is never persisted or logged.
      return new SlideshowMusicFile(file, '本地音乐');
    } catch (error) {
      if (created) { await this.remove(file); }
      else if (directory) {
        try { await fileIo.rmdir(directory); }
        catch (_) { hilog.warn(0, 'Slideshow', 'Could not remove empty music import directory'); }
      }
      throw error as Error;
    } finally { await fileIo.close(source.fd); }
  }
  async remove(file: string): Promise<void> {
    if (!file) { return; }
    try {
      const path = this.path(file);
      await fileIo.unlink(path);
      await fileIo.rmdir(path.substring(0, path.lastIndexOf('/')));
    }
    catch (_) { hilog.warn(0, 'Slideshow', 'Could not remove imported music cache'); }
  }
}
