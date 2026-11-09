import { GalleryAlbum } from '../domain/models/GalleryAlbum';
import { PhotoThumbnail } from './PhotoThumbnail';
import { AppIcon } from './AppIcon';

@Component
export struct GalleryAlbumTile {
  album: GalleryAlbum = new GalleryAlbum('', '', 0, 0);
  activated: () => void = () => {};
  @Prop actionLabel: string = '点击整理此相册';
  @State private visible: boolean = false;
  build() {
    Button({ type: ButtonType.Normal }) {
      Column({ space: 6 }) {
        Stack() {
          if (this.visible && this.album.cover) {
            PhotoThumbnail({ reference: this.album.cover, fit: ImageFit.Cover })
          } else { AppIcon({ source: $r('app.media.lucide_images'), iconSize: 32 }) }
        }.width('100%').aspectRatio(1).borderRadius(18).clip(true)
          .backgroundColor($r('app.color.surface'))
        Text(this.album.name).fontSize(16).fontWeight(FontWeight.Medium).maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis }).fontColor($r('app.color.text_primary')).width('100%')
        Text(`${this.album.count}`).fontSize(13).fontColor($r('app.color.text_secondary')).width('100%')
      }.width('100%').alignItems(HorizontalAlign.Start)
    }.width('100%').padding(0).backgroundColor(Color.Transparent).borderRadius(18)
      .accessibilityText(`${this.album.name}，${this.album.count}张照片，${this.actionLabel}`)
      .onVisibleAreaChange([0, 0.01], (visible: boolean) => { this.visible = visible; })
      .onClick(() => { this.activated(); })
  }
}
