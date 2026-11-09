import { FULL_SCREEN_FADE } from '../common/UiMotion';
import { GalleryAlbumGuide } from '../services/operations/GalleryAlbumGuide';
import { common } from '@kit.AbilityKit';
import { AppTheme } from '../common/AppTheme';
import { AppIcon } from '../components/AppIcon';
import { GalleryAlbumTile } from '../components/GalleryAlbumTile';
import { GalleryAlbum } from '../domain/models/GalleryAlbum';
import { TargetAlbumSelectionViewModel } from '../viewmodels/TargetAlbumSelectionViewModel';
interface TargetAlbumsRoute { capacity?: number; }
@Entry
@Component
struct TargetAlbums {
  @State model: TargetAlbumSelectionViewModel = new TargetAlbumSelectionViewModel();
  @State areaWidth: number = 320;
  aboutToAppear(): void {
    const params = this.getUIContext().getRouter().getParams() as TargetAlbumsRoute;
    this.model.initialize(this.getUIContext().getHostContext() as common.UIAbilityContext, params?.capacity || 3); this.model.load();
  }
  aboutToDisappear(): void { this.model.dispose(); }
  onBackPress(): boolean {
    if (this.model.busy) { return true; }
    if (!this.model.dirty()) { return false; }
    this.requestBack();
    return true;
  }
  private requestBack(): void {
    if (this.model.busy) { return; }
    if (!this.model.dirty()) { this.getUIContext().getRouter().back(); return; }
    this.getUIContext().showAlertDialog({
      title: '放弃相册选择？', message: '本次选择尚未保存。',
      primaryButton: { value: '继续选择', action: () => {} },
      secondaryButton: { value: '放弃', action: () => { this.getUIContext().getRouter().back(); } }
    });
  }
  private columns(): number { return Math.max(2, Math.floor((this.areaWidth + 12) / 124)); }
  private albumRows(): GalleryAlbum[][] {
    const columns = this.columns();
    const rows: GalleryAlbum[][] = [];
    for (let start = 0; start < this.model.albums.length; start += columns) {
      rows.push(this.model.albums.slice(start, start + columns));
    }
    return rows;
  }
  private emptySlots(used: number): number[] {
    const slots: number[] = [];
    for (let index = used; index < this.columns(); index++) { slots.push(index); }
    return slots;
  }
  pageTransition() {
    PageTransitionEnter(FULL_SCREEN_FADE).opacity(0)
    PageTransitionExit(FULL_SCREEN_FADE).opacity(0)
  }

  build() {
    Column({ space: 12 }) {
      Row({ space: 8 }) {
        Button({ type: ButtonType.Circle }) { AppIcon({ source: $r('app.media.lucide_arrow_left'), iconSize: 20 }) }
          .width(48).height(48).padding(0).buttonStyle(ButtonStyleMode.TEXTUAL).border({ radius: 24, width: 1, color: $r('sys.color.ohos_id_color_list_separator') }).accessibilityText('取消目标相册选择').enabled(!this.model.busy).onClick(() => { this.requestBack(); })
        Text('选择目标相册').fontSize(20).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary')).layoutWeight(1)
        Button('完成').type(ButtonType.Capsule).buttonStyle(ButtonStyleMode.TEXTUAL).border({ radius: 999, width: 1, color: $r('sys.color.ohos_id_color_list_separator') }).fontColor($r('app.color.accent')).constraintSize({ minWidth: 48, minHeight: 48 }).enabled(this.model.canSave())
          .onClick(async () => { if (await this.model.save()) { this.getUIContext().getRouter().back(); } })
      }.width('100%')
      if (this.model.busy) { LoadingProgress().width(24).height(24).color($r('app.color.loading_indicator')) }
      if (this.model.error) { Text(this.model.error).fontSize(14).fontColor($r('app.color.warning')).width('100%') }
      Text(this.model.hint()).fontSize(14).fontColor($r('app.color.text_secondary')).width('100%')
      Scroll() {
        Column({ space: 16 }) {
          Text('已选相册').fontSize(18).fontColor($r('app.color.text_primary')).width('100%')
          Column() {
            ForEach(this.model.selectedAlbums(), (album: GalleryAlbum, index: number) => {
              if (index > 0) {
                Divider().color($r('app.color.divider')).strokeWidth(0.5).margin({ left: 16, right: 16 })
              }
              Button({ type: ButtonType.Normal }) {
                Row({ space: 12 }) {
                  Text(`${index + 1}`).fontSize(16).fontWeight(FontWeight.Medium).fontColor($r('app.color.accent')).width(28)
                  Text(album.name).fontSize(16).fontColor($r('app.color.text_primary')).maxLines(2)
                    .textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
                  AppIcon({ source: $r('app.media.lucide_x'), iconSize: 20 })
                }.width('100%').padding(16)
              }.width('100%').constraintSize({ minHeight: 56 }).backgroundColor(Color.Transparent)
                .enabled(this.model.ready && !this.model.busy)
                .accessibilityText(`第${index + 1}个，${album.name}，点击取消选择`)
                .onClick(() => { this.model.toggle(album.reference); })
            }, (album: GalleryAlbum, index: number) => album.reference + String(index))
          }.width('100%').borderRadius(20).clip(true).backgroundColor($r('app.color.surface'))
          Row({ space: 8 }) {
            Text('可选相册').fontSize(18).fontColor($r('app.color.text_primary')).layoutWeight(1)
            Button('新建').type(ButtonType.Capsule).buttonStyle(ButtonStyleMode.TEXTUAL).border({ radius: 999, width: 1, color: $r('sys.color.ohos_id_color_list_separator') }).constraintSize({ minHeight: 48, minWidth: 48 }).fontColor($r('app.color.text_primary')).enabled(!this.model.busy).onClick(async () => {
              try { await new GalleryAlbumGuide(this.getUIContext().getHostContext() as common.UIAbilityContext).open(); }
              catch (_) { this.getUIContext().getPromptAction().showToast({ message: '请到系统图库新建相册后刷新。' }); }
            })
            Button('刷新').type(ButtonType.Capsule).buttonStyle(ButtonStyleMode.TEXTUAL).border({ radius: 999, width: 1, color: $r('sys.color.ohos_id_color_list_separator') }).constraintSize({ minHeight: 48, minWidth: 48 }).fontColor($r('app.color.text_primary')).enabled(!this.model.busy).onClick(() => { this.model.load(); })
          }.width('100%')
          Column({ space: 16 }) {
            ForEach(this.albumRows(), (row: GalleryAlbum[]) => {
              Row({ space: 12 }) {
                ForEach(row, (album: GalleryAlbum) => {
              Stack({ alignContent: Alignment.TopEnd }) {
                GalleryAlbumTile({ album, actionLabel: this.model.selected.includes(album.reference) ? `已选第 ${this.model.selected.indexOf(album.reference) + 1} 个，点击取消` : '点击设为目标相册', activated: () => { this.model.toggle(album.reference); } }).width('100%').enabled(this.model.ready && !this.model.busy)
                if (this.model.selected.includes(album.reference)) {
                  Text(`${this.model.selected.indexOf(album.reference) + 1}`).fontSize(14).fontWeight(FontWeight.Bold).fontColor($r('app.color.on_accent'))
                    .width(28).height(28).textAlign(TextAlign.Center).borderRadius(14).backgroundColor($r('app.color.accent')).margin(6).hitTestBehavior(HitTestMode.None)
                }
              }.layoutWeight(1).padding(4).borderRadius(20).border({ width: this.model.selected.includes(album.reference) ? 2 : 0, color: $r('app.color.accent') })
                .accessibilityDescription(this.model.selected.includes(album.reference) ? `已选，第${this.model.selected.indexOf(album.reference) + 1}个` : '未选择')
                }, (album: GalleryAlbum) => JSON.stringify(album))
                ForEach(this.emptySlots(row.length), (index: number) => { Blank().layoutWeight(1) }, (index: number) => String(index))
              }.width('100%').alignItems(VerticalAlign.Top)
            }, (row: GalleryAlbum[]) => JSON.stringify([this.columns(), row]))
          }.width('100%').onAreaChange((_old: Area, area: Area) => { if (Number(area.width) > 0) { this.areaWidth = Number(area.width); } })
          if (this.model.ready && !this.model.albums.length) { Text('暂无可写入的用户相册，请到系统图库新建后刷新。').fontColor($r('app.color.text_secondary')).width('100%') }
        }.width('100%').padding({ bottom: 24 })
      }.layoutWeight(1).width('100%').align(Alignment.TopStart).edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true }).scrollBar(BarState.Auto)
    }.padding(AppTheme.pagePadding).width('100%').height('100%').backgroundColor($r('app.color.page_background'))
  }
}
