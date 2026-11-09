import { OrganizingReport } from '../models/OrganizingReport';

export function formatEstimatedSpace(bytes: number = 0): string {
  const known = Number.isFinite(bytes) && bytes >= 0 ? bytes : 0;
  return known >= 1073741824 ? `${(known / 1073741824).toFixed(2)}GB` : `${(known / 1048576).toFixed(known > 0 && known < 10485.76 ? 4 : 2)}MB`;
}
export function reportSummary(report: OrganizingReport): string {
  const incomplete = report.unknownBytes > 0 || (report.recycled > 0 && !Number.isFinite(report.recycledBytes));
  return `本次分类${report.organized}张\n删除图片${report.recycled}张\n预计释放空间${incomplete ? '≥' : ''}${formatEstimatedSpace(report.recycledBytes)}`;
}
