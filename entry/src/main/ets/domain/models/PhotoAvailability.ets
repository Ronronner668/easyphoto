export enum PhotoAvailability {
  Ready = 'ready', Missing = 'missing', Changed = 'changed', NotImage = 'not_image', Unavailable = 'unavailable', Legacy = 'legacy'
}
export class PhotoReferenceCheck {
  reference: string;
  state: PhotoAvailability;
  constructor(reference: string, state: PhotoAvailability) { this.reference = reference; this.state = state; }
}
export function canSkipPhoto(state: PhotoAvailability): boolean {
  return state === PhotoAvailability.Missing || state === PhotoAvailability.Changed || state === PhotoAvailability.NotImage;
}
export function photoIssue(state: PhotoAvailability): string {
  if (state === PhotoAvailability.Missing) { return '原图已不在图库，已跳过'; }
  if (state === PhotoAvailability.Changed) { return '引用已失效，已跳过；可保留或重新选图'; }
  if (state === PhotoAvailability.NotImage) { return '已不是可处理的图片，已跳过'; }
  if (state === PhotoAvailability.Unavailable) { return '暂时无法核验，标记保留，稍后重试'; }
  if (state === PhotoAvailability.Legacy) { return '历史文件标记仅供查看'; }
  return '';
}
