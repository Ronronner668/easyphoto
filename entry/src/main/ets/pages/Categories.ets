import { AppIcon } from '../components/AppIcon';
import { common } from '@kit.AbilityKit';
import { Category, TargetKind, TargetRef } from '../domain/models/Category';
import { CategoryViewModel } from '../viewmodels/CategoryViewModel';
import { AppTheme } from '../common/AppTheme';

@Entry
@Component
struct Categories {
  @State model: CategoryViewModel = new CategoryViewModel();
  @State picking: string = '';
  @State naming: boolean = false;
  @State albumTab: number = 0;
  aboutToAppear(): void { this.model.initialize(this.getUIContext().getHostContext() as common.UIAbilityContext); }
  aboutToDisappear(): void { this.model.dispose(); }
  onBackPress(): boolean {
    if (this.picking) { this.picking = ''; return true; }
    if (this.naming) { this.naming = false; return true; }
    return false;
  }
  private async selectTarget(category: Category): Promise<void> {
    this.picking = category.id; this.albumTab = 0;
    await this.model.loadAlbums();
  }
  private async chooseAlbum(index: number): Promise<void> {
    const target = this.model.albums[index];
    await this.model.bindAlbum(this.picking, index);
    if (this.model.snapshot.categories.find((item: Category) => item.id === this.picking)?.album?.reference === target.reference) {
      this.picking = '';
    } else { this.getUIContext().getPromptAction().showToast({ message: this.model.message }); }
  }
  build() {
    Stack() {
      Column({ space: 16 }) {
        Row() {
          Button('取消').height(48).backgroundColor($r('app.color.accent_soft')).fontColor($r('app.color.text_primary')).backgroundColor(Color.Transparent).fontColor($r('app.color.accent'))
            .onClick(() => { this.getUIContext().getRouter().back(); })
          Text('分类与绑定').fontSize(22).fontWeight(FontWeight.Medium).layoutWeight(1).textAlign(TextAlign.Center)
          Button('保存').height(48).backgroundColor($r('app.color.accent_soft')).fontColor($r('app.color.text_primary')).enabled(this.model.ready && !this.model.busy)
            .onClick(async () => { if (await this.model.commit()) { this.getUIContext().getRouter().back(); }
              else { this.getUIContext().getPromptAction().showToast({ message: this.model.message }); } })
        }.width('100%')
        if (this.model.busy) { LoadingProgress().width(24).height(24) }
        Scroll() {
          Column({ space: 10 }) {
            ForEach(this.model.snapshot.categories, (category: Category, index: number) => {
              Column({ space: 10 }) {
              Row({ space: 10 }) {
                AppIcon({ source: $r('app.media.lucide_images') })
                Column({ space: 6 }) {
                  Text(category.name).fontSize(17).fontColor($r('app.color.text_primary')).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                Button({ type: ButtonType.Circle }) { AppIcon({ source: $r('app.media.lucide_ellipsis') }) }
                  .width(48).height(48).backgroundColor(Color.Transparent).accessibilityText('管理分类' + category.name)
                  .bindMenu([
                    { value: '重命名', action: () => { this.model.edit(category); this.naming = true; } },
                    { value: '上移', action: () => { this.model.reorder(category.id, -1); } },
                    { value: '下移', action: () => { this.model.reorder(category.id, 1); } },
                    { value: '解除相册绑定', action: () => { this.model.unbind(category.id, TargetKind.Album); } },
                    { value: '删除分类', action: () => { this.model.remove(category.id); } }
                  ])
              }.width('100%')
              Column({ space: 8 }) {
                  Button(`相册 · ${category.album?.name || '选择'}`).constraintSize({ minHeight: 48 }).width('100%').fontSize(14).borderRadius(12).backgroundColor($r('app.color.accent_soft')).fontColor($r('app.color.text_primary')).enabled(this.model.ready && !this.model.busy).onClick(() => { this.selectTarget(category); })
              }.width('100%')
              }.padding(16).width('100%').borderRadius(AppTheme.cardRadius).backgroundColor($r('app.color.surface'))
            }, (category: Category, index: number) => JSON.stringify(category) + index)
          }.width('100%')
        }.align(Alignment.TopStart).layoutWeight(1).width('100%')
        Button('新增分类').height(48).backgroundColor($r('app.color.accent_soft')).fontColor($r('app.color.text_primary')).width('100%').enabled(this.model.ready && !this.model.busy)
          .onClick(() => { this.model.cancelEdit(); this.naming = true; })
      }.padding(20).width('100%').height('100%').backgroundColor($r('app.color.page_background'))
      if (this.picking) {
        Column() {
        Column({ space: 12 }) {
          Row() {
            Text('选择相册').fontSize(22).fontWeight(FontWeight.Bold).layoutWeight(1)
            Button('关闭').height(48).backgroundColor($r('app.color.accent_soft')).fontColor($r('app.color.text_primary')).onClick(() => { this.picking = ''; })
          }.width('100%')
            Row({ space: 12 }) {
              Button('已有').constraintSize({ minHeight: 48 }).layoutWeight(1).backgroundColor(this.albumTab === 0 ? $r('app.color.accent') : $r('app.color.accent_soft')).fontColor(this.albumTab === 0 ? $r('app.color.on_accent') : $r('app.color.text_primary')).onClick(() => { this.albumTab = 0; this.model.loadAlbums(); })
              Button('新增').constraintSize({ minHeight: 48 }).layoutWeight(1).backgroundColor(this.albumTab === 1 ? $r('app.color.accent') : $r('app.color.accent_soft')).fontColor(this.albumTab === 1 ? $r('app.color.on_accent') : $r('app.color.text_primary')).onClick(() => { this.albumTab = 1; })
            }.width('100%')
            if (this.albumTab === 1) {
              Text('系统新建相册接口只向系统应用开放。请在系统图库新建，返回后刷新选择。').fontSize(15).fontColor($r('app.color.text_secondary'))
              Button('打开系统图库').height(48).width('100%').backgroundColor($r('app.color.accent_soft')).fontColor($r('app.color.text_primary')).onClick(async () => {
                try { await (this.getUIContext().getHostContext() as common.UIAbilityContext).startAbility({ bundleName: 'com.huawei.hmos.photos', abilityName: 'com.huawei.hmos.photos.MainAbility' }); }
                catch (_) { this.getUIContext().getPromptAction().showToast({ message: '请打开系统图库新建相册后返回。' }); }
              })
            } else {
            if (this.model.busy) { LoadingProgress().width(32).height(32) }
            else if (!this.model.albums.length) {
              Text('暂无可选相册').fontSize(18)
              Text(this.model.message).fontSize(13).fontColor($r('app.color.text_secondary'))
              Button('刷新').height(48).backgroundColor($r('app.color.accent_soft')).fontColor($r('app.color.text_primary')).onClick(() => { this.model.loadAlbums(); })
            }
            Scroll() {
              Column({ space: 8 }) {
                ForEach(this.model.albums, (target: TargetRef, index: number) => {
                  Button() {
                    Row({ space: 12 }) {
                      AppIcon({ source: $r('app.media.lucide_images') })
                      Text(target.name).fontSize(17).layoutWeight(1).textAlign(TextAlign.Start)
                    }.padding(16).width('100%')
                  }.width('100%').height(64).borderRadius(16).backgroundColor($r('app.color.surface'))
                    .fontColor($r('app.color.text_primary')).enabled(!this.model.busy).onClick(() => { this.chooseAlbum(index); })
                }, (target: TargetRef) => target.reference)
              }.width('100%')
            }.align(Alignment.TopStart).layoutWeight(1).width('100%')
            }
        }.padding(24).width('92%').height('80%').constraintSize({ maxWidth: 600, maxHeight: 640 })
          .borderRadius(28).backgroundColor($r('app.color.surface')).shadow({ radius: 24, color: $r('app.color.shadow_soft') })
        }.width('100%').height('100%').justifyContent(FlexAlign.Center).backgroundColor($r('app.color.scrim'))
      }
      if (this.naming) {
        Column() {
        Column({ space: 16 }) {
          Text(this.model.editingId ? '重命名' : '新增分类').fontSize(22)
          TextInput({ text: this.model.draft, placeholder: '分类名称' }).maxLength(16).onChange((value: string) => { this.model.draft = value; })
          Row({ space: 12 }) {
            Button('取消').height(48).backgroundColor($r('app.color.accent_soft')).fontColor($r('app.color.text_primary')).onClick(() => { this.naming = false; this.model.cancelEdit(); })
            Button('确定').height(48).backgroundColor($r('app.color.accent_soft')).fontColor($r('app.color.text_primary')).onClick(async () => { await this.model.saveName();
              if (!this.model.draft) { this.naming = false; } else { this.getUIContext().getPromptAction().showToast({ message: this.model.message }); }
            })
          }
        }.padding(24).width('90%').borderRadius(AppTheme.cardRadius).backgroundColor($r('app.color.surface'))
          .shadow({ radius: 24, color: $r('app.color.shadow_soft') })
        }.width('100%').height('100%').justifyContent(FlexAlign.Center).backgroundColor($r('app.color.scrim'))
      }
    }.width('100%').height('100%').foregroundColor($r('app.color.text_primary'))
  }
}
