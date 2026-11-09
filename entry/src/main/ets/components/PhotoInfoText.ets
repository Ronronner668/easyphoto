@Component
export struct PhotoInfoText {
  @Prop @Watch('schedule') content: string = '';
  @Prop textSize: number = 14;
  @Prop lines: number = 2;
  @State private scrolling: boolean = false;
  @State private blockHeight: number = 0;
  private measuredWidth: number = 0;
  private timer: number = -1;
  private version: number = 0;
  private disposed: boolean = false;
  aboutToAppear(): void { this.disposed = false; }
  aboutToDisappear(): void { this.disposed = true; this.version++; this.clear(); }
  private clear(): void { if (this.timer >= 0) { clearTimeout(this.timer); this.timer = -1; } }
  private schedule(): void {
    this.clear(); this.scrolling = false; const version = ++this.version;
    if (!this.content || this.measuredWidth <= 0 || this.disposed) { return; }
    const measure = this.getUIContext().getMeasureUtils();
    const full = Number(measure.measureTextSize({ textContent: this.content, fontSize: this.textSize, constraintWidth: this.measuredWidth, wordBreak: WordBreak.BREAK_ALL }).height);
    const bounded = Number(measure.measureTextSize({ textContent: this.content, fontSize: this.textSize,
      constraintWidth: this.measuredWidth, wordBreak: WordBreak.BREAK_ALL, maxLines: this.lines }).height);
    this.blockHeight = this.getUIContext().px2vp(bounded);
    if (full > bounded + 1) {
      this.timer = setTimeout(() => { if (!this.disposed && version === this.version) { this.scrolling = true; } }, 3000);
    }
  }
  build() {
    Stack({ alignContent: Alignment.Start }) {
      if (this.scrolling) {
        Marquee({ start: true, src: this.content, step: 1, loop: -1, fromStart: true, delay: 3000 })
          .width('100%').fontSize(this.textSize).fontColor($r('app.color.text_primary')).accessibilityText(this.content)
      } else {
        Text(this.content).fontSize(this.textSize).fontColor($r('app.color.text_primary')).width('100%')
          .wordBreak(WordBreak.BREAK_ALL).maxLines(this.lines).textOverflow({ overflow: TextOverflow.Ellipsis })
      }
    }.width('100%').constraintSize({ minHeight: this.blockHeight }).onAreaChange((_old: Area, area: Area) => {
      const width = Number(area.width); if (width > 0 && Math.abs(width - this.measuredWidth) > 1) { this.measuredWidth = width; this.schedule(); }
    })
  }
}
