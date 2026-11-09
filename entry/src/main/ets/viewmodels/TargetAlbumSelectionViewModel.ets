import { common } from '@kit.AbilityKit';
import { GalleryAlbum } from '../domain/models/GalleryAlbum';
import { toggleTargetOrder, validateTargetOrder } from '../domain/usecases/TargetAlbumOrder';
import { ExperimentError } from '../domain/models/Experiment';
import { WorkbenchPreferences } from '../data/repositories/WorkbenchPreferences';
import { LocalTargetProvider } from '../platform/media/LocalTargetProvider';

@Observed
export class TargetAlbumSelectionViewModel {
  albums: GalleryAlbum[] = [];
  selected: string[] = [];
  capacity: number = 3;
  ready: boolean = false;
  busy: boolean = false;
  error: string = '';
  private store: WorkbenchPreferences | undefined = undefined;
  private provider: LocalTargetProvider | undefined = undefined;
  private loadedDraft: boolean = false;
  private savedOrder: string = '';
  private generation: number = 0;
  initialize(context: common.UIAbilityContext, capacity: number): void {
    this.store = new WorkbenchPreferences(context); this.provider = new LocalTargetProvider(context); this.capacity = capacity === 4 ? 4 : 3;
  }
  selectedAlbums(): GalleryAlbum[] {
    return this.selected.map(reference => this.albums.find(album => album.reference === reference) || new GalleryAlbum(reference, '相册已不可用', 0, 0));
  }
  dirty(): boolean { return this.loadedDraft && JSON.stringify(this.selected) !== this.savedOrder; }
  canSave(): boolean { return this.ready && !this.busy && this.selected.length > 0 && this.selected.length <= this.capacity && this.selected.every(ref => this.albums.some(album => album.reference === ref)); }
  hint(): string {
    if (this.selected.length > this.capacity) { return `已选${this.selected.length}个，当前布局最多${this.capacity}个。请明确取消多余相册，原配置尚未改变。`; }
    if (this.selected.some(ref => !this.albums.some(album => album.reference === ref))) { return '部分已选相册不可访问，请取消失效项并重新选择。'; }
    return `按点击顺序排列，至少1个，最多${this.capacity}个。`;
  }
  async load(): Promise<void> {
    if (!this.store || !this.provider || this.busy) { return; }
    const preserveDraft = this.loadedDraft; const draft = [...this.selected];
    const version = ++this.generation; this.busy = true; this.ready = false;
    try {
      const selected = await this.store.loadTargetAlbums(); const albums = await this.provider.details();
      if (version === this.generation) { this.selected = preserveDraft ? draft : selected || []; this.savedOrder = JSON.stringify(selected || []); this.loadedDraft = true; this.albums = albums; this.ready = true; this.error = ''; }
    } catch (error) { if (version === this.generation) { this.error = error instanceof ExperimentError ? error.message : '目标相册读取失败，请检查图库权限后重试，原配置保留。'; } }
    finally { if (version === this.generation) { this.busy = false; } }
  }
  toggle(reference: string): void {
    if (!this.ready || this.busy || (!this.selected.includes(reference) && !this.albums.some(album => album.reference === reference))) { return; }
    try { this.selected = toggleTargetOrder(this.selected, reference, this.capacity); this.error = ''; }
    catch (error) { this.error = (error as ExperimentError).message; }
  }
  async save(): Promise<boolean> {
    if (!this.canSave() || !this.store || !this.provider) { return false; }
    this.busy = true; const version = this.generation; const selected = [...this.selected];
    try {
      validateTargetOrder(selected, this.capacity);
      const albums = await this.provider.details(false);
      if (selected.some(ref => !albums.some(album => album.reference === ref))) { throw new ExperimentError('相册已变化，未保存，请重新读取后选择。'); }
      if (version !== this.generation) { return false; }
      await this.store.saveTargetAlbums(selected, this.capacity);
      return version === this.generation;
    } catch (error) { if (version === this.generation) { this.error = error instanceof ExperimentError ? error.message : '目标相册未确认保存，请重试。'; } return false; }
    finally { if (version === this.generation) { this.busy = false; } }
  }
  dispose(): void { this.generation++; this.store = undefined; this.provider = undefined; }
}
