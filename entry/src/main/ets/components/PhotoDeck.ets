import { UI_SPRING } from '../common/UiMotion';
import { photoCardWidth, photoCardHeight, isLongPhoto } from '../domain/usecases/PhotoGeometry';
import { PhotoThumbnail } from './PhotoThumbnail';
import { PhotoReviewViewModel } from '../viewmodels/PhotoReviewViewModel';
import { DropZone, hitDropTarget } from '../domain/usecases/DropTarget';
import { reviewImageSource } from '../common/ReviewImageSource';

class DeckPhoto {
  id: string;
  uri: string;
  constructor(id: string, uri: string) { this.id = id; this.uri = uri; }
}

@Component
export struct PhotoDeck {
  @ObjectLink model: PhotoReviewViewModel;
  zones: () => DropZone[] = () => [];
  dropped: (id: string) => void = () => {};
  hovered: (id: string) => void = () => {};
  opened: () => void = () => {};
  @State private dragging: boolean = false;
  @State private areaWidth: number = 360;
  @State private areaHeight: number = 450;
  @State private dx: number = 0;
  @State private dy: number = 0;
  private startX: number = 0;
  private startY: number = 0;
  private dragPhotoId: string = '';
  private dragReference: string = '';
  private hover: string = '';
  private cardZone: DropZone[] = [];
  private overControls(x: number, y: number): boolean {
    const card = this.cardZone[0];
    if (!card) { return false; }
    const controls: DropZone[] = [];
    if (this.model.streamError) { controls.push(new DropZone('retry', card.x + 8, card.y + card.height - 56, card.width * 0.70, 48)); }
    return !!hitDropTarget(controls, x, y);
  }
  private neighbor(step: number): string { return this.model.session.items[this.model.session.index + step]?.reference || ''; }
  private setHover(id: string): void { if (id !== this.hover) { this.hover = id; this.hovered(id); } }
  private cardWidth(): number {
    return photoCardWidth(this.areaWidth, this.areaHeight, this.model.photo?.width || 1, this.model.photo?.height || 1, 1);
  }
  private cardHeight(): number {
    return photoCardHeight(this.areaWidth, this.areaHeight, this.model.photo?.width || 1, this.model.photo?.height || 1, 1);
  }
  private badge(): string {
    const reference = this.model.photo?.uri || '';
    const classification = this.model.classificationLabel(reference);
    if (!this.model.marks.some(mark => mark.reference === reference)) { return classification; }
    return classification ? classification + ' · 已标记删除' : '已标记删除';
  }
  private settleCard(): void {
    this.getUIContext().animateTo({ curve: UI_SPRING }, () => {
      this.dx = 0;
      this.dy = 0;
      this.dragging = false;
    });
    this.setHover('');
  }

  build() {
    Stack() {
      // Neighbor previews stay inside the stream; the active card can travel over category controls.
      Stack() {
      if (this.neighbor(-1)) {
        PhotoThumbnail({ reference: this.neighbor(-1), maxPreviewWidth: this.areaWidth * 0.42,
          maxPreviewHeight: this.areaHeight * 0.68 }).rotate({ angle: -12 })
          .translate({ x: -this.areaWidth * 0.28, y: 12 }).hitTestBehavior(HitTestMode.None)
      }
      if (this.neighbor(1)) {
        PhotoThumbnail({ reference: this.neighbor(1), maxPreviewWidth: this.areaWidth * 0.42,
          maxPreviewHeight: this.areaHeight * 0.68 }).rotate({ angle: 12 })
          .translate({ x: this.areaWidth * 0.28, y: 12 }).hitTestBehavior(HitTestMode.None)
      }
      }.width('100%').height('100%').clip(true).hitTestBehavior(HitTestMode.None)
      Stack() {
        if (this.model.photo) {
          ForEach([new DeckPhoto(this.model.displayedId, this.model.photo.uri)], (photo: DeckPhoto) => {
            Image(reviewImageSource(photo.uri)).width('100%').height('100%')
              .objectFit(isLongPhoto(this.model.photo?.width || 1, this.model.photo?.height || 1) ? ImageFit.Cover : ImageFit.Contain).draggable(false).autoResize(true).syncLoad(false)
              .transition(TransitionEffect.opacity(0).animation({ curve: UI_SPRING }))
              .onError(() => { this.model.imageFailed(photo.id, photo.uri); })
          }, (photo: DeckPhoto) => photo.id + photo.uri)
        } else { Text(this.model.busy ? '正在读取…' : this.model.message).padding(20).fontSize(15) }
        if (this.model.busy) { LoadingProgress().width(32).height(32).color($r('app.color.loading_indicator')) }
        if (this.badge()) { Text(this.badge()).fontSize(12).maxLines(2).constraintSize({ maxWidth: '85%' }).padding(8).borderRadius(12).backgroundColor($r('app.color.photo_control')).fontColor($r('app.color.photo_foreground')).position({ right: 8, top: 8 }) }
        if (this.model.streamError) {
          Button('读取失败，点击重试').type(ButtonType.Capsule).height(48).fontSize(14).buttonStyle(ButtonStyleMode.TEXTUAL)
            .constraintSize({ maxWidth: '70%' }).position({ left: 8, bottom: 8 }).enabled(!this.model.busy)
            .accessibilityDescription(this.model.streamError).onClick(() => { this.model.retryStream(); })
        }
      }.width(this.cardWidth()).height(this.cardHeight()).borderRadius(18).clip(true).renderGroup(true)
        .onAreaChange((_old: Area, area: Area) => { this.cardZone = [new DropZone('photo', Number(area.globalPosition.x), Number(area.globalPosition.y), Number(area.width), Number(area.height))]; })
        .translate({ x: this.dx, y: this.dy }).rotate({ angle: this.dx / 30 })
        .scale({ x: this.dragging ? 0.5 : 1, y: this.dragging ? 0.5 : 1 })
        .shadow({ radius: 8, color: $r('app.color.shadow_soft'), offsetY: 4 })
    }.width('100%').height('100%').clip(false)
      .onAreaChange((_old: Area, area: Area) => { this.areaWidth = Number(area.width); this.areaHeight = Number(area.height); })
      .parallelGesture(TapGesture().onAction((event: GestureEvent) => {
        const x = event.fingerList[0]?.globalX || 0;
        const y = event.fingerList[0]?.globalY || 0;
        if (!this.model.busy && this.model.photo && hitDropTarget(this.cardZone, x, y) && !this.overControls(x, y)) { this.opened(); }
      }))
      .gesture(PanGesture({ direction: PanDirection.All, distance: 8 })
        .onActionStart((event: GestureEvent) => { if (this.model.busy || !this.model.photo) { return; }
          this.dragPhotoId = this.model.displayedId;
          this.dragReference = this.model.photo.uri;
          this.startX = event.fingerList[0]?.globalX || 0; this.startY = event.fingerList[0]?.globalY || 0; this.getUIContext().animateTo({ duration: 100 }, () => { this.dragging = true; }); })
        .onActionUpdate((event: GestureEvent) => {
          if (this.dragging && !this.model.busy) {
            this.dx = event.offsetX; this.dy = event.offsetY;
            this.setHover(hitDropTarget(this.zones(), this.startX + event.offsetX, this.startY + event.offsetY));
          }
        })
        .onActionEnd((event: GestureEvent) => {
          if (!this.dragging) { return; }
          const id = hitDropTarget(this.zones(), this.startX + event.offsetX, this.startY + event.offsetY);
          this.settleCard();
          if (this.model.busy || this.dragPhotoId !== this.model.displayedId || this.dragReference !== this.model.photo?.uri) { return; }
          if (id) { this.dropped(id); } else { this.model.gesture(event.offsetX, event.offsetY).then(() => { if ((this.model.isPractice() || (event.offsetY >= 80 && Math.abs(event.offsetY) > Math.abs(event.offsetX) * 1.2)) && this.model.operationFeedback) { this.getUIContext().getPromptAction().showToast({ message: this.model.operationFeedback }); } }); }
        }).onActionCancel(() => { this.settleCard(); }))
  }
}
