import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';

export class PhotoPlaceCache {
  private context: common.UIAbilityContext;
  constructor(context: common.UIAbilityContext) { this.context = context; }

  async load(latitude: number, longitude: number): Promise<string> {
    const store = await preferences.getPreferences(this.context, { name: 'photo_place_cache_v1' });
    const value = await store.get(latitude.toString() + ',' + longitude.toString(), '');
    return typeof value === 'string' && value.length <= 128 ? value.trim() : '';
  }

  async save(latitude: number, longitude: number, place: string): Promise<void> {
    const store = await preferences.getPreferences(this.context, { name: 'photo_place_cache_v1' });
    await store.put(latitude.toString() + ',' + longitude.toString(), place);
    await store.flush();
  }
}
