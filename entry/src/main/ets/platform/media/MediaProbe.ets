import { common } from '@kit.AbilityKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { dataSharePredicates } from '@kit.ArkData';
import { fileIo } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { PhotoProbeResult, ProbePhoto, ProbeResult, ProbeStatus } from '../../domain/models/ProbeResult';
import { probeError } from '../../common/ProbeError';
import { PermissionProbe } from '../permissions/PermissionProbe';

export class MediaProbe {
  async inspectAlbums(context: common.UIAbilityContext): Promise<ProbeResult> {
    let helper: photoAccessHelper.PhotoAccessHelper | undefined = undefined;
    let albums: photoAccessHelper.FetchResult<photoAccessHelper.Album> | undefined = undefined;
    try {
      if (!new PermissionProbe().canReadLibrary()) {
        return new ProbeResult('系统相册读取', ProbeStatus.Blocked,
          '未取得批量图库读取权限，请先点击“申请图库读取权限”。若请求无效，检查调试签名 Profile。选中单张照片不等于全库授权。');
      }
      helper = photoAccessHelper.getPhotoAccessHelper(context);
      albums = await helper.getAlbums(photoAccessHelper.AlbumType.USER, photoAccessHelper.AlbumSubtype.USER_GENERIC);
      return new ProbeResult('系统相册读取', ProbeStatus.Observed,
        `本次查询到 ${albums.getCount()} 个用户相册。未执行创建、添加、移出或移动。`);
    } catch (error) {
      return probeError('系统相册读取', error as BusinessError);
    } finally {
      try { albums?.close(); }
      finally { if (helper) { await helper.release(); } }
    }
  }

  async selectPhoto(context: common.UIAbilityContext): Promise<PhotoProbeResult> {
    let helper: photoAccessHelper.PhotoAccessHelper | undefined = undefined;
    let assets: photoAccessHelper.FetchResult<photoAccessHelper.PhotoAsset> | undefined = undefined;
    try {
      const options = new photoAccessHelper.PhotoSelectOptions();
      options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
      options.maxSelectNumber = 1;
      const selected = await new photoAccessHelper.PhotoViewPicker().select(options);
      if (selected.photoUris.length === 0) {
        return new PhotoProbeResult(new ProbeResult('选择测试照片', ProbeStatus.Cancelled, '已取消，未读取照片。'));
      }
      // Resolve opaque Picker references via getAssets, never derive a file path.
      helper = photoAccessHelper.getPhotoAccessHelper(context);
      const predicates = new dataSharePredicates.DataSharePredicates();
      predicates.equalTo(photoAccessHelper.PhotoKeys.URI, selected.photoUris[0]);
      assets = await helper.getAssets({ fetchColumns: ['width', 'height'], predicates: predicates });
      if (assets.getCount() === 0) {
        return new PhotoProbeResult(new ProbeResult('选择测试照片', ProbeStatus.Failed, '未能解析所选照片，请重新选择。'));
      }
      const asset = await assets.getFirstObject();
      const file = await fileIo.open(asset.uri, fileIo.OpenMode.READ_ONLY);
      let bytesRead: number = 0;
      try {
        bytesRead = await fileIo.read(file.fd, new ArrayBuffer(32));
      } finally {
        await fileIo.close(file.fd);
      }
      if (bytesRead === 0) {
        return new PhotoProbeResult(new ProbeResult('选择测试照片', ProbeStatus.Failed, '资源可打开，但未读到内容。'));
      }
      const photo = new ProbePhoto(asset.uri, asset.displayName,
        asset.get(photoAccessHelper.PhotoKeys.WIDTH) as number,
        asset.get(photoAccessHelper.PhotoKeys.HEIGHT) as number);
      return new PhotoProbeResult(new ProbeResult('选择测试照片', ProbeStatus.Observed,
        '已解析所选照片并读取文件头。仅证明本次读取成功，移动、重启及撤销授权仍需单独验证。'), photo);
    } catch (error) {
      return new PhotoProbeResult(probeError('选择测试照片', error as BusinessError));
    } finally {
      try { assets?.close(); }
      finally { if (helper) { await helper.release(); } }
    }
  }
}
