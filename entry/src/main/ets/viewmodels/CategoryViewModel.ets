import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { Category, CategorySnapshot, TargetKind, TargetRef } from '../domain/models/Category';
import { ExperimentError } from '../domain/models/Experiment';
import { CategoryService } from '../services/operations/CategoryService';

@Observed
export class CategoryViewModel {
  snapshot: CategorySnapshot = new CategorySnapshot();
  albums: TargetRef[] = [];
  ready: boolean = false;
  busy: boolean = false;
  draft: string = '';
  editingId: string = '';
  message: string = '正在读取分类。';
  private service: CategoryService | undefined = undefined;
  private disposed: boolean = false;
  initialize(context: common.UIAbilityContext): void {
    this.service = new CategoryService(context); this.service.beginEditing(); this.refresh();
  }
  async commit(): Promise<boolean> {
    return this.update(() => this.service!.commit(this.snapshot), '设置已保存。');
  }
  async refresh(): Promise<void> {
    if (this.busy) { return; }
    this.ready = false;
    await this.update(() => this.service!.load(), '分类已读取。相册分类与照片记录分别保存。');
  }
  edit(category: Category): void {
    if (this.busy || !this.ready) { return; }
    this.editingId = category.id; this.draft = category.name;
  }
  cancelEdit(): void { if (!this.busy) { this.editingId = ''; this.draft = ''; } }
  async saveName(): Promise<void> {
    if (!this.ready) { return; }
    const id = this.editingId;
    const name = this.draft;
    const saved = await this.update(() => id ? this.service!.rename(this.snapshot, id, name) : this.service!.create(this.snapshot, name),
      id ? '分类名称已更新。' : '分类已创建，绑定相册后可分类照片。');
    if (saved) { this.editingId = ''; this.draft = ''; }
  }
  async remove(id: string): Promise<void> {
    if (!this.ready) { return; }
    if (await this.update(() => this.service!.remove(this.snapshot, id), '分类已删除；照片、相册与待删除标记保持原状。')) {
      if (this.editingId === id) { this.cancelEdit(); }
    }
  }
  async reorder(id: string, step: number): Promise<void> {
    if (this.ready) { await this.update(() => this.service!.reorder(this.snapshot, id, step), '分类顺序已保存。'); }
  }
  async loadAlbums(): Promise<void> {
    if (this.busy || !this.service || this.disposed) { return; }
    this.busy = true;
    try {
      const albums = await this.service.albums();
      if (!this.disposed) {
        this.albums = albums;
        this.message = albums.length ? `已读取 ${albums.length} 个用户相册（最多 100 个），可为分类选择绑定。` : '没有可用用户相册，请先在系统图库创建。';
      }
    } catch (error) { this.showError(error as BusinessError); }
    finally { this.busy = false; }
  }
  async bindAlbum(id: string, index: number): Promise<void> {
    const target = this.albums[index];
    if (this.ready && target) { await this.update(() => this.service!.bindAlbum(this.snapshot, id, target), '相册绑定待保存。'); }
  }
  async unbind(id: string, kind: TargetKind): Promise<void> {
    if (this.ready) { await this.update(() => this.service!.unbind(this.snapshot, id, kind), '已解除目标绑定，未修改系统照片。'); }
  }
  private showError(error: BusinessError): void {
    if (!this.disposed) { this.message = error instanceof ExperimentError ? error.message : `分类操作未完成（错误码 ${error.code || -1}），请刷新后核对。`; }
  }
  private async update(action: () => Promise<CategorySnapshot>, message: string): Promise<boolean> {
    if (this.busy || !this.service || this.disposed) { return false; }
    this.busy = true;
    try {
      const snapshot = await action();
      if (!this.disposed) {
        this.snapshot = snapshot; this.ready = true;
        this.message = message.replace('已保存', '待保存').replace('已创建', '已加入草稿').replace('已删除', '已从草稿移除') + ' 修改后请点击顶部保存。';
        return true;
      }
    } catch (error) { this.showError(error as BusinessError); }
    finally { this.busy = false; }
    return false;
  }
  dispose(): void { this.disposed = true; }
}
