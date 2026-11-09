export enum ProbeStatus {
  Observed = 'observed',
  Cancelled = 'cancelled',
  Blocked = 'blocked',
  Failed = 'failed'
}

// A single API observation is not a verified product capability.
export class ProbeResult {
  canOpenPermissionSettings: boolean = false;
  title: string;
  status: ProbeStatus;
  detail: string;
  timestamp: number;
  errorCode: number;
  constructor(title: string, status: ProbeStatus, detail: string,
    timestamp: number = Date.now(), errorCode: number = 0) {
    this.title = title;
    this.status = status;
    this.detail = detail;
    this.timestamp = timestamp;
    this.errorCode = errorCode;
  }
}

export class ProbePhoto {
  favorite: boolean = false;
  storagePath: string = '';
  added: number = 0;
  modified: number = 0;
  subtype: number = 0;
  bytes: number = 0;
  taken: number = 0;
  timeRecorded: boolean = false;
  placePermissionNeeded: boolean = false;
  place: string = '未提供地点';
  uri: string;
  name: string;
  width: number;
  height: number;
  constructor(uri: string, name: string, width: number, height: number) {
    this.uri = uri;
    this.name = name;
    this.width = width;
    this.height = height;
  }
}

export class PhotoProbeResult {
  result: ProbeResult;
  photo?: ProbePhoto;
  constructor(result: ProbeResult, photo?: ProbePhoto) {
    this.result = result;
    this.photo = photo;
  }
}
