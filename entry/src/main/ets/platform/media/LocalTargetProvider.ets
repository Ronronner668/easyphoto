import { GalleryAlbum } from '../../domain/models/GalleryAlbum';
import { common } from '@kit.AbilityKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { TargetKind, TargetRef } from '../../domain/models/Category';
import { ExperimentError } from '../../domain/models/Experiment';
import { PermissionProbe } from '../permissions/PermissionProbe';

export class LocalTargetProvider {
  private context: common.UIAbilityContext;
  constructor(context: common.UIAbilityContext) { this.context = context; }
  async albums(request: boolean = true): Promise<TargetRef[]> {
    return (await this.details(request)).map(album => new TargetRef(TargetKind.Album, album.reference, album.name));
  }
  async details(request: boolean = true): Promise<GalleryAlbum[]> {
    const permission = new PermissionProbe();
    if (request && !permission.canReadLibrary()) { await permission.requestRead(this.context); }
    if (!permission.canReadLibrary()) { throw new ExperimentError('未取得图库读取授权，无法列出系统相册。请允许图库访问后刷新。'); }
    const helper = photoAccessHelper.getPhotoAccessHelper(this.context);
    try {
      const result = await helper.getAlbums(photoAccessHelper.AlbumType.USER, photoAccessHelper.AlbumSubtype.USER_GENERIC);
      try {
        const items: GalleryAlbum[] = [];
        for (let index = 0; index < result.getCount(); index++) {
          const album = await result.getObjectByPosition(index);
          items.push(new GalleryAlbum(album.albumUri, album.albumName, album.albumType, album.albumSubtype, album.count, album.coverUri));
        }
        return items;
      } finally { result.close(); }
    } finally { await helper.release(); }
  }
}
