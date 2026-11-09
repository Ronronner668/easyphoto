import { AppIcon } from '../components/AppIcon';
import { common } from '@kit.AbilityKit';
import { ExperimentViewModel, LabCommand } from '../viewmodels/ExperimentViewModel';
import { AlbumPhase, LabAlbum } from '../domain/models/Experiment';
import { AppTheme } from '../common/AppTheme';

@Entry
@Component
struct PlatformLab {
  @State model: ExperimentViewModel = new ExperimentViewModel();
  @State confirmed: boolean = false;
  @State manuallyChecked: boolean = false;

  aboutToAppear(): void {
    this.model.initialize(this.getUIContext().getHostContext() as common.UIAbilityContext);
  }

  @Builder
  action(label: string, command: LabCommand, write: boolean = false) {
    Button(label).width('100%').constraintSize({ minHeight: 48 }).fontSize(14)
      .fontColor($r('app.color.accent')).backgroundColor($r('app.color.accent_soft'))
      .enabled(!this.model.busy && this.model.ready && (!write || this.confirmed))
      .onClick(() => { this.model.run(command, this.confirmed); })
  }

  @Builder
  albumSelector(second: boolean) {
    Select(this.model.albums.map((album: LabAlbum): SelectOption => ({ value: album.name })))
      .value(second ? (this.model.album.albumB?.name || '选择测试相册 B') : (this.model.album.albumA?.name || '选择测试相册 A'))
      .enabled(!this.model.busy && this.model.ready && this.model.album.phase === AlbumPhase.Empty)
      .onSelect((index: number) => { this.model.selectAlbum(index, second); })
      .width('100%')
  }

  build() {
    Scroll() {
      Column({ space: 18 }) {
        Button({ type: ButtonType.Circle }) { AppIcon({ source: $r('app.media.lucide_arrow_left') }) }.width(48).constraintSize({ minHeight: 48 }).accessibilityText('返回').backgroundColor(Color.Transparent).fontColor($r('app.color.accent'))
          .onClick(() => { this.getUIContext().getRouter().back(); })
        Text('平台操作实验室').fontSize(27).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary'))
        Text('逐项验证真实接口。图片只使用本页生成的彩色 JPEG；不选择私人照片进行修改。')
          .fontSize(15).lineHeight(24).fontColor($r('app.color.text_secondary'))
        Row({ space: 10 }) {
          Checkbox({ name: 'generatedSamplesOnly' }).select(this.confirmed).onChange((value: boolean) => { this.confirmed = value; })
          Text('我确认使用本页生成的可丢弃样本，并会到系统应用核对结果。')
            .fontSize(14).lineHeight(22).fontColor($r('app.color.text_primary')).layoutWeight(1)
        }
        if (this.model.busy) { LoadingProgress().width(32).height(32) }
        Text(this.model.status).fontSize(14).lineHeight(23).fontColor($r('app.color.warning'))

        Column({ space: 12 }) {
          Text('相册归属与图库回收站').fontSize(21).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
          this.action('申请图库写入权限', LabCommand.RequestWrite)
          if (this.model.writeSettingsAvailable) { this.action('前往设置授权图库写入', LabCommand.WriteSettings) }
          this.action('加载已有用户相册', LabCommand.LoadAlbums)
          this.albumSelector(false)
          this.albumSelector(true)
          Text('请先创建两个空专用相册。添加接口会生成副本；原图、A 副本、B 副本分别核对。移除 B 副本会请求回收站，不是恢复到 A。')
            .fontSize(14).lineHeight(22).fontColor($r('app.color.text_secondary'))
          this.action('1 · 创建一张测试图片', LabCommand.CreateSample, true)
          this.action('2 · 向 A 添加样本副本并核对', LabCommand.AddA, true)
          this.action('3 · 向 B 添加另一副本（A 保留）', LabCommand.AddB, true)
          this.action('4 · 将本轮 B 副本移入回收站', LabCommand.RemoveB, true)
          this.action('5 · 原样本移入系统图库回收站', LabCommand.AlbumTrash, true)
          this.action('重新核查样本与相册状态', LabCommand.AlbumCheck)
          if (this.model.album.assetUri.length > 0) {
            Image(this.model.album.assetUri).height(140).width('100%').objectFit(ImageFit.Contain)
              .onError(() => { this.model.status = '样本预览不可用；请使用重新核查并检查系统图库，不能仅凭预览判断删除。'; })
          }
          Text(this.model.album.message).fontSize(14).lineHeight(23).fontColor($r('app.color.text_secondary'))
          Text(`A：${this.model.album.albumA?.name || '未选择'}；B：${this.model.album.albumB?.name || '未选择'}`)
            .fontSize(14).fontColor($r('app.color.text_secondary'))
          if (this.model.album.lastError) {
            Text(`${this.model.album.lastError} 系统接口正常返回：${this.model.album.lastNativeReturned ? '是' : '否或结果未知'}；` +
              `错误码：${this.model.album.lastErrorCode || '未返回'}`)
              .fontSize(14).lineHeight(22).fontColor($r('app.color.warning'))
          }
          Text(`实验记录：${this.model.album.id || '尚未创建'} · ${this.model.album.phase}`)
            .fontSize(14).fontColor($r('app.color.text_secondary'))
        }.width('100%').padding(18).backgroundColor($r('app.color.surface')).borderRadius(AppTheme.cardRadius)

        Text('实验记录保存在应用私有存储，包含核查所需的样本引用与摘要。中断后不自动重放写操作，不提供永久删除入口。')
          .fontSize(14).lineHeight(21).fontColor($r('app.color.text_secondary'))
        Row({ space: 10 }) {
          Checkbox({ name: 'externalCheckComplete' }).select(this.manuallyChecked)
            .onChange((value: boolean) => { this.manuallyChecked = value; })
          Text('我已在对应系统应用核对本轮样本，并确认可以归档记录。')
            .fontSize(14).lineHeight(22).fontColor($r('app.color.text_primary')).layoutWeight(1)
        }
        Button('归档相册实验并开启新一轮').width('100%').enabled(this.manuallyChecked && !this.model.busy)
          .onClick(() => { this.model.finishRound(this.manuallyChecked); this.manuallyChecked = false; this.confirmed = false; })
      }.padding(AppTheme.pagePadding).width('100%').alignItems(HorizontalAlign.Start)
    }.height('100%').width('100%').backgroundColor($r('app.color.page_background')).foregroundColor($r('app.color.text_primary'))
  }
}
