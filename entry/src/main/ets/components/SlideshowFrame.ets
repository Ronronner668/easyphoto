import { ChromeRegion, ChromeInk, ContrastGrid, contrastInk } from '../domain/usecases/SlideshowContrast';
import { SlideshowContrastSource } from '../platform/media/SlideshowContrastSource';
import { SlideshowViewport } from '../domain/usecases/SlideshowViewport';
import { ViewerTapGuard } from '../domain/usecases/ViewerTapGuard';
import { image } from '@kit.ImageKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { SlideshowImageSource } from '../platform/media/SlideshowImageSource';

@Component
export struct SlideshowFrame {
  @Prop @Watch('reload') reference: string = '';
  @Prop @Watch('preload') nextReference: string = '';
  @Prop @Watch('updateContrast') regions: ChromeRegion[] = [];
  contrastChanged: (inks: ChromeInk[]) => void = () => {};
  private contrastGrid?: ContrastGrid;
  private inks: ChromeInk[] = [];
  private frameX: number = 0;
  private frameY: number = 0;
  @Prop controlsVisible: boolean = true;
  @Prop @Watch('playbackChanged') playing: boolean = false;
  @Prop imageWidth: number = 1;
  @Prop imageHeight: number = 1;
  tapped: () => void = () => {};
  zoomStarted: () => void = () => {};
  swipeStarted: () => void = () => {};
  swipeEnded: (direction: number) => void = () => {};
  @State private zoomScale: number = 1;
  @State private x: number = 0;
  @State private y: number = 0;
  private viewport: SlideshowViewport = new SlideshowViewport();
  private tapGuard: ViewerTapGuard = new ViewerTapGuard();
  private navigating: boolean = false;
  private pinchActive: boolean = false;
  @Prop faded: boolean = true;
  loaded: (reference: string) => void = () => {};
  failed: (reference: string) => void = () => {};
  @State private pixels: image.PixelMap | undefined = undefined;
  @State private opacityValue: number = 0;
  @State private unavailable: boolean = false;
  private generation: number = 0;
  private preloadGeneration: number = 0;
  private cached?: image.PixelMap;
  private cachedReference: string = '';
  private viewportWidth: number = 0;
  private viewportHeight: number = 0;
  private disposed: boolean = false;
  aboutToAppear(): void { this.disposed = false; }
  private release(pixels?: image.PixelMap): void {
    if (pixels) { pixels.release().catch(() => { hilog.warn(0, 'Slideshow', 'Photo display resource release failed'); }); }
  }
  private async decode(reference: string): Promise<image.PixelMap> {
    return new SlideshowImageSource().load(reference,
      this.getUIContext().vp2px(this.viewportWidth), this.getUIContext().vp2px(this.viewportHeight));
  }
  private async reload(): Promise<void> {
    if (this.disposed || this.viewportWidth <= 0 || this.viewportHeight <= 0) { return; }
    this.resetTransform();
    const version = ++this.generation;
    const reference = this.reference;
    this.unavailable = false;
    const contrastTask = this.readContrast(reference);
    try {
      let pixels: image.PixelMap;
      if (this.cached && this.cachedReference === reference) {
        pixels = this.cached; this.cached = undefined; this.cachedReference = '';
      } else { pixels = await this.decode(reference); }
      const grid = await contrastTask;
      if (version !== this.generation || this.disposed) { this.release(pixels); return; }
      this.contrastGrid = grid;
      if (grid) { this.updateContrast(); } else { this.publishInks(this.regions.map(region => new ChromeInk(region.key, false))); }
      const previous = this.pixels;
      this.opacityValue = 0; this.pixels = pixels;
      this.getUIContext().animateTo({ duration: this.faded ? 350 : 0 }, () => { this.opacityValue = 1; });
      this.release(previous); this.loaded(reference); this.preload();
    } catch (_) {
      if (version === this.generation && !this.disposed) {
        this.contrastGrid = undefined; this.publishInks(this.regions.map(region => new ChromeInk(region.key, false)));
        this.release(this.pixels); this.pixels = undefined; this.unavailable = true; this.failed(reference);
      }
    }
  }
  private async readContrast(reference: string): Promise<ContrastGrid | undefined> {
    try { return await new SlideshowContrastSource().load(reference); }
    catch (_) {
      if (!this.disposed) { hilog.info(0, 'Slideshow', 'Local contrast sampling unavailable; using light controls'); }
      return undefined;
    }
  }
  private publishInks(next: ChromeInk[]): void {
    if (next.length === this.inks.length && next.every((ink, index) => ink.key === this.inks[index].key && ink.dark === this.inks[index].dark)) { return; }
    this.inks = next; this.contrastChanged(next);
  }
  private updateContrast(): void {
    const grid = this.contrastGrid;
    if (!grid || this.disposed) { return; }
    this.publishInks(this.regions.map(region => {
      const local = new ChromeRegion(region.key, region.x - this.frameX, region.y - this.frameY, region.width, region.height);
      const wasDark = this.inks.find(ink => ink.key === region.key)?.dark || false;
      return new ChromeInk(region.key, contrastInk(grid, local, this.viewportWidth, this.viewportHeight,
        this.zoomScale, this.x, this.y, wasDark));
    }));
  }
  private async preload(): Promise<void> {
    const version = ++this.preloadGeneration;
    const reference = this.nextReference;
    if (this.cachedReference === reference) { return; }
    this.release(this.cached); this.cached = undefined; this.cachedReference = '';
    if (this.disposed || !reference || reference === this.reference || !this.pixels) { return; }
    try {
      const pixels = await this.decode(reference);
      if (this.disposed || version !== this.preloadGeneration || reference !== this.nextReference) { this.release(pixels); return; }
      this.cached = pixels; this.cachedReference = reference;
    } catch (_) {
      // Speculative loading has no user-visible outcome. The active frame retries and reports failures.
    }
  }
  aboutToDisappear(): void {
    this.contrastGrid = undefined;
    this.disposed = true; this.generation++; this.preloadGeneration++;
    this.release(this.pixels); this.pixels = undefined; this.release(this.cached); this.cached = undefined;
    this.cachedReference = ''; this.viewportWidth = 0; this.viewportHeight = 0;
  }
  private updateTransform(): void {
    this.viewport.clamp(this.viewportWidth, this.viewportHeight, this.imageWidth, this.imageHeight);
    this.zoomScale = this.viewport.scale; this.x = this.viewport.x; this.y = this.viewport.y; this.updateContrast();
  }
  private resetTransform(): void { this.viewport.reset(); this.updateTransform(); }
  private playbackChanged(): void { if (this.playing) { this.resetTransform(); } }
  private finishPan(offset: number): void {
    if (this.navigating) { this.swipeEnded(Math.abs(offset) >= 40 ? (offset < 0 ? 1 : -1) : 0); }
    this.navigating = false; this.tapGuard.finish('pan');
  }
  build() {
    Stack() {
      if (this.pixels) {
        Image(this.pixels).objectFit(ImageFit.Contain).width('100%').height('100%')
          .opacity(this.opacityValue).draggable(false)
          .scale({ x: this.zoomScale, y: this.zoomScale }).translate({ x: this.x, y: this.y }).hitTestBehavior(HitTestMode.None)
          .accessibilityText('正在放映的照片')
      } else if (this.unavailable) {
        Text('照片暂不可读取').fontColor($r('app.color.photo_foreground'))
      } else { LoadingProgress().width(40).height(40).color($r('app.color.loading_indicator')) }
    }.width('100%').height('100%').clip(true)
      .gesture(GestureGroup(GestureMode.Exclusive,
        GestureGroup(GestureMode.Parallel,
          PinchGesture({ fingers: 2 })
            .onActionStart(() => {
              this.tapGuard.start('pinch');
              this.pinchActive = this.viewport.beginPinch(this.controlsVisible);
              if (this.pinchActive) {
                if (this.navigating) { this.swipeEnded(0); this.navigating = false; }
                this.zoomStarted();
              }
            })
            .onActionUpdate((event: GestureEvent) => {
              this.viewport.pinch(event.scale); this.updateTransform();
            })
            .onActionEnd(() => { this.pinchActive = false; this.viewport.endPinch(); this.tapGuard.finish('pinch'); })
            .onActionCancel(() => { this.pinchActive = false; this.viewport.endPinch(); this.tapGuard.finish('pinch'); }),
          PanGesture({ fingers: 1, direction: PanDirection.All, distance: 10 })
            .onActionStart(() => {
              this.tapGuard.start('pan'); this.viewport.beginPan();
              this.navigating = this.zoomScale <= 1 && !this.pinchActive;
              if (this.navigating) { this.swipeStarted(); }
            })
            .onActionUpdate((event: GestureEvent) => {
              if (this.zoomScale > 1 && !this.pinchActive) { this.viewport.pan(event.offsetX, event.offsetY); this.updateTransform(); }
            })
            .onActionEnd((event: GestureEvent) => { this.finishPan(Math.abs(event.offsetX) > Math.abs(event.offsetY) ? event.offsetX : 0); })
            .onActionCancel(() => { this.finishPan(0); })
        ),
        TapGesture().onAction(() => { if (this.tapGuard.canClose()) { this.tapped(); } })
      ))
      .onAreaChange((_old: Area, area: Area) => {
        const first = this.viewportWidth === 0;
        this.frameX = Number(area.globalPosition.x); this.frameY = Number(area.globalPosition.y);
        this.viewportWidth = Number(area.width); this.viewportHeight = Number(area.height);
        this.updateTransform();
        if (first && this.viewportWidth > 0) { this.reload(); }
      })
  }
}
