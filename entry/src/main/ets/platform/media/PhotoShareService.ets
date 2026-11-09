import { common } from '@kit.AbilityKit';
import { systemShare } from '@kit.ShareKit';
import { uniformTypeDescriptor } from '@kit.ArkData';
import { GalleryReferenceInspector } from './GalleryReferenceInspector';
import { PhotoAvailability } from '../../domain/models/PhotoAvailability';
import { ExperimentError } from '../../domain/models/Experiment';
export class PhotoShareService {
  private static running: boolean = false;
  private context: common.UIAbilityContext;
  constructor(context: common.UIAbilityContext) { this.context = context; }
  async share(reference: string, name: string): Promise<void> {
    if (PhotoShareService.running) { throw new ExperimentError('分享面板正在打开。'); }
    PhotoShareService.running = true;
    try {
      const check = (await new GalleryReferenceInspector(this.context).inspect([reference]))[0];
      if (check.state !== PhotoAvailability.Ready) { throw new ExperimentError('当前照片暂不可分享，请刷新后重试。'); }
      const data = new systemShare.SharedData({ utd: uniformTypeDescriptor.UniformDataType.IMAGE, uri: reference, title: name });
      await new systemShare.ShareController(data).show(this.context, { previewMode: systemShare.SharePreviewMode.DETAIL });
      // show() means the system panel opened, not that the user completed sharing.
    } finally { PhotoShareService.running = false; }
  }
}
