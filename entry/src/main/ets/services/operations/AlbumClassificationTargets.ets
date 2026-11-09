import { common } from '@kit.AbilityKit';
import { Category, CategorySnapshot } from '../../domain/models/Category';
import { LocalTargetProvider } from '../../platform/media/LocalTargetProvider';

export class AlbumClassificationTargets {
  private context: common.UIAbilityContext;
  constructor(context: common.UIAbilityContext) { this.context = context; }
  async load(): Promise<CategorySnapshot> {
    const snapshot = new CategorySnapshot();
    snapshot.categories = (await new LocalTargetProvider(this.context).albums(false)).map(target => {
      const item = new Category(target.reference, target.name); item.album = target; return item;
    });
    return snapshot;
  }
}
