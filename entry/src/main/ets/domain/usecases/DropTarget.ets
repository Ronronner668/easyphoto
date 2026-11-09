export class DropZone {
  id: string;
  x: number;
  y: number;
  width: number;
  height: number;
  constructor(id: string, x: number, y: number, width: number, height: number) {
    this.id = id; this.x = x; this.y = y; this.width = width; this.height = height;
  }
}
export function hitDropTarget(zones: DropZone[], x: number, y: number): string {
  if (!Number.isFinite(x) || !Number.isFinite(y)) { return ''; }
  const hits = zones.filter((zone: DropZone) => zone.width > 0 && zone.height > 0 &&
    x >= zone.x && x < zone.x + zone.width && y >= zone.y && y < zone.y + zone.height);
  return hits.length === 1 ? hits[0].id : '';
}
