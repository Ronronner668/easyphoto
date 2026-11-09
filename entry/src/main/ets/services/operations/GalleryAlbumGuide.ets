import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
export class GalleryAlbumGuide {
  private context: common.UIAbilityContext;
  constructor(context: common.UIAbilityContext) { this.context = context; }
  async shouldShow(): Promise<boolean> {
    return await (await preferences.getPreferences(this.context, { name: 'workbench_settings' })).get('showNewAlbumHint', true) !== false;
  }
  async remember(show: boolean): Promise<void> {
    const store = await preferences.getPreferences(this.context, { name: 'workbench_settings' });
    await store.put('showNewAlbumHint', show); await store.flush();
  }
  // Opens Gallery only. No private API/deep link promises to open its creation dialog.
  open(): Promise<void> {
    return this.context.startAbility({ bundleName: 'com.huawei.hmos.photos', abilityName: 'com.huawei.hmos.photos.MainAbility' });
  }
}
