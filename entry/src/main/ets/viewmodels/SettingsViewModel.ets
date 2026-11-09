import { ExperimentError } from '../domain/models/Experiment';
import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { PhotoInfoSettings } from '../domain/models/PhotoInfoSettings';
import { WorkbenchPreferences } from '../data/repositories/WorkbenchPreferences';

interface SettingsSnapshot {
  layout: number;
  keepOriginal: boolean;
  colorMode: ConfigurationConstant.ColorMode;
  info: PhotoInfoSettings;
}

@Observed
export class SettingsViewModel {
  ready: boolean = false;
  saving: boolean = false;
  error: string = '';
  draftLayout: number = 0;
  draftKeepOriginal: boolean = false;
  draftColorMode: ConfigurationConstant.ColorMode = ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET;
  draftInfo: PhotoInfoSettings = new PhotoInfoSettings();
  private baseline: string = '';
  private context?: common.UIAbilityContext;
  private store: WorkbenchPreferences | undefined = undefined;
  private generation: number = 0;
  private snapshot(): SettingsSnapshot {
    return { layout: this.draftLayout, keepOriginal: this.draftKeepOriginal,
      colorMode: this.draftColorMode,
      info: JSON.parse(JSON.stringify(this.draftInfo)) as PhotoInfoSettings };
  }
  savedLayout(): number { return (JSON.parse(this.baseline) as SettingsSnapshot).layout; }
  dirty(): boolean { return this.ready && JSON.stringify(this.snapshot()) !== this.baseline; }
  initialize(context: common.UIAbilityContext): void { this.context = context; this.store = new WorkbenchPreferences(context); }
  dispose(): void { this.generation++; this.store = undefined; this.context = undefined; }
  async load(): Promise<void> {
    if (!this.store || this.saving) { return; }
    const version = ++this.generation; this.ready = false;
    try {
      const layout = await this.store.loadLayout();
      const info = await this.store.loadInfo(); const keepOriginal = await this.store.loadKeepOriginal();
      const colorMode = await this.store.loadColorMode();
      if (version !== this.generation) { return; }
      this.draftColorMode = colorMode;
      this.draftLayout = layout; this.draftInfo = info; this.draftKeepOriginal = keepOriginal;
      this.baseline = JSON.stringify(this.snapshot()); this.error = ''; this.ready = true;
    } catch (_) { if (version === this.generation) { this.error = '设置读取失败，请重试。'; } }
  }
  discard(): void {
    if (!this.ready || this.saving || !this.baseline) { return; }
    const saved = JSON.parse(this.baseline) as SettingsSnapshot;
    this.draftLayout = saved.layout; this.draftKeepOriginal = saved.keepOriginal; this.draftInfo = saved.info;
    this.draftColorMode = saved.colorMode;
    this.error = '';
  }
  async save(): Promise<boolean> {
    if (!this.ready || this.saving || !this.store) { return false; }
    const version = this.generation; const saved = this.snapshot(); this.saving = true;
    const previous = JSON.parse(this.baseline) as SettingsSnapshot;
    try {
      // Source selection now belongs to the home page. Preserve the legacy key without using it.
      await this.store.save(saved.layout, saved.info, saved.keepOriginal, saved.colorMode);
      if (version !== this.generation) { return false; }
      this.baseline = JSON.stringify(saved);
      if (saved.colorMode !== previous.colorMode) {
        try { this.context?.getApplicationContext().setColorMode(saved.colorMode); }
        catch (_) { this.error = '外观偏好已保存，请重启应用以应用该设置。'; return false; }
      }
      this.error = ''; return true;
    } catch (error) {
      if (version === this.generation) { this.error = error instanceof ExperimentError ? error.message : '设置未确认保存，请重试。'; }
      return false;
    } finally { this.saving = false; }
  }
}
