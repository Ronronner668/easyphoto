import { TitleButtonMaterial } from '../common/TitleButtonMaterial';
import { AppIcon } from '../components/AppIcon';
import { FULL_SCREEN_FADE } from '../common/UiMotion';
import { targetCapacity } from '../domain/usecases/TargetAlbumOrder';
import { AppTheme } from '../common/AppTheme';
import { SettingsRow } from '../components/SettingsRow';
import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { SettingsViewModel } from '../viewmodels/SettingsViewModel';
import { supportsGalleryFavorite } from '../platform/media/GalleryFavorite';

interface SettingsRoute { openLayout?: boolean; }

@Entry
@Component
struct Settings {
  @State section: number = -1;
  @State model: SettingsViewModel = new SettingsViewModel();
  private openedFromReview: boolean = false;
  private prompting: boolean = false;
  private openingPractice: boolean = false;
  private favoriteSupported: boolean = supportsGalleryFavorite();
  private titleMaterial: TitleButtonMaterial = new TitleButtonMaterial();
  aboutToAppear(): void {
    this.titleMaterial.initialize();
    const params = this.getUIContext().getRouter().getParams() as SettingsRoute | undefined;
    this.openedFromReview = params?.openLayout === true;
    if (this.openedFromReview) { this.section = 1; }
    this.model.initialize(this.getUIContext().getHostContext() as common.UIAbilityContext);
    this.model.load();
  }
  aboutToDisappear(): void { this.model.dispose(); }
  private async openPractice(): Promise<void> {
    if (this.openingPractice || this.model.saving) { return; }
    this.openingPractice = true;
    try { await this.getUIContext().getRouter().pushUrl({ url: 'pages/PhotoReview', params: { practice: true } }); }
    catch (_) { this.getUIContext().getPromptAction().showToast({ message: '练习页打开失败，请重试。' }); }
    finally { this.openingPractice = false; }
  }
  private async saveSettings(): Promise<void> {
    if (await this.model.save()) { this.leave(0); }
    else if (this.model.error) { this.getUIContext().getPromptAction().showToast({ message: this.model.error }); }
  }
  private leave(target: number): void {
    if (target === 1 || this.openedFromReview) { this.getUIContext().getRouter().back(); }
    else { this.section = -1; }
  }
  private requestLeave(target: number): void {
    if (this.model.saving || this.prompting) { return; }
    if (!this.model.dirty()) { this.leave(target); return; }
    this.prompting = true;
    this.getUIContext().showAlertDialog({
      title: '保存设置？', message: '设置已修改，是否保存后离开？', autoCancel: false,
      cancel: () => { this.prompting = false; },
      buttons: [
        { value: '保存', action: async () => {
          try { if (await this.model.save()) { this.leave(target); }
            else { this.getUIContext().getPromptAction().showToast({ message: this.model.error }); }
          } finally { this.prompting = false; }
        } },
        { value: '不保存', action: () => { this.model.discard(); this.prompting = false; this.leave(target); } },
        { value: '继续编辑', action: () => { this.prompting = false; } }
      ]
    });
  }
  onBackPress(): boolean {
    if (this.model.saving || this.prompting) { return true; }
    if (this.section >= 0) { this.requestLeave(0); return true; }
    if (this.model.dirty()) { this.requestLeave(1); return true; }
    return false;
  }
  @Builder
  colorModeOption(label: string, mode: ConfigurationConstant.ColorMode) {
    Button(label).type(ButtonType.Capsule)
      .layoutWeight(1).constraintSize({ minHeight: 48 }).fontSize(14)
      .buttonStyle(ButtonStyleMode.TEXTUAL)
      .border({ radius: 24, width: this.model.draftColorMode === mode ? 2 : 1,
        color: this.model.draftColorMode === mode ? $r('app.color.accent') : $r('sys.color.ohos_id_color_list_separator') })
      .fontColor(this.model.draftColorMode === mode ? $r('app.color.accent') : $r('app.color.text_primary'))
      .accessibilityText(this.model.draftColorMode === mode ? label + '，已选中' : label)
      .enabled(this.model.ready && !this.model.saving)
      .onClick(() => { this.model.draftColorMode = mode; })
  }
  @Builder
  layoutOption(title: string, preview: Resource, layout: number) {
    Button({ type: ButtonType.Normal }) {
      Column({ space: 8 }) {
        Image(preview).width('100%').aspectRatio(480 / 256).objectFit(ImageFit.Contain).borderRadius(8)
          .accessibilityLevel('no')
        Text(title).fontSize(14).textAlign(TextAlign.Center)
          .fontColor(this.model.draftLayout === layout ? $r('app.color.accent') : $r('app.color.text_primary'))
      }.width('100%').padding(8)
    }.layoutWeight(1).constraintSize({ minHeight: 52 }).clip(true)
      .buttonStyle(this.model.draftLayout === layout ? ButtonStyleMode.NORMAL : ButtonStyleMode.TEXTUAL)
      .border({ radius: 20, width: this.model.draftLayout === layout ? 2 : 1,
        color: this.model.draftLayout === layout ? $r('app.color.accent') : $r('sys.color.ohos_id_color_list_separator') })
      .accessibilityText(this.model.draftLayout === layout ? title + '，已选中' : title)
      .onClick(() => { this.model.draftLayout = layout; })
  }
  @Builder
  preferences() {
    Column({ space: 24 }) {
      Scroll() {
      Column({ space: 24 }) {
      if (this.section === 1) {
      Column({ space: 8 }) {
      Text('入口位置').fontSize(14).fontColor($r('app.color.text_secondary')).width('100%')
      Row({ space: 12 }) {
        this.layoutOption('下方三个', $r('app.media.review_layout_three'), 0)
        this.layoutOption('左右各两个', $r('app.media.review_layout_four'), 1)
      }.padding(20).width('100%').borderRadius(AppTheme.cardRadius).backgroundColor($r('app.color.surface'))
      if (this.model.error) { Text(this.model.error).fontSize(14).fontColor($r('app.color.warning')).width('100%') }
      }.width('100%')
      }
      }.width('100%').padding({ left: 20, right: 20, bottom: 24 })
      }.width('100%').layoutWeight(1).align(Alignment.TopStart).edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true }).scrollBar(BarState.Auto).enabled(this.model.ready && !this.model.saving)
      Column({ space: 8 }) {
      Button('调整目标相册').type(ButtonType.Capsule).buttonStyle(ButtonStyleMode.TEXTUAL).border({ radius: 999, width: 1, color: $r('sys.color.ohos_id_color_list_separator') }).width('100%').constraintSize({ minHeight: 52 }).fontColor($r('app.color.text_primary')).enabled(this.model.ready && !this.model.saving).onClick(async () => {
        try {
          const capacity = targetCapacity(this.model.draftLayout);
          const savedCapacity = targetCapacity(this.model.savedLayout());
          if (capacity > savedCapacity) { this.getUIContext().getPromptAction().showToast({ message: '请先保存左右各两个的布局，再选择第四个目标相册。' }); return; }
          await this.getUIContext().getRouter().pushUrl({ url: 'pages/TargetAlbums', params: { capacity } });
        }
        catch (_) { this.getUIContext().getPromptAction().showToast({ message: '目标相册页未能打开，设置草稿保留，请重试。' }); }
      })
      }.width('100%').padding({ left: AppTheme.pagePadding, right: AppTheme.pagePadding })
      this.saveBar()
    }.padding({ top: 12, bottom: 12 }).width('100%').height('100%').backgroundColor($r('app.color.console_background')).transition(TransitionEffect.opacity(0).animation(FULL_SCREEN_FADE))
  }
  @Builder
  saveBar() {
    Row() {
      Button(this.model.saving ? '正在保存…' : '保存设置').type(ButtonType.Capsule).buttonStyle(ButtonStyleMode.TEXTUAL).border({ radius: 999, width: 1, color: $r('sys.color.ohos_id_color_list_separator') }).fontColor($r('app.color.accent'))
        .width('100%').constraintSize({ minHeight: 52 })
        .fontColor($r('app.color.accent'))
        .enabled(this.model.ready && !this.model.saving && this.model.dirty())
        .onClick(() => { this.saveSettings(); })
    }.width('100%').padding({ left: AppTheme.pagePadding, right: AppTheme.pagePadding, top: 8, bottom: 8 })
  }
  pageTransition() {
    PageTransitionEnter(FULL_SCREEN_FADE).opacity(0)
    PageTransitionExit(FULL_SCREEN_FADE).opacity(0)
  }

  @Builder
  settingsTitle() {
    Row({ space: 8 }) {
      Button({ type: ButtonType.Circle }) {
        AppIcon({ source: $r('app.media.lucide_arrow_left'), iconSize: 20 })
      }.width(48).height(48).padding(0).buttonStyle(ButtonStyleMode.TEXTUAL)
        .attributeModifier(this.titleMaterial).accessibilityText('返回')
        .onClick(() => { this.requestLeave(this.section >= 0 ? 0 : 1); })
      if (this.section >= 0) {
        Text('整理布局').fontColor($r('app.color.text_primary')).fontSize(18).fontWeight(FontWeight.Medium)
          .layoutWeight(1).textAlign(TextAlign.Center)
        Blank().width(48)
      } else {
        Text('设置').fontSize(AppTheme.titleSize).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary'))
      }
    }.width('100%').height('100%').padding({ left: 12, right: 12 })
  }

  @Builder
  settingsContent() {
    if (this.section >= 0) { this.preferences() }
    else {
      Column() {
        Scroll() {
          Column({ space: 16 }) {
            if (this.model.error) {
              Text(this.model.error).fontSize(14).fontColor($r('app.color.warning')).width('100%')
              Button('重新读取').type(ButtonType.Capsule).buttonStyle(ButtonStyleMode.TEXTUAL).border({ radius: 999, width: 1, color: $r('sys.color.ohos_id_color_list_separator') }).constraintSize({ minHeight: 48 }).onClick(() => { this.model.load(); })
            }
            Column({ space: 8 }) {
              Text('外观模式').fontSize(16).fontColor($r('app.color.text_primary')).width('100%')
              Row({ space: 8 }) {
                this.colorModeOption('跟随系统', ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET)
                this.colorModeOption('日间', ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT)
                this.colorModeOption('夜间', ConfigurationConstant.ColorMode.COLOR_MODE_DARK)
              }.width('100%')
            }.width('100%').padding(16).borderRadius(AppTheme.cardRadius).backgroundColor($r('app.color.surface'))
            Column() {
              Row({ space: 12 }) {
                Text('保留原位置照片').fontSize(16).fontColor($r('app.color.text_primary')).layoutWeight(1)
                Toggle({ type: ToggleType.Switch, isOn: this.model.draftKeepOriginal }).enabled(this.model.ready && !this.model.saving)
                  .selectedColor($r('app.color.accent')).onChange((value: boolean) => { this.model.draftKeepOriginal = value; })
              }.width('100%').padding(20)
              Text(this.model.draftKeepOriginal ? '相册分类保留原图' : '相册分类验证后，结束时统一回收原图').fontSize(14).fontColor($r('app.color.text_secondary')).width('100%').padding({ left: 20, right: 20, bottom: 12 })
              Divider().color($r('app.color.divider')).margin({ left: 20, right: 20 })
              SettingsRow({ title: '整理布局', description: '目标相册的展示布局', icon: $r('app.media.lucide_layout_grid'), available: this.model.ready, divider: true,
                activated: () => { this.section = 1; } })
              SettingsRow({ title: '整理练习', description: '用示例照片练习手势和分类', icon: $r('app.media.lucide_images'),
                available: !this.model.saving, activated: () => { this.openPractice(); } })
            }.width('100%').borderRadius(AppTheme.cardRadius).clip(true).backgroundColor($r('app.color.surface'))
            if (!this.favoriteSupported) {
              Text('当前系统不支持应用内收藏，可在系统图库中收藏。').fontSize(14).fontColor($r('app.color.text_secondary')).width('100%').padding(16)
            }
          }.width('100%').constraintSize({ maxWidth: 720 }).padding(AppTheme.pagePadding)
        }.width('100%').layoutWeight(1).align(Alignment.TopStart).edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true }).scrollBar(BarState.Auto)
        this.saveBar()
      }.width('100%').height('100%').backgroundColor($r('app.color.console_background')).transition(TransitionEffect.opacity(0).animation(FULL_SCREEN_FADE))
    }
  }

  build() {
    Navigation() {
      this.settingsContent()
    }
      .title({ builder: this.settingsTitle, height: 80 }, { backgroundColor: $r('app.color.console_background') })
      .mode(NavigationMode.Stack).hideBackButton(true).hideToolBar(true)
      .width('100%').height('100%')
  }
}
