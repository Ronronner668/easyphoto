import { Category, CategorySnapshot, TargetKind, TargetRef } from '../models/Category';
import { ExperimentError } from '../models/Experiment';

export function categoryName(raw: string): string {
  const name = raw.trim();
  if (!name || name.length > 16 || /[\u0000-\u001f\u007f]/.test(name)) {
    throw new ExperimentError('分类名称需为 1–16 个字符，不能包含换行或控制字符。');
  }
  return name;
}

export function validateCategories(items: Category[]): void {
  if (items.length > 30) { throw new ExperimentError('最多配置 30 个分类。'); }
  const ids = new Set<string>();
  const names = new Set<string>();
  items.forEach((item: Category) => {
    const normalized = categoryName(item.name).toLowerCase();
    if (!item.id || ids.has(item.id) || names.has(normalized)) { throw new ExperimentError('分类名称或记录重复，未保存。'); }
    ids.add(item.id); names.add(normalized);
    [item.album, item.directory].forEach((target: TargetRef | undefined, index: number) => {
      if (target && (!target.reference || target.reference.length > 4096 || !target.name || target.name.length > 128 ||
        target.kind !== (index === 0 ? TargetKind.Album : TargetKind.Directory))) {
        throw new ExperimentError('目标绑定记录不可用，未保存。');
      }
    });
  });
}

export function copyCategories(snapshot: CategorySnapshot): CategorySnapshot {
  return JSON.parse(JSON.stringify(snapshot)) as CategorySnapshot;
}

export function findCategory(snapshot: CategorySnapshot, id: string): Category {
  const category = snapshot.categories.find((item: Category) => item.id === id);
  if (!category) { throw new ExperimentError('分类已经变化，请刷新后再操作。'); }
  return category;
}
