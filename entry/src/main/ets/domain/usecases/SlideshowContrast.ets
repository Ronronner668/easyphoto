export class ChromeRegion {
  key: string; x: number; y: number; width: number; height: number;
  constructor(key: string, x: number, y: number, width: number, height: number) {
    this.key = key; this.x = x; this.y = y; this.width = width; this.height = height;
  }
}
export class ChromeInk {
  key: string; dark: boolean;
  constructor(key: string, dark: boolean) { this.key = key; this.dark = dark; }
}
export class ContrastGrid {
  width: number; height: number; imageWidth: number; imageHeight: number; luminance: number[];
  constructor(width: number, height: number, imageWidth: number, imageHeight: number, luminance: number[]) {
    this.width = width; this.height = height; this.imageWidth = imageWidth; this.imageHeight = imageHeight; this.luminance = luminance;
  }
}
export function channelLuminance(value: number): number {
  const normalized = value / 255;
  return normalized <= 0.04045 ? normalized / 12.92 : Math.pow((normalized + 0.055) / 1.055, 2.4);
}
// Coordinates are relative to the actual image viewport, including its contain-fit letterboxing.
export function contrastInk(grid: ContrastGrid, region: ChromeRegion, width: number, height: number,
  scale: number, offsetX: number, offsetY: number, wasDark: boolean): boolean {
  if (width <= 0 || height <= 0 || region.width <= 0 || region.height <= 0) { return false; }
  const fit = Math.min(width / grid.imageWidth, height / grid.imageHeight) * scale;
  const drawnWidth = grid.imageWidth * fit, drawnHeight = grid.imageHeight * fit;
  const left = (width - drawnWidth) / 2 + offsetX, top = (height - drawnHeight) / 2 + offsetY;
  let sum = 0;
  for (let row = 0; row < 3; row++) {
    for (let column = 0; column < 7; column++) {
      const x = region.x + region.width * (column + 0.5) / 7;
      const y = region.y + region.height * (row + 0.5) / 3;
      const u = (x - left) / drawnWidth, v = (y - top) / drawnHeight;
      if (x >= 0 && y >= 0 && x < width && y < height && u >= 0 && u < 1 && v >= 0 && v < 1) {
        sum += grid.luminance[Math.floor(v * grid.height) * grid.width + Math.floor(u * grid.width)];
      }
      // Outside the photograph is the dark slideshow canvas (approximately zero linear luminance).
    }
  }
  return sum / 21 > (wasDark ? 0.15 : 0.21);
}
