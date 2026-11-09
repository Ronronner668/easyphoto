import { ReviewMetadataCache } from '../../domain/usecases/ReviewMetadataCache';
import { GalleryAlbumLocation } from '../../platform/media/GalleryAlbumLocation';
import { common } from '@kit.AbilityKit';
import { PhotoReviewSource } from '../../domain/models/PhotoReview';
import { ProbePhoto } from '../../domain/models/ProbeResult';
import { LocalPhotoReviewSource } from '../../platform/media/LocalPhotoReviewSource';
import { MoveJournal } from '../../data/repositories/MoveJournal';
import { GalleryAlbum } from '../../domain/models/GalleryAlbum';
import { ExperimentError } from '../../domain/models/Experiment';
import { DiscardQueueRepository } from '../../data/repositories/DiscardQueueRepository';
import { GalleryReferenceInspector } from '../../platform/media/GalleryReferenceInspector';
import { PhotoAvailability } from '../../domain/models/PhotoAvailability';
import { PendingDiscardOrder } from '../../domain/usecases/PendingDiscardOrder';

export class PhotoReviewService implements PhotoReviewSource {
  private context: common.UIAbilityContext;
  private reader: LocalPhotoReviewSource;
  private metadata: ReviewMetadataCache;
  private pendingLibrary: string[] | undefined = undefined;
  private delivered: Set<string> = new Set();
  private order: PendingDiscardOrder | undefined = undefined;
  private async beginRound(): Promise<void> {
    const marks = await new DiscardQueueRepository(this.context).load();
    this.order = new PendingDiscardOrder(marks.map(mark => mark.reference));
    this.delivered.clear(); this.pendingLibrary = undefined;
  }
  setAlbum(album?: GalleryAlbum): void { this.metadata.clear(); this.reader.setAlbum(album); this.pendingLibrary = undefined; this.delivered.clear(); this.order = undefined; }
  constructor(context: common.UIAbilityContext) { this.context = context; this.reader = new LocalPhotoReviewSource(context); this.metadata = new ReviewMetadataCache(reference => this.reader.resolve(reference)); }
  private unique(references: string[]): string[] {
    return references.filter(reference => { if (this.delivered.has(reference)) { return false; } this.delivered.add(reference); return true; });
  }
  async pick(): Promise<string[]> {
    const selected = await this.reader.pick();
    if (!selected.length) { return []; }
    const marks = await new DiscardQueueRepository(this.context).load();
    const order = new PendingDiscardOrder(marks.map(mark => mark.reference));
    const excluded = this.reader.isAllPhotos() ? await new MoveJournal(this.context).excludedReferences(selected) : new Set<string>();
    const remaining = [...order.accept(selected, excluded), ...order.take()];
    if (selected.length && !remaining.length) { throw new ExperimentError('所选照片均已整理，请选择其他照片。'); }
    return remaining;
  }
  async library(next: boolean = false): Promise<string[]> {
    if (!next || !this.order) { await this.beginRound(); }
    let following = next;
    do {
      const page = this.pendingLibrary || await this.reader.library(following);
      this.pendingLibrary = page;
      const values = this.unique(await this.unstaged(page));
      this.pendingLibrary = undefined;
      if (values.length) { return values; }
      following = true;
    } while (this.reader.hasMore());
    return this.unique(this.order?.take() || []);
  }
  hasMore(): boolean {
    return !!this.order?.hasPending() || (!!this.pendingLibrary || this.reader.hasMore());
  }
  close(): void { this.metadata.clear(); this.reader.close(); }
  private async unstaged(references: string[]): Promise<string[]> {
    const excluded = this.reader.isAllPhotos() ? await new MoveJournal(this.context).excludedReferences(references) : new Set<string>();
    return this.order ? this.order.accept(references, excluded) : references.filter(reference => !excluded.has(reference));
  }
  async availability(reference: string): Promise<PhotoAvailability> {
    return (await new GalleryReferenceInspector(this.context).inspect([reference]))[0].state;
  }
  resolve(reference: string): Promise<ProbePhoto> { return this.metadata.take(reference); }
  setPlaceEnabled(enabled: boolean): void { this.metadata.clear(); this.reader.setPlaceEnabled(enabled); }
  preload(references: string[]): void { this.metadata.preload(references); }
  invalidate(): void { this.metadata.clear(); }
  location(reference: string): Promise<string> { return new GalleryAlbumLocation(this.context).find(reference); }
}
