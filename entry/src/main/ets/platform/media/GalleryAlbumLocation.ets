import { common } from '@kit.AbilityKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { dataSharePredicates } from '@kit.ArkData';
import { PermissionProbe } from '../permissions/PermissionProbe';

// Public virtual album locations, resolved from exact membership, never by parsing a resource URI.
export class GalleryAlbumLocation {
  private context: common.UIAbilityContext;
  constructor(context: common.UIAbilityContext) { this.context = context; }
  async find(reference: string): Promise<string> {
    if (!new PermissionProbe().canReadLibrary()) { return ''; }
    const helper = photoAccessHelper.getPhotoAccessHelper(this.context);
    try {
      for (const type of [photoAccessHelper.AlbumType.SOURCE, photoAccessHelper.AlbumType.USER]) {
        const subtype = type === photoAccessHelper.AlbumType.SOURCE ? photoAccessHelper.AlbumSubtype.SOURCE_GENERIC : photoAccessHelper.AlbumSubtype.USER_GENERIC;
        const albums = await helper.getAlbums(type, subtype);
        try {
          for (let index = 0; index < albums.getCount(); index++) {
            const album = await albums.getObjectByPosition(index);
            if (!album.lpath) { continue; }
            const predicates = new dataSharePredicates.DataSharePredicates(); predicates.equalTo(photoAccessHelper.PhotoKeys.URI, reference);
            const members = await album.getAssets({ predicates, fetchColumns: [] });
            try {
              if (members.getCount() === 1 && (await members.getFirstObject()).uri === reference) {
                return album.lpath + '（相册虚拟路径）';
              }
            } finally { members.close(); }
          }
        } finally { albums.close(); }
      }
      return '';
    } finally { await helper.release(); }
  }
}
