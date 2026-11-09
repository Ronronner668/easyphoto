import { SlideshowPhoto } from '../domain/models/Slideshow';
import { PhotoThumbnail } from './PhotoThumbnail';

@Component
export struct SlideshowPhotoTile {
  photo: SlideshowPhoto = new SlideshowPhoto('', '', 0, 0, 1, 1);
  selected: boolean = false;
  activated: () => void = () => {};
  @State private visible: boolean = false;
  build() {
    Button({ type: ButtonType.Normal }) {
      Stack() {
        if (this.visible) { PhotoThumbnail({ reference: this.photo.reference, fit: ImageFit.Cover }) }
      }.width('100%').aspectRatio(1).backgroundColor($r('app.color.accent_soft'))
    }.width('100%').aspectRatio(1).padding(0).borderRadius(12).clip(true)
      .border({ width: this.selected ? 3 : 0, color: $r('app.color.accent') })
      .accessibilityText(`${this.photo.name}，点击从此处放映`)
      .onVisibleAreaChange([0, 0.01], (visible: boolean) => { this.visible = visible; })
      .onClick(() => { this.activated(); })
  }
}
