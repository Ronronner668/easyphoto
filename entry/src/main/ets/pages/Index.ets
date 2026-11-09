import { MemoriesHome } from '../components/MemoriesHome';
import { FULL_SCREEN_FADE } from '../common/UiMotion';
import { GalleryAlbumGuide } from '../services/operations/GalleryAlbumGuide';
import { NewAlbumHint } from '../components/NewAlbumHint';
import { AppTheme } from '../common/AppTheme';
import { AppIcon } from '../components/AppIcon';
import { SettingsRow } from '../components/SettingsRow';
import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { PhotoPlaceReader } from '../platform/media/PhotoPlaceReader';
import { PermissionProbe } from '../platform/permissions/PermissionProbe';
import { HdsTabs, HdsTabsController, hdsMaterial } from '@kit.UIDesignKit';
import { GalleryAlbumsViewModel } from '../viewmodels/GalleryAlbumsViewModel';
import { GalleryAlbum } from '../domain/models/GalleryAlbum';
import { GalleryAlbumTile } from '../components/GalleryAlbumTile';
// 单机版暂时停用账号；保留账号实现，恢复时同时复核网络权限和发布申报。
// import { HuaweiAccountCard } from '../components/HuaweiAccountCard';

@Entry
@Component
struct Index {
  @State tab: number = 0;
  @State memoryRefresh: number = 0;
  @State opening: boolean = false;
  @State albums: GalleryAlbumsViewModel = new GalleryAlbumsViewModel();
  @State albumAreaWidth: number = 320;
  private newAlbumDialog: CustomDialogController = new CustomDialogController({ builder: NewAlbumHint({ confirmed: (showAgain: boolean) => { this.openGallery(showAgain); }, dismissed: (showAgain: boolean) => { this.rememberAlbumHint(showAgain); } }) });
  private guide(): GalleryAlbumGuide { return new GalleryAlbumGuide(this.getUIContext().getHostContext() as common.UIAbilityContext); }
  private async newAlbum(): Promise<void> {
    try { if (await this.guide().shouldShow()) { this.newAlbumDialog.open(); } else { await this.openGallery(false); } }
    catch (_) { this.getUIContext().getPromptAction().showToast({ message: '新建相册提示读取失败，请稍后重试。' }); }
  }
  private async rememberAlbumHint(showAgain: boolean): Promise<void> {
    try { await this.guide().remember(showAgain); }
    catch (_) { this.getUIContext().getPromptAction().showToast({ message: '提示偏好未保存，下次会再次询问。' }); }
  }
  private async openGallery(showAgain: boolean): Promise<void> {
    try { await this.guide().open(); }
    catch (_) { this.getUIContext().getPromptAction().showToast({ message: '图库未能打开，请手动进入系统图库新建相册。' }); return; }
    await this.rememberAlbumHint(showAgain);
  }
  private tabsController: HdsTabsController = new HdsTabsController();
  aboutToAppear(): void { this.albums.initialize(this.getUIContext().getHostContext() as common.UIAbilityContext); }
  @State private initializingAccess: boolean = false;
  @State private visible: boolean = false;
  private tutorialPromptOpen: boolean = false;

  onPageShow(): void {
    this.visible = true; this.memoryRefresh++;
    if (AppStorage.get<boolean>('openMemories')) {
      AppStorage.set<boolean>('openMemories', false);
      this.tab = 1; this.tabsController.changeIndex(1);
    }
    this.initializeAccess();
  }
  onPageHide(): void { this.visible = false; this.albums.suspend(); }

  private async initializeAccess(): Promise<void> {
    if (this.initializingAccess) { return; }
    this.initializingAccess = true;
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const store = await preferences.getPreferences(context, { name: 'first_launch_access' });
      const galleryOffered = await store.get('galleryReadOffered', false);
      if (!this.visible) { return; }
      const tutorialPending = await store.get('tutorialPending', !galleryOffered) === true;
      if (!this.visible) { return; }
      if (!galleryOffered) {
        if (tutorialPending) {
          await store.put('tutorialPending', true);
          await store.flush();
        }
        if (!this.visible) { return; }
        await new PermissionProbe().requestRead(context);
        await store.put('galleryReadOffered', true);
        await store.flush();
      }
      const locationOffered = await store.get('mediaLocationOffered', false);
      if (!this.visible) { return; }
      if (!locationOffered && new PermissionProbe().canReadLibrary()) {
        try { await new PhotoPlaceReader(context).request(); }
        catch (_) { hilog.warn(0, 'Index', 'First-launch photo location permission unavailable'); }
        await store.put('mediaLocationOffered', true);
        await store.flush();
      }
      if (this.visible && tutorialPending) { this.offerTutorial(store); }
    } catch (_) { hilog.warn(0, 'Index', 'First-launch access state unavailable'); }
    finally {
      this.initializingAccess = false;
      if (this.visible) { this.albums.refresh(); }
    }
  }
  private offerTutorial(store: preferences.Preferences): void {
    if (this.tutorialPromptOpen) { return; }
    this.tutorialPromptOpen = true;
    const finish = async (enter: boolean): Promise<void> => {
      try {
        await store.put('tutorialPending', false);
        await store.flush();
      } catch (_) { hilog.warn(0, 'Index', 'Could not save first-launch tutorial choice'); }
      try {
        if (enter && this.visible) {
          await this.getUIContext().getRouter().pushUrl({ url: 'pages/PhotoReview', params: { practice: true } });
        }
      } catch (_) {
        if (this.visible) { this.getUIContext().getPromptAction().showToast({ message: '教学未能打开，可在设置中进入整理练习。' }); }
      } finally { this.tutorialPromptOpen = false; }
    };
    try {
      this.getUIContext().showAlertDialog({
        title: '进入整理教学？',
        message: '使用示例照片练习浏览和分类。也可以稍后在设置中打开「整理练习」。',
        autoCancel: false,
        cancel: () => { finish(false); },
        primaryButton: { value: '暂不进入', action: () => { finish(false); } },
        secondaryButton: { value: '进入教学', action: () => { finish(true); } }
      });
    } catch (error) { this.tutorialPromptOpen = false; throw error as Error; }
  }
  aboutToDisappear(): void { this.albums.close(); }
  private albumColumns(): number { return Math.max(2, Math.floor((this.albumAreaWidth + 12) / 124)); }
  private albumRows(): GalleryAlbum[][] {
    const columns = this.albumColumns();
    const rows: GalleryAlbum[][] = [];
    for (let start = 0; start < this.albums.albums.length; start += columns) {
      rows.push(this.albums.albums.slice(start, start + columns));
    }
    return rows;
  }
  private emptyAlbumSlots(used: number): number[] {
    const slots: number[] = [];
    for (let index = used; index < this.albumColumns(); index++) {
      slots.push(index);
    }
    return slots;
  }
  private async begin(album?: GalleryAlbum): Promise<void> {
    if (this.opening || this.initializingAccess) { return; }
    this.opening = true;
    try {
      await this.getUIContext().getRouter().pushUrl({ url: 'pages/PhotoReview', params: { source: 0, album } });
    } catch (_) { this.getUIContext().getPromptAction().showToast({ message: '整理页打开失败，请重试。' }); }
    finally { this.opening = false; }
  }
  @Builder
  homePage() {
    Scroll() {
      Column({ space: 24 }) {
        Column({ space: 8 }) {
          Text('拾光整理').fontSize(AppTheme.titleSize).fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
        }.width('100%').alignItems(HorizontalAlign.Start).padding({ top: 24, bottom: 8 })
        Column({ space: 20 }) {
          Column({ space: 8 }) {
            Row({ space: 16 }) {
              AppIcon({ source: $r('app.media.lucide_images_accent'), iconSize: 32 })
              Column({ space: 6 }) {
                Text('从一张照片开始').fontSize(22).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
              }.layoutWeight(1).alignItems(HorizontalAlign.Start)
            }.width('100%')
            Button('开始整理').type(ButtonType.Capsule).buttonStyle(ButtonStyleMode.TEXTUAL).border({ radius: 999, width: 1, color: $r('sys.color.ohos_id_color_list_separator') }).fontColor($r('app.color.accent')).width('100%').constraintSize({ minHeight: 52 }).fontSize(16)
              .fontColor($r('app.color.accent'))
              .enabled(!this.opening && !this.initializingAccess && !this.albums.loading).onClick(() => { this.begin(); })
          }.padding(24).width('100%').borderRadius(AppTheme.cardRadius).backgroundColor($r('app.color.surface'))
          Column({ space: 12 }) {
            Row({ space: 8 }) {
              Text('整理来源').fontSize(20).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary')).layoutWeight(1)
              Button('新建').type(ButtonType.Capsule).buttonStyle(ButtonStyleMode.TEXTUAL).border({ radius: 999, width: 1, color: $r('sys.color.ohos_id_color_list_separator') }).constraintSize({ minHeight: 44, minWidth: 48 })
                .padding({ left: 8, right: 8 }).responseRegion({ x: 0, y: -2, width: '100%', height: 48 }).fontColor($r('app.color.text_primary')).onClick(() => { this.newAlbum(); })
              Button('刷新').type(ButtonType.Capsule).buttonStyle(ButtonStyleMode.TEXTUAL).border({ radius: 999, width: 1, color: $r('sys.color.ohos_id_color_list_separator') }).constraintSize({ minHeight: 44, minWidth: 48 })
                .padding({ left: 8, right: 8 }).responseRegion({ x: 0, y: -2, width: '100%', height: 48 })
                .fontColor($r('app.color.text_primary')).enabled(!this.albums.loading)
                .onClick(() => { this.albums.refresh(); })
            }.width('100%').constraintSize({ minHeight: 48 })
            if (this.albums.loading) {
              LoadingProgress().width(32).height(32).color($r('app.color.loading_indicator')).accessibilityText('正在读取相册')
            }
            if (this.albums.error) {
              Text(this.albums.error).fontSize(14).fontColor($r('app.color.text_secondary')).width('100%')
            }
            if (!this.albums.authorized && !this.albums.loading) {
              Column({ space: 8 }) {
                Text('允许访问图库后，按相册选择要整理的照片').fontSize(14).fontColor($r('app.color.text_secondary'))
                Button('允许访问图库').type(ButtonType.Capsule).buttonStyle(ButtonStyleMode.TEXTUAL).border({ radius: 999, width: 1, color: $r('sys.color.ohos_id_color_list_separator') }).fontColor($r('app.color.accent')).constraintSize({ minHeight: 48 }).onClick(() => { this.albums.refresh(true); })
                Button('前往权限设置').type(ButtonType.Capsule).buttonStyle(ButtonStyleMode.TEXTUAL).border({ radius: 999, width: 1, color: $r('sys.color.ohos_id_color_list_separator') }).constraintSize({ minHeight: 48 })
                  .fontColor($r('app.color.text_primary')).onClick(() => { this.albums.refresh(true, true); })
              }.padding(16).width('100%').backgroundColor($r('app.color.surface')).borderRadius(AppTheme.cardRadius)
            } else if (this.albums.authorized) {
              if (!this.albums.loading && !this.albums.error && this.albums.albums.length === 0) {
                Text('图库中暂无可展示的相册').fontSize(14).fontColor($r('app.color.text_secondary')).width('100%')
              }
              Column({ space: 20 }) {
                ForEach(this.albumRows(), (row: GalleryAlbum[]) => {
                  Row({ space: 12 }) {
                    ForEach(row, (album: GalleryAlbum) => {
                      Column() {
                        GalleryAlbumTile({ album: album, activated: () => { this.begin(album); } })
                          .enabled(!this.albums.loading && !this.opening)
                      }.layoutWeight(1)
                    }, (album: GalleryAlbum) => JSON.stringify(album))
                    ForEach(this.emptyAlbumSlots(row.length),
                      (index: number) => { Blank().layoutWeight(1) }, (index: number) => String(index))
                  }.width('100%').alignItems(VerticalAlign.Top)
                }, (row: GalleryAlbum[]) => JSON.stringify([this.albumColumns(), row]))
              }.width('100%').onAreaChange((_old: Area, area: Area) => { if (Number(area.width) > 0) { this.albumAreaWidth = Number(area.width); } })
            }
          }.width('100%')
        }
      }.padding({ left: AppTheme.pagePadding, right: AppTheme.pagePadding, bottom: 112 }).width('100%')
        .constraintSize({ maxWidth: 720 })
    }.width('100%').height('100%').align(Alignment.Top).edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true }).scrollBar(BarState.Auto)
  }

  @Builder
  minePage() {
    Scroll() {
      Column({ space: 24 }) {
        Column({ space: 8 }) {
          Text('我的').fontSize(AppTheme.titleSize).fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))

        }.width('100%').alignItems(HorizontalAlign.Start).padding({ top: 24, bottom: 8 })
        // 单机版暂不显示登录、头像及退出账号入口。
        // HuaweiAccountCard()
        Column() {
          SettingsRow({ title: '设置', icon: $r('app.media.lucide_settings'), divider: true,
            activated: () => { this.getUIContext().getRouter().pushUrl({ url: 'pages/Settings' }); } })
        }.width('100%').borderRadius(AppTheme.cardRadius).clip(true)
        Column() {
          SettingsRow({ title: '关于本应用', icon: $r('app.media.lucide_info'), activated: () => { this.getUIContext().getRouter().pushUrl({ url: 'pages/About' }); } })
        }.width('100%').borderRadius(AppTheme.cardRadius).clip(true)
      }.padding({ left: AppTheme.pagePadding, right: AppTheme.pagePadding, bottom: 24 }).width('100%')
        .constraintSize({ maxWidth: 720 })
    }.width('100%').height('100%').align(Alignment.Top).edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true }).scrollBar(BarState.Auto)
  }

  pageTransition() {
    PageTransitionEnter(FULL_SCREEN_FADE).opacity(0)
    PageTransitionExit(FULL_SCREEN_FADE).opacity(0)
  }

  build() {
    HdsTabs({ controller: this.tabsController }) {
      TabContent() {
        this.homePage()
      }.tabBar(new BottomTabBarStyle($r('app.media.lucide_house'), '整理')
        .labelStyle({ selectedColor: $r('app.color.accent'), unselectedColor: $r('app.color.text_secondary') }))
      TabContent() {
        MemoriesHome({ active: this.tab === 1 && this.visible, refreshKey: this.memoryRefresh })
      }.tabBar(new BottomTabBarStyle($r('app.media.lucide_images'), '回忆')
        .labelStyle({ selectedColor: $r('app.color.accent'), unselectedColor: $r('app.color.text_secondary') }))
      TabContent() {
        this.minePage()
      }.tabBar(new BottomTabBarStyle($r('app.media.lucide_user_round'), '我的')
        .labelStyle({ selectedColor: $r('app.color.accent'), unselectedColor: $r('app.color.text_secondary') }))
    }
      .width('100%').height('100%').barOverlap(true).vertical(false).barPosition(BarPosition.End)
      .barFloatingStyle({
        barWidth: { smallWidth: 240, mediumWidth: 256, largeWidth: 280 },
        barBottomMargin: 12,
        systemMaterialEffect: {
          materialType: hdsMaterial.MaterialType.ADAPTIVE,
          materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
        }
      })
      .onChange((index: number) => { this.tab = index; })
      .backgroundColor($r('app.color.console_background'))
  }
}
