import { PhotoAvailability } from './PhotoAvailability';

export class DiscardMark {
  availability: PhotoAvailability = PhotoAvailability.Ready;
  reference: string;
  name: string;
  markedAt: number;
  constructor(reference: string, name: string, markedAt: number) {
    this.reference = reference;
    this.name = name;
    this.markedAt = markedAt;
  }
}

export interface DiscardQueuePort {
  load(): Promise<DiscardMark[]>;
  mark(reference: string, name: string): Promise<DiscardMark[]>;
  unmark(reference: string): Promise<DiscardMark[]>;
}
