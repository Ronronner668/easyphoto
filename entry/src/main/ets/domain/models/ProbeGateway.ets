import { PhotoProbeResult, ProbeResult } from './ProbeResult';

export enum ProbeAction { Permissions, Albums, RequestRead, ReadSettings }

// Business-facing port: no platform Context, PhotoAsset, File or Picker types.
export interface ProbeGateway {
  selectPhoto(): Promise<PhotoProbeResult>;
  run(action: ProbeAction): Promise<ProbeResult>;
}
