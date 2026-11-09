import { DiscardMark, DiscardQueuePort } from '../models/DiscardMark';
import { ExperimentError } from '../models/Experiment';
import { PhotoReviewSource } from '../models/PhotoReview';
import { ProbePhoto } from '../models/ProbeResult';

export enum PracticeAction {
  Next,
  Previous,
  Mark,
  Down,
  Drag,
  Tap
}

export class PracticeStep {
  action: PracticeAction;
  hint: string;
  alternative: string;
  album: string;

  constructor(action: PracticeAction, hint: string, alternative: string, album: string = '') {
    this.action = action;
    this.hint = hint;
    this.alternative = alternative;
    this.album = album;
  }
}

export const practiceSteps: PracticeStep[] = [
  new PracticeStep(PracticeAction.Next, '向左滑，跳过这张建筑照。', '跳过照片'),
  new PracticeStep(PracticeAction.Previous, '向右滑，回到刚才的照片。', '返回上一张'),
  new PracticeStep(PracticeAction.Next, '再向左滑，来到第二张建筑照。', '前往下一张'),
  new PracticeStep(PracticeAction.Mark, '向上滑，将这张照片标记为待删除。', '标记待删除'),
  new PracticeStep(PracticeAction.Previous, '待删除标记已添加。向右滑，回去查看标记。', '回看待删除标记'),
  new PracticeStep(PracticeAction.Down, '向下滑，清除这张照片的待删除标记。', '清除待删除标记'),
  new PracticeStep(PracticeAction.Next, '标记已清除。向左滑，开始练习分类。', '前往人像照片'),
  new PracticeStep(PracticeAction.Drag, '将照片拖到下方的「人像」相册。', '放入人像相册', '人像'),
  new PracticeStep(PracticeAction.Tap, '点击下方的「动物」相册，给这张照片分类。', '放入动物相册', '动物'),
  new PracticeStep(PracticeAction.Down, '向下滑，收藏这张自然照片。', '收藏照片')
];

export class PhotoPracticeSession implements PhotoReviewSource, DiscardQueuePort {
  private photos: ProbePhoto[] = [
    new ProbePhoto('practice-architecture-one', '建筑照片一', 640, 960),
    new ProbePhoto('practice-architecture-two', '建筑照片二', 640, 853),
    new ProbePhoto('practice-portrait', '人像照片', 640, 435),
    new ProbePhoto('practice-animal', '动物照片', 640, 955),
    new ProbePhoto('practice-nature', '自然照片', 640, 1030)
  ];
  private marks: DiscardMark[] = [];
  private favorites: Set<string> = new Set();

  references(): string[] { return this.photos.map(photo => photo.uri); }
  async pick(): Promise<string[]> { return this.references(); }

  async resolve(reference: string): Promise<ProbePhoto> {
    const sample = this.photos.find(photo => photo.uri === reference);
    if (!sample) { throw new ExperimentError('找不到这张示例照片。'); }
    const photo = new ProbePhoto(sample.uri, sample.name, sample.width, sample.height);
    photo.favorite = this.favorites.has(reference);
    return photo;
  }

  async setFavorite(reference: string, favorite: boolean): Promise<void> {
    await this.resolve(reference);
    if (favorite) { this.favorites.add(reference); }
    else { this.favorites.delete(reference); }
  }

  async load(): Promise<DiscardMark[]> { return this.marks.slice(); }

  async mark(reference: string, name: string): Promise<DiscardMark[]> {
    await this.resolve(reference);
    if (!this.marks.some(mark => mark.reference === reference)) {
      this.marks.push(new DiscardMark(reference, name, Date.now()));
    }
    return this.load();
  }

  async unmark(reference: string): Promise<DiscardMark[]> {
    this.marks = this.marks.filter(mark => mark.reference !== reference);
    return this.load();
  }
}
