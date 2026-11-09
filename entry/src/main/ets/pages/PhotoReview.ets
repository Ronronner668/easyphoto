import { TitleButtonMaterial } from '../common/TitleButtonMaterial';
import { SettingsRow } from '../components/SettingsRow';
import { FULL_SCREEN_FADE, UI_SPRING } from '../common/UiMotion';
import { targetCapacity, targetColumnIndexes } from '../domain/usecases/TargetAlbumOrder';
import { ReviewLocatorViewModel, LocatorRow, LocatorEntry } from '../viewmodels/ReviewLocatorViewModel';
import { PhotoPlaceReader } from '../platform/media/PhotoPlaceReader';
import { PhotoThumbnail } from '../components/PhotoThumbnail';
import { AppTheme } from '../common/AppTheme';
import { AppIcon } from '../components/AppIcon';
import { common } from '@kit.AbilityKit';
import { PhotoReviewViewModel } from '../viewmodels/PhotoReviewViewModel';
import { Category } from '../domain/models/Category';
import { DiscardMark } from '../domain/models/DiscardMark';
import { DropZone } from '../domain/usecases/DropTarget';
import { WorkbenchPreferences } from '../data/repositories/WorkbenchPreferences';
import { PhotoDeck } from '../components/PhotoDeck';
import { PhotoViewer } from '../components/PhotoViewer';
import { photoInfoRows } from '../domain/models/PhotoInfoSettings';
import { PhotoDetails } from '../components/PhotoDetails';
import { GalleryAlbum } from '../domain/models/GalleryAlbum';
import { reportSummary } from '../domain/usecases/ReportSummary';
import { supportsGalleryFavorite } from '../platform/media/GalleryFavorite';
import { PhotoInfoText } from '../components/PhotoInfoText';

interface ReviewRoute { source?: number; album?: GalleryAlbum; practice?: boolean; }

@Entry
@Component
struct PhotoReview {
  @State model: PhotoReviewViewModel = new PhotoReviewViewModel();
  @State private practice: boolean = false;
  @State appliedSource: number = 0;
  @State hovering: string = '';
  @State layout: number = 0;
  @State markPreview: string = '';
  @State fullScreen: boolean = false;
  @State details: boolean = false;
  @State startPicker: boolean = false;
  @State moreOpen: boolean = false;
  @State locatorRows: LocatorRow[] = [];
  @State placeBusy: boolean = false;
  @State placeFeedback: string = '';
  private placeVersion: number = 0;
  @State locatorHeight: number = 400;
  @State locatorOffset: number = 16;
  @State locatorDate: string = '';
  @State locatorScrolling: boolean = false;
  @State locator: ReviewLocatorViewModel = new ReviewLocatorViewModel();
  @State activeTarget: string = '';
  @State pressedTarget: string = '';
  @State ending: boolean = false;
  @State preferencesReady: boolean = false;
  @State preferencesLoading: boolean = true;
  @State reportShown: boolean = false;
  private preferenceVersion: number = 0;
  private pageDisposed: boolean = false;
  private pageVisible: boolean = false;
  private exitPrompt: boolean = false;
  private practiceFinishDialog: boolean = false;
  private completingExit: boolean = false;
  private favoriteSupported: boolean = supportsGalleryFavorite();
  private zones: DropZone[] = [];
  private zonesOrder: string = '';
  private pendingMoreAction: (() => void) | undefined = undefined;
  private targetSignature(): string { return JSON.stringify([this.layout, this.model.selectedTargetRefs]); }
  private store: WorkbenchPreferences | undefined = undefined;
  private titleMaterial: TitleButtonMaterial = new TitleButtonMaterial();

  aboutToAppear(): void {
    this.titleMaterial.initialize();
    this.pageDisposed = false;
    const params = this.getUIContext().getRouter().getParams() as ReviewRoute | undefined;
    if (params?.practice === true) {
      this.practice = true;
      this.preferencesReady = true;
      this.preferencesLoading = false;
      this.model.initializePractice();
      return;
    }
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    this.model.initialize(context);
    this.store = new WorkbenchPreferences(context);
    this.start();
  }
  private async start(): Promise<void> {
    await this.refreshPreferences();
    const params = this.getUIContext().getRouter().getParams() as ReviewRoute;
    this.appliedSource = params?.source === 1 ? 1 : 0;
    this.model.setSourceAlbum(params?.album);
    if (this.appliedSource === 1) { await this.model.choose(); }
    else { await this.model.loadLibrary(); }
  }
  private async refreshPreferences(): Promise<void> {
    if (!this.store) { return; }
    const version = ++this.preferenceVersion; this.preferencesLoading = true;
    try {
      const keep = await this.store.loadKeepOriginal(); const layout = await this.store.loadLayout();
      if (!this.pageDisposed && version === this.preferenceVersion) { this.layout = layout; this.model.keepOriginal = keep; this.model.targetCapacity = targetCapacity(layout); this.model.configurePlace(false); this.preferencesReady = true; }
    } catch (_) { if (!this.pageDisposed && version === this.preferenceVersion) { this.preferencesReady = false; this.getUIContext().getPromptAction().showToast({ message: '设置读取失败，未执行分类或处理原图，请重试。' }); } }
    finally { if (!this.pageDisposed && version === this.preferenceVersion) { this.preferencesLoading = false; } }
  }
  private async openTargets(): Promise<void> {
    try { await this.getUIContext().getRouter().pushUrl({ url: 'pages/TargetAlbums', params: { capacity: targetCapacity(this.layout) } }); }
    catch (_) { if (!this.pageDisposed) { this.getUIContext().getPromptAction().showToast({ message: '目标相册页未能打开，请稍后重试。' }); } }
  }
  private async openLayoutSettings(): Promise<void> {
    try { await this.getUIContext().getRouter().pushUrl({ url: 'pages/Settings', params: { openLayout: true } }); }
    catch (_) {
      if (!this.pageDisposed) { this.getUIContext().getPromptAction().showToast({ message: '整理布局设置未能打开，请稍后重试。' }); }
    }
  }
  private openStart(): void {
    this.locatorRows = []; this.locatorDate = ''; this.startPicker = true;
    this.locator.initialize(reference => this.model.describeStart(reference));
    this.locator.updated = () => { if (!this.pageDisposed && this.startPicker) { this.locatorRows = this.locator.rows(); } };
    this.locator.refresh(this.model.session.items);
  }
  private closeDetails(): void {
    this.placeVersion++;
    this.placeBusy = false;
    this.details = false;
  }
  private async readPlace(): Promise<void> {
    if (this.practice) { return; }
    const reference = this.model.photo?.uri;
    if (!reference || reference.startsWith('file://docs/') || this.placeBusy || !this.details) { return; }
    const version = ++this.placeVersion;
    this.placeBusy = true;
    this.placeFeedback = '';
    try {
      const reader = new PhotoPlaceReader(this.getUIContext().getHostContext() as common.UIAbilityContext);
      const result = await reader.read(reference);
      if (version === this.placeVersion && this.model.photo?.uri === reference) { this.placeFeedback = result.text; }
    } catch (_) {
      if (version === this.placeVersion) { this.placeFeedback = '无地理位置信息'; }
    } finally {
      if (version === this.placeVersion) { this.placeBusy = false; }
    }
  }
  private batchOverlay(): boolean {
    return this.model.batchEnded && !this.model.showSummary && !this.moreOpen && !this.startPicker &&
      !this.details && !this.fullScreen && !this.markPreview && !this.reportShown && !this.ending;
  }
  private closeStart(): void { this.startPicker = false; this.locator.close(); }
  private targetSide(column: number): Category[] { const targets = this.model.selectedTargets(); return targetColumnIndexes(targets.length, column).map(index => targets[index]); }
  @Builder
  moreItem(title: string, icon: Resource, activated: () => void, available: boolean, divider: boolean = false) {
    SettingsRow({ title, icon, available, divider,
      activated: () => { this.pendingMoreAction = activated; this.moreOpen = false; } })
  }
  @Builder
  moreMenu() {
    Scroll() {
      Column({ space: 12 }) {
        if (this.model.practiceHint()) {
          Column() {
            this.moreItem(this.model.practiceHint()!.alternative, $r('app.media.lucide_images'),
              () => { this.model.performPracticeHint(); }, true, true)
            this.moreItem('跳过指引', $r('app.media.lucide_info'), () => { this.model.skipPracticeGuide(); }, true)
          }.width('100%').borderRadius(AppTheme.cardRadius).clip(true)
        }
        Text('整理导航').fontSize(14).fontColor($r('app.color.text_secondary')).width('100%').padding({ left: 16 })
        Column() {
          this.moreItem('定位整理起点', $r('app.media.lucide_scan_search'), () => { this.openStart(); },
            !this.model.practiceHint() && this.model.session.items.length > 0, true)
          this.moreItem('选择目标相册', $r('app.media.lucide_images'), () => { this.openTargets(); }, !this.practice, true)
          this.moreItem('整理布局调整', $r('app.media.lucide_layout_grid'), () => { this.openLayoutSettings(); }, !this.practice)
        }.width('100%').borderRadius(AppTheme.cardRadius).clip(true)
        Text('照片操作').fontSize(14).fontColor($r('app.color.text_secondary')).width('100%').padding({ left: 16 })
        Column() {
          this.moreItem('照片详细信息', $r('app.media.lucide_info'), () => {
            if (this.model.photo && !this.model.showSummary) { this.placeFeedback = ''; this.details = true; this.model.loadStoragePath(); this.readPlace(); }
          }, !!this.model.photo && !this.model.showSummary, true)
          this.moreItem('分享当前照片', $r('app.media.lucide_share_2'), async () => {
            await this.model.shareCurrent();
            if (this.model.operationFeedback) { this.getUIContext().getPromptAction().showToast({ message: this.model.operationFeedback }); }
          }, !this.practice && !!this.model.photo && !this.model.showSummary)
        }.width('100%').borderRadius(AppTheme.cardRadius).clip(true)
      }.padding({ left: 16, right: 16, top: 8, bottom: 24 }).width('100%')
    }.width('100%').constraintSize({ maxHeight: 520 }).edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
  }
  private targetLabel(category: Category): string {
    return category.name;
  }
  private targetType(category: Category): string { return this.practice ? '示例相册' : this.model.isSampleTarget(category.id) ? '样例占位，不整理照片' : '系统相册'; }
  private highlighted(id: string): boolean { return this.hovering === id || this.activeTarget === id || this.pressedTarget === id; }
  @Builder
  targetButton(category: Category, side: boolean) {
    Button() {
      if (side) {
        Row({ space: 8 }) {
          AppIcon({ source: this.highlighted(category.id) ? $r('app.media.lucide_images_accent') : $r('app.media.lucide_images'), iconSize: 22 })
          Column({ space: 2 }) {
            Text(this.targetLabel(category)).fontSize(14).fontColor(this.highlighted(category.id) ? $r('app.color.accent') : $r('app.color.text_primary')).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        }.padding(8).width('100%')
      } else {
      Column({ space: 5 }) {
        AppIcon({ source: this.highlighted(category.id) ? $r('app.media.lucide_images_accent') : $r('app.media.lucide_images') })
        Text(this.targetLabel(category)).fontSize(13).fontColor(this.highlighted(category.id) ? $r('app.color.accent') : $r('app.color.text_primary')).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
      }.padding(8)
      }
    }.width(side ? '100%' : '31%').constraintSize({ minHeight: side ? 80 : 116 })
      .type(ButtonType.ROUNDED_RECTANGLE)
      .buttonStyle(this.highlighted(category.id) ? ButtonStyleMode.NORMAL : ButtonStyleMode.TEXTUAL)
      .border({ radius: side ? 40 : 32, width: 1,
        color: this.highlighted(category.id) ? $r('app.color.accent') : $r('sys.color.ohos_id_color_list_separator') })
      .accessibilityText('整理到' + this.targetLabel(category) + '，' + this.targetType(category)).accessibilityDescription(this.model.isSampleTarget(category.id) ? '点击选择真实目标相册，选择顺序对应样例序号' : this.activeTarget === category.id ? '正在处理' : '点击分类，也可拖入照片')
      .fontColor($r('app.color.text_primary')).enabled(this.preferencesReady && this.model.targetsReady && !this.model.marksBusy && (this.model.isSampleTarget(category.id) ? !this.model.busy : (this.practice || !!category.album) && this.model.categoriesReady && !!this.model.photo && (!this.model.busy || this.activeTarget === category.id)))
      .onClick(() => { if (this.model.isSampleTarget(category.id)) { this.openTargets(); } else { this.checkTarget(category.id); } })
      .onTouch((event: TouchEvent) => { this.pressedTarget = event.type === TouchType.Down ? category.id : ''; })
      .onAreaChange((_old: Area, area: Area) => {
        const signature = this.targetSignature();
        if (signature !== this.zonesOrder) { this.zones = []; this.zonesOrder = signature; }
        this.zones = this.zones.filter((zone: DropZone) => zone.id !== category.id);
        this.zones.push(new DropZone(category.id, Number(area.globalPosition.x), Number(area.globalPosition.y), Number(area.width), Number(area.height)));
      })
  }
  private async checkTarget(id: string, dragged: boolean = false): Promise<void> {
    if (!this.preferencesReady) { this.getUIContext().getPromptAction().showToast({ message: '请先重新读取整理设置，未执行分类。' }); return; }
    if (this.model.busy) { return; }
    if (this.model.isSampleTarget(id)) { this.getUIContext().getPromptAction().showToast({ message: '请点击样例或在更多中选择目标相册。' }); return; }
    const target = this.model.selectedTargets().find(item => item.id === id);
    if (!this.model.categoriesReady || !this.model.targetsReady || !target || (!this.practice && !target.album)) {
      this.getUIContext().getPromptAction().showToast({ message: '此目标相册已不可用，请在更多中重新选择。' }); return;
    }
    this.activeTarget = id;
    try { await this.model.organize(id, dragged); } finally { this.activeTarget = ''; }
    if (this.model.operationFeedback) {
      this.getUIContext().getPromptAction().showToast({ message: this.model.operationFeedback });
    }
  }
  private showReport(): void {
    if (this.pageDisposed || this.reportShown) { return; }
    const report = this.model.report();
    if (!report.organized && !report.recycled) { this.getUIContext().getRouter().back({ url: 'pages/Index' }); return; }
    this.reportShown = true;
    const leave = (): void => { if (!this.pageDisposed) { this.getUIContext().getRouter().back({ url: 'pages/Index' }); } };
    const viewMemories = (): void => {
      AppStorage.setOrCreate<boolean>('openMemories', true);
      leave();
    };
    this.getUIContext().showAlertDialog({ title: '整理报告', message: reportSummary(report), autoCancel: false,
      buttons: report.organized > 0 ? [
        { value: '完成', action: leave },
        { value: '回看相册', action: viewMemories }
      ] : [{ value: '完成', action: leave }], cancel: leave });
  }
  private async completeExit(approvedReferences: string[] = []): Promise<void> {
    if (this.completingExit || this.pageDisposed) { return; }
    this.completingExit = true;
    this.exitPrompt = false;
    try {
      try { this.model.keepOriginal = await this.store!.loadKeepOriginal(); }
      catch (_) { if (!this.pageDisposed) { this.getUIContext().getPromptAction().showToast({ message: '原图保留设置读取失败，本次未处理原图。' }); } return; }
      if (this.pageDisposed) { return; }
      if (!await this.model.saveLastClassification()) {
        if (!this.pageDisposed && this.model.operationFeedback) {
          this.getUIContext().getPromptAction().showToast({ message: this.model.operationFeedback });
        }
        return;
      }
      if (this.pageDisposed) { return; }
      if (approvedReferences.length > 0) {
        const requested = new Set(approvedReferences);
        await this.model.trashMarked(undefined, approvedReferences);
        if (this.pageDisposed) { return; }
        if (!this.model.marksReady || this.model.marks.some(mark => requested.has(mark.reference))) {
          this.model.showSummary = true;
          return;
        }
      }
      const protectedSources = this.model.marks.map(mark => mark.reference);
      const finished = await this.model.finishRound(protectedSources);
      if (this.pageDisposed) { return; }
      if (finished) { this.showReport(); }
      else if (this.model.operationFeedback) { this.getUIContext().getPromptAction().showToast({ message: this.model.operationFeedback }); }
    } finally { this.completingExit = false; if (!this.pageDisposed) { this.ending = false; } }
  }
  private async endRound(): Promise<void> {
    if (this.practice) {
      if (this.model.practiceCompletionPending) { this.confirmPracticeFinish(); }
      else { this.getUIContext().getRouter().back(); }
      return;
    }
    if (!this.preferencesReady && (this.model.staged.length > 0 || this.model.hasLastClassification())) { this.getUIContext().getPromptAction().showToast({ message: '设置尚未读取，未处理原图，请重新读取设置。' }); return; }
    if (this.ending || this.exitPrompt || this.reportShown || this.model.busy || this.model.marksBusy || this.pageDisposed) { return; }
    this.ending = true;
    await this.model.refreshMarks();
    if (this.pageDisposed) { return; }
    if (!this.model.marksReady) {
      this.ending = false; this.getUIContext().getPromptAction().showToast({ message: this.model.marksMessage }); return;
    }
    const galleryMarks = this.model.marks.filter(mark => this.model.canTrashMark(mark));
    const hasClassification = this.model.hasLastClassification() || this.model.staged.length > 0;
    if (!galleryMarks.length && !hasClassification) { await this.completeExit(); return; }
    this.exitPrompt = true;
    const messages: string[] = [];
    if (hasClassification) {
      messages.push(this.model.keepOriginal ? '分类后将复制原图至目标相册' : '分类后将复制原图至目标相册再删除原图');
    }
    if (galleryMarks.length > 0) { messages.push(`手动标记可回收 ${galleryMarks.length} 张`); }
    if (galleryMarks.length > 100) { messages.push('手动标记超过 100 张，系统可能多次确认。'); }
    const cancel = (): void => { this.exitPrompt = false; this.ending = false; };
    this.getUIContext().showAlertDialog({
      title: '结束整理？', message: messages.join('\n'),
      autoCancel: false, cancel, buttons: galleryMarks.length > 0 ? [
        { value: '结束并回收手动标记', action: () => { this.completeExit(galleryMarks.map(mark => mark.reference)); } },
        { value: '结束并保留手动标记', action: () => { this.completeExit(); } },
        { value: '继续整理', action: cancel }
      ] : [
        { value: '继续整理', action: cancel },
        { value: '确认结束', action: () => { this.completeExit(); } }
      ]
    });
  }
  private async recycleMarked(): Promise<void> {
    const approved = this.model.marks.filter(mark => this.model.canTrashMark(mark)).map(mark => mark.reference);
    const count = approved.length;
    if (!this.model.marksReady || this.model.busy || !count) { return; }
    if (count <= 100) { await this.model.trashMarked(); return; }
    this.getUIContext().showAlertDialog({
      title: `回收 ${count} 张照片？`,
      message: '每批最多 100 张，系统可能多次确认。中途取消时，已完成的批次会保留结果。',
      primaryButton: { value: '取消', action: () => {} },
      secondaryButton: { value: '继续', action: () => { this.model.trashMarked(undefined, approved); } }
    });
  }
  private visibleZones(): DropZone[] {
    if (this.zonesOrder !== this.targetSignature()) { return []; }
    const ids = this.model.selectedTargets().map(item => item.id);
    return this.zones.filter(zone => ids.includes(zone.id));
  }
  private confirmPracticeFinish(): void {
    if (this.pageDisposed || this.practiceFinishDialog) { return; }
    this.practiceFinishDialog = true;
    const cancel = (): void => { this.practiceFinishDialog = false; };
    this.getUIContext().showAlertDialog({
      title: '结束整理？',
      message: '已完成第五张照片的收藏。',
      cancel,
      primaryButton: { value: '取消', action: cancel },
      secondaryButton: { value: '确认结束', action: () => { this.showPracticeFinish(); } }
    });
  }
  private showPracticeFinish(): void {
    if (this.pageDisposed) { return; }
    const continuePractice = (): void => {
      this.practiceFinishDialog = false;
      this.model.continueFreePractice();
    };
    this.getUIContext().showAlertDialog({
      title: '练习结束',
      message: '接下来可以自由练习，也可以直接退出。之后可在「设置 → 整理练习」再次体验。',
      autoCancel: false,
      cancel: continuePractice,
      primaryButton: { value: '退出练习', action: () => {
        this.practiceFinishDialog = false;
        this.getUIContext().getRouter().back();
      } },
      secondaryButton: { value: '自由练习', action: continuePractice }
    });
  }
  async onPageShow(): Promise<void> {
    this.pageVisible = true;
    if (this.practice) { return; }
    await this.refreshPreferences(); if (this.pageDisposed || !this.pageVisible) { return; }
    this.model.recheck(); this.model.refreshCategories(); this.model.refreshStaged();
  }
  onPageHide(): void { this.pageVisible = false; }
  aboutToDisappear(): void { this.onPageHide(); this.pageDisposed = true; this.placeVersion++; this.pendingMoreAction = undefined; this.preferenceVersion++; this.locator.close(); this.model.dispose(); }
  onBackPress(): boolean {
    if (this.moreOpen) { this.moreOpen = false; return true; }
    if (this.startPicker) { this.closeStart(); return true; }
    if (this.markPreview) { this.markPreview = ''; return true; }
    if (this.ending || this.model.busy || this.model.marksBusy) { return true; }
    if (this.details) { this.closeDetails(); return true; }
    if (this.fullScreen) { this.fullScreen = false; return true; }
    if (this.model.showSummary) { this.model.showSummary = false; return true; }
    if (this.practice) { return false; }
    if (this.reportShown) { return true; }
    this.endRound(); return true;
  }
  private metadata(): string[] {
    if (this.practice) {
      const title = `整理练习 · ${this.model.session.index + 1}/${this.model.session.items.length}`;
      return [title, this.model.practiceCompletionPending ? '已收藏，请点击下方「结束整理」。' : this.model.practiceHint()?.hint || '自由练习 · 操作仅对示例生效'];
    }
    const photo = this.model.photo;
    if (!photo) { return []; }
    return photoInfoRows(photo);
  }
  pageTransition() {
    PageTransitionEnter(FULL_SCREEN_FADE).opacity(0)
    PageTransitionExit(FULL_SCREEN_FADE).opacity(0)
  }

  @Builder
  reviewTitle() {
    Row({ space: 8 }) {
      Button({ type: ButtonType.Circle }) {
        AppIcon({ source: $r('app.media.lucide_arrow_left'), iconSize: 20 })
      }.width(44).height(44).flexShrink(0).padding(0)
        .responseRegion({ x: -2, y: -2, width: 48, height: 48 }).buttonStyle(ButtonStyleMode.TEXTUAL).attributeModifier(this.titleMaterial).accessibilityText('返回')
        .enabled(!this.model.busy && !this.model.marksBusy)
        .onClick(() => { if (!this.onBackPress()) { this.getUIContext().getRouter().back(); } })
      if (this.model.showSummary) {
        Text('待删除汇总').fontSize(18).fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary')).layoutWeight(1).textAlign(TextAlign.Center)
        Blank().width(44).flexShrink(0)
      } else {
        Column({ space: 4 }) {
          Text(this.metadata()[0] || '等待照片').fontSize(18).fontWeight(FontWeight.Medium).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).fontColor($r('app.color.text_primary')).width('100%').textAlign(TextAlign.Start)
          Text(this.metadata()[1] || '').fontSize(13).maxLines(this.practice ? 3 : 1).textOverflow({ overflow: TextOverflow.Ellipsis }).fontColor($r('app.color.text_secondary')).width('100%').textAlign(TextAlign.Start)
        }.layoutWeight(1).alignItems(HorizontalAlign.Center).clip(true)
        Button({ type: ButtonType.Circle }) {
          AppIcon({ source: this.model.photo?.favorite ? $r('app.media.lucide_heart_accent') : $r('app.media.lucide_heart'), iconSize: 20 })
        }.width(44).height(44).flexShrink(0).padding(0)
        .responseRegion({ x: -2, y: -2, width: 48, height: 48 }).buttonStyle(ButtonStyleMode.TEXTUAL).attributeModifier(this.titleMaterial)
          .accessibilityText(this.practice ? (this.model.photo?.favorite ? '取消示例收藏' : '收藏示例照片') : this.model.photo?.favorite ? '取消系统收藏' : '收藏到系统图库')
          .enabled(!!this.model.photo && !this.model.practiceHint() && !this.model.photo!.uri.startsWith('file://docs/') && !this.model.busy && !this.model.marksBusy && !this.model.showSummary)
          .onClick(async () => { if (!this.practice && !this.favoriteSupported) { this.getUIContext().getPromptAction().showToast({ message: '当前系统不支持应用内系统收藏，请使用系统图库。' }); return; } await this.model.toggleFavorite(); if (this.model.operationFeedback) { this.getUIContext().getPromptAction().showToast({ message: this.model.operationFeedback }); } })
        Button({ type: ButtonType.Circle }) {
          AppIcon({ source: $r('app.media.lucide_ellipsis'), iconSize: 20 })
        }.width(44).height(44).flexShrink(0).padding(0)
        .responseRegion({ x: -2, y: -2, width: 48, height: 48 }).buttonStyle(ButtonStyleMode.TEXTUAL).attributeModifier(this.titleMaterial).accessibilityText('更多操作')
          .enabled(!this.model.busy && !this.model.marksBusy)
          .onClick(() => { if (!this.model.practiceCompletionPending) { this.moreOpen = true; } })
          .bindSheet($$this.moreOpen, this.moreMenu(), { height: SheetSize.FIT_CONTENT, preferType: SheetType.BOTTOM, showClose: true,
            title: { title: '更多操作' }, backgroundColor: $r('app.color.console_background'),
            onDisappear: () => { const action = this.pendingMoreAction; this.pendingMoreAction = undefined; if (!this.pageDisposed) { action?.(); } } })
      }
    }.width('100%').height('100%').padding({ left: AppTheme.pagePadding, right: AppTheme.pagePadding })
  }

  build() {
    Stack() {
      Navigation() {
        Column({ space: 12 }) {
        if (!this.preferencesReady && !this.preferencesLoading) {
          Button('重新读取整理设置').type(ButtonType.Capsule).buttonStyle(ButtonStyleMode.TEXTUAL).border({ radius: 999, width: 1, color: $r('sys.color.ohos_id_color_list_separator') }).constraintSize({ minHeight: 48 }).width('100%').onClick(() => { this.refreshPreferences(); })
        }
        if (!this.model.marksReady && !this.model.marksBusy) {
          Text(this.model.marksMessage).fontSize(14).width('100%').fontColor($r('app.color.warning'))
          Button('重新读取待删除标记').type(ButtonType.Capsule).buttonStyle(ButtonStyleMode.TEXTUAL).border({ radius: 999, width: 1, color: $r('sys.color.ohos_id_color_list_separator') }).constraintSize({ minHeight: 48 }).enabled(!this.model.busy).onClick(() => { this.model.refreshMarks(); })
        }
        if (this.model.markError && this.model.marksReady) {
          Text(this.model.markError).fontSize(14).width('100%').fontColor($r('app.color.warning'))
        }
        if (this.model.markNotice && !this.model.markError && this.model.marksReady) {
          Text(this.model.markNotice).fontSize(14).width('100%').fontColor($r('app.color.text_secondary'))
        }
        if (this.model.trashProgress) {
          Text(this.model.trashProgress).fontSize(14).width('100%').fontColor($r('app.color.text_primary'))
        }
        if (this.model.showSummary) {
          Scroll() {
            Column({ space: 16 }) {
              Text(`共 ${this.model.marks.length} 张`).fontSize(22).width('100%').textAlign(TextAlign.Center)
              Text(this.practice ? '练习中的待删除标记仅在本次会话生效。' : '移入系统回收站后仍可在系统图库恢复。').fontSize(14).width('100%').textAlign(TextAlign.Center)
              if (this.model.trashResult) { Text(this.model.trashResult).fontSize(14).width('100%') }
              if (this.model.marksBusy) { LoadingProgress().width(24).height(24).color($r('app.color.loading_indicator')) }
              ForEach(this.model.marks, (mark: DiscardMark) => {
                Row({ space: 12 }) {
                  Button({ type: ButtonType.Normal }) {
                    PhotoThumbnail({ reference: mark.reference })
                  }.width(64).height(64).padding(0).borderRadius(10).clip(true).flexShrink(0)
                    .backgroundColor(Color.Transparent).accessibilityText(`放大查看 ${mark.name}`)
                    .onClick(() => { this.markPreview = mark.reference; })
                  Column({ space: 8 }) {
                  PhotoInfoText({ content: mark.name, textSize: 14, lines: 1 })
                  Row({ space: 8 }) {
                  Button('保留').type(ButtonType.Capsule).buttonStyle(ButtonStyleMode.TEXTUAL).border({ radius: 999, width: 1, color: $r('sys.color.ohos_id_color_list_separator') }).height(48).fontColor($r('app.color.text_primary')).enabled(this.model.marksReady && !this.model.marksBusy && !this.model.busy).onClick(() => { this.model.unmark(mark.reference); })
                  if (this.model.canTrashMark(mark)) {
                  Button('移入回收站').type(ButtonType.Capsule).buttonStyle(ButtonStyleMode.TEXTUAL).border({ radius: 999, width: 1, color: $r('sys.color.ohos_id_color_list_separator') }).constraintSize({ minHeight: 48 }).fontSize(14).fontColor($r('app.color.text_primary')).enabled(this.model.marksReady && !this.model.busy && !this.model.marksBusy).onClick(async () => { await this.model.trashMarked(mark.reference); })
                  }
                  }.width('100%')
                  if (!this.model.canTrashMark(mark)) {
                    Text(this.model.markIssue(mark)).fontSize(12).maxLines(3).textOverflow({ overflow: TextOverflow.Ellipsis }).fontColor($r('app.color.text_secondary')).width('100%')
                  }
                  }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                }.width('100%')
              }, (mark: DiscardMark) => mark.reference + mark.markedAt + mark.availability)
            }.padding(16).width('100%')
          }.align(Alignment.TopStart).layoutWeight(1).edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true }).transition(TransitionEffect.opacity(0).animation({ curve: UI_SPRING }))
          Button(`移入回收站 · ${this.model.marks.filter(mark => this.model.canTrashMark(mark)).length} 张`).type(ButtonType.Capsule).buttonStyle(ButtonStyleMode.TEXTUAL).border({ radius: 999, width: 1, color: $r('sys.color.ohos_id_color_list_separator') }).fontColor($r('app.color.accent')).height(48).width('100%').enabled(this.model.marksReady && !this.model.busy && !this.model.marksBusy && this.model.marks.some(mark => this.model.canTrashMark(mark)))
            .onClick(() => { this.recycleMarked(); })
          Button('继续浏览').type(ButtonType.Capsule).buttonStyle(ButtonStyleMode.TEXTUAL).border({ radius: 999, width: 1, color: $r('sys.color.ohos_id_color_list_separator') }).height(48).width('100%').fontColor($r('app.color.text_primary')).enabled(!this.model.busy).onClick(() => { this.model.showSummary = false; this.model.recheck(); })
        } else {
          Stack() {
            PhotoDeck({ model: this.model,
              zones: () => this.visibleZones(), dropped: (id: string) => { this.checkTarget(id, true); }, hovered: (id: string) => { this.hovering = id; }, opened: () => { if (!this.model.practiceCompletionPending) { this.fullScreen = true; } } })
          }.width('100%').layoutWeight(1).zIndex(10).transition(TransitionEffect.opacity(0).animation({ curve: UI_SPRING }))
          if (this.model.targetMessage) { Text(this.model.targetMessage).fontSize(13).maxLines(2).fontColor($r('app.color.text_secondary')).width('100%') }
          if (this.layout === 1) {
              Row() {
                Column({ space: 8 }) {
                  ForEach(this.targetSide(0), (category: Category) => { this.targetButton(category, true) }, (category: Category) => JSON.stringify(category) + this.targetSignature())
                }.width('46%')
                Blank()
                Column({ space: 8 }) {
                  ForEach(this.targetSide(1), (category: Category) => { this.targetButton(category, true) }, (category: Category) => JSON.stringify(category) + this.targetSignature())
                }.width('46%')
              }.width('100%').padding({ top: 4, bottom: 4 })
          } else {
            Row() {
              ForEach(this.model.selectedTargets(), (category: Category) => { this.targetButton(category, false) }, (category: Category) => JSON.stringify(category) + this.targetSignature())
            }.width('100%').justifyContent(FlexAlign.SpaceBetween).padding({ top: 8, bottom: 8 })
          }
          Row({ space: 12 }) {
          Button(this.practice && !this.model.practiceCompletionPending ? '结束练习' : this.ending ? '正在结束…' : '结束整理').type(ButtonType.Capsule).buttonStyle(ButtonStyleMode.TEXTUAL).border({ radius: 999, width: 1, color: $r('sys.color.ohos_id_color_list_separator') }).height(48).layoutWeight(1).fontColor($r('app.color.text_primary'))
            .enabled(!this.ending && !this.model.busy && !this.model.marksBusy).onClick(() => { this.endRound(); })
          Button(`待删除 · ${this.model.marks.length}`).type(ButtonType.Capsule).buttonStyle(ButtonStyleMode.TEXTUAL).border({ radius: 999, width: 1, color: $r('sys.color.ohos_id_color_list_separator') }).height(48).layoutWeight(1)
            .fontColor($r('app.color.accent')).enabled(!this.model.practiceHint() && !this.model.busy && !this.model.marksBusy)
            .onClick(() => { this.model.showSummary = true; this.model.refreshMarks(); })
          }.width('100%')
        }
        }.padding({ left: AppTheme.pagePadding, right: AppTheme.pagePadding, bottom: AppTheme.pagePadding })
          .width('100%').height('100%').backgroundColor($r('app.color.page_background'))
          .foregroundColor($r('app.color.text_primary'))
      }
        .title({ builder: this.reviewTitle, height: 80 }, { backgroundColor: $r('app.color.page_background') })
        .mode(NavigationMode.Stack).hideBackButton(true).hideToolBar(true)
        .width('100%').height('100%')
        .enabled(!this.ending && !this.reportShown && !this.markPreview && !this.details && !this.fullScreen && !this.startPicker && !this.batchOverlay())
      if (this.startPicker) {
        Column({ space: 12 }) {
          Row() {
            Text('定位整理起点').fontSize(22).layoutWeight(1).fontColor($r('app.color.text_primary'))
            Button({ type: ButtonType.Circle }) { AppIcon({ source: $r('app.media.lucide_x'), iconSize: 20 }) }
              .width(48).height(48).padding(0).buttonStyle(ButtonStyleMode.TEXTUAL).border({ radius: 24, width: 1, color: $r('sys.color.ohos_id_color_list_separator') }).accessibilityText('关闭整理起点').onClick(() => { this.closeStart(); })
          }.width('100%')
          if (this.locator.busy) { Text('正在读取照片日期…').fontSize(14).width('100%') }
          Stack({ alignContent: Alignment.TopEnd }) {
            List() {
              ForEach(this.locatorRows, (row: LocatorRow) => {
                ListItem() {
                  if (row.title) {
                    Text(row.title).fontSize(20).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary')).width('100%').padding({ top: 20, bottom: 16 })
                  } else {
                    Row({ space: 2 }) {
                      ForEach(row.items, (item: LocatorEntry) => {
                        Button({ type: ButtonType.Normal }) {
                          PhotoThumbnail({ reference: item.reference, fit: ImageFit.Cover }).width('100%').aspectRatio(1)
                        }.layoutWeight(1).aspectRatio(1).padding(0).backgroundColor(Color.Transparent).enabled(!this.model.busy)
                          .accessibilityText(`${item.date || '日期未提供'}，${item.name}，从此照片开始整理`)
                          .onClick(async () => { if (!this.model.busy) { this.closeStart(); await this.model.selectStart(item.reference); } })
                      }, (item: LocatorEntry) => item.reference)
                      if (row.items.length < 4) { ForEach([0, 1, 2].slice(0, 4 - row.items.length), (value: number) => { Blank().layoutWeight(1) }, (value: number) => `${value}`) }
                    }.width('100%')
                  }
                }
              }, (row: LocatorRow) => row.title || row.items[0].reference)
            }.width('100%').height('100%').edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true }).scrollBar(BarState.On)
              .onScrollIndex((first: number) => { this.locatorDate = this.locatorRows[first]?.date || '日期未提供'; this.locatorOffset = Math.max(0, this.locatorHeight - 48) * first / Math.max(1, this.locatorRows.length - 1); })
              .onScrollStart(() => { this.locatorScrolling = true; }).onScrollStop(() => { this.locatorScrolling = false; })
            if (this.locatorScrolling && this.locatorDate) {
              Text(this.locatorDate).fontSize(14).fontColor($r('app.color.text_primary')).padding(12).borderRadius(16).backgroundColor($r('app.color.surface')).margin({ right: 20, top: this.locatorOffset }).hitTestBehavior(HitTestMode.None)
            }
          }.width('100%').layoutWeight(1).onAreaChange((_old: Area, area: Area) => { this.locatorHeight = Number(area.height); })
          if (this.locator.failed > 0) { Button('重试读取照片信息').buttonStyle(ButtonStyleMode.TEXTUAL).constraintSize({ minHeight: 48 }).enabled(!this.locator.busy).onClick(() => { this.locator.refresh(this.model.session.items); }) }
          if (this.model.streamError) { Text(this.model.streamError).fontColor($r('app.color.text_secondary')) }
          if (this.model.hasMore) { Button(this.model.busy ? '正在读取…' : '加载更多', { type: ButtonType.Capsule })
            .height(48).width('100%').buttonStyle(ButtonStyleMode.TEXTUAL)
            .border({ radius: 24, width: 1, color: $r('sys.color.ohos_id_color_list_separator') })
            .enabled(!this.model.busy && !this.locator.busy).onClick(async () => { await this.model.extendStartChoices(); if (this.startPicker && !this.pageDisposed) { await this.locator.refresh(this.model.session.items); } }) }
        }.padding(20).width('100%').height('100%').backgroundColor($r('app.color.page_background')).zIndex(30).transition(TransitionEffect.opacity(0).animation(FULL_SCREEN_FADE))
      }
      if (this.markPreview) {
        PhotoViewer({ reference: this.markPreview, closed: () => { this.markPreview = ''; } })
      }
      if (this.fullScreen && this.model.photo) {
        PhotoViewer({ reference: this.model.photo!.uri, imageWidth: this.model.photo!.width, imageHeight: this.model.photo!.height, closed: () => { this.fullScreen = false; } })
      }
      if (this.details && this.model.photo) {
        PhotoDetails({ photo: this.model.photo!, dateFormat: 'YYYY年MM月DD日',
          status: this.model.currentMarked() ? '已标记删除' : this.model.classificationLabel(this.model.photo!.uri), placeBusy: this.placeBusy, placeFeedback: this.placeFeedback, closed: () => { this.closeDetails(); } })
      }
      if (this.batchOverlay()) {
        Column({ space: 20 }) {
          Text('本批已浏览完成').fontSize(24)
          Button('返回本批查看').type(ButtonType.Capsule).buttonStyle(ButtonStyleMode.TEXTUAL).border({ radius: 999, width: 1, color: $r('sys.color.ohos_id_color_list_separator') }).height(48).width('100%').fontColor($r('app.color.text_primary')).enabled(!this.model.busy && this.model.session.items.length > 0).onClick(() => { this.model.returnToBatch(); })
          Button(`查看待删除 · ${this.model.marks.length}`).type(ButtonType.Capsule).buttonStyle(ButtonStyleMode.TEXTUAL).border({ radius: 999, width: 1, color: $r('sys.color.ohos_id_color_list_separator') }).height(48).width('100%').fontColor($r('app.color.accent'))
            .enabled(!this.model.busy && !this.model.marksBusy)
            .onClick(() => { this.model.showSummary = true; this.model.refreshMarks(); })
          if (this.practice || this.appliedSource === 1 || this.model.hasMore) {
          Button(this.practice ? '回到第一张' : this.appliedSource === 1 ? '继续选取照片' : this.model.hasMore ? '继续读取下一批' : '本次图库已浏览完').type(ButtonType.Capsule).buttonStyle(ButtonStyleMode.TEXTUAL).border({ radius: 999, width: 1, color: $r('sys.color.ohos_id_color_list_separator') }).height(48).width('100%').enabled(this.practice || (this.appliedSource === 1 ? !this.model.hasLastClassification() : this.model.hasMore))
            .fontColor($r('app.color.text_primary')).onClick(async () => {
              if (this.practice) { await this.model.selectStart(this.model.session.items[0].reference); }
              else if (this.appliedSource === 1) { await this.model.choose(); }
              else { await this.model.loadLibrary(true); }
            })
          }
          Button(this.practice && !this.model.practiceCompletionPending ? '结束练习' : this.ending ? '正在结束…' : '结束整理').type(ButtonType.Capsule).buttonStyle(ButtonStyleMode.TEXTUAL).border({ radius: 999, width: 1, color: $r('sys.color.ohos_id_color_list_separator') }).height(48).width('100%').fontColor($r('app.color.text_primary'))
            .enabled(!this.ending && !this.model.busy && !this.model.marksBusy).onClick(() => { this.endRound(); })
        }.padding(24).width('100%').height('100%').justifyContent(FlexAlign.Center).backgroundColor($r('app.color.surface')).transition(TransitionEffect.opacity(0).animation(FULL_SCREEN_FADE))
      }

    }.width('100%').height('100%')
  }
}
