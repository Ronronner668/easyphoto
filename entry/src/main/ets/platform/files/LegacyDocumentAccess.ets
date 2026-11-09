import { common } from '@kit.AbilityKit';
import { fileIo, fileUri } from '@kit.CoreFileKit';
import { uri } from '@kit.ArkTS';
import { preferences } from '@kit.ArkData';
import { ExperimentError } from '../../domain/models/Experiment';
import { withinDownloadScope } from '../../domain/usecases/LegacyDocumentScope';

// Compatibility reader only. Never selects, persists grants, creates, copies or recycles files.
export class LegacyDocumentAccess {
  private context: common.UIAbilityContext;
  constructor(context: common.UIAbilityContext) { this.context = context; }
  private store(): Promise<preferences.Preferences> {
    return preferences.getPreferences(this.context, { name: 'managed_download' });
  }
  async validate(reference: string): Promise<string> {
    const store = await this.store(); const saved = await store.get('root', '');
    const customs = JSON.parse(await store.get('customRoots', '[]') as string) as string[];
    const candidate = new uri.URI(reference);
    const custom = customs.find(value => {
      const root = new uri.URI(value); const parts = root.getSegment(); const target = candidate.getSegment();
      return root.scheme === 'file' && candidate.scheme === 'file' && root.authority === candidate.authority && target.length >= parts.length && parts.every((part: string, index: number) => part === target[index]);
    });
    if (custom) {
      throw new ExperimentError('此历史照片依赖旧版目录授权，请在系统文件管理器查看原文件。');
    }
    if (typeof saved !== 'string' || !saved) { throw new ExperimentError('历史文件授权已不可用，请使用系统文件管理器查看。'); }
    const root = new uri.URI(saved); const target = new uri.URI(reference);
    if (root.scheme !== 'file' || target.scheme !== 'file' || target.query || target.fragment ||
      !withinDownloadScope(root.authority, root.getSegment(), target.authority, target.getSegment()) ||
      target.getSegment().some(part => !part || part === '.' || part === '..' || /[\\/\x00-\x1f]/.test(part))) {
      throw new ExperimentError('历史文件不在原授权范围内，无法读取。');
    }
    const path = new fileUri.FileUri(reference).path;
    // Check every ancestor, so a substituted symlink cannot expand the granted scope.
    let current = saved;
    if (!(await fileIo.lstat(new fileUri.FileUri(current).path)).isDirectory()) { throw new ExperimentError('下载目录已不可访问。'); }
    for (const segment of target.getSegment().slice(root.getSegment().length)) {
      current = new uri.URI(current).addSegment(segment).toString();
      const stat = await fileIo.lstat(new fileUri.FileUri(current).path);
      if (stat.isSymbolicLink()) { throw new ExperimentError('不支持符号链接目标。'); }
    }
    return path;
  }
}
