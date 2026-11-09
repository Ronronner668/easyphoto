import { Category } from '../models/Category';
import { ExperimentError } from '../models/Experiment';
export function targetCapacity(layout: number): number { return layout === 1 ? 4 : 3; }
export function validateTargetOrder(references: string[], capacity: number): void {
  if (!Array.isArray(references) || references.length < 1 || references.length > capacity ||
    references.some(reference => typeof reference !== 'string' || !reference || reference.length > 4096 || isSampleTarget(reference)) || new Set(references).size !== references.length) {
    throw new ExperimentError(`请选择1至${capacity}个不同的目标相册。`);
  }
}
export function toggleTargetOrder(references: string[], reference: string, capacity: number): string[] {
  if (references.includes(reference)) { return references.filter(value => value !== reference); }
  if (references.length >= capacity) { throw new ExperimentError(`此布局最多选择${capacity}个相册，请先取消一个。`); }
  return [...references, reference];
}
// UI positions only; selection order never changes when the layout changes.
export function targetColumnIndexes(length: number, column: number): number[] {
  const indexes: number[] = [];
  for (let index = column; index < length; index += 2) { indexes.push(index); }
  return indexes;
}

// Display-only targets. No native album reference is attached and these are never persisted.
export function sampleTargets(capacity: number): Category[] {
  const result: Category[] = [];
  for (let index = 1; index <= (capacity === 4 ? 4 : 3); index++) { result.push(new Category(`sample-target-${index}`, `样例${index}`)); }
  return result;
}
export function isSampleTarget(id: string): boolean { return /^sample-target-[1-4]$/.test(id); }
