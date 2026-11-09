export type SlideshowOrder = 'oldest' | 'newest' | 'random';

export class SlideshowPhoto {
  reference: string;
  name: string;
  taken: number;
  added: number;
  width: number;
  height: number;
  constructor(reference: string, name: string, taken: number, added: number, width: number, height: number) {
    this.reference = reference; this.name = name;
    this.taken = Number.isFinite(taken) && taken > 0 ? taken : 0;
    this.added = Number.isFinite(added) && added > 0 ? added : 0;
    this.width = Number.isFinite(width) && width > 0 ? width : 1;
    this.height = Number.isFinite(height) && height > 0 ? height : 1;
  }
}

export class SlideshowSettings {
  order: SlideshowOrder = 'oldest';
  interval: number = 5;
  loop: boolean = false;
  showDate: boolean = true;
  fade: boolean = true;
  music: string = '';
  musicName: string = '';
  volume: number = 0.4;
}

export class SlideshowRecord {
  reference: string = '';
  name: string = '';
  current: string = '';
  sequence: string[] = [];
  updated: number = 0;
  settings: SlideshowSettings = new SlideshowSettings();
}

export class SlideshowStore {
  version: number = 1;
  albums: SlideshowRecord[] = [];
}

export function copySlideshowSettings(settings: SlideshowSettings): SlideshowSettings {
  const next = new SlideshowSettings();
  next.order = settings.order; next.interval = settings.interval; next.loop = settings.loop;
  next.showDate = settings.showDate; next.fade = settings.fade; next.music = settings.music;
  next.musicName = settings.musicName; next.volume = settings.volume;
  return next;
}
