import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { ProbeResult } from '../../domain/models/ProbeResult';

export class ProbeRepository {
  async load(context: common.UIAbilityContext): Promise<ProbeResult[]> {
    const store = await preferences.getPreferences(context, { name: 'capability_probe' });
    const raw = await store.get('observations', '[]') as string;
    return JSON.parse(raw) as ProbeResult[];
  }

  async save(context: common.UIAbilityContext, results: ProbeResult[]): Promise<void> {
    const store = await preferences.getPreferences(context, { name: 'capability_probe' });
    // Reports contain outcomes/codes only. No selected URIs or filenames are persisted.
    await store.put('observations', JSON.stringify(results.slice(0, 30)));
    await store.flush();
  }
}
