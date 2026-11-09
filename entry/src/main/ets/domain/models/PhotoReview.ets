import { ProbePhoto } from './ProbeResult';

export class ReviewPhotoRef {
  id: string;
  reference: string;
  constructor(id: string, reference: string) { this.id = id; this.reference = reference; }
}

// Browsing position is independent of all future organization/discard operations.
export class PhotoReviewSession {
  private static sequence: number = 0;
  items: ReviewPhotoRef[] = [];
  index: number = 0;
  constructor(references: string[] = [], seed: string = '') {
    const sessionSeed = seed || `${Date.now()}-${++PhotoReviewSession.sequence}`;
    const seen = new Set<string>();
    references.forEach((reference: string) => {
      if (reference && !seen.has(reference) && this.items.length < 100) {
        seen.add(reference);
        this.items.push(new ReviewPhotoRef(`${sessionSeed}-${this.items.length}`, reference));
      }
    });
  }

  current(): ReviewPhotoRef | undefined { return this.items[this.index]; }

  navigate(step: number): boolean {
    if (step !== 1 && step !== -1) { return false; }
    const next = this.index + step;
    if (next < 0 || next >= this.items.length) { return false; }
    this.index = next;
    return true;
  }
}

export interface PhotoReviewSource {
  pick(): Promise<string[]>;
  resolve(reference: string): Promise<ProbePhoto>;
}
