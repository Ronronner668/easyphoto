@Component
export struct EmptyState {
  title: string = '';
  message: string = '';

  build() {
    Column({ space: 16 }) {
      Text('拾').fontSize(44).fontWeight(FontWeight.Lighter).fontColor($r('app.color.accent'))
        .width(92).height(92).textAlign(TextAlign.Center)
        .backgroundColor($r('app.color.accent_soft')).borderRadius(28)
      Text(this.title).fontSize(23).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
      Text(this.message).fontSize(16).lineHeight(24).fontColor($r('app.color.text_secondary'))
        .textAlign(TextAlign.Center)
    }.width('100%').padding({ top: 48, bottom: 40, left: 12, right: 12 })
  }
}
