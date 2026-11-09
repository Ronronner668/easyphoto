import { AppTheme } from '../common/AppTheme';

// SVG strokes are explicit in base/dark resources; no dependency on currentColor or fillColor.
@Component
export struct AppIcon {
  @Prop source: Resource = $r('app.media.lucide_folder');
  @Prop iconSize: number = AppTheme.iconSize;

  @Prop haloColor: ResourceColor = Color.Transparent;
  @Prop haloRadius: number = 0;

  build() {
    Image(this.source).width(this.iconSize).height(this.iconSize).objectFit(ImageFit.Contain)
      .shadow({ radius: this.haloRadius, color: this.haloColor })
      .draggable(false).hitTestBehavior(HitTestMode.None).accessibilityLevel('no')
  }
}
