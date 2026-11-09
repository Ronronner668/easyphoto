import { AppIcon } from '../components/AppIcon';
import { common } from '@kit.AbilityKit';
import { AppTheme } from '../common/AppTheme';
import { Category } from '../domain/models/Category';
import { ConflictPolicy, MovePlanItem, PlanItemState } from '../domain/models/MovePlan';
import { MovePreviewViewModel } from '../viewmodels/MovePreviewViewModel';

@Entry
@Component
struct MovePreview {
  @State model: MovePreviewViewModel = new MovePreviewViewModel();
  aboutToAppear(): void { this.model.initialize(this.getUIContext().getHostContext() as common.UIAbilityContext); }
  aboutToDisappear(): void { this.model.dispose(); }
  build() {
    Scroll() {
      Column({ space: 16 }) {
        Row() {
          Button({ type: ButtonType.Circle }) { AppIcon({ source: $r('app.media.lucide_arrow_left') }) }.width(48).constraintSize({ minHeight: 48 }).backgroundColor(Color.Transparent).accessibilityText('返回').onClick(() => { this.getUIContext().getRouter().back(); })
          Text('相册分类预览').fontSize(24).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary'))
        }.width('100%')
        Text('先选照片，再选择目标分类。此页仅检查计划；逐张分类请返回整理工作台。')
          .fontSize(14).lineHeight(22).fontColor($r('app.color.text_secondary'))
        Button(`选择照片 · 已选 ${this.model.selection.items.length} 张`).width('100%').enabled(!this.model.busy)
          .onClick(() => { this.model.choose(); })
        Select(this.model.categories.categories.map((category: Category): SelectOption => ({ value: category.name })))
          .width('100%').value(this.model.categories.categories.find((category: Category) => category.id === this.model.categoryId)?.name || '尚无可用分类')
          .enabled(!this.model.busy && this.model.categories.categories.length > 0)
          .onSelect((index: number) => { this.model.selectCategory(index); })
        Select([{ value: '重名：跳过，不覆盖' }, { value: '重名：检查可用新名称' }]).width('100%')
          .value(this.model.policy === ConflictPolicy.Skip ? '重名：跳过，不覆盖' : '重名：检查可用新名称')
          .selected(this.model.policy === ConflictPolicy.Skip ? 0 : 1).enabled(!this.model.busy)
          .onSelect((index: number) => { this.model.setPolicy(index === 0 ? ConflictPolicy.Skip : ConflictPolicy.Rename); })
        Row({ space: 12 }) {
          Button('刷新分类').enabled(!this.model.busy).onClick(() => { this.model.refresh(); })
          Button('生成逐项计划').layoutWeight(1)
            .enabled(!this.model.busy && this.model.selection.items.length > 0 && !!this.model.categoryId)
            .onClick(() => { this.model.generate(); })
        }.width('100%')
        if (this.model.busy) { LoadingProgress().width(30).height(30) }
        Text(this.model.message).fontSize(14).lineHeight(22).fontColor($r('app.color.text_secondary'))
        if (this.model.plan) {
          Text(`${this.model.plan!.items.length} 项 · 可执行 0 项`).fontSize(20).fontColor($r('app.color.text_primary'))
          Text(this.model.plan!.requiredBytes === undefined ? '空间需求尚待实际检查，不能按 0 计算。' :
            `复制阶段预计至少需要 ${this.model.plan!.requiredBytes} 字节，执行前仍须核查。`)
            .fontSize(14).fontColor($r('app.color.text_secondary'))
          ForEach(this.model.plan!.items, (item: MovePlanItem, index: number) => {
            Column({ space: 10 }) {
              Text(`${index + 1}. ${item.source.name}`).fontSize(18).maxLines(2).fontColor($r('app.color.text_primary'))
              Text(`目标：${item.target?.name || '未绑定'} · ${item.state === PlanItemState.Skipped ? '跳过' : item.state === PlanItemState.Conflict ? '重名待处理' : '仅预览'}`)
                .fontSize(14).fontColor($r('app.color.text_secondary'))
              ForEach(item.reasons, (reason: string) => {
                Text(reason).fontSize(14).lineHeight(21).fontColor($r('app.color.text_secondary'))
              })
            }.padding(16).width('100%').alignItems(HorizontalAlign.Start)
              .backgroundColor($r('app.color.surface')).borderRadius(AppTheme.cardRadius)
          }, (item: MovePlanItem) => item.source.id)
          Button('请在工作台逐张分类').width('100%').enabled(false)
        }
      }.padding(AppTheme.pagePadding).width('100%')
    }.align(Alignment.TopStart).width('100%').height('100%').backgroundColor($r('app.color.page_background'))
  }
}
