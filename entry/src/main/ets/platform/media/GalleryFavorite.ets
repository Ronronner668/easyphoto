import { common } from '@kit.AbilityKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { dataSharePredicates } from '@kit.ArkData';
import { PermissionProbe } from '../permissions/PermissionProbe';
import { ExperimentError } from '../../domain/models/Experiment';
import { deviceInfo } from '@kit.BasicServicesKit';

export function supportsGalleryFavorite(): boolean {
  const api = deviceInfo.sdkApiVersion;
  const level = api >= 1000 ? api % 1000 : api;
  return Number.isFinite(level) && level >= 26;
}

export class GalleryFavorite {
  private static running: Set<string> = new Set();
  private context: common.UIAbilityContext;
  constructor(context: common.UIAbilityContext) { this.context = context; }
  async set(reference: string, favorite: boolean): Promise<void> {
    if (reference.startsWith('file://docs/')) { throw new ExperimentError('系统收藏仅支持图库照片。'); }
    if (!supportsGalleryFavorite()) { throw new ExperimentError('当前系统不支持应用内系统收藏，请使用系统图库；此公开接口需要API26及以上。'); }
    if (GalleryFavorite.running.has(reference)) { throw new ExperimentError('正在更新此照片的收藏状态。'); }
    GalleryFavorite.running.add(reference);
    try {
      const permissions = new PermissionProbe();
      if (!permissions.canWriteLibrary()) { await permissions.requestWrite(this.context); }
      if (!permissions.canReadLibrary() || !permissions.canWriteLibrary()) { throw new ExperimentError('需要图库读写权限才能修改系统收藏。'); }
      const helper = photoAccessHelper.getPhotoAccessHelper(this.context);
      try {
        const asset = await this.asset(helper, reference);
        const request = new photoAccessHelper.MediaAssetChangeRequest(asset);
        if (typeof request.setFavorite !== 'function') { throw new ExperimentError('当前系统不支持应用内系统收藏，请使用系统图库；此公开接口需要API26及以上。'); }
        request.setFavorite(favorite); await helper.applyChanges(request);
        const verified = await this.asset(helper, reference);
        const value = verified.get(photoAccessHelper.PhotoKeys.FAVORITE);
        if ((value === true || value === 1) !== favorite) { throw new ExperimentError('收藏结果尚未确认，请刷新后核对。'); }
      } finally { await helper.release(); }
    } finally { GalleryFavorite.running.delete(reference); }
  }
  private async asset(helper: photoAccessHelper.PhotoAccessHelper, reference: string): Promise<photoAccessHelper.PhotoAsset> {
    const predicates = new dataSharePredicates.DataSharePredicates(); predicates.equalTo(photoAccessHelper.PhotoKeys.URI, reference);
    const result = await helper.getAssets({ predicates: predicates, fetchColumns: ['is_favorite'] });
    try {
      if (result.getCount() !== 1) { throw new ExperimentError('当前照片已不可访问。'); }
      const asset = await result.getFirstObject();
      if (asset.uri !== reference) { throw new ExperimentError('照片引用已变化，未修改收藏。'); }
      return asset;
    } finally { result.close(); }
  }
}
