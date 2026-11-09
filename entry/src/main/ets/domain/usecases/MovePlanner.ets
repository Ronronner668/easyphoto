import { Category, TargetKind, TargetRef } from '../models/Category';
import { ConflictPolicy, MovePlan, MovePlanItem, MoveSource, PlanItemState, TargetObservation } from '../models/MovePlan';
import { ExperimentError } from '../models/Experiment';

function nextName(name: string, occupied: Set<string>): string {
  const dot = name.lastIndexOf('.');
  const stem = dot > 0 ? name.substring(0, dot) : name;
  const extension = dot > 0 ? name.substring(dot) : '';
  for (let number = 1; number <= 1000; number++) {
    const candidate = `${stem} (${number})${extension}`;
    if (!occupied.has(candidate.toLowerCase())) { return candidate; }
  }
  return '';
}

// Pure inspection only. No verified move channel exists yet, so no item can become executable.
export function planMoves(sources: MoveSource[], category: Category, kind: TargetKind, revision: number,
  policy: ConflictPolicy = ConflictPolicy.Skip, observation?: TargetObservation): MovePlan {
  if (sources.length > 100 || kind !== TargetKind.Album ||
    (policy !== ConflictPolicy.Skip && policy !== ConflictPolicy.Rename)) { throw new ExperimentError('计划输入不可用，请重新选择。'); }
  const target = category.album;
  if (target && (target.kind !== kind || !target.reference || !target.name)) {
    throw new ExperimentError('目标绑定已变化，请到分类管理重新选择。');
  }
  const plan = new MovePlan(kind, category.name, revision);
  const ids = new Set<string>();
  const references = new Set<string>();
  const occupied = new Set<string>();
  observation?.names.forEach((name: string) => occupied.add(name.toLowerCase()));
  let total = 0;
  let sizesKnown = true;
  sources.forEach((source: MoveSource) => {
    if (!source.id || !source.reference || ids.has(source.id) || references.has(source.reference)) {
      throw new ExperimentError('照片记录重复或不完整，未生成计划。');
    }
    ids.add(source.id); references.add(source.reference);
    // Detach the plan from mutable page state, preserving references verbatim.
    const input = new MoveSource(source.id, source.reference, source.name, source.readable);
    input.bytes = source.bytes;
    input.location = source.location ? new TargetRef(source.location.kind, source.location.reference, source.location.name) : undefined;
    const item = new MovePlanItem(input, target ? new TargetRef(target.kind, target.reference, target.name) : undefined);
    plan.items.push(item);
    if (!source.readable) { item.reasons.push('当前照片尚不可读取，请先重新读取或选图。'); return; }
    if (!target) { item.reasons.push(`“${category.name}”尚未绑定系统相册，请先管理分类目标。`); return; }
    if (source.location?.kind === target.kind && source.location.reference === target.reference) {
      item.state = PlanItemState.Skipped; item.reasons.push('已在相同目标位置，跳过。'); return;
    }
    item.reasons.push(`相册“${target.name}”已绑定。本页仅预览，不修改照片。`);
    if (!observation) { item.reasons.push('目标可用性、写入授权、重名与剩余空间尚待实际检查。'); }
    else {
      if (!observation.available) { item.reasons.push('目标当前不可用。'); }
      if (!observation.writable) { item.reasons.push('目标写入授权未确认。'); }
      if (!observation.namesComplete) { item.reasons.push('目标名称检查不完整，不能确认无重名。'); }
    }
    if (!source.name || /[\u0000-\u001f\u007f/\\]/.test(source.name)) {
      item.reasons.push('未取得可用的原文件名称。');
    } else if (occupied.has(source.name.toLowerCase())) {
      item.conflict = true;
      item.state = PlanItemState.Conflict;
      if (policy === ConflictPolicy.Skip) { item.state = PlanItemState.Skipped; item.reasons.push('检测到重名，按默认策略跳过，不覆盖。'); }
      else if (!observation?.namesComplete) { item.reasons.push('重名检查尚未完整，不能确定新名称。'); }
      else {
        item.proposedName = nextName(source.name, occupied);
        item.reasons.push(item.proposedName ? `建议新名称：${item.proposedName}；执行前仍需重新核查。` : '未找到可用的新名称。');
        if (item.proposedName) { occupied.add(item.proposedName.toLowerCase()); }
      }
    } else { occupied.add(source.name.toLowerCase()); }
    if (item.state === PlanItemState.Skipped) { return; }
    if (source.bytes === undefined || !Number.isSafeInteger(source.bytes) || source.bytes < 0 || !Number.isSafeInteger(total + source.bytes)) {
      sizesKnown = false;
    } else { total += source.bytes; }
  });
  // This is an estimate for a possible copy stage, never a claim that a move needs zero bytes.
  const candidates = plan.items.filter((item: MovePlanItem) => item.state !== PlanItemState.Skipped);
  if (sizesKnown && candidates.every((item: MovePlanItem) => item.source.readable && !!item.target)) { plan.requiredBytes = total; }
  if (plan.requiredBytes !== undefined && observation?.freeBytes !== undefined &&
    Number.isSafeInteger(observation.freeBytes) && observation.freeBytes >= 0 && plan.requiredBytes > observation.freeBytes) {
    candidates.forEach((item: MovePlanItem) => item.reasons.push('目标剩余空间不足，不能开始写入。'));
  }
  return plan;
}
