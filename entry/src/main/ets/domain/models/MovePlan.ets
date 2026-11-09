import { TargetKind, TargetRef } from './Category';

export enum PlanItemState { Blocked = 'blocked', Conflict = 'conflict', Skipped = 'skipped' }
export enum ConflictPolicy { Skip = 'skip', Rename = 'rename' }

export class MoveSource {
  id: string;
  reference: string;
  name: string;
  readable: boolean;
  bytes: number | undefined = undefined;
  location: TargetRef | undefined = undefined;
  constructor(id: string, reference: string, name: string, readable: boolean) {
    this.id = id; this.reference = reference; this.name = name; this.readable = readable;
  }
}

// These facts must come from a target adapter, never from parsing an opaque reference.
export class TargetObservation {
  available: boolean = false;
  writable: boolean = false;
  names: string[] = [];
  namesComplete: boolean = false;
  freeBytes: number | undefined = undefined;
}

export class MovePlanItem {
  source: MoveSource;
  target: TargetRef | undefined;
  operation: string = 'move';
  state: PlanItemState = PlanItemState.Blocked;
  reasons: string[] = [];
  proposedName: string = '';
  conflict: boolean = false;
  constructor(source: MoveSource, target: TargetRef | undefined) { this.source = source; this.target = target; }
}

export class MovePlan {
  mode: TargetKind;
  categoryName: string;
  categoryRevision: number;
  items: MovePlanItem[] = [];
  executableCount: number = 0;
  requiredBytes: number | undefined = undefined;
  constructor(mode: TargetKind, categoryName: string, revision: number) {
    this.mode = mode; this.categoryName = categoryName; this.categoryRevision = revision;
  }
}
