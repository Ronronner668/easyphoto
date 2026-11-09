import { common } from '@kit.AbilityKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { dataSharePredicates } from '@kit.ArkData';
import { MoveIdentity, VerifiedMovePort } from '../../domain/models/VerifiedMove';
import { ExperimentError } from '../../domain/models/Experiment';
import { contentHash } from '../files/ContentHash';
import { fileIo } from '@kit.CoreFileKit';

export class VerifiedAlbumMoveAdapter implements VerifiedMovePort {
  private context: common.UIAbilityContext;
  constructor(context: common.UIAbilityContext) { this.context = context; }
  private options(uri?: string): photoAccessHelper.FetchOptions {
    const predicates = new dataSharePredicates.DataSharePredicates();
    if (uri) { predicates.equalTo(photoAccessHelper.PhotoKeys.URI, uri); }
    return { predicates: predicates, fetchColumns: ['size', 'date_taken', 'subtype', 'media_type'] };
  }
  private async asset(helper: photoAccessHelper.PhotoAccessHelper, uri: string): Promise<photoAccessHelper.PhotoAsset> {
    const rows = await helper.getAssets(this.options(uri));
    try {
      if (rows.getCount() !== 1) { throw new ExperimentError('照片引用当前不可访问。'); }
      const asset = await rows.getFirstObject();
      if (asset.uri !== uri) { throw new ExperimentError('照片引用已变化，请重新选择照片后标记；旧标记可选择保留。'); }
      if (asset.get(photoAccessHelper.PhotoKeys.PHOTO_TYPE) !== photoAccessHelper.PhotoType.IMAGE) {
        throw new ExperimentError('此标记的来源不是图片，未提交回收；可以选择保留并重新选图。');
      }
      return asset;
    } finally { rows.close(); }
  }
  private async album(helper: photoAccessHelper.PhotoAccessHelper, uri: string): Promise<photoAccessHelper.Album> {
    const rows = await helper.getAlbums(photoAccessHelper.AlbumType.USER, photoAccessHelper.AlbumSubtype.USER_GENERIC);
    try {
      if (rows.getCount() > 1000) { throw new ExperimentError('相册数量超出本版检查范围。'); }
      for (let index = 0; index < rows.getCount(); index++) {
        const album = await rows.getObjectByPosition(index);
        if (album.albumUri === uri) { return album; }
      }
      throw new ExperimentError('目标相册已不可访问。');
    } finally { rows.close(); }
  }
  async identify(uri: string): Promise<MoveIdentity> {
    const helper = photoAccessHelper.getPhotoAccessHelper(this.context);
    try {
      const asset = await this.asset(helper, uri);
      const result = new MoveIdentity(); result.uri = asset.uri; result.name = asset.displayName;
      const file = await fileIo.open(uri, fileIo.OpenMode.READ_ONLY);
      try { result.bytes = (await fileIo.stat(file.fd)).size; } finally { await fileIo.close(file.fd); }
      result.taken = asset.get(photoAccessHelper.PhotoKeys.DATE_TAKEN) as number;
      result.subtype = asset.get(photoAccessHelper.PhotoKeys.PHOTO_SUBTYPE) as number;
      result.retainOriginal = result.subtype === photoAccessHelper.PhotoSubtype.MOVING_PHOTO || result.subtype === photoAccessHelper.PhotoSubtype.BURST;
      result.hash = await contentHash(uri);
      return result;
    } finally { await helper.release(); }
  }
  async members(uri: string): Promise<MoveIdentity[]> {
    const helper = photoAccessHelper.getPhotoAccessHelper(this.context);
    try {
      const album = await this.album(helper, uri);
      const rows = await album.getAssets(this.options());
      try {
        if (rows.getCount() > 1000 || rows.getCount() !== album.count) { throw new ExperimentError('目标相册清单无法完整检查。'); }
        const members: MoveIdentity[] = [];
        const seen = new Set<string>();
        for (let index = 0; index < rows.getCount(); index++) {
          const asset = await rows.getObjectByPosition(index);
          if (!asset.uri || seen.has(asset.uri)) { throw new ExperimentError('相册成员不完整，停止操作。'); }
          seen.add(asset.uri);
          const item = new MoveIdentity(); item.uri = asset.uri; item.name = asset.displayName; members.push(item);
        }
        return members;
      } finally { rows.close(); }
    } finally { await helper.release(); }
  }
  async copy(uri: string, target: string): Promise<void> {
    const helper = photoAccessHelper.getPhotoAccessHelper(this.context);
    try {
      const request = new photoAccessHelper.MediaAlbumChangeRequest(await this.album(helper, target));
      request.addAssets([await this.asset(helper, uri)]); await helper.applyChanges(request);
    } finally { await helper.release(); }
  }
  trash(uri: string): Promise<void> { return photoAccessHelper.MediaAssetChangeRequest.deleteAssets(this.context, [uri]); }
  async exists(uri: string): Promise<boolean> {
    const helper = photoAccessHelper.getPhotoAccessHelper(this.context);
    try {
      const rows = await helper.getAssets(this.options(uri));
      try {
        if (rows.getCount() === 0) { return false; }
        if (rows.getCount() !== 1 || (await rows.getFirstObject()).uri !== uri) { throw new ExperimentError('照片引用无法核验，保留原记录。'); }
        return true;
      } finally { rows.close(); }
    } finally { await helper.release(); }
  }
}
