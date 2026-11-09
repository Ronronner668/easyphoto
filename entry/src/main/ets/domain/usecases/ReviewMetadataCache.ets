import { ProbePhoto } from '../models/ProbeResult';
class MetadataEntry {
  reference: string; created: number = Date.now(); value: Promise<ProbePhoto>;
  constructor(reference: string, value: Promise<ProbePhoto>) { this.reference = reference; this.value = value; }
}
export class ReviewMetadataCache {
  private entries: MetadataEntry[] = [];
  private inFlight: number = 0;
  private read: (reference: string) => Promise<ProbePhoto>;
  constructor(read: (reference: string) => Promise<ProbePhoto>) { this.read = read; }
  clear(): void { this.entries = []; }
  async take(reference: string): Promise<ProbePhoto> {
    const entry = this.entries.find(item => item.reference === reference && Date.now() - item.created < 3000);
    this.entries = this.entries.filter(item => item.reference !== reference);
    // Prefetch failure is never cached as absence. An explicit read retries it.
    if (entry) { try { return await entry.value; } catch (_) { } }
    return this.read(reference);
  }
  preload(references: string[]): void {
    const selected = references.filter((ref, index) => !!ref && references.indexOf(ref) === index).slice(0, 2);
    this.entries = this.entries.filter(item => selected.includes(item.reference) && Date.now() - item.created < 3000);
    for (const reference of selected) {
      if (this.entries.some(item => item.reference === reference)) { continue; }
      if (this.inFlight >= 2) { continue; }
      this.inFlight++;
      const value = this.read(reference).finally(() => { this.inFlight--; }); value.catch(() => {});
      this.entries.push(new MetadataEntry(reference, value));
    }
  }
}
