import { common } from '@kit.AbilityKit';
import { GalleryAlbum } from '../domain/models/GalleryAlbum';
import { GalleryAlbumSource } from '../platform/media/GalleryAlbumSource';
import { PermissionProbe } from '../platform/permissions/PermissionProbe';

@Observed
export class GalleryAlbumsViewModel {
  albums: GalleryAlbum[] = [];
  loading: boolean = false;
  authorized: boolean = false;
  error: string = '';
  private generation: number = 0;
  private context: common.UIAbilityContext | undefined = undefined;
  initialize(context: common.UIAbilityContext): void { this.context = context; }
  suspend(): void { this.generation++; this.loading = false; }
  close(): void { this.generation++; this.loading = false; this.context = undefined; }
  async refresh(request: boolean = false, settings: boolean = false): Promise<void> {
    if (!this.context || this.loading) { return; }
    const context = this.context; const generation = ++this.generation;
    this.loading = true; this.error = '';
    try {
      const permission = new PermissionProbe();
      if (request && !permission.canReadLibrary()) {
        if (settings) { await permission.requestReadOnSettings(context); }
        else { await permission.requestRead(context); }
      }
      if (generation !== this.generation) { return; }
      this.authorized = permission.canReadLibrary();
      if (!this.authorized) { this.albums = []; return; }
      const albums = await new GalleryAlbumSource(context).list();
      if (generation === this.generation) { this.albums = albums; }
    } catch (_) {
      if (generation === this.generation) { this.error = '相册读取失败，请检查图库权限后重试。'; }
    } finally { if (generation === this.generation) { this.loading = false; } }
  }
}
