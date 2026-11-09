import { common } from '@kit.AbilityKit';
import { GalleryAlbum } from '../domain/models/GalleryAlbum';
import { SlideshowPhoto, SlideshowRecord, SlideshowSettings, SlideshowOrder, copySlideshowSettings } from '../domain/models/Slideshow';
import { SlideshowSession } from '../domain/usecases/SlideshowSession';
import { SlideshowAlbumSource } from '../platform/media/SlideshowAlbumSource';
import { SlideshowMusic } from '../platform/media/SlideshowMusic';
import { SlideshowMusicFiles } from '../platform/files/SlideshowMusicFiles';
import { SlideshowRepository } from '../data/repositories/SlideshowRepository';

@Observed
export class SlideshowViewModel {
  photos: SlideshowPhoto[] = [];
  current?: SlideshowPhoto;
  index: number = 0;
  loading: boolean = false;
  preparing: boolean = false;
  importing: boolean = false;
  playing: boolean = false;
  presenting: boolean = false;
  ready: boolean = false;
  imageReady: boolean = false;
  error: string = '';
  saveError: string = '';
  notice: string = '';
  ended: boolean = false;
  canResume: boolean = false;
  settings: SlideshowSettings = new SlideshowSettings();
  album?: GalleryAlbum;
  private context?: common.UIAbilityContext;
  private repository?: SlideshowRepository;
  private session: SlideshowSession = new SlideshowSession();
  private generation: number = 0;
  private timer: number = -1;
  private timerGeneration: number = 0;
  private failures: number = 0;
  private swiping: boolean = false;
  private music: SlideshowMusic = new SlideshowMusic();
  private musicLoaded: boolean = false;
  private musicUnavailable: boolean = false;
  private musicGeneration: number = 0;
  private saveVersion: number = 0;
  changed: () => void = () => {};

  initialize(context: common.UIAbilityContext, album: GalleryAlbum): void {
    this.context = context; this.album = album; this.repository = new SlideshowRepository(context);
    this.music.interrupted = () => { this.pause(); this.notice = '音频已中断，点击播放继续。'; };
    this.music.failed = () => {
      this.musicLoaded = false; this.musicUnavailable = true;
      if (!this.preparing) {
        this.pause(); this.notice = '音乐播放中断，点击播放可静音继续。';
        this.music.close().catch(() => { this.notice = '音乐资源未能完全释放，请返回后重试。'; });
      }
    };
  }

  async load(): Promise<void> {
    if (!this.context || !this.album || !this.repository || this.loading || this.importing) { return; }
    this.pause();
    const version = ++this.generation;
    this.loading = true; this.error = ''; this.ready = false;
    try {
      const saved = (await this.repository.load()).albums.find(item => item.reference === this.album!.reference);
      if (version !== this.generation) { return; }
      const photos = await new SlideshowAlbumSource(this.context).read(this.album, () => version !== this.generation);
      if (version !== this.generation) { return; }
      this.settings = saved?.settings || new SlideshowSettings();
      this.canResume = !!saved?.current && photos.some(photo => photo.reference === saved.current);
      this.session.configure(photos, this.settings.order, saved?.sequence, saved?.current);
      this.ready = true; this.failures = 0; this.sync();
      if (saved?.current && !this.canResume && photos.length) { this.notice = '上次观看的照片已不在相册，将从头播放。'; }
    } catch (_) {
      if (version === this.generation) { this.error = '相册或放映记录读取失败，请检查图库权限后重试。原记录已保留。'; }
    } finally { if (version === this.generation) { this.loading = false; } }
  }

  private sync(): void {
    const previous = this.current?.reference;
    this.photos = this.session.photos; this.current = this.session.current(); this.index = this.session.index;
    this.playing = this.session.playing; this.ended = this.session.ended;
    if (previous !== this.current?.reference) { this.imageReady = false; }
    this.music.setPlaying(this.playing && this.musicLoaded, this.settings.volume);
    this.changed();
  }
  private clearTimer(): void {
    this.timerGeneration++;
    if (this.timer >= 0) { clearTimeout(this.timer); this.timer = -1; }
  }
  private schedule(): void {
    this.clearTimer();
    if (this.playing && this.imageReady && !this.swiping) {
      const version = this.timerGeneration;
      this.timer = setTimeout(() => {
        if (version !== this.timerGeneration) { return; }
        this.timer = -1; this.move(1);
      }, this.settings.interval * 1000);
    }
  }
  imageLoaded(reference: string): void {
    if (reference !== this.current?.reference) { return; }
    this.failures = 0; this.imageReady = true; this.schedule();
  }
  imageFailed(reference: string): void {
    if (reference !== this.current?.reference) { return; }
    this.clearTimer(); this.failures++; this.imageReady = false;
    this.notice = '这张照片暂不可读取，可切换下一张或返回刷新相册。';
    if (!this.playing || this.swiping || this.failures >= Math.min(3, this.photos.length)) { this.pause(); return; }
    const version = this.generation;
    const timerVersion = this.timerGeneration;
    this.timer = setTimeout(() => {
      if (version === this.generation && timerVersion === this.timerGeneration) { this.move(1); }
    }, 1500);
  }
  async start(resume: boolean = false): Promise<void> {
    if (!this.ready || !this.current || this.loading || this.importing || this.preparing) { return; }
    if (!resume) { this.session.index = 0; this.sync(); }
    this.presenting = true; this.imageReady = false; this.session.ended = false;
    await this.play();
  }
  async play(): Promise<void> {
    if (!this.ready || !this.current || this.loading || this.importing || this.preparing || this.playing) { return; }
    this.preparing = true;
    const version = this.generation;
    const musicVersion = ++this.musicGeneration;
    this.notice = '';
    try {
      if (this.settings.music && !this.musicLoaded && !this.musicUnavailable && this.context) {
        try {
          await this.music.load(new SlideshowMusicFiles(this.context).path(this.settings.music), this.settings.volume);
          if (version !== this.generation || musicVersion !== this.musicGeneration) { await this.music.close(); return; }
          this.musicLoaded = true;
        } catch (_) { this.musicUnavailable = true; this.notice = '音乐不可播放，本次将静音放映。可返回重新选择音乐。'; }
      }
      if (version !== this.generation || musicVersion !== this.musicGeneration) { return; }
      if (this.session.ended) { this.session.index = 0; }
      this.session.ended = false; this.session.playing = true; this.sync(); this.schedule();
    } finally { this.preparing = false; }
  }
  pause(): void {
    this.musicGeneration++; this.clearTimer(); this.swiping = false; this.session.playing = false; this.sync();
    this.save();
  }
  async toggle(): Promise<void> {
    if (this.playing || this.preparing) { this.pause(); }
    else { await this.play(); }
  }
  beginSwipe(): void {
    if (!this.presenting || !this.ready || this.preparing) { return; }
    this.swiping = true; this.clearTimer();
  }
  endSwipe(direction: number): void {
    if (!this.swiping) { return; }
    this.swiping = false;
    if (direction === 1 || direction === -1) { this.move(direction); }
    else { this.schedule(); }
  }
  move(direction: number): void {
    this.clearTimer(); this.session.move(direction, this.settings.loop); this.sync(); this.schedule(); this.save();
  }
  select(index: number): void {
    if (index < 0 || index >= this.photos.length) { return; }
    this.session.index = index; this.session.ended = false; this.sync(); this.schedule(); this.save();
  }
  stop(): void { this.suspend(); this.presenting = false; this.imageReady = false; this.changed(); }
  setOrder(order: SlideshowOrder): void {
    this.pause(); this.settings.order = order;
    this.session.configure(this.photos, order); this.canResume = false; this.sync(); this.save();
  }
  updateSettings(): void { this.settings = copySlideshowSettings(this.settings); this.schedule(); this.music.setPlaying(this.playing && this.musicLoaded, this.settings.volume); this.save(); }
  private record(): SlideshowRecord {
    const record = new SlideshowRecord(); record.reference = this.album!.reference; record.name = this.album!.name;
    record.current = this.current?.reference || ''; record.updated = Date.now(); record.settings = this.settings;
    record.sequence = this.settings.order === 'random' ? this.photos.map(photo => photo.reference) : [];
    return record;
  }
  async save(): Promise<boolean> {
    if (!this.ready || !this.repository || !this.album) { return false; }
    const version = ++this.saveVersion;
    try {
      await this.repository.save(this.record());
      if (version === this.saveVersion) { this.saveError = ''; this.canResume = !!this.current; }
      return true;
    } catch (_) {
      if (version === this.saveVersion) { this.saveError = '放映偏好或进度保存失败，请重试。'; }
      return false;
    }
  }
  async chooseMusic(): Promise<void> {
    if (!this.context || !this.ready || this.importing) { return; }
    this.pause(); this.importing = true; const version = this.generation;
    const files = new SlideshowMusicFiles(this.context);
    const previous = this.settings.music; const previousName = this.settings.musicName;
    let imported = '';
    try {
      const selected = await files.choose();
      if (!selected) { return; }
      imported = selected.file;
      if (version !== this.generation) { await files.remove(imported); return; }
      await this.music.load(files.path(imported), this.settings.volume);
      if (version !== this.generation) { await this.music.close(); await files.remove(imported); return; }
      this.settings.music = imported; this.settings.musicName = selected.name; this.musicLoaded = true; this.musicUnavailable = false;
      if (!await this.save()) {
        this.settings.music = previous; this.settings.musicName = previousName; this.musicLoaded = false;
        await this.music.close();
        // A failed flush has an unknown persistence outcome. Preserve both copies.
        return;
      }
      if (previous) { await files.remove(previous); }
      this.notice = '音乐已导入，将随放映播放。'; this.settings = copySlideshowSettings(this.settings);
    } catch (_) {
      this.musicLoaded = false;
      if (imported) { await files.remove(imported); }
      if (version === this.generation) { this.notice = '音乐未能导入，请选择 50MB 以内的可播放音频。'; }
    } finally { if (version === this.generation) { this.importing = false; } }
  }
  async removeMusic(): Promise<void> {
    if (!this.context || this.importing) { return; }
    this.pause(); this.importing = true;
    const previous = this.settings.music; this.settings.music = ''; this.settings.musicName = '';
    try {
      if (await this.save()) { await this.music.close(); this.musicLoaded = false; await new SlideshowMusicFiles(this.context).remove(previous); }
      else { this.settings.music = previous; this.settings.musicName = '本地音乐'; }
      this.settings = copySlideshowSettings(this.settings);
    } finally { this.importing = false; }
  }
  suspend(): void { this.pause(); this.music.close().catch(() => { this.notice = '音乐资源未能完全释放。'; }); this.musicLoaded = false; }
  close(): void { this.suspend(); this.generation++; this.loading = false; this.importing = false; this.changed = () => {}; }
}
