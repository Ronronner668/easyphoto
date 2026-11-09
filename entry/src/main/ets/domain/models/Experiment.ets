export class LabAlbum {
  uri: string;
  name: string;
  constructor(uri: string, name: string) { this.uri = uri; this.name = name; }
}

export class AlbumCopyEvidence {
  uri: string = '';
  sha256: string = '';
  bytes: number = 0;
  dateTaken: number = 0;
}

export class AssetEvidence {
  membershipVersion: number = 3;
  uri: string = '';
  sha256: string = '';
  bytes: number = 0;
  dateTaken: number = 0;
  ownerAlbum: string = '';
  inA: boolean = false;
  inB: boolean = false;
  originalInA: boolean = false;
  originalInB: boolean = false;
  albumACount: number = 0;
  albumBCount: number = 0;
  copyA: AlbumCopyEvidence | undefined = undefined;
  copyB: AlbumCopyEvidence | undefined = undefined;
}

export enum AlbumPhase {
  Empty = 'empty', Creating = 'creating', Created = 'created',
  AddingA = 'adding_a', InA = 'in_a', AddingB = 'adding_b', InB = 'in_b',
  RemovingB = 'removing_b', RemovedB = 'removed_b', Trashing = 'trashing',
  TrashRequested = 'trash_requested', Review = 'review'
}

export enum AlbumAction { AddA = 'add_a', AddB = 'add_b', RemoveB = 'remove_b', Trash = 'trash' }

export class AlbumExperiment {
  id: string = '';
  phase: AlbumPhase = AlbumPhase.Empty;
  assetUri: string = '';
  fixturePath: string = '';
  fixtureHash: string = '';
  createdByLab: boolean = false;
  albumA: LabAlbum | undefined = undefined;
  albumB: LabAlbum | undefined = undefined;
  baseline: AssetEvidence | undefined = undefined;
  latest: AssetEvidence | undefined = undefined;
  verifiedCopyA: AlbumCopyEvidence | undefined = undefined;
  verifiedCopyB: AlbumCopyEvidence | undefined = undefined;
  lastAction: string = '';
  lastNativeReturned: boolean = false;
  lastErrorCode: number = 0;
  lastError: string = '';
  message: string = '先在系统图库创建两个空测试相册，再返回加载并选择相册 A 和 B。';
}

export class ExperimentError extends Error {}

export class AlreadyInTargetError extends ExperimentError {}
