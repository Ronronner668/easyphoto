import { common } from '@kit.AbilityKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { dataSharePredicates } from '@kit.ArkData';
import { PermissionProbe } from '../permissions/PermissionProbe';
import { PhotoAvailability, PhotoReferenceCheck } from '../../domain/models/PhotoAvailability';

// Metadata-only checks: no URI substitution, native deletion, thumbnail decoding or authorization request.
export class GalleryReferenceInspector {
  private context: common.UIAbilityContext;
  constructor(context: common.UIAbilityContext) { this.context = context; }
  private async references(helper: photoAccessHelper.PhotoAccessHelper): Promise<Set<string>> {
    const rows = await helper.getAssets({ predicates: new dataSharePredicates.DataSharePredicates(), fetchColumns: [] });
    try {
      const count = rows.getCount(); const references = new Set<string>();
      if (!Number.isInteger(count) || count < 0) { throw new Error('图库快照数量不可核验，保留旧标记。'); }
      for (let index = 0; index < count; index++) {
        const asset = await rows.getObjectByPosition(index);
        if (!asset.uri || references.has(asset.uri)) { throw new Error('图库快照不完整，保留旧标记。'); }
        references.add(asset.uri);
      }
      if (rows.getCount() !== count) { throw new Error('图库快照已变化，请刷新重试。'); }
      return references;
    } finally { rows.close(); }
  }
  async inspect(references: string[]): Promise<PhotoReferenceCheck[]> {
    const results = references.map(reference => new PhotoReferenceCheck(reference,
      reference.startsWith('file://docs/') ? PhotoAvailability.Legacy : PhotoAvailability.Unavailable));
    if (!references.length) { return results; }
    const permission = new PermissionProbe();
    try {
      if (!permission.canReadLibrary()) { return results; }
      const helper = photoAccessHelper.getPhotoAccessHelper(this.context);
      try {
        let snapshot: Set<string> | undefined = undefined;
        for (const result of results) {
          if (result.state === PhotoAvailability.Legacy) { continue; }
          try {
            const predicates = new dataSharePredicates.DataSharePredicates();
            predicates.equalTo(photoAccessHelper.PhotoKeys.URI, result.reference);
            const rows = await helper.getAssets({ predicates, fetchColumns: ['media_type'] });
            try {
              if (rows.getCount() === 0) { result.state = PhotoAvailability.Missing; }
              else if (rows.getCount() === 1) {
                const asset = await rows.getFirstObject();
                result.state = asset.uri !== result.reference ? PhotoAvailability.Changed :
                  asset.get(photoAccessHelper.PhotoKeys.PHOTO_TYPE) !== photoAccessHelper.PhotoType.IMAGE ? PhotoAvailability.NotImage : PhotoAvailability.Ready;
              }
            } finally { rows.close(); }
            if (result.state === PhotoAvailability.Changed) {
              if (!snapshot) { snapshot = await this.references(helper); }
              if (!snapshot.has(result.reference)) { result.state = PhotoAvailability.Missing; }
            }
          } catch (_) { result.state = PhotoAvailability.Unavailable; }
        }
        if (!permission.canReadLibrary()) { return results.map(result => new PhotoReferenceCheck(result.reference,
          result.state === PhotoAvailability.Legacy ? result.state : PhotoAvailability.Unavailable)); }
      } finally { await helper.release(); }
      return results;
    } catch (_) {
      return results.map(result => new PhotoReferenceCheck(result.reference,
        result.state === PhotoAvailability.Legacy ? result.state : PhotoAvailability.Unavailable));
    }
  }
}
