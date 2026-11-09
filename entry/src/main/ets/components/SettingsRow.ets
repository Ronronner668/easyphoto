import { AppIcon } from './AppIcon';
import { AppTheme } from '../common/AppTheme';

@Component
export struct SettingsRow {
  @Prop title: string = '';
  @Prop description: string = '';
  @Prop icon: Resource = $r('app.media.lucide_folder');
  @Prop available: boolean = true;
  @Prop divider: boolean = false;
  activated: () => void = () => {};

  build() {
    Column() {
      Button({ type: ButtonType.Normal }) {
        Row({ space: 16 }) {
          AppIcon({ source: this.icon })
          Column({ space: 4 }) {
            Text(this.title).fontSize(AppTheme.bodySize).fontColor($r('app.color.text_primary'))
              .width('100%').textAlign(TextAlign.Start)
            if (this.description) {
              Text(this.description).fontSize(AppTheme.detailSize).fontColor($r('app.color.text_secondary'))
                .width('100%').textAlign(TextAlign.Start)
            }
          }.layoutWeight(1).alignItems(HorizontalAlign.Start)
          AppIcon({ source: $r('app.media.lucide_chevron_right_muted'), iconSize: 18 })
        }.width('100%').padding({ left: 20, right: 16, top: 18, bottom: 18 })
      }.width('100%').constraintSize({ minHeight: 72 }).borderRadius(0)
        .backgroundColor($r('app.color.surface')).enabled(this.available)
        .accessibilityText(this.title + (this.description ? '，' + this.description : ''))
        .onClick(() => { this.activated(); })
      if (this.divider) {
        Row() { Divider().color($r('app.color.divider')).strokeWidth(0.5) }.width('100%').padding({ left: 60, right: 20 })
      }
    }.width('100%')
  }
}
