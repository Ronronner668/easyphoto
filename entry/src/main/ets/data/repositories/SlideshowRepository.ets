import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { SlideshowRecord, SlideshowStore } from '../../domain/models/Slideshow';

export class SlideshowRepository {
  private static writing: Promise<void> = Promise.resolve();
  private context: common.UIAbilityContext;
  constructor(context: common.UIAbilityContext) { this.context = context; }

  async load(): Promise<SlideshowStore> {
    const store = await preferences.getPreferences(this.context, { name: 'slideshow' });
    const raw = await store.get('albumsV1', '');
    if (raw === '') { return new SlideshowStore(); }
    if (typeof raw !== 'string') { throw new Error('放映记录不可读取，原数据已保留'); }
    return this.validate(JSON.parse(raw) as SlideshowStore);
  }

  private validate(data: SlideshowStore): SlideshowStore {
    if (data.version !== 1 || !Array.isArray(data.albums)) { throw new Error('放映记录版本不可读取'); }
    const references = new Set<string>();
    for (const item of data.albums) {
      const settings = item.settings;
      if (typeof item.reference !== 'string' || !item.reference || references.has(item.reference) ||
        typeof item.name !== 'string' || typeof item.current !== 'string' || !Number.isFinite(item.updated) ||
        !Array.isArray(item.sequence) || !item.sequence.every(value => typeof value === 'string') || !settings ||
        !['oldest', 'newest', 'random'].includes(settings.order) || ![3, 5, 8, 12].includes(settings.interval) ||
        typeof settings.loop !== 'boolean' || typeof settings.showDate !== 'boolean' || typeof settings.fade !== 'boolean' ||
        typeof settings.music !== 'string' || (settings.music !== '' && !/^memory_[A-Za-z0-9]{6}\/track\.audio$/.test(settings.music)) ||
        typeof settings.musicName !== 'string' || !Number.isFinite(settings.volume) || settings.volume < 0 || settings.volume > 1) {
        throw new Error('放映记录损坏，原数据已保留');
      }
      references.add(item.reference);
    }
    return data;
  }

  save(record: SlideshowRecord): Promise<void> {
    // Capture before joining the queue so later UI changes cannot alter this write.
    const snapshot = JSON.stringify(record);
    const task = SlideshowRepository.writing.then(async () => {
      const data = await this.load();
      const saved = JSON.parse(snapshot) as SlideshowRecord;
      const index = data.albums.findIndex(item => item.reference === saved.reference);
      if (index < 0) { data.albums.push(saved); } else { data.albums[index] = saved; }
      this.validate(data);
      const store = await preferences.getPreferences(this.context, { name: 'slideshow' });
      await store.put('albumsV1', JSON.stringify(data));
      await store.flush();
    });
    // Keep subsequent writes usable. The caller receives the original rejection.
    SlideshowRepository.writing = task.catch(() => {});
    return task;
  }
}
