import { ProbePhoto } from './ProbeResult';

export class PhotoInfoSettings {
  dateFormat: string = 'YYYY/MM/DD';
  name: boolean = true;
  date: boolean = true;
  place: boolean = true;
  dimensions: boolean = true;
  bytes: boolean = false;
}
// Legacy settings fields remain readable; the review header has a fixed date/time layout.
export function photoInfoRows(photo: ProbePhoto): string[] {
  const valid = Number.isFinite(photo.taken) && photo.taken > 0;
  const date = new Date(valid ? photo.taken * 1000 : 0);
  const day = valid ? `${date.getFullYear()}年${date.getMonth() + 1}月${date.getDate()}日` : '日期未提供';
  const time = valid ? `${date.getHours().toString().padStart(2, '0')}:${date.getMinutes().toString().padStart(2, '0')}` : '时间未提供';
  return [day, time];
}
