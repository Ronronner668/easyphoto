export class PendingDiscardOrder {
  private marked: Set<string>;
  private deferred: string[] = [];
  private seen: Set<string> = new Set();
  private offset: number = 0;
  constructor(marked: string[]) { this.marked = new Set(marked); }
  accept(references: string[], organized: Set<string>): string[] {
    const fresh: string[] = [];
    for (const reference of references) {
      if (this.marked.has(reference)) {
        if (!this.seen.has(reference)) { this.seen.add(reference); this.deferred.push(reference); }
      } else if (!organized.has(reference)) { fresh.push(reference); }
    }
    return fresh;
  }
  hasPending(): boolean { return this.offset < this.deferred.length; }
  take(): string[] { const page = this.deferred.slice(this.offset, this.offset + 100); this.offset += page.length; return page; }
}
