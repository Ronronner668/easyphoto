import { uiMaterial } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';

export class TitleButtonMaterial implements AttributeModifier<ButtonAttribute> {
  private material?: uiMaterial.Material;

  initialize(): void {
    try {
      if (uiMaterial.isImmersiveMaterialSupported()) {
        this.material = new uiMaterial.ImmersiveMaterial({
          style: uiMaterial.ImmersiveStyle.ULTRA_THIN, interactive: true, lightEffect: {}
        });
      }
    } catch (_) { hilog.info(0, 'TitleButtonMaterial', 'System title material is unavailable'); }
  }

  applyNormalAttribute(button: ButtonAttribute): void {
    if (this.material) {
      button.systemMaterial(this.material);
    } else {
      button.border({ radius: 24, width: 1, color: $r('sys.color.ohos_id_color_list_separator') });
    }
  }
}
