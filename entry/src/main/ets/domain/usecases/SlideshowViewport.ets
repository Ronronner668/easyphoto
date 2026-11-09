export class SlideshowViewport {
  scale: number = 1;
  x: number = 0;
  y: number = 0;
  private startScale: number = 1;
  private startX: number = 0;
  private startY: number = 0;
  private pinching: boolean = false;

  reset(): void { this.scale = 1; this.x = 0; this.y = 0; this.pinching = false; }
  beginPinch(controlsVisible: boolean): boolean {
    this.pinching = controlsVisible;
    this.startScale = this.scale;
    return this.pinching;
  }
  pinch(factor: number): void {
    if (this.pinching && Number.isFinite(factor)) { this.scale = Math.max(1, Math.min(12, this.startScale * factor)); }
  }
  endPinch(): void { this.pinching = false; }
  beginPan(): void { this.startX = this.x; this.startY = this.y; }
  pan(x: number, y: number): void { this.x = this.startX + x; this.y = this.startY + y; }
  clamp(width: number, height: number, imageWidth: number, imageHeight: number): void {
    const fit = Math.min(width / Math.max(1, imageWidth), height / Math.max(1, imageHeight));
    const maxX = Math.max(0, (imageWidth * fit * this.scale - width) / 2);
    const maxY = Math.max(0, (imageHeight * fit * this.scale - height) / 2);
    this.x = Math.max(-maxX, Math.min(maxX, this.x)) || 0;
    this.y = Math.max(-maxY, Math.min(maxY, this.y)) || 0;
  }
}
