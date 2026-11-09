import { sampleTargets, isSampleTarget } from '../domain/usecases/TargetAlbumOrder';
import { PhotoShareService } from '../platform/media/PhotoShareService';
import { WorkbenchPreferences } from '../data/repositories/WorkbenchPreferences';
import { PhotoAvailability, canSkipPhoto, photoIssue } from '../domain/models/PhotoAvailability';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { PhotoReviewSession, PhotoReviewSource } from '../domain/models/PhotoReview';
import { ProbePhoto } from '../domain/models/ProbeResult';
import { AlreadyInTargetError, ExperimentError } from '../domain/models/Experiment';
import { PhotoReviewService } from '../services/operations/PhotoReviewService';
import { DiscardMark, DiscardQueuePort } from '../domain/models/DiscardMark';
import { DiscardQueueService } from '../services/operations/DiscardQueueService';
import { Category, CategorySnapshot, TargetKind } from '../domain/models/Category';
import { planMoves } from '../domain/usecases/MovePlanner';
import { MoveSource } from '../domain/models/MovePlan';
import { AlbumClassificationTargets } from '../services/operations/AlbumClassificationTargets';
import { VerifiedMoveService } from '../services/operations/VerifiedMoveService';
import { ReviewPhotoRef } from '../domain/models/PhotoReview';
import { VerifiedMove } from '../domain/models/VerifiedMove';
import { DiscardTrashService } from '../services/operations/DiscardTrashService';
import { GalleryAlbum } from '../domain/models/GalleryAlbum';
import { GalleryFavorite } from '../platform/media/GalleryFavorite';
import { OrganizingReport, RoundProgress } from '../domain/models/OrganizingReport';
import { PhotoPracticeSession, PracticeAction, PracticeStep, practiceSteps } from '../domain/usecases/PhotoPracticeSession';

interface ClassificationIntent {
  photo: ReviewPhotoRef;
  targetId: string;
  label: string;
}

@Observed
export class PhotoReviewViewModel {
  private practice: PhotoPracticeSession | undefined = undefined;
  practiceStep: number = 0;
  practiceCompletionPending: boolean = false;
  isPractice(): boolean { return this.practice !== undefined; }
  practiceHint(): PracticeStep | undefined { return this.isPractice() ? practiceSteps[this.practiceStep] : undefined; }

  async initializePractice(): Promise<void> {
    const practice = new PhotoPracticeSession();
    this.practice = practice;
    this.source = practice;
    this.queue = practice;
    this.marksReady = true;
    this.categoriesReady = true;
    this.targetsReady = true;
    this.categories.categories = ['动物', '自然', '人像'].map(name => new Category(name, name));
    this.selectedTargetRefs = this.categories.categories.map(item => item.id);
    await this.choose();
  }

  private allowsPracticeAction(action: PracticeAction, album: string = ''): boolean {
    if (this.practiceCompletionPending) { return false; }
    const step = this.practiceHint();
    if (!step || (step.action === action && step.album === album)) { return true; }
    this.operationFeedback = '请先完成当前提示的操作。';
    return false;
  }

  private advancePracticeGuide(): void {
    if (!this.practiceHint() || this.disposed || this.practiceCompletionPending) { return; }
    if (this.practiceStep === practiceSteps.length - 1) {
      if (this.photo?.favorite) {
        this.practiceCompletionPending = true;
      }
      return;
    }
    this.practiceStep++;
  }

  async continueFreePractice(): Promise<void> {
    if (!this.practiceCompletionPending || this.disposed) { return; }
    this.practiceCompletionPending = false;
    this.practiceStep = practiceSteps.length;
    await this.selectStart(this.session.items[0].reference);
  }

  private async performReviewAction(action: PracticeAction): Promise<void> {
    if (this.busy || this.disposed || (this.practice && (this.showSummary || this.marksBusy)) ||
      !this.allowsPracticeAction(action)) { return; }
    switch (action) {
      case PracticeAction.Next: await this.move(1); break;
      case PracticeAction.Previous: await this.move(-1); break;
      case PracticeAction.Mark: await this.markCurrent(); break;
      case PracticeAction.Down: await this.downward(); break;
    }
    this.advancePracticeGuide();
  }

  async performPracticeHint(): Promise<void> {
    const step = this.practiceHint();
    if (!step) { return; }
    if (step.action === PracticeAction.Drag || step.action === PracticeAction.Tap) {
      await this.organize(step.album, step.action === PracticeAction.Drag);
    } else {
      await this.performReviewAction(step.action);
    }
  }

  async skipPracticeGuide(): Promise<void> {
    if (!this.practiceHint() || this.practiceCompletionPending || this.disposed || this.busy || this.marksBusy) { return; }
    this.practiceStep = practiceSteps.length;
    await this.selectStart(this.session.items[0].reference);
  }

  private async setFavorite(reference: string, value: boolean): Promise<void> {
    if (this.practice) { await this.practice.setFavorite(reference, value); }
    else {
      await this.favoriteService!.set(reference, value);
      (this.source as PhotoReviewService).invalidate();
    }
  }

  private round: RoundProgress = new RoundProgress();
  private shareService: PhotoShareService | undefined = undefined;
  private favoriteService: GalleryFavorite | undefined = undefined;
  report(): OrganizingReport { return this.round.snapshot(this.staged.length); }
  async toggleFavorite(): Promise<void> {
    if (this.busy || this.marksBusy || this.disposed || !this.photo || (!this.favoriteService && !this.practice)) { return; }
    const id = this.displayedId; const reference = this.photo.uri; const version = this.generation;
    if (id !== this.session.current()?.id) { return; }
    const previous = this.photo; const wanted = !previous.favorite;
    const optimistic = JSON.parse(JSON.stringify(previous)) as ProbePhoto; optimistic.favorite = wanted;
    this.busy = true; this.operationFeedback = ''; this.photo = optimistic;
    try {
      await this.setFavorite(reference, wanted);
      const photo = await this.source!.resolve(reference);
      if (!this.disposed && version === this.generation && id === this.session.current()?.id && photo.uri === reference) { this.photo = photo; }
    } catch (error) { if (!this.disposed && version === this.generation && id === this.session.current()?.id) { this.photo = previous; this.operationFeedback = error instanceof ExperimentError ? error.message : '系统收藏更新未确认，请刷新核对。'; } }
    finally { if (!this.disposed) { this.busy = false; } }
  }
  session: PhotoReviewSession = new PhotoReviewSession();
  photo: ProbePhoto | undefined = undefined;
  displayedId: string = '';
  busy: boolean = false;
  message: string = '选择最多 100 张照片，逐张查看。';
  marks: DiscardMark[] = [];
  marksReady: boolean = false;
  trashProgress: string = '';
  trashResult: string = '';
  markError: string = '';
  markNotice: string = '';
  marksBusy: boolean = false;
  marksMessage: string = '正在读取待删除标记。';
  showSummary: boolean = false;
  categories: CategorySnapshot = new CategorySnapshot();
  categoriesReady: boolean = false;
  targetCapacity: number = 3;
  selectedTargetRefs: string[] = [];
  targetsReady: boolean = false;
  targetMessage: string = '';
  private targetStore: WorkbenchPreferences | undefined = undefined;
  selectedTargets(): Category[] {
    if (!this.targetsReady || this.selectedTargetRefs.length > this.targetCapacity) { return []; }
    const targets = this.selectedTargetRefs.map(reference => this.categories.categories.find(category => category.id === reference) || new Category(reference, '相册已不可用'));
    return [...targets, ...sampleTargets(this.targetCapacity).slice(targets.length)];
  }
  isSampleTarget(id: string): boolean { return isSampleTarget(id); }
  keepOriginal: boolean = false;
  private categoryService: AlbumClassificationTargets | undefined = undefined;
  private categoriesLoading: boolean = false;
  private queue: DiscardQueuePort | undefined = undefined;
  private source: PhotoReviewSource | undefined = undefined;
  private generation: number = 0;
  private disposed: boolean = false;
  private mover: VerifiedMoveService | undefined = undefined;
  operationFeedback: string = '';
  organizedCount: number = 0;
  staged: VerifiedMove[] = [];
  classified: VerifiedMove[] = [];
  private classificationNames: Map<string, string> = new Map();
  private stageVersion: number = 0;
  batchEnded: boolean = false;
  hasMore: boolean = true;
  streamError: string = '';
  private retryNext: boolean = false;
  private usingPicker: boolean = false;
  private trasher: DiscardTrashService | undefined = undefined;
  private lastClassification: ClassificationIntent | undefined = undefined;
  classificationLabel(reference: string): string {
    return this.lastClassification?.photo.reference === reference ? this.lastClassification.label : this.classificationNames.get(reference) || '';
  }
  private indexClassifications(): void {
    const names = new Map<string, string>();
    for (const record of [...this.staged, ...this.classified]) {
      const label = `已分类：${record.targetName || this.categories.categories.find(item => item.id === record.categoryId)?.name || '历史分类目标'}`;
      const refs = [record.source.uri, record.copy?.uri || ''];
      record.destinations?.forEach(target => { if (target.copy) { refs.push(target.copy.uri); } });
      refs.forEach(ref => { if (ref && !names.has(ref)) { names.set(ref, label); } });
    }
    this.classificationNames = names;
  }
  async trashMarked(reference?: string, approvedReferences?: string[]): Promise<void> {
    if (this.busy || this.marksBusy || !this.marksReady || !this.trasher || this.disposed) { return; }
    this.busy = true;
    const requested = (reference ? [reference] : approvedReferences ?? this.marks.map(item => item.reference)).filter(uri => this.marks.some(mark => mark.reference === uri && this.canTrashMark(mark)));
    this.trashProgress = '正在核对待删除照片…';
    this.trashResult = '';
    try { this.operationFeedback = await this.trasher.trash(requested, message => { if (!this.disposed) { this.trashProgress = message; } }); }
    catch (error) { this.operationFeedback = error instanceof ExperimentError ? error.message : `回收未完成（错误码 ${(error as BusinessError).code || -1}），标记保留，请核对来源。`; }
    finally {
      if (!this.disposed) { this.trasher.confirmedRemoved?.forEach(identity => { this.round.removed(identity); }); }
      await this.refreshMarks();
      if (!this.disposed) {
        const gone = requested.filter(uri => this.marksReady && !this.marks.some(mark => mark.reference === uri));
        const next = new PhotoReviewSession(); next.items = this.session.items.filter(item => !gone.includes(item.reference));
        const keptIndex = next.items.findIndex(item => item.id === this.session.current()?.id);
        next.index = keptIndex >= 0 ? keptIndex : Math.max(0, Math.min(this.session.index, next.items.length - 1)); this.session = next;
        this.generation++;
        if (!next.items.length) { this.photo = undefined; this.displayedId = ''; }
        else { await this.loadCurrent(); }
      }
      this.trashProgress = '';
      if (!this.disposed) { this.trashResult = this.operationFeedback; }
      this.busy = false;
    }
  }
  async refreshStaged(): Promise<void> {
    const version = this.stageVersion;
    try { const records = await this.mover!.staged(); if (!this.disposed && version === this.stageVersion) { this.staged = records; } } catch (_) { }
    try { const records = await this.mover!.classified(); if (!this.disposed && version === this.stageVersion) { this.classified = records; } } catch (_) { }
    if (!this.disposed) { this.indexClassifications(); }
  }
  async finishRound(protectedSources: string[] = []): Promise<boolean> {
    if (this.busy || this.marksBusy || this.disposed || !this.mover) { return false; }
    this.busy = true;
    try {
      await this.commitLastClassification();
      if (this.disposed) { return false; }
      this.stageVersion++;
      const previous = this.staged;
      this.operationFeedback = await this.mover.finish(this.keepOriginal, protectedSources);
      // Readback failure must not be mistaken for an empty successful queue.
      const pending = await this.mover.staged(); const classified = await this.mover.classified();
      if (!this.disposed) {
        this.staged = pending; this.classified = classified; this.indexClassifications();
        const next = new PhotoReviewSession(); next.index = this.session.index;
        next.items = this.session.items.map((item: ReviewPhotoRef) => {
          const old = previous.find(record => record.source.uri === item.reference);
          const done = old ? classified.find(record => record.id === old.id) : undefined;
          return new ReviewPhotoRef(item.id, done?.phase === 'complete' ? done.copy?.uri || item.reference : item.reference);
        });
        this.session = next;
        await this.refreshMoveCount(); await this.loadCurrent();
        return !this.disposed && pending.every(record => protectedSources.includes(record.source.uri));
      }
      return false;
    } catch (error) { if (!this.disposed) { this.operationFeedback = this.moveError(error as BusinessError); } return false; }
    finally {
      this.busy = false;
    }
  }
  private async refreshMoveCount(): Promise<void> {
    try { const count = await this.mover!.completedCount(); if (!this.disposed) { this.organizedCount = count; } } catch (_) { }
  }

  initialize(context: common.UIAbilityContext): void {
    this.shareService = new PhotoShareService(context);
    this.targetStore = new WorkbenchPreferences(context);
    this.favoriteService = new GalleryFavorite(context);
    this.source = new PhotoReviewService(context);
    this.queue = new DiscardQueueService(context);
    this.categoryService = new AlbumClassificationTargets(context);
    this.mover = new VerifiedMoveService(context);
    this.trasher = new DiscardTrashService(context);
    this.refreshStaged();
    this.refreshMoveCount();
    this.refreshCategories();
    this.refreshMarks();
  }

  hasLastClassification(): boolean { return !!this.lastClassification; }

  canUndoClassification(): boolean {
    const current = this.session.current();
    const intent = this.lastClassification;
    return !!intent && !!current && !this.practiceHint() && !this.busy && !this.marksBusy && !this.disposed && !this.showSummary &&
      current.id === intent.photo.id && current.reference === intent.photo.reference &&
      (!this.photo || (current.id === this.displayedId && this.photo.uri === intent.photo.reference));
  }

  undoClassification(): void {
    if (this.canUndoClassification()) {
      this.lastClassification = undefined;
      this.operationFeedback = '';
    }
  }

  async saveLastClassification(): Promise<boolean> {
    if (this.busy || this.marksBusy || this.disposed || !this.mover) { return false; }
    this.busy = true;
    this.operationFeedback = '';
    try { await this.commitLastClassification(); return !this.disposed; }
    catch (error) {
      if (!this.disposed) { this.operationFeedback = this.moveError(error as BusinessError); }
      return false;
    } finally { if (!this.disposed) { this.busy = false; } }
  }

  private async commitLastClassification(): Promise<void> {
    const intent = this.lastClassification;
    if (!intent) { return; }
    if (this.practice) {
      this.classificationNames.set(intent.photo.reference, `已分类：${intent.targetId}`);
      this.lastClassification = undefined;
      await this.unmarkAfterClassification(intent.photo.reference);
      return;
    }
    let record: VerifiedMove;
    try {
      record = await this.mover!.move(intent.photo.reference, intent.targetId, TargetKind.Album, this.keepOriginal);
    } catch (error) {
      // Exact source membership is a no-op before any copy or journal write.
      if (error instanceof AlreadyInTargetError) {
        if (!this.disposed && this.lastClassification === intent) { this.lastClassification = undefined; }
        return;
      }
      throw error as Error;
    }
    if (this.disposed || this.lastClassification !== intent) { return; }
    if (!record.copy || record.source.uri !== intent.photo.reference ||
      (record.phase !== 'retained' && record.phase !== 'awaiting_trash' && record.phase !== 'complete')) {
      throw new ExperimentError('上一张照片的分类结果未确认，请返回检查。');
    }

    this.lastClassification = undefined;
    this.stageVersion++;
    if (record.phase === 'awaiting_trash') {
      this.staged = [...this.staged, record];
    } else {
      this.classified = [record, ...this.classified];
      this.organizedCount++;
    }
    if (record.phase === 'complete') {
      const next = new PhotoReviewSession();
      next.index = this.session.index;
      next.items = this.session.items.map((item: ReviewPhotoRef) =>
        item.id === intent.photo.id && item.reference === intent.photo.reference ?
          new ReviewPhotoRef(item.id, record.copy!.uri) : item);
      this.session = next;
    }
    this.indexClassifications();
    this.round.classified(intent.photo.reference);
    if (this.marks.some(item => item.reference === intent.photo.reference)) {
      await this.unmarkAfterClassification(intent.photo.reference);
    }
  }

  async organize(id: string, dragged: boolean = false): Promise<void> {
    if (this.busy || this.marksBusy || this.disposed || !this.photo || (!this.mover && !this.practice) || this.showSummary) { return; }
    this.operationFeedback = '';
    if (this.practice && (!this.allowsPracticeAction(dragged ? PracticeAction.Drag : PracticeAction.Tap, id) ||
      !this.selectedTargetRefs.includes(id))) { return; }
    if (isSampleTarget(id)) { this.operationFeedback = '样例仅作占位，请先选择真实目标相册。'; return; }
    const current = this.session.current();
    if (!current || current.id !== this.displayedId || current.reference !== this.photo.uri) { return; }
    if (this.lastClassification?.photo.reference === current.reference) {
      this.operationFeedback = '这张照片已有待提交的分类。';
      return;
    }
    if (this.staged.some(record => record.source.uri === current.reference || record.copy?.uri === current.reference ||
      record.destinations?.some(target => target.copy?.uri === current.reference))) {
      this.operationFeedback = '这张已分类，原图会在结束整理时统一处理。';
      return;
    }
    const label = this.categories.categories.find(item => item.id === id)?.name;
    const generation = this.generation;
    this.busy = true;
    try {
      await this.commitLastClassification();
      if (this.disposed || generation !== this.generation || this.session.current()?.id !== current.id ||
        this.photo?.uri !== current.reference) { return; }
      this.lastClassification = { photo: current, targetId: id, label: label ? `待提交分类：${label}` : '分类待提交' };
      this.message = '分类待提交。';
    } catch (error) {
      if (!this.disposed) { this.operationFeedback = this.moveError(error as BusinessError); }
      return;
    } finally { if (!this.disposed) { this.busy = false; } }
    await this.move(1);
    this.advancePracticeGuide();
  }

  setSourceAlbum(album?: GalleryAlbum): void {
    if (!this.practice && this.source && !this.busy && !this.lastClassification) { (this.source as PhotoReviewService).setAlbum(album); }
  }
  private async unmarkAfterClassification(reference: string): Promise<void> {
    if (this.queue) { this.marks = await this.queue.unmark(reference); }
  }

  async retryStream(): Promise<void> { await this.loadLibrary(this.retryNext); }

  async loadLibrary(next: boolean = false): Promise<void> {
    if (this.practice) { return; }
    if (!this.source || this.busy || this.disposed) { return; }
    if (!next && this.lastClassification) { this.message = '请先结束本轮整理，再更换照片来源。'; return; }
    this.retryNext = next; this.streamError = '';
    this.busy = true;
    const generation = ++this.generation;
    try {
      const service = this.source as PhotoReviewService;
      const references = await service.library(next);
      if (this.disposed || generation !== this.generation) { return; }
      this.hasMore = service.hasMore?.() ?? references.length === 100;
      if (next && !references.length) { this.message = '本次图库已浏览完。'; this.batchEnded = true; return; }
      const loaded = new PhotoReviewSession(references);
      if (next) {
        const additions = loaded.items.filter(item => !this.session.items.some(previous => previous.reference === item.reference));
        if (!additions.length) { this.message = '未取得新的照片，请重试读取下一批。'; this.streamError = this.message; return; }
        loaded.index = this.session.items.length; loaded.items = [...this.session.items, ...additions];
      }
      this.session = loaded; this.usingPicker = false;
      if (!this.categoriesReady) { this.refreshCategories(); }
      this.batchEnded = false;
      this.showSummary = false;
      if (references.length) { await this.loadCurrent(); }
      else { this.photo = undefined; this.message = '图库中暂无可读取的图片。'; }
    } catch (error) {
      if (!this.disposed) { this.message = this.errorMessage(error as BusinessError); this.streamError = this.message; }
    } finally { if (!this.disposed) { this.busy = false; } }
  }

  async refreshCategories(): Promise<void> {
    if (!this.categoryService || this.disposed || this.categoriesLoading) { return; }
    this.categoriesLoading = true;
    try {
      const snapshot = await this.categoryService.load();
      const selected = await this.targetStore!.loadTargetAlbums();
      if (!this.disposed) {
        this.categories = snapshot; this.categoriesReady = true; this.selectedTargetRefs = selected || []; this.targetsReady = true; this.indexClassifications();
        this.targetMessage = !selected ? '' : selected.length > this.targetCapacity ? '已选4个相册，当前三列布局无法展示；原配置保留，请在更多中调整。' :
          selected.some(ref => !snapshot.categories.some(item => item.id === ref)) ? '部分目标相册已不可用，请在更多中重新选择。' : '';
      }
    } catch (_) {
      if (!this.disposed) { this.categoriesReady = false; this.targetsReady = false; this.targetMessage = '目标相册或配置读取失败，原配置保留，请在更多中重试。'; }
    } finally { this.categoriesLoading = false; }
  }

  checkCategory(id: string): void {
    if (this.busy || this.disposed || !this.categoriesReady || this.showSummary) { return; }
    const category = this.categories.categories.find((item: Category) => item.id === id);
    if (!category) { this.message = '分类已经变化，请刷新目标。'; return; }
    const current = this.session.current();
    if (!current) { return; }
    const source = new MoveSource(current.id, current.reference, this.photo?.name || '当前照片',
      !!this.photo && this.displayedId === current.id && this.photo.uri === current.reference);
    this.message = planMoves([source], category, TargetKind.Album, this.categories.revision).items[0].reasons[0];
  }

  canTrashMark(mark: DiscardMark): boolean {
    if (this.practice) { return false; }
    return mark.reference !== this.lastClassification?.photo.reference && !mark.reference.startsWith('file://docs/') && (!mark.availability || mark.availability === PhotoAvailability.Ready);
  }
  markIssue(mark: DiscardMark): string {
    if (this.practice) { return '示例照片可撤销标记。'; }
    if (mark.reference === this.lastClassification?.photo.reference) { return '照片有待提交的分类，暂不可移入回收站。'; }
    return photoIssue(mark.availability || PhotoAvailability.Legacy);
  }
  async refreshMarks(): Promise<void> {
    if (!this.queue || this.marksBusy || this.disposed) { return; }
    this.marksBusy = true;
    try {
      const marks = await this.queue.load();
      if (!this.disposed) {
        this.marks = marks;
        this.marksReady = true;
        this.markError = '';
        this.marksMessage = '标记仅保存在应用内，可在汇总中撤销；系统照片保持原状。';
      }
    } catch (_) {
      if (!this.disposed) { this.marksReady = false; this.marksMessage = '待删除标记读取失败，请刷新；现有记录保留。'; }
    } finally { this.marksBusy = false; }
  }

  currentMarked(): boolean {
    return !!this.photo && this.marks.some((mark: DiscardMark) => mark.reference === this.photo!.uri);
  }

  async markCurrent(): Promise<void> {
    const current = this.session.current();
    const photo = this.photo;
    if (!current || !photo || current.id !== this.displayedId || !this.queue || !this.marksReady ||
      this.busy || this.marksBusy || this.disposed || this.showSummary) { return; }
    this.busy = true;
    this.marksBusy = true;
    this.markError = '';
    this.markNotice = '';
    let saved = false;
    try {
      const marks = await this.queue.mark(photo.uri, photo.name);
      if (!this.disposed) {
        this.marks = marks;
        this.marksMessage = '';
        this.markNotice = '';
        saved = true;
      }
    } catch (error) {
      if (!this.disposed) { this.marksMessage = error instanceof ExperimentError ? error.message : '标记未确认保存，停留在当前照片，请刷新核对。'; this.markError = this.marksMessage; }
    } finally { this.busy = false; this.marksBusy = false; }
    if (saved) {
      if (this.session.index + 1 < this.session.items.length) { await this.move(1); }
      else { await this.move(1); }
    }
  }

  async unmark(reference: string): Promise<void> {
    if (!this.queue || !this.marksReady || this.busy || this.marksBusy || this.disposed) { return; }
    this.marksBusy = true;
    this.markError = '';
    this.markNotice = '';
    try {
      const marks = await this.queue.unmark(reference);
      if (!this.disposed) { this.marks = marks; this.marksMessage = '已撤销待删除标记。'; this.markNotice = this.marksMessage; }
    } catch (_) {
      if (!this.disposed) { this.marksMessage = '撤销未确认保存，请刷新核对。'; this.markError = this.marksMessage; }
    } finally { this.marksBusy = false; }
  }

  configurePlace(enabled: boolean): void { (this.source as PhotoReviewService)?.setPlaceEnabled?.(enabled); }
  async loadStoragePath(): Promise<void> {
    if (this.practice) { return; }
    const photo = this.photo; const generation = this.generation;
    if (!photo || photo.storagePath || this.disposed || photo.uri.startsWith('file://docs/')) { return; }
    try {
      const location = await (this.source as PhotoReviewService).location(photo.uri);
      if (!this.disposed && generation === this.generation && this.photo === photo) {
        const next = JSON.parse(JSON.stringify(photo)) as ProbePhoto;
        next.storagePath = location; this.photo = next;
      }
    } catch (_) { if (!this.disposed && this.photo === photo) { this.operationFeedback = '相册位置暂时读取失败，可稍后重试。'; } }
  }
  async describeStart(reference: string): Promise<ProbePhoto> {
    if (!this.source || this.disposed || !this.session.items.some(item => item.reference === reference)) { throw new ExperimentError('此照片不在当前整理队列中。'); }
    return this.source.resolve(reference);
  }
  async shareCurrent(): Promise<void> {
    if (!this.shareService || !this.photo || this.disposed || this.busy || this.marksBusy || this.showSummary || this.displayedId !== this.session.current()?.id) { return; }
    const photo = this.photo; const generation = this.generation; this.busy = true; this.operationFeedback = '';
    try { await this.shareService.share(photo.uri, photo.name); }
    catch (error) { if (!this.disposed && generation === this.generation) { this.operationFeedback = error instanceof ExperimentError ? error.message : '系统分享面板未能打开，可稍后重试。'; } }
    finally { if (!this.disposed) { this.busy = false; } }
  }
  async selectStart(reference: string): Promise<void> {
    if (this.busy || this.marksBusy || this.disposed) { return; }
    const index = this.session.items.findIndex(item => item.reference === reference);
    if (index < 0) { return; }
    const next = new PhotoReviewSession(); next.items = this.session.items; next.index = index;
    this.session = next; this.batchEnded = false; this.showSummary = false;
    await this.loadCurrent();
  }
  async extendStartChoices(): Promise<void> {
    if (!this.source || this.busy || this.marksBusy || this.disposed || !this.hasMore || this.usingPicker) { return; }
    this.busy = true; const generation = this.generation; this.streamError = '';
    try {
      const references = await (this.source as PhotoReviewService).library(true);
      if (this.disposed || generation !== this.generation) { return; }
      const next = new PhotoReviewSession(); next.items = [...this.session.items]; next.index = this.session.index;
      for (const item of new PhotoReviewSession(references).items) {
        if (!next.items.some(previous => previous.reference === item.reference)) { next.items.push(item); }
      }
      this.session = next; this.hasMore = (this.source as PhotoReviewService).hasMore();
    } catch (_) { if (!this.disposed && generation === this.generation) { this.streamError = '起始照片读取失败，请重试。'; } }
    finally { if (!this.disposed && generation === this.generation) { this.busy = false; } }
  }
  async choose(): Promise<void> {
    if (this.busy || !this.source || this.disposed) { return; }
    if (this.lastClassification) { this.message = '请先结束本轮整理，再重新选图。'; return; }
    this.busy = true;
    const generation = ++this.generation;
    try {
      const references = await this.source.pick();
      if (this.disposed || this.generation !== generation) { return; }
      if (references.length === 0) { this.message = '已取消选择，保留当前浏览位置。'; return; }
      const nextSession = new PhotoReviewSession(references);
      if (nextSession.items.length === 0) { this.message = '没有取得可用照片引用，保留当前浏览。'; return; }
      this.session = nextSession; this.usingPicker = true;
      this.batchEnded = false; this.hasMore = false;
      this.showSummary = false;
      await this.loadCurrent();
    } catch (error) {
      if (!this.disposed && this.generation === generation) { this.message = this.errorMessage(error as BusinessError); }
    } finally { if (!this.disposed) { this.busy = false; } }
  }

  async move(step: number): Promise<void> {
    if (this.busy || this.disposed) { return; }
    this.streamError = '';
    const next = new PhotoReviewSession();
    next.items = this.session.items;
    next.index = this.session.index;
    if (!next.navigate(step)) {
      if (step === 1 && this.session.current()) {
        if (!this.usingPicker && this.hasMore) { await this.loadLibrary(true); }
        else { this.batchEnded = true; }
      }
      return;
    }
    this.session = next;
    await this.loadCurrent();
  }

  async downward(): Promise<void> {
    const current = this.session.current(); const photo = this.photo;
    if (!current || !photo || this.disposed || this.busy || this.marksBusy || this.showSummary || current.id !== this.displayedId || !this.marksReady) { return; }
    const marked = this.marks.some(mark => mark.reference === photo.uri);
    const classified = !!this.classificationLabel(photo.uri);
    if (!marked && !photo.favorite && !classified) { await this.toggleFavorite(); return; }
    if (!marked && !photo.favorite) { this.operationFeedback = '分类记录已保留；已完成或保留原图的照片可再次分类，待收尾项请先结束整理。'; return; }
    const generation = this.generation; this.busy = true; this.operationFeedback = '';
    try {
      if (photo.favorite) {
        await this.setFavorite(photo.uri, false);
        const refreshed = await this.source!.resolve(photo.uri);
        if (this.disposed || generation !== this.generation || current.id !== this.session.current()?.id || refreshed.uri !== photo.uri) { return; }
        this.photo = refreshed;
      }
      if (marked) {
        const marks = await this.queue!.unmark(photo.uri);
        if (this.disposed || generation !== this.generation || current.id !== this.session.current()?.id) { return; }
        this.marks = marks;
        if (this.practice) { this.markNotice = ''; }
      }
      if (!this.disposed && generation === this.generation) { this.operationFeedback = classified ? '已清除待删标记和收藏，分类记录保留。' : '已清除当前待删标记和收藏。'; }
    } catch (error) { if (!this.disposed && generation === this.generation) { this.operationFeedback = error instanceof ExperimentError ? error.message : '状态未全部清除，请核对后重试；未改变分类记录。'; } }
    finally { if (!this.disposed) { this.busy = false; } }
  }
  async gesture(offsetX: number, offsetY: number): Promise<void> {
    if (this.busy || this.disposed || !Number.isFinite(offsetX) || !Number.isFinite(offsetY)) { return; }
    this.operationFeedback = '';
    if (offsetY <= -80 && Math.abs(offsetY) > Math.abs(offsetX) * 1.2) { await this.performReviewAction(PracticeAction.Mark); }
    else if (offsetY >= 80 && Math.abs(offsetY) > Math.abs(offsetX) * 1.2) { await this.performReviewAction(PracticeAction.Down); }
    else if (Math.abs(offsetX) > Math.abs(offsetY) * 1.2) {
      if (offsetX <= -60) { await this.performReviewAction(PracticeAction.Next); }
      else if (offsetX >= 60) { await this.performReviewAction(PracticeAction.Previous); }
    }
  }

  async recheck(): Promise<void> {
    if (!this.busy && !this.disposed && this.session.current()) { await this.loadCurrent(); }
  }

  private errorMessage(error: BusinessError): string {
    return error instanceof ExperimentError ? error.message :
      `照片读取未完成（错误码 ${error.code || -1}），请重新选图或手动浏览其他照片。`;
  }
  private moveError(error: BusinessError): string {
    return error instanceof ExperimentError ? error.message :
      `分类未完成（错误码 ${error.code || -1}），当前照片不自动跳过。`;
  }

  private async availability(reference: string): Promise<PhotoAvailability> {
    try { return await (this.source as PhotoReviewService)?.availability?.(reference) || PhotoAvailability.Unavailable; }
    catch (_) { return PhotoAvailability.Unavailable; }
  }
  private skipCurrent(id: string): void {
    if (this.session.current()?.id !== id) { return; }
    const next = new PhotoReviewSession();
    next.items = this.session.items.filter(item => item.id !== id);
    next.index = this.session.index;
    this.session = next; this.photo = undefined; this.displayedId = '';
    this.message = '已跳过失效照片。'; this.batchEnded = !next.current();
  }
  async returnToBatch(): Promise<void> {
    if (this.busy || this.disposed || !this.session.items.length) { return; }
    if (!this.session.current()) {
      const next = new PhotoReviewSession(); next.items = this.session.items; next.index = next.items.length - 1; this.session = next;
    }
    this.batchEnded = false; await this.loadCurrent();
  }
  private async loadCurrent(): Promise<void> {
    if (!this.session.current() || !this.source || this.disposed) { return; }
    const generation = ++this.generation; this.busy = true;
    try {
      while (this.session.current() && !this.disposed && generation === this.generation) {
        const current = this.session.current()!;
        if (this.photo?.uri !== current.reference || this.displayedId !== current.id) { this.photo = undefined; this.displayedId = ''; }
        this.message = '正在读取当前照片';
        try {
          const photo = await this.source.resolve(current.reference);
          if (!this.disposed && generation === this.generation && current.id === this.session.current()?.id) {
            this.photo = photo; this.displayedId = current.id; this.message = '左右浏览 · 上滑标记待删除，保存后自动下一张。';
            (this.source as PhotoReviewService).preload?.(this.session.items.slice(this.session.index + 1, this.session.index + 3).map(item => item.reference));
          }
          return;
        } catch (error) {
          const state = await this.availability(current.reference);
          if (this.disposed || generation !== this.generation || current.id !== this.session.current()?.id) { return; }
          if (current.id === this.lastClassification?.photo.id) {
            this.photo = undefined; this.displayedId = '';
            this.message = '照片暂不可读取，请检查图库后重试。';
            return;
          }
          if (canSkipPhoto(state)) { this.skipCurrent(current.id); }
          else { this.photo = undefined; this.displayedId = ''; this.message = this.errorMessage(error as BusinessError); return; }
        }
      }
    } finally { if (!this.disposed && generation === this.generation) { this.busy = false; } }
    if (!this.disposed && generation === this.generation && !this.session.current() && !this.usingPicker && this.hasMore) { await this.loadLibrary(true); }
  }

  imageFailed(id: string, reference?: string): void {
    if (this.practice) { return; }
    if (reference && reference !== this.photo?.uri) { return; }
    if (id === this.displayedId && id === this.session.current()?.id) {
      const current = this.session.current()!; const generation = this.generation;
      this.message = '照片预览未能显示，请重新读取或重新选图。'; this.photo = undefined; this.displayedId = '';
      this.recoverPreview(current, generation);
    }
  }
  private async recoverPreview(current: ReviewPhotoRef, generation: number): Promise<void> {
    const state = await this.availability(current.reference);
    if (this.disposed || generation !== this.generation || current.id !== this.session.current()?.id || this.busy || current.id === this.lastClassification?.photo.id || !canSkipPhoto(state)) { return; }
    this.skipCurrent(current.id);
    if (this.session.current()) { await this.loadCurrent(); }
    else if (!this.usingPicker && this.hasMore) { await this.loadLibrary(true); }
  }

  dispose(): void {
    this.disposed = true;
    this.generation++;
    this.photo = undefined;
    try { (this.source as PhotoReviewService)?.close?.(); } catch (_) { }
    this.source = undefined;
  }
}
