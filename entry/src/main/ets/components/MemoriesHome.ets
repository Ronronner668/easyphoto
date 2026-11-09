import { common } from '@kit.AbilityKit';
import { AppTheme } from '../common/AppTheme';
import { GalleryAlbumsViewModel } from '../viewmodels/GalleryAlbumsViewModel';
import { GalleryAlbum } from '../domain/models/GalleryAlbum';
import { SlideshowRecord } from '../domain/models/Slideshow';
import { SlideshowRepository } from '../data/repositories/SlideshowRepository';
import { GalleryAlbumTile } from './GalleryAlbumTile';
import { PhotoThumbnail } from './PhotoThumbnail';
import { AppIcon } from './AppIcon';

@Component
export struct MemoriesHome {
  @Prop @Watch('visibilityChanged') active: boolean = false;
  @Prop @Watch('visibilityChanged') refreshKey: number = 0;
  @State private model: GalleryAlbumsViewModel = new GalleryAlbumsViewModel();
  @State private recent: SlideshowRecord[] = [];
  @State private historyError: string = '';
  @State private query: string = '';
  @State private areaWidth: number = 320;
  @State private opening: boolean = false;
  private generation: number = 0;
  private mounted: boolean = false;
  aboutToAppear(): void {
    this.mounted = true;
    this.model.initialize(this.getUIContext().getHostContext() as common.UIAbilityContext);
    this.visibilityChanged();
  }
  aboutToDisappear(): void { this.mounted = false; this.generation++; this.model.close(); }
  private visibilityChanged(): void {
    if (!this.mounted) { return; }
    if (!this.active) { this.generation++; this.model.suspend(); return; }
    this.refresh();
  }
  private async refresh(): Promise<void> {
    const version = ++this.generation;
    await this.model.refresh();
    if (version !== this.generation || !this.active) { return; }
    if (!this.model.authorized) { this.recent = []; return; }
    try {
      const data = await new SlideshowRepository(this.getUIContext().getHostContext() as common.UIAbilityContext).load();
      if (version !== this.generation) { return; }
      this.recent = data.albums.filter(item => !!item.current && this.model.albums.some(album => album.reference === item.reference))
        .sort((a, b) => b.updated - a.updated).slice(0, 3);
      this.historyError = '';
    } catch (_) { if (version === this.generation) { this.historyError = '最近观看记录读取失败，请刷新重试。'; } }
  }
  private groups(): string[] { return ['我的相册', '收藏与图库', '应用来源']; }
  private rows(group: string): GalleryAlbum[][] {
    const columns = Math.max(2, Math.floor((this.areaWidth + 16) / 160));
    const items = this.model.albums.filter(album => album.name.toLowerCase().includes(this.query.trim().toLowerCase()) &&
      (group === '我的相册' ? album.type === 0 : group === '应用来源' ? album.type === 2048 : album.type !== 0 && album.type !== 2048));
    const rows: GalleryAlbum[][] = [];
    for (let index = 0; index < items.length; index += columns) { rows.push(items.slice(index, index + columns)); }
    return rows;
  }
  private slots(used: number): number[] {
    const slots: number[] = [];
    const columns = Math.max(2, Math.floor((this.areaWidth + 16) / 160));
    for (let index = used; index < columns; index++) { slots.push(index); }
    return slots;
  }
  private async open(album: GalleryAlbum): Promise<void> {
    if (this.opening || this.model.loading) { return; }
    this.opening = true;
    try { await this.getUIContext().getRouter().pushUrl({ url: 'pages/Slideshow', params: { album } }); }
    catch (_) { this.getUIContext().getPromptAction().showToast({ message: '回忆未能打开，请重试。' }); }
    finally { this.opening = false; }
  }
  private recentAlbum(record: SlideshowRecord): GalleryAlbum | undefined {
    return this.model.albums.find(album => album.reference === record.reference);
  }
  private async openRecent(record: SlideshowRecord): Promise<void> {
    const album = this.recentAlbum(record);
    if (album) { await this.open(album); }
    else { this.refresh(); }
  }
  build() {
    Scroll() {
      Column({ space: 24 }) {
        Row({ space: 12 }) {
          Column({ space: 8 }) {
            Text('回忆').fontSize(AppTheme.titleSize).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary'))
          }.layoutWeight(1).alignItems(HorizontalAlign.Start)
          Button('刷新').type(ButtonType.Capsule).constraintSize({ minWidth: 48, minHeight: 48 }).buttonStyle(ButtonStyleMode.TEXTUAL)
            .border({ radius: 999, width: 1, color: $r('sys.color.ohos_id_color_list_separator') })
            .fontColor($r('app.color.text_primary')).enabled(!this.model.loading).onClick(() => { this.refresh(); })
        }.width('100%').padding({ top: 24 })
        Search({ placeholder: '搜索相册', value: this.query }).onChange(value => { this.query = value; }).width('100%')
        if (this.model.loading) { LoadingProgress().width(32).height(32).color($r('app.color.loading_indicator')) }
        if (this.model.error || this.historyError) {
          Text(this.model.error || this.historyError).fontColor($r('app.color.warning')).fontSize(14).width('100%')
        }
        if (!this.model.authorized && !this.model.loading) {
          Text('允许读取图库，即可播放已经整理好的相册。').fontColor($r('app.color.text_secondary'))
          Button('允许访问图库').constraintSize({ minHeight: 48 }).onClick(() => { this.model.refresh(true); })
          Button('前往权限设置').constraintSize({ minHeight: 48 }).buttonStyle(ButtonStyleMode.TEXTUAL)
            .onClick(() => { this.model.refresh(true, true); })
        }
        if (this.model.authorized) {
          if (!this.query && this.recent.length) {
            Column({ space: 12 }) {
              Text('继续回忆').fontSize(20).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary')).width('100%')
              ForEach(this.recent, (record: SlideshowRecord) => {
                Button({ type: ButtonType.Normal }) {
                  Row({ space: 16 }) {
                    PhotoThumbnail({ reference: this.recentAlbum(record)?.cover || '', fit: ImageFit.Cover }).width(64).height(64).borderRadius(12).clip(true)
                    Column({ space: 6 }) {
                      Text(this.recentAlbum(record)?.name || record.name).fontSize(17).fontColor($r('app.color.text_primary')).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                      Text('从上次停留的照片继续').fontSize(13).fontColor($r('app.color.text_secondary'))
                    }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                    AppIcon({ source: $r('app.media.lucide_chevron_right') })
                  }.width('100%').padding(12)
                }.width('100%').padding(0).backgroundColor($r('app.color.surface')).borderRadius(18)
                  .enabled(!this.opening && !this.model.loading).onClick(() => { this.openRecent(record); })
              }, (record: SlideshowRecord) => record.reference)
            }.width('100%')
          }
          ForEach(this.groups(), (group: string) => {
            if (this.rows(group).length) {
              Column({ space: 16 }) {
                Text(group).fontSize(20).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary')).width('100%')
                ForEach(this.rows(group), (row: GalleryAlbum[]) => {
                  Row({ space: 16 }) {
                    ForEach(row, (album: GalleryAlbum) => {
                      Column() {
                        GalleryAlbumTile({ album, actionLabel: '回看和放映此相册', activated: () => { this.open(album); } })
                          .enabled(!this.opening && !this.model.loading)
                      }.layoutWeight(1)
                    }, (album: GalleryAlbum) => JSON.stringify(album))
                    ForEach(this.slots(row.length), (slot: number) => { Blank().layoutWeight(1) }, (slot: number) => String(slot))
                  }.width('100%').alignItems(VerticalAlign.Top)
                }, (row: GalleryAlbum[]) => JSON.stringify(row))
              }.width('100%')
            }
          }, (group: string) => group)
          if (!this.model.loading && !this.model.error && !this.groups().some(group => this.rows(group).length > 0)) {
            Text(this.query ? '没有找到匹配的相册' : '图库中还没有可播放的相册').fontColor($r('app.color.text_secondary'))
          }
        }
      }.width('100%').constraintSize({ maxWidth: 1120 }).padding({ left: 20, right: 20, bottom: 112 })
        .onAreaChange((_old: Area, area: Area) => { if (Number(area.width) > 0) { this.areaWidth = Number(area.width) - 40; } })
    }.width('100%').height('100%').align(Alignment.Top).edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
  }
}
