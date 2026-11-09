import { uiMaterial } from '@kit.ArkUI';
import { hdsEffect } from '@kit.UIDesignKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

// This modifier must be hosted by Navigation's title area or a bottom TabBar.
// ImmersiveMaterial is not effective on a generic Row in the page content.
// Grouped actions have no separate idle material panels. Native pressed/hover states add light feedback.
export class PlaybackButtonMaterial implements AttributeModifier<ButtonAttribute> {
  private material?: uiMaterial.Material;
  private empty?: uiMaterial.Material;
  private resting?: VisualEffect;
  private pressed?: VisualEffect;
  private standalone: boolean;
  constructor(standalone: boolean = false) { this.standalone = standalone; }
  initialize(): void {
    try {
      if (uiMaterial.isImmersiveMaterialSupported()) {
        const empty = uiMaterial.Material.empty;
        this.material = new uiMaterial.ImmersiveMaterial({
          style: uiMaterial.ImmersiveStyle.ULTRA_THIN, materialColor: Color.Transparent,
          applyShadow: false, interactive: true, lightEffect: {}
        });
        this.empty = empty;
      }
    } catch (_) { hilog.info(0, 'PlaybackMaterial', 'Immersive action unavailable; using native light feedback'); }
    try {
      this.resting = new hdsEffect.HdsEffectBuilder().pressShadow(hdsEffect.PressShadowType.NONE)
        .pointLight({ sourceType: hdsEffect.PointLightSourceType.NONE }).buildEffect();
      this.pressed = new hdsEffect.HdsEffectBuilder().pressShadow(this.standalone ? hdsEffect.PressShadowType.BLEND_WHITE : hdsEffect.PressShadowType.NONE)
        .pointLight({ sourceType: hdsEffect.PointLightSourceType.SOFT,
          illuminatedType: this.standalone ? hdsEffect.PointLightIlluminatedType.BORDER_CONTENT : hdsEffect.PointLightIlluminatedType.NONE,
          options: { intensity: 0.35, height: 48, bloom: 0.1, color: $r('app.color.photo_foreground') } }).buildEffect();
    } catch (_) { hilog.info(0, 'PlaybackMaterial', 'Native action light feedback unavailable'); }
  }
  applyNormalAttribute(button: ButtonAttribute): void {
    button.backgroundColor(Color.Transparent);
    if (!this.standalone) { button.borderWidth(0).stateEffect(false); }
    if (this.material) { button.systemMaterial(this.standalone ? this.material : this.empty); }
    if (!this.material || !this.standalone) {
      if (this.standalone) { button.backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THIN); }
      if (this.resting) { button.visualEffect(this.resting); }
    }
  }
  applyPressedAttribute(button: ButtonAttribute): void { this.feedback(button); }
  applyHoveredAttribute(button: ButtonAttribute): void { this.feedback(button); }
  private feedback(button: ButtonAttribute): void {
    if (this.material && this.standalone) { button.systemMaterial(this.material); }
    else {
      if (this.material) { button.systemMaterial(this.empty); }
      if (this.pressed) { button.visualEffect(this.pressed); }
    }
  }
}
