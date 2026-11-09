import { common } from '@kit.AbilityKit';
import { Category, CategorySnapshot, TargetKind, TargetRef } from '../../domain/models/Category';
import { categoryName, copyCategories, findCategory, validateCategories } from '../../domain/usecases/CategoryRules';
import { ExperimentError } from '../../domain/models/Experiment';
import { CategoryRepository } from '../../data/repositories/CategoryRepository';
import { LocalTargetProvider } from '../../platform/media/LocalTargetProvider';

export class CategoryService {
  private static active: boolean = false;
  private static idle: Promise<void> = Promise.resolve();
  private static sequence: number = 0;
  private repository: CategoryRepository;
  private provider: LocalTargetProvider;
  private staging: boolean = false;
  beginEditing(): void { this.staging = true; }
  private save(next: CategorySnapshot): Promise<CategorySnapshot> {
    if (!this.staging) { return this.repository.save(next); }
    validateCategories(next.categories);
    return Promise.resolve(copyCategories(next));
  }
  commit(current: CategorySnapshot): Promise<CategorySnapshot> {
    return this.serialized(async () => {
      const previous = await this.repository.load();
      for (const item of current.categories) {
        const old = previous.categories.find(category => category.id === item.id);
        if (JSON.stringify(item.directory) !== JSON.stringify(old?.directory)) {
          throw new ExperimentError('历史文件绑定仅保留，不支持新增或修改。');
        }
      }
      return this.repository.save(copyCategories(current));
    });
  }
  constructor(context: common.UIAbilityContext) {
    this.repository = new CategoryRepository(context);
    this.provider = new LocalTargetProvider(context);
  }
  private async serialized(action: () => Promise<CategorySnapshot>): Promise<CategorySnapshot> {
    if (CategoryService.active) { throw new ExperimentError('另一页正在读写分类，请稍后刷新。'); }
    CategoryService.active = true;
    let release: () => void = () => {};
    CategoryService.idle = new Promise<void>((resolve) => { release = resolve; });
    try { return await action(); } finally { CategoryService.active = false; release(); }
  }
  async load(): Promise<CategorySnapshot> {
    // Independent startup readers wait for the same process lease instead of
    // treating normal category refresh as a failure to open the photo source.
    while (CategoryService.active) { await CategoryService.idle; }
    return this.serialized(() => this.repository.load());
  }
  albums(): Promise<TargetRef[]> { return this.provider.albums(); }
  create(current: CategorySnapshot, name: string): Promise<CategorySnapshot> {
    return this.serialized(async () => {
      const next = copyCategories(current);
      next.categories.push(new Category(`category-${Date.now()}-${++CategoryService.sequence}`, categoryName(name)));
      return this.save(next);
    });
  }
  rename(current: CategorySnapshot, id: string, name: string): Promise<CategorySnapshot> {
    return this.serialized(async () => {
      const next = copyCategories(current);
      findCategory(next, id).name = categoryName(name);
      return this.save(next);
    });
  }
  remove(current: CategorySnapshot, id: string): Promise<CategorySnapshot> {
    return this.serialized(async () => {
      const next = copyCategories(current);
      findCategory(next, id);
      next.categories = next.categories.filter((item: Category) => item.id !== id);
      return this.save(next);
    });
  }
  reorder(current: CategorySnapshot, id: string, step: number): Promise<CategorySnapshot> {
    return this.serialized(async () => {
      const next = copyCategories(current);
      findCategory(next, id);
      const index = next.categories.findIndex((item: Category) => item.id === id);
      if ((step !== 1 && step !== -1) || index + step < 0 || index + step >= next.categories.length) {
        throw new ExperimentError('已到分类边界，未改变顺序。');
      }
      const item = next.categories[index];
      next.categories[index] = next.categories[index + step];
      next.categories[index + step] = item;
      return this.save(next);
    });
  }
  bindAlbum(current: CategorySnapshot, id: string, selected: TargetRef): Promise<CategorySnapshot> {
    return this.serialized(async () => {
      const next = copyCategories(current);
      const category = findCategory(next, id);
      const available = await this.provider.albums();
      const target = available.find((item: TargetRef) => item.reference === selected.reference);
      if (!target || selected.kind !== TargetKind.Album) { throw new ExperimentError('所选相册已不可访问，请重新读取相册列表。'); }
      category.album = target;
      return this.save(next);
    });
  }
  unbind(current: CategorySnapshot, id: string, kind: TargetKind): Promise<CategorySnapshot> {
    return this.serialized(async () => {
      const next = copyCategories(current);
      const category = findCategory(next, id);
      if (kind !== TargetKind.Album) { throw new ExperimentError('仅支持系统相册分类。'); }
      category.album = undefined;
      return this.save(next);
    });
  }
}
