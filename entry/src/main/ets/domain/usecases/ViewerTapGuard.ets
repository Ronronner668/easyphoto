// A lifted finger after pinch/pan must not be mistaken for a fresh single tap.
export class ViewerTapGuard {
  private active: Set<string> = new Set();
  private until: number = 0;
  start(gesture: string): void { this.active.add(gesture); }
  finish(gesture: string, now: number = Date.now()): void { this.active.delete(gesture); this.until = now + 200; }
  canClose(now: number = Date.now()): boolean { return this.active.size === 0 && now >= this.until; }
}
