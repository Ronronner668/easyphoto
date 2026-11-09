import { ExperimentError } from '../../domain/models/Experiment';
import { validateTargetOrder, targetCapacity } from '../../domain/usecases/TargetAlbumOrder';
import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { PhotoInfoSettings } from '../../domain/models/PhotoInfoSettings';

interface TargetAlbumConfiguration { version: number; references: string[]; }

export class WorkbenchPreferences {
  private static writing: boolean = false;
  private context: common.UIAbilityContext;
  constructor(context: common.UIAbilityContext) { this.context = context; }
  async loadTargetAlbums(): Promise<string[] | undefined> {
    const store = await preferences.getPreferences(this.context, { name: 'workbench_settings' });
    const raw = await store.get('reviewTargetAlbumsV1', '');
    if (raw === '') { return undefined; }
    if (typeof raw !== 'string') { throw new ExperimentError('目标相册配置不可读取，原配置已保留。'); }
    try {
      const saved = JSON.parse(raw) as TargetAlbumConfiguration;
      if (saved.version !== 1) { throw new Error('Unsupported target configuration'); }
      validateTargetOrder(saved.references, 4); return [...saved.references];
    } catch (_) { throw new ExperimentError('目标相册配置不可读取，原配置已保留，请核对后重试。'); }
  }
  async saveTargetAlbums(references: string[], capacity: number): Promise<void> {
    if (WorkbenchPreferences.writing) { throw new ExperimentError('设置正在保存，请稍后重试。'); }
    WorkbenchPreferences.writing = true;
    try {
      // Read first; corrupt/future configurations must not be overwritten by default values.
      await this.loadTargetAlbums();
      validateTargetOrder(references, capacity);
      if (references.length > targetCapacity(await this.loadLayout())) { throw new ExperimentError('当前保存的是三列布局，请先保存2×2布局，再选择第四个相册；原配置保留。'); }
      const store = await preferences.getPreferences(this.context, { name: 'workbench_settings' });
      const saved: TargetAlbumConfiguration = { version: 1, references: [...references] };
      await store.put('reviewTargetAlbumsV1', JSON.stringify(saved)); await store.flush();
    } finally { WorkbenchPreferences.writing = false; }
  }
  // Legacy mode/source keys remain on disk but no longer select filesystem features.
  async loadLayout(): Promise<number> {
    return await (await preferences.getPreferences(this.context, { name: 'workbench_settings' })).get('layout', 0) === 1 ? 1 : 0;
  }
  async loadInfo(): Promise<PhotoInfoSettings> {
    const store = await preferences.getPreferences(this.context, { name: 'workbench_settings' });
    const value = await store.get('photoInfo', ''); const result = new PhotoInfoSettings();
    if (typeof value === 'string' && value) {
      try {
        const saved = JSON.parse(value) as PhotoInfoSettings;
        if (['YYYY/MM/DD', 'YYYY-MM-DD', 'YYYY年MM月DD日'].includes(saved.dateFormat)) { result.dateFormat = saved.dateFormat; }
        if (typeof saved.name === 'boolean') { result.name = saved.name; }
        if (typeof saved.date === 'boolean') { result.date = saved.date; }
        if (typeof saved.place === 'boolean') { result.place = saved.place; }
        if (typeof saved.dimensions === 'boolean') { result.dimensions = saved.dimensions; }
        if (typeof saved.bytes === 'boolean') { result.bytes = saved.bytes; }
      } catch (_) { }
    }
    return result;
  }
  async loadKeepOriginal(): Promise<boolean> {
    return await (await preferences.getPreferences(this.context, { name: 'workbench_settings' })).get('keepFolderOriginal', false) === true;
  }
  async loadColorMode(): Promise<ConfigurationConstant.ColorMode> {
    const store = await preferences.getPreferences(this.context, { name: 'workbench_settings' });
    const value = await store.get('colorMode', ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    if (value === ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT ||
      value === ConfigurationConstant.ColorMode.COLOR_MODE_DARK) { return value; }
    return ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET;
  }
  async save(layout: number = 0, info?: PhotoInfoSettings, keepOriginal?: boolean,
    colorMode?: ConfigurationConstant.ColorMode): Promise<void> {
    if (WorkbenchPreferences.writing) { throw new ExperimentError('设置正在保存，请稍后重试。'); }
    WorkbenchPreferences.writing = true;
    try {
    const targets = await this.loadTargetAlbums();
    if (targets && targets.length > targetCapacity(layout)) { throw new ExperimentError('已选择4个目标相册，请先调整为最多3个，再保存三列布局；原配置保留。'); }
    const store = await preferences.getPreferences(this.context, { name: 'workbench_settings' });
    // Obsolete sourceMode and targetMode remain untouched for historical compatibility.
    await store.put('layout', layout === 1 ? 1 : 0);
    if (info) { await store.put('photoInfo', JSON.stringify(info)); }
    if (keepOriginal !== undefined) { await store.put('keepFolderOriginal', keepOriginal); }
    if (colorMode !== undefined) { await store.put('colorMode', colorMode); }
    await store.flush();
    } finally { WorkbenchPreferences.writing = false; }
  }
}
