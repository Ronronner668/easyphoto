import { VerifiedMove } from '../models/VerifiedMove';

export function isLegacyDocument(reference: string): boolean { return reference.startsWith('file://docs/'); }
export function isAlbumOnlyMove(record: VerifiedMove): boolean {
  return (!record.targetKind || record.targetKind === 'album') && !isLegacyDocument(record.source.uri) &&
    !!record.target && !isLegacyDocument(record.target) && !isLegacyDocument(record.copy?.uri || '') && !record.destinations?.length;
}
