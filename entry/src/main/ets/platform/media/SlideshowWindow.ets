import { common } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';

export class SlideshowWindow {
  private target?: window.Window;
  private active: boolean = true;
  private presenting: boolean = false;
  private playing: boolean = false;
  private initialKeepOn: boolean = false;
  private initialImmersive: boolean = false;
  private initialBars?: window.SystemBarProperties;
  private initialOrientation?: window.Orientation;
  private appliedOrientation?: window.Orientation;
  private playbackBars: boolean = false;
  private autoRotate: boolean;
  private foregroundColor: string;
  private backgroundColor: string;
  private queue: Promise<void> = Promise.resolve();
  private fullscreen: boolean = false;
  private previousStatus?: window.WindowStatusType;
  private hidden: (visible: boolean) => void;
  private context: common.UIAbilityContext;
  constructor(context: common.UIAbilityContext, pause: () => void, autoRotate: boolean = false,
    foregroundColor: string = '', backgroundColor: string = '') {
    this.context = context;
    this.autoRotate = autoRotate; this.foregroundColor = foregroundColor; this.backgroundColor = backgroundColor;
    this.hidden = (visible: boolean) => { if (!visible) { pause(); } };
  }
  async open(): Promise<void> {
    const target = await window.getLastWindow(this.context);
    if (!this.active) { return; }
    const keepOn = target.getWindowProperties().isKeepScreenOn;
    const immersive = target.getImmersiveModeEnabledState();
    let bars: window.SystemBarProperties | undefined = undefined;
    let orientation: window.Orientation | undefined = undefined;
    if (this.autoRotate) {
      bars = target.getWindowSystemBarProperties();
      orientation = target.getPreferredOrientation();
    }
    // Publish only a complete snapshot so a failed query cannot leave un-restorable window changes.
    this.initialKeepOn = keepOn; this.initialImmersive = immersive;
    this.initialBars = bars; this.initialOrientation = orientation; this.appliedOrientation = orientation;
    this.target = target;
    target.on('windowVisibilityChange', this.hidden);
    this.update(this.presenting, this.playing);
  }
  update(presenting: boolean, playing: boolean): void {
    this.presenting = presenting; this.playing = playing;
    this.queue = this.queue.then(async () => {
      if (!this.target) { return; }
      if ((!this.active || !this.presenting) && this.fullscreen) { await this.restoreFullscreen(); }
      // Native Navigation owns the safe title area. Only desktop full-screen extends window content.
      this.target.setImmersiveModeEnabledState(this.fullscreen || (this.active && this.presenting ? false : this.initialImmersive));
      if (this.autoRotate) {
        const orientation = this.active ? window.Orientation.AUTO_ROTATION : this.initialOrientation!;
        if (orientation !== this.appliedOrientation) {
          await this.target.setPreferredOrientation(orientation);
          this.appliedOrientation = orientation;
        }
      }
      const playbackBars = this.active && this.presenting;
      if (playbackBars !== this.playbackBars && this.initialBars && this.foregroundColor) {
        await this.target.setWindowSystemBarProperties(playbackBars ? {
          statusBarColor: this.backgroundColor, navigationBarColor: this.backgroundColor,
          statusBarContentColor: this.foregroundColor, navigationBarContentColor: this.foregroundColor
        } : this.initialBars);
        this.playbackBars = playbackBars;
      }
      await this.target.setWindowKeepScreenOn(this.active && this.playing ? true : this.initialKeepOn);
    }).catch(() => { hilog.warn(0, 'Slideshow', 'Could not update playback window state'); });
  }
  toggleFullscreen(): Promise<void> {
    const task = this.queue.then(async () => {
      const target = this.target;
      if (!target || !this.active) { return; }
      if (this.fullscreen) { await this.restoreFullscreen(); return; }
      this.previousStatus = target.getWindowStatus();
      await target.maximize(window.MaximizePresentation.ENTER_IMMERSIVE);
      this.fullscreen = true;
      if (!this.active || !this.presenting) { await this.restoreFullscreen(); }
    });
    this.queue = task.catch(() => { hilog.warn(0, 'Slideshow', 'Could not change full-screen playback'); });
    return task;
  }
  private async restoreFullscreen(): Promise<void> {
    if (!this.target || !this.fullscreen) { return; }
    if (this.previousStatus === window.WindowStatusType.FLOATING) { await this.target.recover(); }
    else { await this.target.maximize(window.MaximizePresentation.EXIT_IMMERSIVE); }
    this.fullscreen = false;
  }
  close(): void {
    this.active = false; this.update(false, false);
    if (this.target) {
      try { this.target.off('windowVisibilityChange', this.hidden); }
      catch (_) { hilog.warn(0, 'Slideshow', 'Could not detach window visibility observer'); }
    }
  }
}
