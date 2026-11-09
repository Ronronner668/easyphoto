import { AppIcon } from './AppIcon';
import { UI_SPRING } from '../common/UiMotion';
import { AppTheme } from '../common/AppTheme';
import { ProbePhoto } from '../domain/models/ProbeResult';

@Component
export struct PhotoDetails {
  @Prop photo: ProbePhoto = new ProbePhoto('', '', 1, 1);
  @Prop dateFormat: string = 'YYYY/MM/DD';
  @Prop status: string = '';
  closed: () => void = () => {};
  @Prop placeBusy: boolean = false;
  @Prop placeFeedback: string = '';
  private time(value: number): string {
    if (!Number.isFinite(value) || value <= 0) { return '未提供'; }
    const date = new Date(value * 1000); const year = date.getFullYear().toString();
    const month = (date.getMonth() + 1).toString().padStart(2, '0'); const day = date.getDate().toString().padStart(2, '0');
    const prefix = this.dateFormat === 'YYYY-MM-DD' ? `${year}-${month}-${day}` : this.dateFormat === 'YYYY年MM月DD日' ? `${year}年${month}月${day}日` : `${year}/${month}/${day}`;
    return `${prefix} ${date.getHours().toString().padStart(2, '0')}:${date.getMinutes().toString().padStart(2, '0')}:${date.getSeconds().toString().padStart(2, '0')}`;
  }
  private value(index: number): string {
    if (index === 0) { return this.photo.name; }
    if (index === 1) { return this.time(this.photo.taken) + (this.photo.timeRecorded ? '（原图记录）' : ''); }
    if (index === 2) { return this.time(this.photo.added); }
    if (index === 3) { return this.time(this.photo.modified); }
    if (index === 4) { return this.placeBusy ? '正在读取…' : this.placeFeedback || this.photo.place || '无地理位置信息'; }
    if (index === 5) { return `${this.photo.width} × ${this.photo.height} 像素`; }
    if (index === 6) { return `${this.photo.bytes.toLocaleString()} 字节 · ${this.photo.bytes >= 1048576 ? (this.photo.bytes / 1048576).toFixed(2) + ' MB' : (this.photo.bytes / 1024).toFixed(2) + ' KB'}`; }
    if (index === 7) { const dot = this.photo.name.lastIndexOf('.'); return dot > 0 ? this.photo.name.slice(dot + 1).toUpperCase() : '未提供'; }
    if (index === 8) { return this.photo.subtype === 1 ? '截图' : this.photo.subtype === 3 ? '动态照片' : this.photo.subtype === 4 ? '连拍' : '普通照片'; }
    if (index === 9) { return this.photo.uri.startsWith('file://docs/') ? '历史文档（只读）' : '系统图库'; }
    if (index === 10) { return this.photo.storagePath || '系统未提供此照片的相册路径（图库资源无公开物理路径）'; }
    if (index === 11) { return this.photo.uri; }
    return this.status || '未分类';
  }
  build() {
    Column() {
      Column({ space: 16 }) {
        Row() {
          Text('照片信息').fontColor($r('app.color.text_primary')).fontSize(22).fontWeight(FontWeight.Medium).layoutWeight(1).maxLines(1)
          Button({ type: ButtonType.Circle }) { AppIcon({ source: $r('app.media.lucide_x'), iconSize: 20 }) }
            .width(AppTheme.touchSize).height(AppTheme.touchSize).padding(0).buttonStyle(ButtonStyleMode.TEXTUAL).border({ radius: 24, width: 1, color: $r('sys.color.ohos_id_color_list_separator') })
            .accessibilityText('关闭照片信息').onClick(() => { this.closed(); })
        }.width('100%')
        Scroll() {
          Column() {
            ForEach(['名称', '拍摄时间', '添加时间', '修改时间', '地点', '尺寸', '文件大小', '文件格式', '图片类型', '来源', '存储路径', '资源引用', '整理状态'], (label: string, index: number) => {
              Row({ space: 12 }) {
                Text(label).fontSize(14).maxLines(1).minFontSize(10).maxFontSize(14).width(88).flexShrink(0).fontColor($r('app.color.text_secondary'))
                Text(this.value(index)).fontSize(index === 0 ? 15 : 14).wordBreak(WordBreak.BREAK_ALL).fontColor($r('app.color.text_primary')).layoutWeight(1)
              }.width('100%').padding({ top: 12, bottom: 12 }).constraintSize({ minHeight: 48 })
              Divider().color($r('app.color.divider')).strokeWidth(0.5)
            })
          }.width('100%')
        }.layoutWeight(1).width('100%').align(Alignment.TopStart).edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      }.padding(24).width('100%').height('76%').borderRadius({ topLeft: 28, topRight: 28 })
        .backgroundColor($r('app.color.surface'))
    }.width('100%').height('100%').justifyContent(FlexAlign.End).backgroundColor($r('app.color.scrim')).transition(TransitionEffect.opacity(0).animation({ curve: UI_SPRING }))
  }
}
