import { ProbeAction, ProbeGateway } from '../models/ProbeGateway';
import { PhotoProbeResult, ProbeResult } from '../models/ProbeResult';

export class ProbeUseCase {
  private gateway: ProbeGateway;
  constructor(gateway: ProbeGateway) { this.gateway = gateway; }

  selectPhoto(): Promise<PhotoProbeResult> {
    return this.gateway.selectPhoto();
  }

  run(action: ProbeAction): Promise<ProbeResult> {
    return this.gateway.run(action);
  }
}
