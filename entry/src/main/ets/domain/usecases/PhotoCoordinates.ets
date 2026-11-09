export function exifCoordinate(value: string, reference: string, latitude: boolean): number | undefined {
  const ref = reference.trim().toUpperCase();
  if (!(latitude ? ['N', 'S'] : ['E', 'W']).includes(ref)) { return undefined; }
  const parts = value.trim().replace(/[°'"\u2032\u2033]/g, ' ').split(/[,\s]+/).filter(part => !!part);
  if (parts.length !== 1 && parts.length !== 3) { return undefined; }
  const values: number[] = [];
  for (const part of parts) {
    if (!/^\d+(?:\.\d+)?(?:\/\d+(?:\.\d+)?)?$/.test(part)) { return undefined; }
    const fraction = part.split('/'); const result = Number(fraction[0]) / (fraction.length === 2 ? Number(fraction[1]) : 1);
    if (!Number.isFinite(result) || result < 0) { return undefined; } values.push(result);
  }
  if (values.length === 3 && (values[1] >= 60 || values[2] >= 60)) { return undefined; }
  const result = values[0] + (values.length === 3 ? values[1] / 60 + values[2] / 3600 : 0);
  if (result > (latitude ? 90 : 180)) { return undefined; }
  return (ref === 'S' || ref === 'W') ? -result : result;
}
export function photoCoordinates(latitude: string, northSouth: string, longitude: string, eastWest: string): string {
  const lat = exifCoordinate(latitude, northSouth, true); const lon = exifCoordinate(longitude, eastWest, false);
  if (lat === undefined || lon === undefined) { return ''; }
  return `${Math.abs(lat).toFixed(5)}°${northSouth.trim().toUpperCase()} · ${Math.abs(lon).toFixed(5)}°${eastWest.trim().toUpperCase()}`;
}
