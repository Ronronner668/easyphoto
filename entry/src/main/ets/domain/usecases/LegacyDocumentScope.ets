export function withinDownloadScope(rootAuthority: string, root: string[], authority: string, target: string[]): boolean {
  return !!rootAuthority && authority === rootAuthority && root.length > 0 && target.length > root.length &&
    root.every((part: string, index: number) => part === target[index]) &&
    target.every((part: string) => !!part && part !== '.' && part !== '..' && !/[\\/\x00-\x1f\x7f]/.test(part)) &&
    target[root.length] === '拾光整理';
}
