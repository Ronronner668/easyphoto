// Directory/Both and directory bindings are retained only for lossless historical schema compatibility.
export enum TargetKind { Album = 'album', Directory = 'directory', Both = 'both' }

export class TargetRef {
  kind: TargetKind;
  reference: string;
  name: string;
  constructor(kind: TargetKind, reference: string, name: string) {
    this.kind = kind; this.reference = reference; this.name = name;
  }
}

export class Category {
  id: string;
  name: string;
  album: TargetRef | undefined = undefined;
  directory: TargetRef | undefined = undefined;
  constructor(id: string, name: string) { this.id = id; this.name = name; }
}

export class CategorySnapshot {
  revision: number = 0;
  categories: Category[] = [];
}

export function defaultCategories(): Category[] {
  return ['旅游', '美食', '人像', '风景', '建筑', '宠物', '其他']
    .map((name: string, index: number) => new Category(`preset-${index}`, name));
}
