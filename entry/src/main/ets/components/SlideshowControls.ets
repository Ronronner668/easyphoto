import { HdsTabs, hdsMaterial } from '@kit.UIDesignKit';
import { PlaybackButtonMaterial } from '../common/PlaybackChromeMaterial';
import { AppIcon } from './AppIcon';
import { ChromeRegion, ChromeInk } from '../domain/usecases/SlideshowContrast';

@Component
export struct SlideshowControls {
  @Prop playing: boolean = false;
  @Prop inks: ChromeInk[] = [];
  regionChanged: (region: ChromeRegion) => void = () => {};
  previous: () => void = () => {};
  toggle: () => void = () => {};
  next: () => void = () => {};
  private buttonMaterial: PlaybackButtonMaterial = new PlaybackButtonMaterial();
  aboutToAppear(): void { this.buttonMaterial.initialize(); }
  private dark(key: string): boolean { return this.inks.find(item => item.key === key)?.dark || false; }
  @Builder
  action(key: string, lightIcon: Resource, darkIcon: Resource, label: string, clicked: () => void) {
    Button({ type: ButtonType.Normal }) {
      AppIcon({ source: this.dark(key) ? darkIcon : lightIcon, iconSize: 24, haloRadius: 1,
        haloColor: this.dark(key) ? $r('app.color.playback_ink_halo_light') : $r('app.color.playback_ink_halo_dark') })
    }.width('100%').height(56).padding(0).borderRadius(20)
      .buttonStyle(ButtonStyleMode.TEXTUAL).attributeModifier(this.buttonMaterial)
      .accessibilityText(label).onClick(clicked)
      .onAreaChange((_old: Area, area: Area) => {
        this.regionChanged(new ChromeRegion(key, Number(area.globalPosition.x) + (Number(area.width) - 32) / 2,
          Number(area.globalPosition.y) + (Number(area.height) - 32) / 2, 32, 32));
      })
  }
  @Builder
  previousTab() {
    this.action('previous', $r('app.media.lucide_skip_back_on_photo'), $r('app.media.lucide_skip_back_dark_on_photo'), '上一张', this.previous)
  }
  @Builder
  toggleTab() {
    this.action('toggle', this.playing ? $r('app.media.lucide_pause_on_photo') : $r('app.media.lucide_play_on_photo'),
      this.playing ? $r('app.media.lucide_pause_dark_on_photo') : $r('app.media.lucide_play_dark_on_photo'),
      this.playing ? '暂停' : '播放', this.toggle)
  }
  @Builder
  nextTab() {
    this.action('next', $r('app.media.lucide_skip_forward_on_photo'), $r('app.media.lucide_skip_forward_dark_on_photo'), '下一张', this.next)
  }
  build() {
    HdsTabs({ index: 1 }) {
      TabContent() {}.tabBar(this.previousTab)
      TabContent() {}.tabBar(this.toggleTab)
      TabContent() {}.tabBar(this.nextTab)
    }.width('100%').height(64).constraintSize({ maxWidth: 320 })
      .barPosition(BarPosition.End).vertical(false).barOverlap(true).barHeight(56).scrollable(false).animationDuration(0)
      .barFloatingStyle({
        barWidth: { smallWidth: 304, mediumWidth: 304, largeWidth: 304 }, barSideMargin: 0, barBottomMargin: 4,
        gradientMask: { maskColor: Color.Transparent, maskHeight: 1 },
        systemMaterialEffect: { materialType: hdsMaterial.MaterialType.ADAPTIVE, materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE }
      })
      // Playback actions keep their own click handlers; there is no content navigation or duplicate tab click handler.
      .onContentWillChange(() => false)
      .backgroundColor(Color.Transparent)
  }
}
