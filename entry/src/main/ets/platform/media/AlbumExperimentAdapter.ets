import { common } from '@kit.AbilityKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { dataSharePredicates } from '@kit.ArkData';
import { fileIo, fileUri } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { AlbumAction, AlbumCopyEvidence, AlbumExperiment, AssetEvidence, ExperimentError, LabAlbum } from '../../domain/models/Experiment';
import { contentHash } from '../files/ContentHash';

class AlbumObservation {
  originalPresent: boolean = false;
  count: number = 0;
  copy: AlbumCopyEvidence | undefined = undefined;
}

export class AlbumExperimentAdapter {
  private context: common.UIAbilityContext;
  constructor(context: common.UIAbilityContext) { this.context = context; }

  async listAlbums(): Promise<LabAlbum[]> {
    const helper = photoAccessHelper.getPhotoAccessHelper(this.context);
    let result: photoAccessHelper.FetchResult<photoAccessHelper.Album> | undefined = undefined;
    try {
      result = await helper.getAlbums(photoAccessHelper.AlbumType.USER, photoAccessHelper.AlbumSubtype.USER_GENERIC);
      const list: LabAlbum[] = [];
      const count = Math.min(result.getCount(), 100);
      for (let index = 0; index < count; index++) {
        const album = await result.getObjectByPosition(index);
        list.push(new LabAlbum(album.albumUri, album.albumName));
      }
      return list;
    } finally {
      try { result?.close(); } finally { await helper.release(); }
    }
  }

  async generateFixture(id: string): Promise<string> {
    const pixels = new Uint8Array(64 * 64 * 4);
    for (let index = 0; index < 64 * 64; index++) {
      pixels[index * 4] = (index % 64) * 4;
      pixels[index * 4 + 1] = Math.floor(index / 64) * 4;
      pixels[index * 4 + 2] = 100;
      pixels[index * 4 + 3] = 255;
    }
    // Encode the round ID as high-contrast 4x4 bit blocks, robust to JPEG quantization.
    for (let character = 0; character < Math.min(id.length, 24); character++) {
      for (let bit = 0; bit < 8; bit++) {
        const block = character * 8 + bit;
        const color = (id.charCodeAt(character) & (1 << bit)) !== 0 ? 240 : 15;
        for (let y = 0; y < 4; y++) {
          for (let x = 0; x < 4; x++) {
            const offset = ((Math.floor(block / 16) * 4 + y) * 64 + (block % 16) * 4 + x) * 4;
            pixels[offset] = color;
            pixels[offset + 1] = color;
            pixels[offset + 2] = color;
          }
        }
      }
    }
    const pixelMap = await image.createPixelMap(pixels.buffer,
      { size: { width: 64, height: 64 }, pixelFormat: image.PixelMapFormat.RGBA_8888 });
    const packer = image.createImagePacker();
    try {
      const encoded = await packer.packing(pixelMap, { format: 'image/jpeg', quality: 100 });
      const path = `${this.context.filesDir}/EasyPhoto_P1_${id}.jpg`;
      if (await fileIo.access(path)) { throw new ExperimentError('同名样本已存在，不覆盖、不重复创建。'); }
      const file = await fileIo.open(path, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY);
      try {
        if (await fileIo.write(file.fd, encoded) !== encoded.byteLength) {
          throw new ExperimentError('测试图片写入不完整。');
        }
      } finally { await fileIo.close(file.fd); }
      return path;
    } finally {
      try { await packer.release(); } finally { await pixelMap.release(); }
    }
  }

  async createAsset(path: string): Promise<string> {
    const helper = photoAccessHelper.getPhotoAccessHelper(this.context);
    try {
      const request = photoAccessHelper.MediaAssetChangeRequest.createImageAssetRequest(this.context,
        fileUri.getUriFromPath(path));
      await helper.applyChanges(request);
      return request.getAsset().uri;
    } finally { await helper.release(); }
  }

  private options(uri: string): photoAccessHelper.FetchOptions {
    const predicates = new dataSharePredicates.DataSharePredicates();
    predicates.equalTo(photoAccessHelper.PhotoKeys.URI, uri);
    return { predicates: predicates, fetchColumns: ['size', 'date_taken', 'owner_album_id', 'subtype'] };
  }

  private async album(helper: photoAccessHelper.PhotoAccessHelper, uri: string): Promise<photoAccessHelper.Album> {
    // Resolve the exact opaque reference ourselves. A native predicate must never select a different album.
    const result = await helper.getAlbums(photoAccessHelper.AlbumType.USER, photoAccessHelper.AlbumSubtype.USER_GENERIC);
    try {
      const count = result.getCount();
      if (count > 1000) { throw new ExperimentError('用户相册超过本实验核查上限，未确定目标相册。'); }
      let matched: photoAccessHelper.Album | undefined = undefined;
      for (let index = 0; index < count; index++) {
        const candidate = await result.getObjectByPosition(index);
        if (candidate.albumUri === uri) {
          if (matched) { throw new ExperimentError('相册引用不唯一，停止操作。'); }
          matched = candidate;
        }
      }
      if (!matched) { throw new ExperimentError('测试相册不可访问或已被移除。'); }
      return matched;
    } finally { result.close(); }
  }

  private async observe(helper: photoAccessHelper.PhotoAccessHelper, albumUri: string, original: AssetEvidence): Promise<AlbumObservation> {
    const album = await this.album(helper, albumUri);
    const result = await album.getAssets({ predicates: new dataSharePredicates.DataSharePredicates(),
      fetchColumns: ['size', 'date_taken', 'subtype'] });
    try {
      const count = result.getCount();
      if (count > 20) { throw new ExperimentError('测试相册超过 20 项，停止副本核查；请为新实验使用空专用相册。'); }
      const observation = new AlbumObservation();
      observation.count = count;
      const seen = new Set<string>();
      for (let index = 0; index < count; index++) {
        const member = await result.getObjectByPosition(index);
        if (!member.uri || seen.has(member.uri)) { throw new ExperimentError('相册成员返回不完整或重复，状态待核对。'); }
        seen.add(member.uri);
        if (member.uri === original.uri) { observation.originalPresent = true; continue; }
        if (member.get(photoAccessHelper.PhotoKeys.SIZE) === original.bytes &&
          member.get(photoAccessHelper.PhotoKeys.PHOTO_SUBTYPE) === photoAccessHelper.PhotoSubtype.DEFAULT) {
          const hash = await contentHash(member.uri);
          if (hash === original.sha256) {
            if (observation.copy) { throw new ExperimentError('相册内有多个同内容副本，无法唯一确认本轮副本；停止后续写入。'); }
            const copy = new AlbumCopyEvidence();
            copy.uri = member.uri;
            copy.bytes = member.get(photoAccessHelper.PhotoKeys.SIZE) as number;
            copy.dateTaken = member.get(photoAccessHelper.PhotoKeys.DATE_TAKEN) as number;
            copy.sha256 = hash;
            observation.copy = copy;
          }
        }
      }
      if (album.count !== count) { throw new ExperimentError('相册数量与可读成员数量不一致，不能判断样本不在其中。'); }
      return observation;
    } finally { result.close(); }
  }

  async snapshot(session: AlbumExperiment): Promise<AssetEvidence> {
    if (!session.albumA || !session.albumB) { throw new ExperimentError('尚未选择测试相册 A/B。'); }
    const helper = photoAccessHelper.getPhotoAccessHelper(this.context);
    let result: photoAccessHelper.FetchResult<photoAccessHelper.PhotoAsset> | undefined = undefined;
    try {
      result = await helper.getAssets(this.options(session.assetUri));
      if (result.getCount() !== 1) { throw new ExperimentError('原始样本引用不可访问，需核对图库状态或重新授权。'); }
      const asset = await result.getFirstObject();
      if (asset.uri !== session.assetUri) { throw new ExperimentError('查询返回了不同于原样本的引用，停止核查。'); }
      if (asset.get(photoAccessHelper.PhotoKeys.PHOTO_SUBTYPE) !== photoAccessHelper.PhotoSubtype.DEFAULT) {
        throw new ExperimentError('仅验证本页创建的普通 JPEG，不操作动态照片或其他特殊资源。');
      }
      const evidence = new AssetEvidence();
      evidence.uri = asset.uri;
      evidence.sha256 = await contentHash(asset.uri);
      evidence.bytes = asset.get(photoAccessHelper.PhotoKeys.SIZE) as number;
      evidence.dateTaken = asset.get(photoAccessHelper.PhotoKeys.DATE_TAKEN) as number;
      evidence.ownerAlbum = String(asset.get(photoAccessHelper.PhotoKeys.OWNER_ALBUM_ID));
      const a = await this.observe(helper, session.albumA.uri, evidence);
      const b = await this.observe(helper, session.albumB.uri, evidence);
      evidence.originalInA = a.originalPresent;
      evidence.originalInB = b.originalPresent;
      evidence.copyA = a.copy;
      evidence.copyB = b.copy;
      evidence.albumACount = a.count;
      evidence.albumBCount = b.count;
      evidence.inA = a.originalPresent || !!a.copy;
      evidence.inB = b.originalPresent || !!b.copy;
      return evidence;
    } finally {
      try { result?.close(); } finally { await helper.release(); }
    }
  }

  async mutate(session: AlbumExperiment, action: AlbumAction): Promise<void> {
    if (!session.createdByLab || !session.assetUri || !session.albumA || !session.albumB) {
      throw new ExperimentError('拒绝操作非本页创建的样本。');
    }
    if (action === AlbumAction.Trash) {
      await photoAccessHelper.MediaAssetChangeRequest.deleteAssets(this.context, [session.assetUri]);
      return;
    }
    const helper = photoAccessHelper.getPhotoAccessHelper(this.context);
    let result: photoAccessHelper.FetchResult<photoAccessHelper.PhotoAsset> | undefined = undefined;
    try {
      const operationUri = action === AlbumAction.RemoveB ? session.verifiedCopyB?.uri : session.assetUri;
      if (!operationUri || (action === AlbumAction.RemoveB && operationUri === session.assetUri)) {
        throw new ExperimentError('没有本轮已核对的 B 副本引用，不提交移除。');
      }
      result = await helper.getAssets(this.options(operationUri));
      if (result.getCount() !== 1) { throw new ExperimentError('样本引用已失效，未执行操作。'); }
      const asset = await result.getFirstObject();
      if (asset.uri !== operationUri) { throw new ExperimentError('查询返回引用与操作目标不同，拒绝修改。'); }
      const target = await this.album(helper, action === AlbumAction.AddA ? session.albumA.uri : session.albumB.uri);
      const request = new photoAccessHelper.MediaAlbumChangeRequest(target);
      if (action === AlbumAction.RemoveB) { request.removeAssets([asset]); }
      else { request.addAssets([asset]); }
      await helper.applyChanges(request);
    } finally {
      try { result?.close(); } finally { await helper.release(); }
    }
  }
}
