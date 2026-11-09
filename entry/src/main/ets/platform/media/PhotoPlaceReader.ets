import { geoLocationManager } from '@kit.LocationKit';
import { abilityAccessCtrl, bundleManager, common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { image } from '@kit.ImageKit';
import { fileIo } from '@kit.CoreFileKit';
import { exifCoordinate, photoCoordinates } from '../../domain/usecases/PhotoCoordinates';
import { PhotoPlaceCache } from '../../data/repositories/PhotoPlaceCache';

export class PhotoPlaceInfo {
  text: string = '无地理位置信息';
  needsPermission: boolean = false;
}

// Uses photo EXIF and the system geocoder, without requesting device positioning.
export class PhotoPlaceReader {
  private context: common.UIAbilityContext;
  constructor(context: common.UIAbilityContext) { this.context = context; }

  private allowed(): boolean {
    const token = bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION).appInfo.accessTokenId;
    return abilityAccessCtrl.createAtManager().checkAccessTokenSync(token, 'ohos.permission.MEDIA_LOCATION') === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED;
  }

  async request(): Promise<boolean> {
    if (!this.allowed()) {
      await abilityAccessCtrl.createAtManager().requestPermissionsFromUser(this.context, ['ohos.permission.MEDIA_LOCATION']);
    }
    return this.allowed();
  }

  private async systemPlace(latitude: number, longitude: number): Promise<string> {
    let timer: number = -1;
    try {
      const request = geoLocationManager.getAddressesFromLocation({ latitude, longitude, maxItems: 1, locale: 'zh' })
        .then(addresses => {
          const province = addresses[0]?.administrativeArea?.trim() || '';
          const city = addresses[0]?.locality?.trim() || addresses[0]?.subAdministrativeArea?.trim() || '';
          return province && city && province !== city ? province + '·' + city : province || city;
        });
      const timeout = new Promise<string>(resolve => {
        timer = setTimeout(() => { resolve(''); }, 2000);
      });
      return await Promise.race([request, timeout]);
    } finally { if (timer !== -1) { clearTimeout(timer); } }
  }

  private async readCoordinates(reference: string): Promise<string[]> {
    const file = await fileIo.open(reference, fileIo.OpenMode.READ_ONLY);
    try {
      const source = image.createImageSource(file.fd);
      try {
        const options: image.ImagePropertyOptions = { index: 0, defaultValue: '' };
        return [
          await source.getImageProperty(image.PropertyKey.GPS_LATITUDE, options),
          await source.getImageProperty(image.PropertyKey.GPS_LATITUDE_REF, options),
          await source.getImageProperty(image.PropertyKey.GPS_LONGITUDE, options),
          await source.getImageProperty(image.PropertyKey.GPS_LONGITUDE_REF, options)
        ];
      } catch (error) {
        if ((error as BusinessError).code === 62980123) { return ['', '', '', '']; }
        throw error as Error;
      } finally { await source.release(); }
    } finally { await fileIo.close(file.fd); }
  }

  async read(reference: string): Promise<PhotoPlaceInfo> {
    const result = new PhotoPlaceInfo();
    if (!this.allowed()) {
      result.text = '尚未授权读取照片地点'; result.needsPermission = true; return result;
    }
    const coordinates = await this.readCoordinates(reference);
    const latitude = exifCoordinate(coordinates[0], coordinates[1], true);
    const longitude = exifCoordinate(coordinates[2], coordinates[3], false);
    if (!this.allowed()) {
      result.text = '照片地点授权已变化'; result.needsPermission = true; return result;
    }
    if (latitude === undefined || longitude === undefined) { return result; }

    const cache = new PhotoPlaceCache(this.context);
    let place = '';
    if (this.allowed()) {
      try { place = await this.systemPlace(latitude, longitude); }
      catch (_) { hilog.warn(0, 'PhotoPlaceReader', 'System geocoder unavailable; using local fallback'); }
      if (place && this.allowed()) {
        try { await cache.save(latitude, longitude, place); }
        catch (_) { hilog.warn(0, 'PhotoPlaceReader', 'Could not persist reverse geocoding cache'); }
      }
    }
    if (!place && this.allowed()) {
      try { place = await cache.load(latitude, longitude); }
      catch (_) { hilog.warn(0, 'PhotoPlaceReader', 'Reverse geocoding cache unreadable; using coordinates'); }
    }
    if (!this.allowed()) {
      result.text = '照片地点授权已变化'; result.needsPermission = true; return result;
    }
    result.text = place || photoCoordinates(coordinates[0], coordinates[1], coordinates[2], coordinates[3]);
    return result;
  }
}
