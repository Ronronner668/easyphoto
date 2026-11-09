import { common } from '@kit.AbilityKit';
import { relationalStore } from '@kit.ArkData';
import { DiscardMark } from '../../domain/models/DiscardMark';
import { ExperimentError } from '../../domain/models/Experiment';

// Each marker is a separate row, avoiding Preferences' per-value string limits for opaque references.
export class DiscardQueueRepository {
  private context: common.UIAbilityContext;
  private store: relationalStore.RdbStore | undefined = undefined;
  constructor(context: common.UIAbilityContext) { this.context = context; }

  private async database(): Promise<relationalStore.RdbStore> {
    if (!this.store) {
      const store = await relationalStore.getRdbStore(this.context,
        { name: 'discard_marks.db', securityLevel: relationalStore.SecurityLevel.S1 });
      await store.executeSql('CREATE TABLE IF NOT EXISTS discard_marks (reference TEXT PRIMARY KEY, name TEXT NOT NULL, marked_at INTEGER NOT NULL)');
      this.store = store;
    }
    return this.store;
  }

  async load(): Promise<DiscardMark[]> {
    const store = await this.database();
    const result = await store.querySql('SELECT reference, name, marked_at FROM discard_marks ORDER BY marked_at, reference');
    try {
      const marks: DiscardMark[] = [];
      while (result.goToNextRow()) {
        const reference = result.getString(0);
        const name = result.getString(1);
        const markedAt = result.getLong(2);
        if (!reference || reference.length > 4096 || !name || name.length > 256 || markedAt <= 0) {
          throw new ExperimentError('待删除标记记录不完整，已保留数据，请停止新增并核对。');
        }
        marks.push(new DiscardMark(reference, name, markedAt));
      }
      return marks;
    } finally { result.close(); }
  }

  async mark(reference: string, name: string): Promise<void> {
    if (!reference || reference.length > 4096 || !name || name.length > 256) {
      throw new ExperimentError('照片引用或名称不可用，未保存标记。');
    }
    const existing = await this.load();
    if (existing.some((item: DiscardMark) => item.reference === reference)) { return; }
    const store = await this.database();
    await store.executeSql('INSERT OR IGNORE INTO discard_marks (reference, name, marked_at) VALUES (?, ?, ?)',
      [reference, name, Date.now()]);
  }

  async removeMissing(mark: DiscardMark): Promise<void> {
    const store = await this.database();
    // Never erase a newer user intent observed after this metadata check started.
    await store.executeSql('DELETE FROM discard_marks WHERE reference = ? AND marked_at = ? AND name = ?',
      [mark.reference, mark.markedAt, mark.name]);
  }

  async unmark(reference: string): Promise<void> {
    const store = await this.database();
    await store.executeSql('DELETE FROM discard_marks WHERE reference = ?', [reference]);
  }
}
