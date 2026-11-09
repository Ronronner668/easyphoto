import { fileIo } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { ContrastGrid, channelLuminance } from '../../domain/usecases/SlideshowContrast';

export class SlideshowContrastSource {
  async load(reference: string): Promise<ContrastGrid> {
    const file = await fileIo.open(reference, fileIo.OpenMode.READ_ONLY);
    try {
      const source = image.createImageSource(file.fd);
      try {
        const original = await source.getImageInfo();
        const ratio = Math.min(1, 64 / Math.max(original.size.width, original.size.height));
        const pixels = await source.createPixelMap({ desiredSize: {
          width: Math.max(1, Math.round(original.size.width * ratio)),
          height: Math.max(1, Math.round(original.size.height * ratio))
        }, desiredPixelFormat: image.PixelMapFormat.BGRA_8888 });
        try {
          const info = await pixels.getImageInfo();
          const buffer = new ArrayBuffer(info.size.width * info.size.height * 4);
          await pixels.readPixels({ pixels: buffer, offset: 0, stride: info.size.width * 4,
            region: { x: 0, y: 0, size: info.size } });
          const bytes = new Uint8Array(buffer), values: number[] = [];
          for (let index = 0; index < bytes.length; index += 4) {
            const alpha = bytes[index + 3] / 255;
            const factor = info.alphaType === image.AlphaType.PREMUL ? 1 : alpha;
            values.push(0.2126 * channelLuminance(bytes[index + 2] * factor) +
              0.7152 * channelLuminance(bytes[index + 1] * factor) + 0.0722 * channelLuminance(bytes[index] * factor));
          }
          return new ContrastGrid(info.size.width, info.size.height, original.size.width, original.size.height, values);
        } finally { await pixels.release(); }
      } finally { await source.release(); }
    } finally { await fileIo.close(file.fd); }
  }
}
