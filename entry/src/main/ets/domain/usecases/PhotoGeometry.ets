export function photoCardHeight(areaWidth: number, areaHeight: number, imageWidth: number, imageHeight: number, fraction: number): number {
  if (![areaWidth, areaHeight, imageWidth, imageHeight, fraction].every(value => Number.isFinite(value) && value > 0)) { return 1; }
  return Math.max(1, Math.min(areaHeight, areaWidth * fraction * imageHeight / imageWidth));
}

export function isLongPhoto(imageWidth: number, imageHeight: number): boolean {
  return Number.isFinite(imageWidth) && Number.isFinite(imageHeight) && imageWidth > 0 && imageHeight / imageWidth >= 3;
}

export function photoCardWidth(areaWidth: number, areaHeight: number, imageWidth: number, imageHeight: number, fraction: number): number {
  if (![areaWidth, areaHeight, imageWidth, imageHeight, fraction].every(value => Number.isFinite(value) && value > 0)) { return 1; }
  if (isLongPhoto(imageWidth, imageHeight)) { return Math.max(1, areaWidth * fraction); }
  return Math.max(1, Math.min(areaWidth * fraction, areaHeight * imageWidth / imageHeight));
}
