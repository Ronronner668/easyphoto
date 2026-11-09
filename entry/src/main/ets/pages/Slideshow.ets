import { PlaybackButtonMaterial } from '../common/PlaybackChromeMaterial';
import { TitleButtonMaterial } from '../common/TitleButtonMaterial';
import { common } from '@kit.AbilityKit';
import { KeyCode } from '@kit.InputKit';
import { deviceInfo } from '@kit.BasicServicesKit';
import { FULL_SCREEN_FADE } from '../common/UiMotion';
import { AppIcon } from '../components/AppIcon';
import { SlideshowControls } from '../components/SlideshowControls';
import { SlideshowFrame } from '../components/SlideshowFrame';
import { SlideshowPhotoTile } from '../components/SlideshowPhotoTile';
import { ChromeRegion, ChromeInk } from '../domain/usecases/SlideshowContrast';
import { SlideshowPhoto } from '../domain/models/Slideshow';
import { GalleryAlbum } from '../domain/models/GalleryAlbum';
import { SlideshowViewModel } from '../viewmodels/SlideshowViewModel';
import { SlideshowWindow } from '../platform/media/SlideshowWindow';

interface SlideshowRoute { album?: GalleryAlbum; }

@Entry
@Component
struct Slideshow {
  @State private model: SlideshowViewModel = new SlideshowViewModel();
  @State private controls: boolean = true;
  @State private controlsOpacity: number = 1;
  @State private areaWidth: number = 360;
  @State private previewLimit: number = 60;
  @StorageLink('slideshowForeground') @Watch('foregroundChanged') foreground: boolean = true;
  private visible: boolean = false;
  private controlTimer: number = -1;
  private controlVersion: number = 0;
  @State private chromeRegions: ChromeRegion[] = [];
  @State private chromeInks: ChromeInk[] = [];
  private playbackWindow?: SlideshowWindow;
  private photoMaterial: PlaybackButtonMaterial = new PlaybackButtonMaterial(true);
  private titleMaterial: TitleButtonMaterial = new TitleButtonMaterial();

  aboutToAppear(): void {
    this.titleMaterial.initialize(); this.photoMaterial.initialize();
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const params = this.getUIContext().getRouter().getParams() as SlideshowRoute;
    if (!params?.album?.reference) { this.model.error = '请选择要回看的相册。'; return; }
    this.model.initialize(context, params.album);
    this.playbackWindow = new SlideshowWindow(context, () => { this.model.suspend(); this.showControls(); }, deviceInfo.deviceType !== '2in1',
      this.windowColor($r('app.color.photo_foreground')), this.windowColor($r('app.color.slideshow_background')));
    this.playbackWindow.open().catch(() => { this.model.notice = '窗口常亮暂不可用，可继续观看。'; });
    this.model.changed = () => {
      this.playbackWindow?.update(this.visible && this.model.presenting, this.visible && this.model.playing);
      if (!this.model.playing) { this.showControls(); }
    };
    this.model.load();
  }
  onPageShow(): void { this.visible = true; }
  onPageHide(): void { this.visible = false; this.model.suspend(); this.clearControlTimer(); this.playbackWindow?.update(false, false); }
  aboutToDisappear(): void {
    this.visible = false; this.clearControlTimer(); this.model.close(); this.playbackWindow?.close();
  }
  private foregroundChanged(): void {
    if (!this.foreground) { this.model.suspend(); this.showControls(); this.playbackWindow?.update(false, false); }
  }
  onBackPress(): boolean {
    if (this.model.presenting) { this.model.stop(); this.showControls(); return true; }
    return false;
  }
  private clearControlTimer(): void {
    this.controlVersion++;
    if (this.controlTimer >= 0) { clearTimeout(this.controlTimer); this.controlTimer = -1; }
  }
  private hideControls(delay: number): void {
    this.clearControlTimer();
    const version = this.controlVersion;
    this.controlTimer = setTimeout(() => {
      this.controlTimer = -1;
      if (version !== this.controlVersion || !this.model.playing || !this.visible) { return; }
      this.getUIContext().animateTo({ duration: 220, onFinish: () => {
        if (version === this.controlVersion && this.model.playing) { this.controls = false; }
      } }, () => { this.controlsOpacity = 0; });
    }, delay);
  }
  private showControls(): void {
    this.clearControlTimer(); this.controls = true;
    this.getUIContext().animateTo({ duration: 120 }, () => { this.controlsOpacity = 1; });
    if (this.model.playing) { this.hideControls(4500); }
  }
  private async start(resume: boolean): Promise<void> {
    await this.model.start(resume); this.updatePlaybackControls();
  }
  private async toggle(): Promise<void> {
    await this.model.toggle();
    this.updatePlaybackControls();
  }
  private updatePlaybackControls(): void {
    if (this.model.playing) { this.hideControls(100); }
    else { this.showControls(); }
  }
  private darkInk(key: string): boolean { return this.chromeInks.find(ink => ink.key === key)?.dark || false; }
  private inkColor(key: string): Resource {
    return this.darkInk(key) ? $r('app.color.playback_ink_dark') : $r('app.color.photo_foreground');
  }
  private inkHalo(key: string): Resource {
    return this.darkInk(key) ? $r('app.color.playback_ink_halo_light') : $r('app.color.playback_ink_halo_dark');
  }
  private captureRegion(key: string, area: Area): void {
    this.captureChrome(new ChromeRegion(key, Number(area.globalPosition.x), Number(area.globalPosition.y), Number(area.width), Number(area.height)));
  }
  private captureChrome(region: ChromeRegion): void {
    const old = this.chromeRegions.find(item => item.key === region.key);
    if (old && old.x === region.x && old.y === region.y && old.width === region.width && old.height === region.height) { return; }
    this.chromeRegions = this.chromeRegions.filter(item => item.key !== region.key).concat([region]);
  }
  private windowColor(colorResource: Resource): string {
    const color = this.getUIContext().getHostContext()!.resourceManager.getColorSync(colorResource.id);
    return '#' + (color >>> 0).toString(16).padStart(8, '0');
  }
  private nextReference(): string {
    const next = this.model.photos[this.model.index + 1];
    return next?.reference || (this.model.settings.loop ? this.model.photos[0]?.reference || '' : '');
  }
  private dateText(): string {
    const taken = this.model.current?.taken || 0;
    if (!taken) { return '拍摄日期未提供'; }
    const date = new Date(taken * 1000);
    return `${date.getFullYear()}年${date.getMonth() + 1}月${date.getDate()}日`;
  }
  private timeText(): string {
    const taken = this.model.current?.taken || 0;
    if (!taken) { return '时间未提供'; }
    const date = new Date(taken * 1000);
    return `${date.getHours().toString().padStart(2, '0')}:${date.getMinutes().toString().padStart(2, '0')}`;
  }
  private rows(): SlideshowPhoto[][] {
    const columns = this.areaWidth >= 840 ? 6 : this.areaWidth >= 600 ? 5 : 3;
    const rows: SlideshowPhoto[][] = [];
    const photos = this.model.photos.slice(0, this.previewLimit);
    for (let index = 0; index < photos.length; index += columns) { rows.push(photos.slice(index, index + columns)); }
    return rows;
  }
  private slots(used: number): number[] {
    const columns = this.areaWidth >= 840 ? 6 : this.areaWidth >= 600 ? 5 : 3;
    const values: number[] = [];
    for (let index = used; index < columns; index++) { values.push(index); }
    return values;
  }
  @Builder
  settingToggle(title: string, value: boolean, changed: (value: boolean) => void) {
    Row({ space: 12 }) {
      Text(title).fontSize(16).fontColor($r('app.color.text_primary')).layoutWeight(1)
      Toggle({ type: ToggleType.Switch, isOn: value }).onChange(changed).accessibilityText(title)
    }.width('100%').constraintSize({ minHeight: 52 })
  }
  @Builder
  settingsPanel() {
    Column({ space: 12 }) {
      Text('放映方式').fontSize(20).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary')).width('100%')
      Row({ space: 8 }) {
        Text('顺序').fontColor($r('app.color.text_secondary')).layoutWeight(1)
        Select([{ value: '拍摄时间正序' }, { value: '拍摄时间倒序' }, { value: '随机播放' }])
          .selected(['oldest', 'newest', 'random'].indexOf(this.model.settings.order))
          .value(['拍摄时间正序', '拍摄时间倒序', '随机播放'][['oldest', 'newest', 'random'].indexOf(this.model.settings.order)]).height(48)
          .onSelect(index => { this.model.setOrder(index === 0 ? 'oldest' : index === 1 ? 'newest' : 'random'); })
      }.width('100%')
      Row({ space: 8 }) {
        Text('每张停留').fontColor($r('app.color.text_secondary')).layoutWeight(1)
        Select([{ value: '3 秒' }, { value: '5 秒' }, { value: '8 秒' }, { value: '12 秒' }])
          .selected([3, 5, 8, 12].indexOf(this.model.settings.interval)).value(`${this.model.settings.interval} 秒`).height(48)
          .onSelect(index => { this.model.settings.interval = [3, 5, 8, 12][index]; this.model.updateSettings(); })
      }.width('100%')
      this.settingToggle('循环播放', this.model.settings.loop, value => { this.model.settings.loop = value; this.model.updateSettings(); })
      this.settingToggle('显示拍摄日期', this.model.settings.showDate, value => { this.model.settings.showDate = value; this.model.updateSettings(); })
      this.settingToggle('淡入转场', this.model.settings.fade, value => { this.model.settings.fade = value; this.model.updateSettings(); })
      Divider().color($r('app.color.divider'))
      Text('背景音乐').fontSize(18).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary')).width('100%')
      Row({ space: 8 }) {
        Button(this.model.importing ? '正在导入…' : this.model.settings.music ? '更换音乐' : '选择本地音乐')
          .constraintSize({ minHeight: 48 }).layoutWeight(1).buttonStyle(ButtonStyleMode.TEXTUAL).attributeModifier(this.titleMaterial)
          .fontColor($r('app.color.accent')).onClick(() => { this.model.chooseMusic(); })
        if (this.model.settings.music) {
          Button('移除').constraintSize({ minHeight: 48 }).buttonStyle(ButtonStyleMode.TEXTUAL).attributeModifier(this.titleMaterial)
            .fontColor($r('app.color.text_primary')).onClick(() => { this.model.removeMusic(); })
        }
      }.width('100%')
      if (this.model.settings.music) {
        Slider({ value: this.model.settings.volume * 100, min: 0, max: 100, step: 5 }).accessibilityText('背景音乐音量')
          .onChange((value: number, mode: SliderChangeMode) => {
            if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) { this.model.settings.volume = value / 100; this.model.updateSettings(); }
          })
      }
    }.width('100%').padding(20).backgroundColor($r('app.color.surface')).borderRadius(24)
      .enabled(this.model.ready && !this.model.importing)
  }
  @Builder
  albumPreview() {
    Column({ space: 16 }) {
      Text('相册照片').fontSize(20).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary')).width('100%')
      Text('点击任意照片，从那里开始放映。').fontSize(14).fontColor($r('app.color.text_secondary')).width('100%')
      ForEach(this.rows(), (row: SlideshowPhoto[]) => {
        Row({ space: 8 }) {
          ForEach(row, (photo: SlideshowPhoto) => {
            Column() {
              SlideshowPhotoTile({ photo, selected: photo.reference === this.model.current?.reference,
                activated: () => { this.model.select(this.model.photos.findIndex(item => item.reference === photo.reference)); this.start(true); } })
            }.layoutWeight(1)
          }, (photo: SlideshowPhoto) => `${photo.reference}_${photo.reference === this.model.current?.reference}`)
          ForEach(this.slots(row.length), (slot: number) => { Blank().layoutWeight(1) }, (slot: number) => String(slot))
        }.width('100%')
      }, (row: SlideshowPhoto[]) => row[0].reference)
      if (this.previewLimit < this.model.photos.length) {
        Button('显示更多照片').constraintSize({ minHeight: 48 }).buttonStyle(ButtonStyleMode.TEXTUAL).attributeModifier(this.titleMaterial)
          .onClick(() => { this.previewLimit += 60; })
      }
    }.width('100%').enabled(this.model.ready && !this.model.loading && !this.model.importing)
  }
  @Builder
  playbackButton(icon: Resource, label: string, action: () => void) {
    Button({ type: ButtonType.Circle }) { AppIcon({ source: this.darkInk('back') ? $r('app.media.lucide_arrow_left_dark_on_photo') : icon, iconSize: 20, haloRadius: 1, haloColor: this.inkHalo('back') }) }
      .width(44).height(44).flexShrink(0).padding(0).responseRegion({ x: -2, y: -2, width: 48, height: 48 })
      .buttonStyle(ButtonStyleMode.TEXTUAL).attributeModifier(this.photoMaterial)
      .onAreaChange((_old: Area, area: Area) => { this.captureChrome(new ChromeRegion('back', Number(area.globalPosition.x) + 8, Number(area.globalPosition.y) + 8, 28, 28)); })
      .accessibilityText(label).onClick(action)
  }
  @Builder
  playback() {
    Stack({ alignContent: Alignment.Bottom }) {
      if (this.model.current) {
        SlideshowFrame({ reference: this.model.current.reference, nextReference: this.nextReference(), faded: this.model.settings.fade,
          regions: this.chromeRegions, contrastChanged: inks => { this.chromeInks = inks; },
          controlsVisible: this.controls, playing: this.model.playing,
          imageWidth: this.model.current.width, imageHeight: this.model.current.height,
          tapped: () => { this.toggle(); }, zoomStarted: () => { this.model.pause(); this.showControls(); },
          swipeStarted: () => { this.model.beginSwipe(); }, swipeEnded: direction => { this.model.endSwipe(direction); },
          loaded: reference => { this.model.imageLoaded(reference); }, failed: reference => { this.model.imageFailed(reference); } })
          .accessibilityText(this.model.playing ? '单击暂停放映' : '单击继续放映，有控件时可双指缩放')
      }
      if (this.controls || !this.model.playing) {
        Column() {
          if (this.model.preparing) { Text('正在准备音乐…').fontColor($r('app.color.photo_foreground')).padding(12) }
          if (this.model.notice) { Text(this.model.notice).fontSize(14).fontColor($r('app.color.photo_foreground')).padding(12).backgroundColor($r('app.color.photo_control')).borderRadius(12) }
          if (this.model.error || this.model.saveError) { Text(this.model.error || this.model.saveError).fontSize(14).fontColor($r('app.color.photo_foreground')).padding(8) }
          if (this.model.ended) { Text('这一段回忆已播放完毕').fontSize(18).fontColor($r('app.color.photo_foreground')).padding(12) }
          SlideshowControls({ playing: this.model.playing, inks: this.chromeInks, regionChanged: region => { this.captureChrome(region); },
            previous: () => { this.model.move(-1); this.showControls(); },
            toggle: () => { this.toggle(); }, next: () => { this.model.move(1); this.showControls(); } })
        }.width('100%').padding(16).opacity(this.controlsOpacity)
      }
    }.width('100%').height('100%').backgroundColor($r('app.color.slideshow_background'))
      .onMouse(event => { if (event.action === MouseAction.Move) { this.showControls(); } })
  }
  @Builder
  albumTitle() {
    Row({ space: 8 }) {
      Button({ type: ButtonType.Circle }) { AppIcon({ source: $r('app.media.lucide_arrow_left'), iconSize: 20 }) }
        .width(44).height(44).flexShrink(0).padding(0).responseRegion({ x: -2, y: -2, width: 48, height: 48 })
        .buttonStyle(ButtonStyleMode.TEXTUAL).attributeModifier(this.titleMaterial).accessibilityText('返回回忆')
        .onClick(() => { this.getUIContext().getRouter().back(); })
      Text(this.model.album?.name || '相册回忆').fontSize(18).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
        .layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
      Button('刷新').constraintSize({ minWidth: 48, minHeight: 44 }).responseRegion({ x: 0, y: -2, width: '100%', height: 48 })
        .buttonStyle(ButtonStyleMode.TEXTUAL).attributeModifier(this.titleMaterial).fontColor($r('app.color.text_primary'))
        .enabled(!this.model.loading && !this.model.importing).onClick(() => { this.model.load(); })
    }.width('100%').height('100%').padding({ left: 12, right: 12 })
  }
  @Builder
  playbackTitle() {
    Row({ space: 8 }) {
      this.playbackButton($r('app.media.lucide_arrow_left_on_photo'), '退出放映', () => { this.model.stop(); })
      Column({ space: 4 }) {
        Text(this.model.settings.showDate ? this.dateText() : this.model.album?.name || '相册放映')
          .fontSize(18).fontWeight(FontWeight.Medium).fontColor(this.inkColor('date')).textShadow({ radius: 1, color: this.inkHalo('date') })
          .constraintSize({ maxWidth: '100%' }).alignSelf(ItemAlign.Start).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          .onAreaChange((_old: Area, area: Area) => { this.captureRegion('date', area); })
        if (this.model.settings.showDate) {
          Text(`${this.timeText()} · ${this.model.album?.name || '相册放映'}`).fontSize(13).fontColor(this.inkColor('time')).textShadow({ radius: 1, color: this.inkHalo('time') })
            .constraintSize({ maxWidth: '100%' }).alignSelf(ItemAlign.Start).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            .onAreaChange((_old: Area, area: Area) => { this.captureRegion('time', area); })
        }
      }.layoutWeight(1).clip(true).alignItems(HorizontalAlign.Start)
      Text(`${this.model.index + 1} / ${this.model.photos.length}`).fontSize(14).fontColor(this.inkColor('count')).textShadow({ radius: 1, color: this.inkHalo('count') })
        .onAreaChange((_old: Area, area: Area) => { this.captureRegion('count', area); })
      if (deviceInfo.deviceType === '2in1') {
        Button('全屏').constraintSize({ minWidth: 48, minHeight: 44 }).buttonStyle(ButtonStyleMode.TEXTUAL)
          .attributeModifier(this.photoMaterial).fontColor(this.inkColor('fullscreen'))
          .onAreaChange((_old: Area, area: Area) => { this.captureRegion('fullscreen', area); }).onClick(() => {
            this.playbackWindow?.toggleFullscreen().catch(() => { this.model.notice = '窗口暂不可全屏，可继续在当前窗口观看。'; });
          })
      }
    }.width('100%').height('100%').padding({ left: 12, right: 12 })
      .opacity(this.controlsOpacity)
      .visibility(this.controls || !this.model.playing ? Visibility.Visible : Visibility.Hidden)
  }
  pageTransition() {
    PageTransitionEnter(FULL_SCREEN_FADE).opacity(0)
    PageTransitionExit(FULL_SCREEN_FADE).opacity(0)
  }
  build() {
    Stack() {
      Navigation() {
        Scroll() {
          Column({ space: 24 }) {
            Column({ space: 12 }) {
              AppIcon({ source: $r('app.media.lucide_images_accent'), iconSize: 36 })
              Text('让照片慢慢讲述').fontSize(26).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
              Text(`${this.model.photos.length} 张照片`).fontSize(14).fontColor($r('app.color.text_secondary'))
              if (this.model.loading) { LoadingProgress().width(32).height(32).color($r('app.color.loading_indicator')) }
              if (this.model.error || this.model.saveError) {
                Text(this.model.error || this.model.saveError).fontColor($r('app.color.warning')).fontSize(14)
                Button('重试保存').constraintSize({ minHeight: 48 }).buttonStyle(ButtonStyleMode.TEXTUAL).attributeModifier(this.titleMaterial).enabled(this.model.ready).onClick(() => { this.model.save(); })
              }
              if (this.model.notice) { Text(this.model.notice).fontColor($r('app.color.text_secondary')).fontSize(14) }
              Button('从头放映').type(ButtonType.Capsule).buttonStyle(ButtonStyleMode.TEXTUAL).attributeModifier(this.titleMaterial).fontColor($r('app.color.accent')).width('100%').constraintSize({ minHeight: 52 })
                .enabled(this.model.ready && !!this.model.current && !this.model.loading && !this.model.importing).onClick(() => { this.start(false); })
              if (this.model.canResume) {
                Button('继续上次观看').width('100%').constraintSize({ minHeight: 48 }).buttonStyle(ButtonStyleMode.TEXTUAL).attributeModifier(this.titleMaterial)
                  .enabled(this.model.ready && !this.model.loading && !this.model.importing).onClick(() => { this.start(true); })
              }
              if (!this.model.loading && this.model.ready && !this.model.photos.length) { Text('这个相册暂时没有可放映的照片').fontColor($r('app.color.text_secondary')) }
            }.width('100%').padding(24).backgroundColor($r('app.color.surface')).borderRadius(24)
            if (this.areaWidth >= 840) {
              Row({ space: 24 }) {
                Column() { this.albumPreview() }.layoutWeight(1)
                Column() { this.settingsPanel() }.width(320)
              }.width('100%').alignItems(VerticalAlign.Top)
            } else {
              this.settingsPanel()
              this.albumPreview()
            }
          }.width('100%').constraintSize({ maxWidth: 1200 }).padding(20)
        }.width('100%').height('100%').align(Alignment.Top).edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      }.title({ builder: this.albumTitle, height: 72 }, { backgroundColor: $r('app.color.console_background') })
        .mode(NavigationMode.Stack).hideBackButton(true).hideToolBar(true).width('100%').height('100%')
      if (this.model.presenting) {
        Navigation() { this.playback() }
          .title({ builder: this.playbackTitle, height: 80 }, { backgroundColor: Color.Transparent, barStyle: BarStyle.STACK })
          .mode(NavigationMode.Stack).hideBackButton(true).hideToolBar(true)
          .width('100%').height('100%').backgroundColor($r('app.color.slideshow_background'))
      }
    }.width('100%').height('100%').backgroundColor($r('app.color.console_background'))
      .onAreaChange((_old: Area, area: Area) => { this.areaWidth = Number(area.width); })
      .focusable(true).defaultFocus(true)
      .onKeyEventDispatch(event => {
        if (!this.model.presenting || event.type !== KeyType.Down) { return false; }
        if (event.keyCode === KeyCode.KEYCODE_ESCAPE) { this.onBackPress(); return true; }
        if (event.keyCode === KeyCode.KEYCODE_SPACE) { this.toggle(); return true; }
        if (event.keyCode === KeyCode.KEYCODE_DPAD_LEFT) { this.model.move(-1); this.showControls(); return true; }
        if (event.keyCode === KeyCode.KEYCODE_DPAD_RIGHT) { this.model.move(1); this.showControls(); return true; }
        return false;
      })
  }
}
