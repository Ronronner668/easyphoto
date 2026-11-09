import { common } from '@kit.AbilityKit';
import { relationalStore } from '@kit.ArkData';
import { Category, CategorySnapshot, defaultCategories, TargetKind, TargetRef } from '../../domain/models/Category';
import { validateCategories } from '../../domain/usecases/CategoryRules';
import { ExperimentError } from '../../domain/models/Experiment';

// Access is serialized by CategoryService. Each save checks the revision inside the same SQL transaction.
export class CategoryRepository {
  private context: common.UIAbilityContext;
  private store: relationalStore.RdbStore | undefined = undefined;
  constructor(context: common.UIAbilityContext) { this.context = context; }

  private async database(): Promise<relationalStore.RdbStore> {
    if (this.store) { return this.store; }
    const store = await relationalStore.getRdbStore(this.context, { name: 'organizer.db', securityLevel: relationalStore.SecurityLevel.S1 });
    await store.executeSql('CREATE TABLE IF NOT EXISTS organizer_meta (id INTEGER PRIMARY KEY CHECK(id=1), schema_version INTEGER NOT NULL, revision INTEGER NOT NULL)');
    await store.executeSql('CREATE TABLE IF NOT EXISTS categories (id TEXT PRIMARY KEY, name TEXT NOT NULL, position INTEGER NOT NULL UNIQUE, album_uri TEXT NOT NULL, album_name TEXT NOT NULL, folder_uri TEXT NOT NULL, folder_name TEXT NOT NULL)');
    const meta = await store.querySql('SELECT schema_version, revision FROM organizer_meta WHERE id=1');
    let initialize = false;
    try {
      initialize = meta.rowCount === 0;
      if (!initialize && (!meta.goToFirstRow() || meta.getLong(0) !== 1)) {
        throw new ExperimentError('分类数据库版本不受当前应用支持，保留记录并停止写入。');
      }
    } finally { meta.close(); }
    if (initialize) {
      store.beginTransaction();
      try {
        const existing = await store.querySql('SELECT id FROM categories');
        try { if (existing.rowCount !== 0) { throw new ExperimentError('分类版本记录缺失，未覆盖已有分类。'); } }
        finally { existing.close(); }
        const initial = defaultCategories();
        for (let index = 0; index < initial.length; index++) { await this.insert(store, initial[index], index); }
        await store.executeSql('INSERT INTO organizer_meta (id, schema_version, revision) VALUES (1, 1, 0)');
        store.commit();
      } catch (error) { store.rollBack(); throw error as Error; }
    }
    this.store = store;
    return store;
  }

  private async revision(store: relationalStore.RdbStore): Promise<number> {
    const meta = await store.querySql('SELECT revision FROM organizer_meta WHERE id=1');
    try {
      if (!meta.goToFirstRow()) { throw new ExperimentError('分类版本记录缺失。'); }
      return meta.getLong(0);
    } finally { meta.close(); }
  }

  async load(): Promise<CategorySnapshot> {
    const store = await this.database();
    const snapshot = new CategorySnapshot();
    snapshot.revision = await this.revision(store);
    const result = await store.querySql('SELECT id, name, position, album_uri, album_name, folder_uri, folder_name FROM categories ORDER BY position');
    try {
      if (result.rowCount > 30) { throw new ExperimentError('分类数量超过当前上限，保留数据并停止写入。'); }
      while (result.goToNextRow()) {
        if (result.getLong(2) !== snapshot.categories.length) { throw new ExperimentError('分类排序记录不完整，保留数据并停止写入。'); }
        const item = new Category(result.getString(0), result.getString(1));
        const album = result.getString(3);
        const folder = result.getString(5);
        if (album) { item.album = new TargetRef(TargetKind.Album, album, result.getString(4)); }
        if (folder) { item.directory = new TargetRef(TargetKind.Directory, folder, result.getString(6)); }
        snapshot.categories.push(item);
      }
      validateCategories(snapshot.categories);
      return snapshot;
    } finally { result.close(); }
  }

  private async insert(store: relationalStore.RdbStore, item: Category, index: number): Promise<void> {
    await store.executeSql('INSERT INTO categories (id, name, position, album_uri, album_name, folder_uri, folder_name) VALUES (?, ?, ?, ?, ?, ?, ?)',
      [item.id, item.name, index, item.album?.reference || '', item.album?.name || '', item.directory?.reference || '', item.directory?.name || '']);
  }

  async save(snapshot: CategorySnapshot): Promise<CategorySnapshot> {
    validateCategories(snapshot.categories);
    const store = await this.database();
    store.beginTransaction();
    try {
      if (await this.revision(store) !== snapshot.revision) { throw new ExperimentError('此页面的分类已经过期，请刷新后再保存，未覆盖其他页面的修改。'); }
      await store.executeSql('DELETE FROM categories');
      for (let index = 0; index < snapshot.categories.length; index++) { await this.insert(store, snapshot.categories[index], index); }
      await store.executeSql('UPDATE organizer_meta SET revision=revision+1 WHERE id=1');
      store.commit();
    } catch (error) { store.rollBack(); throw error as Error; }
    return this.load();
  }
}
