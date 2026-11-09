import { ProbePhoto } from '../domain/models/ProbeResult';
import { ReviewPhotoRef } from '../domain/models/PhotoReview';
export class LocatorEntry extends ReviewPhotoRef {
  name: string = '正在读取名称';
  date: string = '';
  loaded: boolean = false;
  readFailed: boolean = false;
  constructor(reference: string) { super(reference, reference); }
}
export class LocatorRow {
  title: string = '';
  date: string = '';
  items: LocatorEntry[] = [];
}
@Observed
export class ReviewLocatorViewModel {
  entries: LocatorEntry[] = [];
  busy: boolean = false;
  failed: number = 0;
  private generation: number = 0;
  updated: () => void = () => {};
  private read: (reference: string) => Promise<ProbePhoto> = async () => { throw new Error('定位页未初始化'); };
  initialize(read: (reference: string) => Promise<ProbePhoto>): void { this.read = read; }
  filtered(query: string): LocatorEntry[] {
    const value = query.trim().toLowerCase().replace(/\//g, '-');
    return this.entries.filter(entry => !value || entry.name.toLowerCase().includes(value) || entry.date.includes(value));
  }
  rows(now: number = Date.now()): LocatorRow[] {
    const today = new Date(now); today.setHours(0, 0, 0, 0);
    const groups: LocatorEntry[][] = [[], [], [], [], [], []];
    const titles: string[] = ['今天', '昨天', '一周内', '一月内', '更早', '日期未提供'];
    const sorted = this.entries.slice().sort((a, b) => b.date.localeCompare(a.date));
    for (const item of sorted) {
      const days = item.date ? Math.floor((today.getTime() - new Date(item.date + 'T00:00:00').getTime()) / 86400000) : NaN;
      const group = !Number.isFinite(days) ? 5 : days <= 0 ? 0 : days === 1 ? 1 : days < 7 ? 2 : days < 30 ? 3 : 4;
      groups[group].push(item);
    }
    const rows: LocatorRow[] = [];
    groups.forEach((items: LocatorEntry[], index: number) => {
      if (!items.length) { return; }
      const header = new LocatorRow(); header.title = titles[index]; header.date = items[0].date; rows.push(header);
      for (let start = 0; start < items.length; start += 4) {
        const row = new LocatorRow(); row.items = items.slice(start, start + 4); row.date = row.items[0].date; rows.push(row);
      }
    });
    return rows;
  }
  entry(reference: string): LocatorEntry | undefined { return this.entries.find(entry => entry.reference === reference); }
  async refresh(items: ReviewPhotoRef[]): Promise<void> {
    const version = ++this.generation; const previous = this.entries;
    const entries = items.map(item => previous.find(entry => entry.reference === item.reference) || new LocatorEntry(item.reference));
    const pending = entries.filter(entry => !entry.loaded || entry.readFailed); this.busy = true; this.failed = 0; this.updated();
    let cursor = 0;
    const worker = async (): Promise<void> => {
      while (version === this.generation && cursor < pending.length) {
        const entry = pending[cursor++];
        try {
          const photo = await this.read(entry.reference);
          if (version !== this.generation) { return; }
          if (photo.uri !== entry.reference) { throw new Error('定位信息引用不匹配'); }
          const next = new LocatorEntry(entry.reference); next.name = photo.name; next.loaded = true;
          if (Number.isFinite(photo.taken) && photo.taken > 0) {
            const date = new Date(photo.taken * 1000);
            next.date = `${date.getFullYear()}-${(date.getMonth() + 1).toString().padStart(2, '0')}-${date.getDate().toString().padStart(2, '0')}`;
          }
          entries[entries.indexOf(entry)] = next;
        } catch (_) {
          if (version !== this.generation) { return; }
          const next = new LocatorEntry(entry.reference); next.name = '名称暂不可读取'; next.loaded = true; next.readFailed = true;
          entries[entries.indexOf(entry)] = next; this.failed++;
        }
      }
    };
    await Promise.all([worker(), worker()]);
    if (version === this.generation) { this.entries = entries; this.busy = false; this.updated(); }
  }
  close(): void { this.generation++; this.busy = false; this.entries = []; }
}
