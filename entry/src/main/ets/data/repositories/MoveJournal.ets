import { common } from '@kit.AbilityKit';
import { relationalStore } from '@kit.ArkData';
import { MoveJournalPort, VerifiedMove } from '../../domain/models/VerifiedMove';
import { ExperimentError } from '../../domain/models/Experiment';
import { BatchMoveJournal } from '../../domain/usecases/FinishStagedMoves';

export class MoveJournal implements BatchMoveJournal {
  private context: common.UIAbilityContext;
  constructor(context: common.UIAbilityContext) { this.context = context; }
  private async db(): Promise<relationalStore.RdbStore> {
    const store = await relationalStore.getRdbStore(this.context, { name: 'verified_moves.db', securityLevel: relationalStore.SecurityLevel.S1 });
    await store.executeSql('CREATE TABLE IF NOT EXISTS move_journal (id TEXT PRIMARY KEY, phase TEXT NOT NULL, payload TEXT NOT NULL)');
    return store;
  }
  async active(source?: string): Promise<VerifiedMove | undefined> {
    const store = await this.db();
    const rows = source ? await store.querySql("SELECT payload FROM move_journal WHERE phase NOT IN ('complete', 'cancelled', 'retained') AND instr(payload, ?) > 0 ORDER BY id", [source]) :
      await store.querySql("SELECT payload FROM move_journal WHERE phase NOT IN ('complete', 'cancelled', 'retained') ORDER BY id LIMIT 1");
    try {
      if (!rows.goToFirstRow()) { return undefined; }
      do {
        const record = JSON.parse(rows.getString(0)) as VerifiedMove;
        if (!record.id || !record.source?.uri || !record.target) { throw new ExperimentError('移动日志损坏，保留记录停止操作。'); }
        if (!source || record.source.uri === source) { return record; }
      } while (rows.goToNextRow());
      return undefined;
    } finally { rows.close(); }
  }
  async completedCount(): Promise<number> {
    const store = await this.db();
    const rows = await store.querySql("SELECT COUNT(*) FROM move_journal WHERE phase IN ('complete', 'retained')");
    try { return rows.goToFirstRow() ? rows.getLong(0) : 0; } finally { rows.close(); }
  }
  async staged(): Promise<VerifiedMove[]> {
    const rows = await (await this.db()).querySql("SELECT payload FROM move_journal WHERE phase IN ('awaiting_trash', 'batch_trashing') ORDER BY id");
    try {
      const result: VerifiedMove[] = [];
      if (rows.goToFirstRow()) { do { result.push(JSON.parse(rows.getString(0)) as VerifiedMove); } while (rows.goToNextRow()); }
      return result;
    } finally { rows.close(); }
  }
  async classified(): Promise<VerifiedMove[]> {
    const rows = await (await this.db()).querySql("SELECT payload FROM move_journal WHERE phase IN ('complete', 'retained', 'awaiting_trash', 'batch_trashing') ORDER BY id DESC LIMIT 3000");
    try {
      const result: VerifiedMove[] = [];
      if (rows.goToFirstRow()) { do { result.push(JSON.parse(rows.getString(0)) as VerifiedMove); } while (rows.goToNextRow()); }
      return result;
    } finally { rows.close(); }
  }
  async excludedReferences(references: string[]): Promise<Set<string>> {
    const excluded = new Set<string>();
    if (!references.length) { return excluded; }
    if (references.length > 100) { throw new ExperimentError('浏览批次数量无效。'); }
    const filters = references.map(() => 'instr(payload, ?) > 0').join(' OR ');
    const rows = await (await this.db()).querySql(`SELECT payload FROM move_journal WHERE phase IN ('complete', 'retained', 'awaiting_trash', 'batch_trashing') AND (${filters})`, references);
    try {
      if (rows.goToFirstRow()) {
        do {
          const record = JSON.parse(rows.getString(0)) as VerifiedMove;
          if (!record.id || !record.source?.uri || !record.target || !record.copy?.uri) { throw new ExperimentError('整理历史记录不完整，停止读取，保留当前批次。'); }
          const values = [record.source.uri, record.copy.uri];
          record.destinations?.forEach(target => { if (target.copy?.uri) { values.push(target.copy.uri); } });
          values.forEach(value => { if (references.includes(value)) { excluded.add(value); } });
        } while (rows.goToNextRow());
      }
      return excluded;
    } finally { rows.close(); }
  }
  async recordedTime(reference: string, hash: string): Promise<number> {
    const store = await this.db();
    const rows = await store.querySql("SELECT payload FROM move_journal WHERE phase IN ('complete', 'retained', 'awaiting_trash', 'batch_trashing') AND instr(payload, ?) > 0 ORDER BY id DESC", [reference]);
    try {
      if (!rows.goToFirstRow()) { return 0; }
      do {
        const record = JSON.parse(rows.getString(0)) as VerifiedMove;
        const copy = record.targetKind === 'directory' ? record.copy : record.destinations?.find(item => item.kind === 'directory' && item.copy?.uri === reference)?.copy;
        if (copy?.uri === reference && copy.hash === hash && hash) {
          const taken = record.source.recordedTaken || record.source.taken || 0;
          return typeof taken === 'number' && Number.isFinite(taken) && taken > 0 ? taken : 0;
        }
      } while (rows.goToNextRow());
      return 0;
    } finally { rows.close(); }
  }
  async latestComplete(): Promise<VerifiedMove | undefined> {
    const rows = await (await this.db()).querySql("SELECT payload FROM move_journal WHERE phase = 'complete' ORDER BY id DESC LIMIT 1");
    try { return rows.goToFirstRow() ? JSON.parse(rows.getString(0)) as VerifiedMove : undefined; }
    finally { rows.close(); }
  }
  async save(record: VerifiedMove): Promise<void> {
    const store = await this.db();
    await store.executeSql('INSERT OR REPLACE INTO move_journal (id, phase, payload) VALUES (?, ?, ?)',
      [record.id, record.phase, JSON.stringify(record)]);
  }
  async saveBatch(records: VerifiedMove[]): Promise<void> {
    const store = await this.db(); store.beginTransaction();
    try {
      for (const record of records) {
        await store.executeSql('INSERT OR REPLACE INTO move_journal (id, phase, payload) VALUES (?, ?, ?)', [record.id, record.phase, JSON.stringify(record)]);
      }
      store.commit();
    } catch (error) { store.rollBack(); throw error as Error; }
  }
}
