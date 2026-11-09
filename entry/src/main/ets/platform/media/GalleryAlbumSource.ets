import { common } from '@kit.AbilityKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { dataSharePredicates } from '@kit.ArkData';
import { GalleryAlbum } from '../../domain/models/GalleryAlbum';
import { ExperimentError } from '../../domain/models/Experiment';
import { PermissionProbe } from '../permissions/PermissionProbe';

export class GalleryAlbumSource {
  private context: common.UIAbilityContext;
  constructor(context: common.UIAbilityContext) { this.context = context; }
  async list(): Promise<GalleryAlbum[]> {
    if (!new PermissionProbe().canReadLibrary()) { throw new ExperimentError('请先允许访问图库，再读取相册。'); }
    const helper = photoAccessHelper.getPhotoAccessHelper(this.context);
    const items: GalleryAlbum[] = [];
    const seen = new Set<string>();
    try {
      await this.append(helper, photoAccessHelper.AlbumType.SYSTEM, photoAccessHelper.AlbumSubtype.IMAGE, items, seen);
      await this.append(helper, photoAccessHelper.AlbumType.SYSTEM, photoAccessHelper.AlbumSubtype.FAVORITE, items, seen);
      await this.append(helper, photoAccessHelper.AlbumType.SOURCE, photoAccessHelper.AlbumSubtype.SOURCE_GENERIC, items, seen);
      await this.append(helper, photoAccessHelper.AlbumType.USER, photoAccessHelper.AlbumSubtype.USER_GENERIC, items, seen);
      return items;
    } finally { await helper.release(); }
  }
  private async append(helper: photoAccessHelper.PhotoAccessHelper, type: photoAccessHelper.AlbumType,
    subtype: photoAccessHelper.AlbumSubtype, items: GalleryAlbum[], seen: Set<string>): Promise<void> {
    const albums = await helper.getAlbums(type, subtype);
    try {
      for (let index = 0; index < albums.getCount(); index++) {
        const album = await albums.getObjectByPosition(index);
        if (seen.has(album.albumUri)) { continue; }
        seen.add(album.albumUri);
        const predicates = new dataSharePredicates.DataSharePredicates();
        predicates.equalTo(photoAccessHelper.PhotoKeys.PHOTO_TYPE, photoAccessHelper.PhotoType.IMAGE);
        predicates.orderByDesc(photoAccessHelper.PhotoKeys.DATE_ADDED);
        const photos = await album.getAssets({ predicates: predicates, fetchColumns: [] });
        try {
          const count = photos.getCount();
          if (count === 0) { continue; }
          const cover = count > 0 ? (await photos.getFirstObject()).uri : '';
          const name = subtype === photoAccessHelper.AlbumSubtype.IMAGE ? '图片' :
            subtype === photoAccessHelper.AlbumSubtype.FAVORITE ? '我的收藏' : album.albumName;
          const item = new GalleryAlbum(album.albumUri, name, album.albumType, album.albumSubtype, count, cover);
          item.location = album.lpath || ''; items.push(item);
        } finally { photos.close(); }
      }
    } finally { albums.close(); }
  }
}
