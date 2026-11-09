// 单机发布版备用代码：Index 已注释账号导入与调用，本文件目前不接入应用入口。
import { common } from '@kit.AbilityKit';
import { AppTheme } from '../common/AppTheme';
import { AppIcon } from './AppIcon';
import { HuaweiAccountViewModel } from '../viewmodels/HuaweiAccountViewModel';
@Component
export struct HuaweiAccountCard {
  @State private avatarFailed: boolean = false;
  @State private expanded: boolean = false;
  @State private model: HuaweiAccountViewModel = new HuaweiAccountViewModel();
  aboutToAppear(): void { this.model.initialize(this.getUIContext().getHostContext() as common.UIAbilityContext); }
  aboutToDisappear(): void { this.model.dispose(); }
  private confirmLogout(): void {
    this.getUIContext().showAlertDialog({ title: '退出登录？', message: '退出后仍可正常使用照片整理。',
      primaryButton: { value: '取消', action: () => {} },
      secondaryButton: { value: '退出登录', action: () => { this.model.logout(); this.expanded = false; } } });
  }
  @Builder
  avatar(size: number) {
    Stack() {
      if (this.model.profile?.avatar && !this.avatarFailed) {
        Image(this.model.profile.avatar).width(size).height(size).objectFit(ImageFit.Cover).draggable(false).onError(() => { this.avatarFailed = true; })
      } else { AppIcon({ source: $r('app.media.lucide_user_round'), iconSize: size / 2 }) }
    }.width(size).height(size).borderRadius(size / 2).clip(true).backgroundColor($r('app.color.accent_soft'))
  }
  @Builder
  accountSheet() {
    Column({ space: 32 }) {
      Row() {
        Text('华为账号').fontSize(24).fontWeight(FontWeight.Bold).layoutWeight(1).fontColor($r('app.color.text_primary'))
        Button({ type: ButtonType.Circle }) { AppIcon({ source: $r('app.media.lucide_x'), iconSize: 20 }) }
          .width(48).height(48).padding(0).buttonStyle(ButtonStyleMode.TEXTUAL).border({ radius: 24, width: 1, color: $r('sys.color.ohos_id_color_list_separator') }).accessibilityText('关闭账号页面').onClick(() => { this.expanded = false; })
      }.width('100%')
      this.avatar(112)
      Text(this.model.profile?.nickname || '未登录').fontSize(26).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
      Button('退出登录').type(ButtonType.Capsule).buttonStyle(ButtonStyleMode.TEXTUAL).border({ radius: 999, width: 1, color: $r('sys.color.ohos_id_color_list_separator') }).width('100%').constraintSize({ minHeight: 56 }).fontColor($r('app.color.text_primary')).onClick(() => { this.confirmLogout(); })
    }.padding(24).width('100%').height('100%').backgroundColor($r('app.color.console_background'))
  }
  build() {
    Column({ space: 12 }) {
      Button({ type: ButtonType.Normal }) {
        Row({ space: 16 }) {
          this.avatar(56)
          Column({ space: 6 }) {
            Text(this.model.profile?.nickname || '未登录').fontSize(22).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).fontColor($r('app.color.text_primary'))
            if (!this.model.profile) { Text('未登录不影响软件使用').fontSize(14).fontColor($r('app.color.text_secondary')) }
          }.layoutWeight(1).alignItems(HorizontalAlign.Start)
          AppIcon({ source: $r('app.media.lucide_chevron_right_muted'), iconSize: 18 })
        }.width('100%').padding(24)
      }.width('100%').backgroundColor(Color.Transparent).enabled(!this.model.busy)
        .accessibilityText(this.model.profile ? '查看华为账号，' + this.model.profile.nickname : '登录华为账号，未登录不影响软件使用')
        .onClick(() => { if (this.model.profile) { this.expanded = true; } else { this.avatarFailed = false; this.model.login(); } })
        .bindSheet($$this.expanded, this.accountSheet(), { height: SheetSize.LARGE, showClose: false, dragBar: false })
      if (this.model.busy) { LoadingProgress().width(24).height(24).color($r('app.color.loading_indicator')) }
      if (this.model.message) { Text(this.model.message).fontSize(14).fontColor($r('app.color.text_secondary')).padding({ left: 24, right: 24, bottom: 16 }) }
    }.width('100%').borderRadius(AppTheme.cardRadius).clip(true).backgroundColor($r('app.color.surface'))
  }
}
