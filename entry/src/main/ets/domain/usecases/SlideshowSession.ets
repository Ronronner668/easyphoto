import { SlideshowPhoto, SlideshowOrder } from '../models/Slideshow';

export class SlideshowSession {
  photos: SlideshowPhoto[] = [];
  index: number = 0;
  playing: boolean = false;
  ended: boolean = false;

  configure(photos: SlideshowPhoto[], order: SlideshowOrder, previous: string[] = [], current: string = ''): void {
    const unique = new Map<string, SlideshowPhoto>();
    photos.forEach(photo => unique.set(photo.reference, photo));
    const sorted = Array.from(unique.values()).sort((a, b) => {
      const difference = (a.taken || a.added) - (b.taken || b.added);
      return difference || a.reference.localeCompare(b.reference);
    });
    if (order === 'newest') { sorted.reverse(); }
    if (order === 'random') {
      for (let index = sorted.length - 1; index > 0; index--) {
        const other = Math.floor(Math.random() * (index + 1));
        const photo = sorted[index]; sorted[index] = sorted[other]; sorted[other] = photo;
      }
      const retained: SlideshowPhoto[] = [];
      const seen = new Set<string>();
      previous.forEach(reference => {
        const photo = unique.get(reference);
        if (photo && !seen.has(reference)) { retained.push(photo); seen.add(reference); }
      });
      this.photos = retained.concat(sorted.filter(photo => !seen.has(photo.reference)));
    } else { this.photos = sorted; }
    this.index = Math.max(0, this.photos.findIndex(photo => photo.reference === current));
    this.playing = false; this.ended = false;
  }

  current(): SlideshowPhoto | undefined { return this.photos[this.index]; }
  move(direction: number, loop: boolean): boolean {
    if (!this.photos.length) { this.playing = false; return false; }
    const next = this.index + direction;
    if (next >= this.photos.length && !loop) { this.playing = false; this.ended = true; return false; }
    if (next < 0 && !loop) { return false; }
    this.index = (next + this.photos.length) % this.photos.length;
    this.ended = false;
    return true;
  }
}
