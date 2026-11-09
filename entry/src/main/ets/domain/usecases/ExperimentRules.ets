import { AlbumAction, AlbumCopyEvidence, AlbumExperiment, AlbumPhase, AssetEvidence } from '../models/Experiment';

export function sameCopy(before: AlbumCopyEvidence | undefined, after: AlbumCopyEvidence | undefined): boolean {
  if (!before || !after) { return before === after; }
  return !!before.uri && before.uri === after.uri && before.sha256.length === 64 && before.sha256 === after.sha256 &&
    before.bytes > 0 && before.bytes === after.bytes && before.dateTaken === after.dateTaken;
}

export function sameAlbumObservation(before: AssetEvidence, after: AssetEvidence): boolean {
  return before.inA === after.inA && before.inB === after.inB && before.albumACount === after.albumACount &&
    before.albumBCount === after.albumBCount && sameCopy(before.copyA, after.copyA) && sameCopy(before.copyB, after.copyB);
}

export function isAlbumPending(phase: AlbumPhase): boolean {
  return phase === AlbumPhase.Creating || phase === AlbumPhase.AddingA || phase === AlbumPhase.AddingB ||
    phase === AlbumPhase.RemovingB || phase === AlbumPhase.Trashing;
}

export function sameAssetContent(before: AssetEvidence, after: AssetEvidence): boolean {
  return typeof before.uri === 'string' && before.uri.length > 0 && typeof before.sha256 === 'string' &&
    before.uri === after.uri && before.sha256.length === 64 && before.sha256 === after.sha256 &&
    before.bytes > 0 && before.bytes === after.bytes && before.dateTaken === after.dateTaken;
}

export function albumActionError(session: AlbumExperiment, action: AlbumAction): string {
  if (!session.createdByLab || !session.assetUri || !session.baseline || !session.latest) {
    return '仅允许操作本验证页创建并记录的样本。';
  }
  if (!Object.values(AlbumPhase).includes(session.phase)) { return '实验阶段未知，拒绝执行写入。'; }
  if (isAlbumPending(session.phase) || session.phase === AlbumPhase.Review || session.phase === AlbumPhase.TrashRequested) {
    return '上次操作尚待核对，禁止自动重试或继续写入。请先重新核查样本或在系统图库人工确认。';
  }
  if (!sameAssetContent(session.baseline, session.latest) || session.fixtureHash !== session.latest.sha256) {
    return '样本身份、原始内容或拍摄时间已变化，停止写入。';
  }
  if (session.latest.membershipVersion !== 3 || session.baseline.membershipVersion !== 3) {
    return '旧版实验没有记录副本身份，请先核查并归档，再使用空专用相册开启新轮；不重放旧请求。';
  }
  if (session.assetUri !== session.baseline.uri) { return '操作引用与创建记录不一致，停止写入。'; }
  if (!session.albumA || !session.albumB || session.albumA.uri === session.albumB.uri) {
    return '请选择两个不同的已有测试相册。';
  }
  if (action === AlbumAction.AddA && (session.phase !== AlbumPhase.Created || session.latest.inA || session.latest.albumACount !== 0)) {
    return '只有新创建且尚未加入 A 的样本可以执行这一步。';
  }
  if (action === AlbumAction.AddB && (session.phase !== AlbumPhase.InA || !session.latest.inA || session.latest.inB ||
    session.latest.albumBCount !== 0 || !session.verifiedCopyA || !sameCopy(session.verifiedCopyA, session.latest.copyA))) {
    return '先确认本轮 A 副本且 B 仍为空；添加 B 将生成另一副本，不是将 A 移动到 B。';
  }
  if (action === AlbumAction.RemoveB && (session.phase !== AlbumPhase.InB || !session.latest.inB ||
    !session.verifiedCopyB || !sameCopy(session.verifiedCopyB, session.latest.copyB) || session.verifiedCopyB.uri === session.assetUri)) {
    return '仅允许将本轮已核对引用的 B 副本移入回收站，不能用原图引用代替副本。';
  }
  if (action === AlbumAction.Trash && ![AlbumPhase.Created, AlbumPhase.InA, AlbumPhase.InB, AlbumPhase.RemovedB].includes(session.phase)) {
    return '当前阶段不允许提交回收站请求。';
  }
  return '';
}

export function membershipSummary(snapshot: AssetEvidence): string {
  const a = snapshot.copyA ? '包含已核对同内容副本' : (snapshot.originalInA ? '包含原样本' : '未发现原样本或同内容副本');
  const b = snapshot.copyB ? '包含已核对同内容副本' : (snapshot.originalInB ? '包含原样本' : '未发现原样本或同内容副本');
  return `相册 A：${a}（${snapshot.albumACount} 项）；相册 B：${b}（${snapshot.albumBCount} 项）。`;
}

export function reconciledAlbumPhase(phase: AlbumPhase, snapshot: AssetEvidence): AlbumPhase {
  if (phase === AlbumPhase.AddingA && snapshot.copyA && snapshot.albumACount === 1) { return AlbumPhase.InA; }
  if (phase === AlbumPhase.AddingB && snapshot.copyB && snapshot.albumBCount === 1) { return AlbumPhase.InB; }
  if (phase === AlbumPhase.RemovingB && !snapshot.inB) { return AlbumPhase.RemovedB; }
  return phase;
}
