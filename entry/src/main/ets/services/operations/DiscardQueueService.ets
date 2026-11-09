import { common } from '@kit.AbilityKit';
import { DiscardMark, DiscardQueuePort } from '../../domain/models/DiscardMark';
import { DiscardQueueRepository } from '../../data/repositories/DiscardQueueRepository';
import { ExperimentError } from '../../domain/models/Experiment';
import { GalleryReferenceInspector } from '../../platform/media/GalleryReferenceInspector';
import { PhotoAvailability } from '../../domain/models/PhotoAvailability';

// Reconciles app-local marks with read-only Gallery observations. Never mutates media.
export class DiscardQueueService implements DiscardQueuePort {
  private static writing: boolean = false;
  private repository: DiscardQueueRepository;
  private inspector: GalleryReferenceInspector;
  private states: Map<string, PhotoAvailability> = new Map();
  constructor(context: common.UIAbilityContext) { this.repository = new DiscardQueueRepository(context); this.inspector = new GalleryReferenceInspector(context); }
  private annotate(marks: DiscardMark[]): DiscardMark[] {
    marks.forEach(mark => { mark.availability = this.states.get(mark.reference) || PhotoAvailability.Ready; });
    return marks;
  }
  async load(): Promise<DiscardMark[]> {
    const marks = await this.repository.load();
    const checks = await this.inspector.inspect(marks.map(mark => mark.reference));
    if (DiscardQueueService.writing) { throw new ExperimentError('待删除标记正在更新，请稍后重试。'); }
    DiscardQueueService.writing = true;
    try {
      for (const check of checks) {
        if (check.state === PhotoAvailability.Missing) {
          const mark = marks.find(item => item.reference === check.reference);
          if (mark) { await this.repository.removeMissing(mark); }
        }
      }
      this.states = new Map(); checks.forEach(check => { this.states.set(check.reference, check.state); });
      return this.annotate(await this.repository.load());
    } finally { DiscardQueueService.writing = false; }
  }
  async mark(reference: string, name: string): Promise<DiscardMark[]> {
    if (DiscardQueueService.writing) { throw new ExperimentError('另一页正在保存标记，请稍后刷新。'); }
    DiscardQueueService.writing = true;
    try { await this.repository.mark(reference, name); this.states.delete(reference); return this.annotate(await this.repository.load()); }
    finally { DiscardQueueService.writing = false; }
  }
  async unmark(reference: string): Promise<DiscardMark[]> {
    if (DiscardQueueService.writing) { throw new ExperimentError('另一页正在保存标记，请稍后刷新。'); }
    DiscardQueueService.writing = true;
    try { await this.repository.unmark(reference); this.states.delete(reference); return this.annotate(await this.repository.load()); }
    finally { DiscardQueueService.writing = false; }
  }
}
