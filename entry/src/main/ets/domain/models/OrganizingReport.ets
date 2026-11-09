import { MoveIdentity } from './VerifiedMove';

export class OrganizingReport {
  organized: number = 0;
  recycled: number = 0;
  recycledBytes: number = 0;
  unknownBytes: number = 0;
  pending: number = 0;
}

// One review-page visit is one round. Counts are based on confirmed outcomes, never on marks.
export class RoundProgress {
  private organized: Set<string> = new Set();
  private recycled: Map<string, number> = new Map();
  classified(reference: string): void { if (reference) { this.organized.add(reference); } }
  removed(identity: MoveIdentity): void {
    if (identity.uri && !this.recycled.has(identity.uri)) {
      this.recycled.set(identity.uri, Number.isFinite(identity.bytes) && identity.bytes >= 0 ? identity.bytes : -1);
    }
  }
  snapshot(pending: number): OrganizingReport {
    const result = new OrganizingReport(); result.organized = this.organized.size; result.recycled = this.recycled.size;
    this.recycled.forEach(bytes => { if (bytes >= 0) { result.recycledBytes += bytes; } else { result.unknownBytes++; } });
    result.pending = pending; return result;
  }
}
