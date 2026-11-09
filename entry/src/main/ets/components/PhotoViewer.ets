import { TitleButtonMaterial } from '../common/TitleButtonMaterial';
import { AppIcon } from './AppIcon';
import { FULL_SCREEN_FADE } from '../common/UiMotion';
import { AppTheme } from '../common/AppTheme';
import { ViewerTapGuard } from '../domain/usecases/ViewerTapGuard';
import { reviewImageSource } from '../common/ReviewImageSource';
@Component
export struct PhotoViewer {
  @Prop reference: string = '';
  @Prop initialZoom: number = 1;
  @Prop tapToClose: boolean = true;
  @Prop imageWidth: number = 1;
  @Prop imageHeight: number = 1;
  closed: () => void = () => {};
  @State private zoom: number = 1;
  @State private x: number = 0;
  @State private y: number = 0;
  @State private viewportWidth: number = 1;
  @State private viewportHeight: number = 1;
  private renderedWidth: number = 0;
  private renderedHeight: number = 0;
  @State private failed: boolean = false;
  private titleMaterial: TitleButtonMaterial = new TitleButtonMaterial();
  aboutToAppear(): void { this.titleMaterial.initialize(); this.zoom = Math.max(1, Math.min(12, this.initialZoom)); }
  private startZoom: number = 1;
  private startX: number = 0;
  private startY: number = 0;
  private tapGuard: ViewerTapGuard = new ViewerTapGuard();
  private clamp(): void {
    const fit = Math.min(this.viewportWidth / Math.max(1, this.imageWidth), this.viewportHeight / Math.max(1, this.imageHeight));
    const width = this.renderedWidth || this.imageWidth * fit;
    const height = this.renderedHeight || this.imageHeight * fit;
    const maxX = Math.max(0, (width * this.zoom - this.viewportWidth) / 2);
    const maxY = Math.max(0, (height * this.zoom - this.viewportHeight) / 2);
    this.x = Math.max(-maxX, Math.min(maxX, this.x)); this.y = Math.max(-maxY, Math.min(maxY, this.y));
  }
  build() {
    Stack() {
      Image(reviewImageSource(this.reference)).width('100%').height('100%').objectFit(ImageFit.Contain).autoResize(true).syncLoad(false).draggable(false)
        .scale({ x: this.zoom, y: this.zoom }).translate({ x: this.x, y: this.y }).hitTestBehavior(HitTestMode.None)
        .onComplete((event) => {
          if (event && event.contentWidth > 0 && event.contentHeight > 0) {
            this.renderedWidth = event.contentWidth;
            this.renderedHeight = event.contentHeight;
            this.clamp();
          }
        })
        .onError(() => { this.failed = true; })
      if (!this.tapToClose) { Text('双指缩放 · 拖动查看').fontSize(14).fontColor($r('app.color.photo_foreground')).padding({ left: 12, right: 12, top: 8, bottom: 8 })
          .backgroundColor($r('app.color.photo_control')).borderRadius(12).position({ left: 16, top: 20 }) }
      if (this.failed) { Text('无法预览此照片').fontColor(Color.White) }
      Button({ type: ButtonType.Circle }) { AppIcon({ source: $r('app.media.lucide_x_on_photo'), iconSize: 20 }) }
        .width(AppTheme.touchSize).height(AppTheme.touchSize).padding(0).buttonStyle(ButtonStyleMode.TEXTUAL).backgroundColor($r('app.color.photo_control')).attributeModifier(this.titleMaterial)
        .position({ right: 16, top: 16 }).accessibilityText('关闭全屏查看').onClick(() => { this.closed(); })
    }.width('100%').height('100%').backgroundColor(Color.Black).clip(true).transition(TransitionEffect.opacity(0).animation(FULL_SCREEN_FADE))
      .onAreaChange((_old: Area, area: Area) => { this.viewportWidth = Number(area.width); this.viewportHeight = Number(area.height); this.clamp(); })
      .gesture(GestureGroup(GestureMode.Exclusive,
        GestureGroup(GestureMode.Parallel,
        PinchGesture({ fingers: 2 }).onActionStart(() => { this.tapGuard.start('pinch'); this.startZoom = this.zoom; })
          .onActionUpdate((event: GestureEvent) => { this.zoom = Math.max(1, Math.min(12, this.startZoom * event.scale)); this.clamp(); })
          .onActionEnd(() => { this.tapGuard.finish('pinch'); }).onActionCancel(() => { this.tapGuard.finish('pinch'); }),
        PanGesture({ distance: 2 }).onActionStart(() => { this.tapGuard.start('pan'); this.startX = this.x; this.startY = this.y; })
          .onActionUpdate((event: GestureEvent) => { if (this.zoom > 1) { this.x = this.startX + event.offsetX; this.y = this.startY + event.offsetY; this.clamp(); } })
          .onActionEnd(() => { this.tapGuard.finish('pan'); }).onActionCancel(() => { this.tapGuard.finish('pan'); })),
        TapGesture({ fingers: 1 }).onAction(() => { if (this.tapToClose && this.tapGuard.canClose()) { this.closed(); } })
      ))
  }
}
