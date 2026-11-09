import { AppIcon } from '../components/AppIcon';
import { common } from '@kit.AbilityKit';
import { ProbeViewModel } from '../viewmodels/ProbeViewModel';
import { ProbeAction } from '../domain/models/ProbeGateway';
import { ProbeResult, ProbeStatus } from '../domain/models/ProbeResult';
import { AppTheme } from '../common/AppTheme';

@Entry
@Component
struct CapabilityProbe {
  @State model: ProbeViewModel = new ProbeViewModel();

  aboutToAppear(): void {
    this.model.load(this.getUIContext().getHostContext() as common.UIAbilityContext);
  }

  private run(action?: ProbeAction): void {
    this.model.execute(this.getUIContext().getHostContext() as common.UIAbilityContext, action);
  }

  private statusLabel(status: ProbeStatus): string {
    switch (status) {
      case ProbeStatus.Observed: return '已取得调用结果';
      case ProbeStatus.Cancelled: return '已取消';
      case ProbeStatus.Blocked: return '条件不足';
      case ProbeStatus.Failed: return '未完成';
    }
  }

  @Builder
  probeButton(label: string, action: ProbeAction) {
    Button(label).width('100%').constraintSize({ minHeight: 48 }).fontColor($r('app.color.accent'))
      .backgroundColor($r('app.color.accent_soft')).enabled(!this.model.busy)
      .onClick(() => { this.run(action); })
  }

  build() {
    Scroll() {
      Column({ space: 18 }) {
        Button({ type: ButtonType.Circle }) { AppIcon({ source: $r('app.media.lucide_arrow_left') }) }.width(48).constraintSize({ minHeight: 48 }).accessibilityText('返回').onClick(() => { this.getUIContext().getRouter().back(); })
          .backgroundColor(Color.Transparent).fontColor($r('app.color.accent')).alignSelf(ItemAlign.Start)
        Text('设备能力验证').fontSize(28).fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary')).width('100%')
        Button('进入平台操作实验室').width('100%').constraintSize({ minHeight: 48 }).backgroundColor($r('app.color.accent'))
          .fontColor($r('app.color.on_accent')).enabled(!this.model.busy)
          .onClick(() => { this.getUIContext().getRouter().pushUrl({ url: 'pages/PlatformLab' }); })
        Text('请使用可丢弃的测试样本。每个结果只记录本次调用；相册分类和回收站状态须逐项核验。')
          .fontSize(14).lineHeight(23).fontColor($r('app.color.text_secondary'))
        Column({ space: 12 }) {
          Button('选择一张测试照片').width('100%').constraintSize({ minHeight: 48 }).backgroundColor($r('app.color.accent'))
            .fontColor($r('app.color.on_accent')).enabled(!this.model.busy).onClick(() => { this.run(); })
          this.probeButton('检查图库权限', ProbeAction.Permissions)
          this.probeButton('申请图库读取权限', ProbeAction.RequestRead)
          if (this.model.permissionSettingsAvailable) {
            this.probeButton('前往设置授权图库读取', ProbeAction.ReadSettings)
          }
          Text('选图只授权所选照片。批量读取需单独申请；已有授权时，系统不会重复弹窗。')
            .fontSize(14).lineHeight(21).fontColor($r('app.color.text_secondary'))
          this.probeButton('检查系统相册读取', ProbeAction.Albums)
        }
        if (this.model.busy) {
          LoadingProgress().width(32).height(32).color($r('app.color.accent'))
          Text('正在处理，请稍候').fontColor($r('app.color.text_secondary'))
        }
        if (this.model.notice.length > 0) {
          Text(this.model.notice).fontSize(14).fontColor($r('app.color.warning'))
        }
        if (this.model.photo) {
          Column({ space: 8 }) {
            Image(this.model.photo.uri).width('100%').height(240).objectFit(ImageFit.Contain)
              .onError(() => { this.model.notice = '预览未能显示；请重新选图检查资源访问。'; })
            Text(this.model.photo.name).fontSize(14).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
              .fontColor($r('app.color.text_primary'))
            Text(`${this.model.photo.width} × ${this.model.photo.height}`).fontSize(14)
              .fontColor($r('app.color.text_secondary'))
          }.padding(16).backgroundColor($r('app.color.surface')).borderRadius(AppTheme.cardRadius)
        }
        Text('验证记录').fontSize(20).fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary')).width('100%')
        if (this.model.results.length === 0) {
          Text('尚无设备调用记录').fontSize(14).fontColor($r('app.color.text_secondary'))
        }
        ForEach(this.model.results, (result: ProbeResult) => {
          Column({ space: 8 }) {
            Text(result.title).fontSize(17).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
            Text(this.statusLabel(result.status)).fontSize(14).fontColor($r('app.color.accent'))
            Text(result.detail).fontSize(14).lineHeight(22).fontColor($r('app.color.text_secondary'))
            Text(new Date(result.timestamp).toLocaleString()).fontSize(14).fontColor($r('app.color.text_secondary'))
          }.alignItems(HorizontalAlign.Start).width('100%').padding(18)
            .backgroundColor($r('app.color.surface')).borderRadius(18)
        })
        Text('仅保留最近 30 条结果，不保存所选照片位置。')
          .fontSize(14).fontColor($r('app.color.text_secondary'))
      }.padding(AppTheme.pagePadding).width('100%').alignItems(HorizontalAlign.Start)
    }.width('100%').height('100%').backgroundColor($r('app.color.page_background'))
  }
}
