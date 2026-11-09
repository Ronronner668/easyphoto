import { AppTheme } from '../common/AppTheme';
@CustomDialog
export struct NewAlbumHint {
  controller: CustomDialogController;
  confirmed: (showAgain: boolean) => void = () => {};
  dismissed: (showAgain: boolean) => void = () => {};
  @State private showAgain: boolean = true;
  build() {
    Column({ space: 16 }) {
      Text('新建相册').fontSize(22).fontColor($r('app.color.text_primary')).width('100%')
      Text('请前往系统图库，在相册页新建相册。返回后刷新即可选择。').fontSize(16).fontColor($r('app.color.text_secondary')).width('100%')
      Button('跳转至图库新建').type(ButtonType.Capsule).buttonStyle(ButtonStyleMode.TEXTUAL).border({ radius: 999, width: 1, color: $r('sys.color.ohos_id_color_list_separator') }).fontColor($r('app.color.accent')).width('100%').constraintSize({ minHeight: 48 }).onClick(() => { this.confirmed(this.showAgain); this.controller.close(); })
      Button('稍等一下').type(ButtonType.Capsule).buttonStyle(ButtonStyleMode.TEXTUAL).border({ radius: 999, width: 1, color: $r('sys.color.ohos_id_color_list_separator') }).width('100%').constraintSize({ minHeight: 48 }).fontColor($r('app.color.text_primary')).onClick(() => { this.dismissed(this.showAgain); this.controller.close(); })
      Row({ space: 8 }) {
        Checkbox({ name: 'showAgain' }).select(this.showAgain).onChange(value => { this.showAgain = value; })
        Text('下次仍显示此提示').fontSize(14).fontColor($r('app.color.text_secondary'))
      }.width('100%')
    }.padding(24).width('100%').borderRadius(AppTheme.cardRadius).backgroundColor($r('app.color.surface'))
  }
}
