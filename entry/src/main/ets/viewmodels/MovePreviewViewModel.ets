import { common } from '@kit.AbilityKit';
import { Category, CategorySnapshot, TargetKind } from '../domain/models/Category';
import { ConflictPolicy, MovePlan, MoveSource } from '../domain/models/MovePlan';
import { PhotoReviewSession } from '../domain/models/PhotoReview';
import { ExperimentError } from '../domain/models/Experiment';
import { planMoves } from '../domain/usecases/MovePlanner';
import { CategoryService } from '../services/operations/CategoryService';
import { PhotoReviewService } from '../services/operations/PhotoReviewService';

@Observed
export class MovePreviewViewModel {
  categories: CategorySnapshot = new CategorySnapshot();
  categoryId: string = '';
  policy: ConflictPolicy = ConflictPolicy.Skip;
  selection: PhotoReviewSession = new PhotoReviewSession();
  plan: MovePlan | undefined = undefined;
  busy: boolean = false;
  message: string = '选择照片和分类，生成逐项计划；此页不会执行分类。';
  private reader: PhotoReviewService | undefined = undefined;
  private service: CategoryService | undefined = undefined;
  private disposed: boolean = false;
  initialize(context: common.UIAbilityContext): void {
    this.reader = new PhotoReviewService(context); this.service = new CategoryService(context); this.refresh();
  }
  async refresh(): Promise<void> {
    if (!this.service || this.busy || this.disposed) { return; }
    this.busy = true; this.plan = undefined;
    try {
      const snapshot = await this.service.load();
      if (!this.disposed) {
        this.categories = snapshot;
        if (!snapshot.categories.some((item: Category) => item.id === this.categoryId)) { this.categoryId = snapshot.categories[0]?.id || ''; }
      }
    } catch (_) { if (!this.disposed) { this.categoryId = ''; this.message = '分类读取失败，请刷新后再生成计划。'; } }
    finally { this.busy = false; }
  }
  selectCategory(index: number): void {
    if (!this.busy && this.categories.categories[index]) { this.categoryId = this.categories.categories[index].id; this.plan = undefined; }
  }
  setPolicy(policy: ConflictPolicy): void { if (!this.busy) { this.policy = policy; this.plan = undefined; } }
  async choose(): Promise<void> {
    if (!this.reader || this.busy || this.disposed) { return; }
    this.busy = true;
    try {
      const references = await this.reader.pick();
      if (this.disposed) { return; }
      const next = new PhotoReviewSession(references);
      if (!next.items.length) { this.message = '已取消或未取得可用照片，保留此前选择。'; return; }
      this.selection = next; this.plan = undefined; this.message = `已选择 ${next.items.length} 张照片，可生成计划。`;
    } catch (_) { if (!this.disposed) { this.message = '选图未完成，保留此前选择。'; } }
    finally { this.busy = false; }
  }
  async generate(): Promise<void> {
    if (!this.reader || !this.service || this.busy || this.disposed || !this.selection.items.length || !this.categoryId) { return; }
    this.busy = true; this.plan = undefined;
    const id = this.categoryId;
    try {
      const snapshot = await this.service.load();
      if (this.disposed) { return; }
      const category = snapshot.categories.find((item: Category) => item.id === id);
      this.categories = snapshot;
      if (!category) { this.categoryId = ''; this.message = '所选分类已被删除，请重新选择。'; return; }
      const sources: MoveSource[] = [];
      for (let index = 0; index < this.selection.items.length; index++) {
        const reference = this.selection.items[index];
        this.message = `正在检查照片 ${index + 1} / ${this.selection.items.length}`;
        try {
          const photo = await this.reader.resolve(reference.reference);
          if (this.disposed) { return; }
          sources.push(new MoveSource(reference.id, reference.reference, photo.name, photo.uri === reference.reference));
        } catch (_) {
          if (this.disposed) { return; }
          sources.push(new MoveSource(reference.id, reference.reference, `照片 ${index + 1}`, false));
        }
      }
      // Check binding revision after asynchronous reads; never present an older binding as current.
      const latest = await this.service.load();
      if (this.disposed) { return; }
      if (latest.revision !== snapshot.revision) { this.categories = latest; this.message = '分类目标在检查期间发生变化，请重新生成计划。'; return; }
      this.plan = planMoves(sources, category, TargetKind.Album, snapshot.revision, this.policy);
      this.message = '计划已生成，照片保持原状。此页仅预览，请返回工作台逐张分类。';
    } catch (error) {
      if (!this.disposed) { this.message = error instanceof ExperimentError ? error.message : '计划检查未完成，请重新生成；照片保持原状。'; }
    } finally { this.busy = false; }
  }
  dispose(): void { this.disposed = true; }
}
