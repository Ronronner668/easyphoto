import { common } from '@kit.AbilityKit';
import { image } from '@kit.ImageKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { PhotoThumbnailSource } from '../platform/media/PhotoThumbnailSource';
import { AppIcon } from './AppIcon';
import { practiceImage, reviewImageSource } from '../common/ReviewImageSource';

@Component
export struct PhotoThumbnail {
  @Prop @Watch('reload') reference: string = '';
  fit: ImageFit = ImageFit.Contain;
  @Prop maxPreviewWidth: number = 0;
  @Prop maxPreviewHeight: number = 0;
  @State private previewRatio: number = 0;
  private previewWidth(): number | string {
    if (!this.maxPreviewWidth) { return '100%'; }
    return this.previewRatio ? Math.min(this.maxPreviewWidth, this.maxPreviewHeight * this.previewRatio) : 1;
  }
  private previewHeight(): number | string {
    if (!this.maxPreviewHeight) { return '100%'; }
    return this.previewRatio ? Math.min(this.maxPreviewHeight, this.maxPreviewWidth / this.previewRatio) : 1;
  }
  private updateRatio(width: number, height: number): void {
    if (width > 0 && height > 0) { this.previewRatio = width / height; }
  }
  @State private pixels: image.PixelMap | undefined = undefined;
  @State private failed: boolean = false;
  private version: number = 0;
  private disposed: boolean = false;
  aboutToAppear(): void { this.disposed = false; this.reload(); }
  aboutToDisappear(): void { this.disposed = true; this.version++; this.release(this.pixels); this.pixels = undefined; }
  private release(pixels?: image.PixelMap): void {
    if (pixels) { pixels.release().catch(() => { hilog.warn(0, 'PhotoThumbnail', 'Thumbnail resource release failed'); }); }
  }
  private async reload(): Promise<void> {
    const version = ++this.version; const reference = this.reference;
    this.release(this.pixels); this.pixels = undefined; this.failed = false; this.previewRatio = 0;
    if (!reference || this.disposed || practiceImage(reference)) { return; }
    try {
      const source = new PhotoThumbnailSource(this.getUIContext().getHostContext() as common.UIAbilityContext);
      const pixels = await source.load(reference, this.maxPreviewWidth > 0);
      if (this.disposed || version !== this.version || reference !== this.reference) { this.release(pixels); return; }
      this.pixels = pixels;
      if (this.maxPreviewWidth) {
        const info = pixels.getImageInfoSync();
        this.updateRatio(info.size.width, info.size.height);
      }
    } catch (_) { if (!this.disposed && version === this.version) { this.failed = true; } }
  }
  build() {
    Stack() {
      if (practiceImage(this.reference)) {
        Image(reviewImageSource(this.reference)).width('100%').height('100%').objectFit(this.fit).draggable(false)
          .onComplete(event => { if (event && this.maxPreviewWidth) { this.updateRatio(event.width, event.height); } })
      }
      else if (this.pixels) { Image(this.pixels).width('100%').height('100%').objectFit(this.fit).draggable(false) }
      else if (this.failed) {
        Column({ space: 2 }) { AppIcon({ source: $r('app.media.lucide_images') }); Text('无法预览').fontSize(10).fontColor($r('app.color.text_secondary')) }
      } else { LoadingProgress().width(24).height(24).color($r('app.color.loading_indicator')) }
    }.width(this.previewWidth()).height(this.previewHeight())
      .backgroundColor(this.maxPreviewWidth ? Color.Transparent : $r('app.color.accent_soft'))
      .borderRadius(this.maxPreviewWidth ? 16 : 0).clip(true)
      .accessibilityText(this.failed ? '缩略图不可读取' : '照片缩略图')
  }
}
