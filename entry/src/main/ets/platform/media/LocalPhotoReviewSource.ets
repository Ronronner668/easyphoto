import { PhotoPlaceReader } from './PhotoPlaceReader';
import { common } from '@kit.AbilityKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { dataSharePredicates } from '@kit.ArkData';
import { fileIo, fileUri } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { LegacyDocumentAccess } from '../files/LegacyDocumentAccess';
import { contentHash } from '../files/ContentHash';
import { MoveJournal } from '../../data/repositories/MoveJournal';
import { PhotoReviewSource } from '../../domain/models/PhotoReview';
import { ProbePhoto } from '../../domain/models/ProbeResult';
import { ExperimentError } from '../../domain/models/Experiment';
import { PermissionProbe } from '../permissions/PermissionProbe';
import { GalleryAlbum } from '../../domain/models/GalleryAlbum';

export class LocalPhotoReviewSource implements PhotoReviewSource {
  private context: common.UIAbilityContext;
  private snapshot: photoAccessHelper.FetchResult<photoAccessHelper.PhotoAsset> | undefined = undefined;
  private snapshotHelper: photoAccessHelper.PhotoAccessHelper | undefined = undefined;
  private offset: number = 0;
  private version: number = 0;
  private placeEnabled: boolean = true;
  setPlaceEnabled(enabled: boolean): void { this.placeEnabled = enabled; }
  private album: GalleryAlbum | undefined = undefined;
  constructor(context: common.UIAbilityContext) { this.context = context; }
  isAllPhotos(): boolean {
    return !this.album || (this.album.type === photoAccessHelper.AlbumType.SYSTEM &&
      this.album.subtype === photoAccessHelper.AlbumSubtype.IMAGE);
  }
  setAlbum(album?: GalleryAlbum): void { this.close(); this.album = album; }

  private async openSnapshot(helper: photoAccessHelper.PhotoAccessHelper,
    options: photoAccessHelper.FetchOptions, selected?: GalleryAlbum): Promise<photoAccessHelper.FetchResult<photoAccessHelper.PhotoAsset>> {
    if (!selected) { return helper.getAssets(options); }
    const predicates = new dataSharePredicates.DataSharePredicates();
    predicates.equalTo(photoAccessHelper.AlbumKeys.URI, selected.reference);
    const albums = await helper.getAlbums(selected.type as photoAccessHelper.AlbumType,
      selected.subtype as photoAccessHelper.AlbumSubtype, { predicates: predicates, fetchColumns: [] });
    let snapshot: photoAccessHelper.FetchResult<photoAccessHelper.PhotoAsset> | undefined = undefined;
    try {
      if (albums.getCount() !== 1) { throw new ExperimentError('所选相册已不可访问，请返回首页重新选择。'); }
      const album = await albums.getFirstObject();
      if (album.albumUri !== selected.reference) { throw new ExperimentError('相册引用已变化，请返回首页重新选择。'); }
      snapshot = await album.getAssets(options);
    } finally {
      try { albums.close(); } catch (error) { snapshot?.close(); throw error as Error; }
    }
    return snapshot!;
  }

  hasMore(): boolean { return !!this.snapshot && this.offset < this.snapshot.getCount(); }
  close(): void {
    this.version++;
    this.snapshot?.close(); this.snapshot = undefined;
    const helper = this.snapshotHelper; this.snapshotHelper = undefined;
    if (helper) { helper.release().catch(() => {}); }
    this.offset = 0;
  }
  async library(next: boolean = false): Promise<string[]> {
    const permission = new PermissionProbe();
    if (!permission.canReadLibrary()) { await permission.requestRead(this.context); }
    if (!permission.canReadLibrary()) { throw new ExperimentError('需要图库读取权限，请在设置中授权或选择照片。'); }
    if (!next || !this.snapshot) {
      this.close();
      const version = this.version;
      const helper = photoAccessHelper.getPhotoAccessHelper(this.context);
      const predicates = new dataSharePredicates.DataSharePredicates();
      predicates.equalTo(photoAccessHelper.PhotoKeys.PHOTO_TYPE, photoAccessHelper.PhotoType.IMAGE);
      predicates.orderByDesc(photoAccessHelper.PhotoKeys.DATE_ADDED);
      try {
        const snapshot = await this.openSnapshot(helper, { predicates: predicates, fetchColumns: [] }, this.album);
        if (version !== this.version) { snapshot.close(); throw new ExperimentError('图片批次已关闭。'); }
        this.snapshot = snapshot; this.snapshotHelper = helper;
      }
      catch (error) { await helper.release(); throw error as Error; }
    }
    const result = this.snapshot!; const end = Math.min(this.offset + 100, result.getCount()); const references: string[] = [];
    for (let index = this.offset; index < end; index++) { references.push((await result.getObjectByPosition(index)).uri); }
    this.offset = end; return references;
  }

  async pick(): Promise<string[]> {
    const options = new photoAccessHelper.PhotoSelectOptions();
    options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
    options.maxSelectNumber = 100;
    return (await new photoAccessHelper.PhotoViewPicker().select(options)).photoUris;
  }

  async resolve(reference: string): Promise<ProbePhoto> {
    if (reference.startsWith('file://docs/')) {
      const storagePath = await new LegacyDocumentAccess(this.context).validate(reference);
      const file = await fileIo.open(reference, fileIo.OpenMode.READ_ONLY);
      try {
        const source = image.createImageSource(file.fd);
        try {
          const info = await source.getImageInfo();
          const photo = new ProbePhoto(reference, new fileUri.FileUri(reference).name, info.size.width, info.size.height);
          photo.storagePath = storagePath;
          photo.bytes = (await fileIo.stat(file.fd)).size;
          photo.modified = (await fileIo.stat(file.fd)).mtime;
          // No Gallery date_taken exists for a Document URI. Do not invent it from filesystem mtime.
          photo.taken = await new MoveJournal(this.context).recordedTime(reference, await contentHash(reference));
          photo.timeRecorded = photo.taken > 0;
          return photo;
        } finally { await source.release(); }
      } finally { await fileIo.close(file.fd); }
    }
    const helper = photoAccessHelper.getPhotoAccessHelper(this.context);
    let results: photoAccessHelper.FetchResult<photoAccessHelper.PhotoAsset> | undefined = undefined;
    try {
      const predicates = new dataSharePredicates.DataSharePredicates();
      predicates.equalTo(photoAccessHelper.PhotoKeys.URI, reference);
      results = await helper.getAssets({ predicates: predicates, fetchColumns: ['width', 'height', 'size', 'date_taken', 'date_added', 'date_modified', 'subtype', 'is_favorite'] });
      if (results.getCount() !== 1) { throw new ExperimentError('这张照片已不可访问，请重新选图或手动查看下一张。'); }
      const asset = await results.getFirstObject();
      if (asset.uri !== reference) { throw new ExperimentError('照片引用已变化，请重新选择。'); }
      const photo = new ProbePhoto(asset.uri, asset.displayName, asset.get(photoAccessHelper.PhotoKeys.WIDTH) as number,
        asset.get(photoAccessHelper.PhotoKeys.HEIGHT) as number);
      if (this.album?.location) { photo.storagePath = `${this.album.location}（相册虚拟路径）`; }
      photo.bytes = asset.get(photoAccessHelper.PhotoKeys.SIZE) as number;
      photo.taken = asset.get(photoAccessHelper.PhotoKeys.DATE_TAKEN) as number;
      photo.added = asset.get(photoAccessHelper.PhotoKeys.DATE_ADDED) as number;
      photo.modified = asset.get(photoAccessHelper.PhotoKeys.DATE_MODIFIED) as number;
      photo.subtype = asset.get(photoAccessHelper.PhotoKeys.PHOTO_SUBTYPE) as number;
      const favorite = asset.get(photoAccessHelper.PhotoKeys.FAVORITE);
      photo.favorite = favorite === true || favorite === 1;
      if (this.placeEnabled) {
        try { const place = await new PhotoPlaceReader(this.context).read(asset.uri); photo.place = place.text; photo.placePermissionNeeded = place.needsPermission; }
        catch (_) { photo.place = '拍摄地点暂不可读取'; }
      }
      return photo;
    } finally {
      try { results?.close(); } finally { await helper.release(); }
    }
  }
}
