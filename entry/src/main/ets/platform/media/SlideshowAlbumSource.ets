import { common } from '@kit.AbilityKit';
import { dataSharePredicates } from '@kit.ArkData';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { GalleryAlbum } from '../../domain/models/GalleryAlbum';
import { SlideshowPhoto } from '../../domain/models/Slideshow';
import { PermissionProbe } from '../permissions/PermissionProbe';

export class SlideshowAlbumSource {
  private context: common.UIAbilityContext;
  constructor(context: common.UIAbilityContext) { this.context = context; }

  async read(selected: GalleryAlbum, cancelled: () => boolean): Promise<SlideshowPhoto[]> {
    if (!new PermissionProbe().canReadLibrary()) { throw new Error('图库读取权限不可用'); }
    const helper = photoAccessHelper.getPhotoAccessHelper(this.context);
    try {
      const filter = new dataSharePredicates.DataSharePredicates();
      filter.equalTo(photoAccessHelper.AlbumKeys.URI, selected.reference);
      const albums = await helper.getAlbums(selected.type as photoAccessHelper.AlbumType,
        selected.subtype as photoAccessHelper.AlbumSubtype, { predicates: filter, fetchColumns: [] });
      try {
        if (cancelled()) { return []; }
        if (albums.getCount() !== 1) { throw new Error('相册已不可访问'); }
        const album = await albums.getFirstObject();
        if (album.albumUri !== selected.reference) { throw new Error('相册引用不匹配'); }
        const predicates = new dataSharePredicates.DataSharePredicates();
        predicates.equalTo(photoAccessHelper.PhotoKeys.PHOTO_TYPE, photoAccessHelper.PhotoType.IMAGE);
        const assets = await album.getAssets({ predicates, fetchColumns: ['date_taken', 'date_added', 'width', 'height'] });
        try {
          const photos: SlideshowPhoto[] = [];
          for (let index = 0; index < assets.getCount(); index++) {
            if (cancelled()) { return []; }
            const asset = await assets.getObjectByPosition(index);
            photos.push(new SlideshowPhoto(asset.uri, asset.displayName,
              Number(asset.get(photoAccessHelper.PhotoKeys.DATE_TAKEN)) || 0,
              Number(asset.get(photoAccessHelper.PhotoKeys.DATE_ADDED)) || 0,
              Number(asset.get(photoAccessHelper.PhotoKeys.WIDTH)) || 1,
              Number(asset.get(photoAccessHelper.PhotoKeys.HEIGHT)) || 1));
          }
          return photos;
        } finally { assets.close(); }
      } finally { albums.close(); }
    } finally { await helper.release(); }
  }
}
