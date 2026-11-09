export class MoveIdentity {
  location: string = '';
  retainOriginal: boolean = false;
  subtype: number = 0;
  uri: string = '';
  name: string = '';
  bytes: number = 0;
  taken: number = 0;
  recordedTaken: number = 0;
  hash: string = '';
}
export class VerifiedMove {
  keepOriginal: boolean = false;
  targetName: string = '';
  id: string = '';
  categoryId: string = '';
  revision: number = 0;
  target: string = '';
  targetKind: string = 'album';
  destinations: MoveDestination[] = [];
  source: MoveIdentity = new MoveIdentity();
  copy: MoveIdentity | undefined = undefined;
  before: string[] = [];
  phase: string = 'copying';
  batchCancelled: boolean = false;
}
export class MoveDestination {
  target: string = '';
  kind: string = 'album';
  before: string[] = [];
  copy: MoveIdentity | undefined = undefined;
}
export interface VerifiedMovePort {
  identify(uri: string): Promise<MoveIdentity>;
  members(target: string): Promise<MoveIdentity[]>;
  copy(source: string, target: string): Promise<void>;
  trash(source: string): Promise<void>;
  exists(source: string): Promise<boolean>;
}
export interface MoveJournalPort {
  active(source?: string): Promise<VerifiedMove | undefined>;
  save(record: VerifiedMove): Promise<void>;
}
