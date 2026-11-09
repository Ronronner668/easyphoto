import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { AlbumExperiment, AlbumPhase, ExperimentError } from '../../domain/models/Experiment';

export class ExperimentRepository {
  private static archiveSequence: number = 0;
  private context: common.UIAbilityContext;
  constructor(context: common.UIAbilityContext) { this.context = context; }

  async loadAlbum(): Promise<AlbumExperiment> {
    const store = await preferences.getPreferences(this.context, { name: 'platform_experiments_v1' });
    const raw = await store.get('album', '') as string;
    if (!raw) { return new AlbumExperiment(); }
    const value = JSON.parse(raw) as AlbumExperiment;
    if (!Object.values(AlbumPhase).includes(value.phase) || typeof value.assetUri !== 'string' || typeof value.createdByLab !== 'boolean') {
      throw new ExperimentError('实验记录不完整，未自动创建新会话；请保留现有数据并核对。');
    }
    return value;
  }

  async saveAlbum(session: AlbumExperiment): Promise<void> {
    const store = await preferences.getPreferences(this.context, { name: 'platform_experiments_v1' });
    await store.put('album', JSON.stringify(session));
    await store.flush();
  }

  async archiveAlbum(session: AlbumExperiment): Promise<void> {
    const current = await this.loadAlbum();
    if (current.id !== session.id || current.phase !== session.phase || current.assetUri !== session.assetUri) {
      throw new ExperimentError('旧页面不能归档或清空另一页的实验记录。');
    }
    await this.archive('album', JSON.stringify(session));
    await this.saveAlbum(new AlbumExperiment());
  }

  private async archive(kind: string, record: string): Promise<void> {
    const store = await preferences.getPreferences(this.context, { name: 'platform_experiments_v1' });
    const indexKey = `${kind}_archive_index`;
    const index = JSON.parse(await store.get(indexKey, '[]') as string) as string[];
    const key = `${kind}_archive_${Date.now()}_${++ExperimentRepository.archiveSequence}`;
    // Keep each record separate instead of exceeding the Preferences per-value string limit.
    await store.put(key, record);
    await store.put(indexKey, JSON.stringify([key, ...index].slice(0, 20)));
    await store.flush();
    for (let position = 19; position < index.length; position++) { await store.delete(index[position]); }
    await store.flush();
  }
}
