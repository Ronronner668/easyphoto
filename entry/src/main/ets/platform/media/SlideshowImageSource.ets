import { fileIo } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';

export class SlideshowImageSource {
  async load(reference: string, width: number, height: number): Promise<image.PixelMap> {
    const file = await fileIo.open(reference, fileIo.OpenMode.READ_ONLY);
    let pixels: image.PixelMap | undefined = undefined;
    try {
      try {
        const source = image.createImageSource(file.fd);
        try {
          const info = await source.getImageInfo();
          const scale = Math.min(1, Math.max(width, height) / Math.max(info.size.width, info.size.height),
            3840 / Math.max(info.size.width, info.size.height));
          pixels = await source.createPixelMap({ desiredSize: {
            width: Math.max(1, Math.round(info.size.width * scale)), height: Math.max(1, Math.round(info.size.height * scale))
          } });
          return pixels;
        } finally { await source.release(); }
      } finally { await fileIo.close(file.fd); }
    } catch (error) {
      if (pixels) { await pixels.release(); }
      throw error as Error;
    }
  }
}
