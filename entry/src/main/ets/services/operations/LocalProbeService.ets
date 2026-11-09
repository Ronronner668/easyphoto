import { common } from '@kit.AbilityKit';
import { ProbeAction, ProbeGateway } from '../../domain/models/ProbeGateway';
import { PhotoProbeResult, ProbeResult } from '../../domain/models/ProbeResult';
import { MediaProbe } from '../../platform/media/MediaProbe';
import { PermissionProbe } from '../../platform/permissions/PermissionProbe';

export class LocalProbeService implements ProbeGateway {
  private context: common.UIAbilityContext;
  constructor(context: common.UIAbilityContext) { this.context = context; }

  selectPhoto(): Promise<PhotoProbeResult> {
    return new MediaProbe().selectPhoto(this.context);
  }

  async run(action: ProbeAction): Promise<ProbeResult> {
    switch (action) {
      case ProbeAction.Permissions: return new PermissionProbe().inspect();
      case ProbeAction.RequestRead: return new PermissionProbe().requestRead(this.context);
      case ProbeAction.ReadSettings: return new PermissionProbe().requestReadOnSettings(this.context);
      case ProbeAction.Albums: return new MediaProbe().inspectAlbums(this.context);
    }
  }
}
