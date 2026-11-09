import { ReviewPhotoRef } from '../domain/models/PhotoReview';
export class ReviewStartData implements IDataSource {
  private items: ReviewPhotoRef[];
  private listeners: DataChangeListener[] = [];
  constructor(items: ReviewPhotoRef[]) { this.items = items; }
  replace(items: ReviewPhotoRef[]): void { this.items = items; this.listeners.forEach(listener => { listener.onDataReloaded(); }); }
  totalCount(): number { return this.items.length; }
  getData(index: number): ReviewPhotoRef { return this.items[index]; }
  registerDataChangeListener(listener: DataChangeListener): void { if (!this.listeners.includes(listener)) { this.listeners.push(listener); } }
  unregisterDataChangeListener(listener: DataChangeListener): void { this.listeners = this.listeners.filter(item => item !== listener); }
}
