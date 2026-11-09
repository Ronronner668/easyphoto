import { common } from '@kit.AbilityKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { dataSharePredicates } from '@kit.ArkData';
import { image } from '@kit.ImageKit';
import { fileIo } from '@kit.CoreFileKit';
import { LegacyDocumentAccess } from '../files/LegacyDocumentAccess';
import { ExperimentError } from '../../domain/models/Experiment';

export class PhotoThumbnailSource {
  private context: common.UIAbilityContext;
  constructor(context: common.UIAbilityContext) { this.context = context; }
  async load(reference: string, preserveAspect: boolean = false): Promise<image.PixelMap> {
    if (reference.startsWith('file://docs/')) {
      await new LegacyDocumentAccess(this.context).validate(reference);
      const file = await fileIo.open(reference, fileIo.OpenMode.READ_ONLY);
      let pixels: image.PixelMap | undefined = undefined;
      try {
      try {
        const source = image.createImageSource(file.fd);
        try {
          const info = await source.getImageInfo();
          const scale = Math.min(1, 256 / Math.max(1, info.size.width, info.size.height));
          pixels = await source.createPixelMap({ desiredSize: { width: Math.max(1, Math.round(info.size.width * scale)), height: Math.max(1, Math.round(info.size.height * scale)) } });
          return pixels;
        } finally { await source.release(); }
      } finally { await fileIo.close(file.fd); }
      } catch (error) { if (pixels) { await pixels.release(); } throw error as Error; }
    }
    const helper = photoAccessHelper.getPhotoAccessHelper(this.context);
    let pixels: image.PixelMap | undefined = undefined;
    try {
    try {
      const predicates = new dataSharePredicates.DataSharePredicates(); predicates.equalTo(photoAccessHelper.PhotoKeys.URI, reference);
      const rows = await helper.getAssets({ predicates: predicates, fetchColumns: preserveAspect ? [photoAccessHelper.PhotoKeys.WIDTH, photoAccessHelper.PhotoKeys.HEIGHT] : [] });
      try {
        if (rows.getCount() !== 1) { throw new ExperimentError('缩略图来源已不可访问。'); }
        const asset = await rows.getFirstObject();
        if (asset.uri !== reference) { throw new ExperimentError('缩略图引用已变化。'); }
        let width = 256;
        let height = 256;
        if (preserveAspect) {
          const originalWidth = Number(asset.get(photoAccessHelper.PhotoKeys.WIDTH));
          const originalHeight = Number(asset.get(photoAccessHelper.PhotoKeys.HEIGHT));
          if (originalWidth > 0 && originalHeight > 0) {
            const scale = 256 / Math.max(originalWidth, originalHeight);
            width = Math.max(1, Math.round(originalWidth * scale));
            height = Math.max(1, Math.round(originalHeight * scale));
          }
        }
        pixels = await asset.getThumbnail({ width, height });
        return pixels;
      } finally { rows.close(); }
    } finally { await helper.release(); }
    } catch (error) { if (pixels) { await pixels.release(); } throw error as Error; }
  }
}
