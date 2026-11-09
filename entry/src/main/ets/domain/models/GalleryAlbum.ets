// Platform references stay opaque; album membership is always queried through the public API.
export class GalleryAlbum {
  location: string = '';
  reference: string;
  name: string;
  type: number;
  subtype: number;
  count: number;
  cover: string;
  constructor(reference: string, name: string, type: number, subtype: number, count: number = 0, cover: string = '') {
    this.reference = reference; this.name = name; this.type = type; this.subtype = subtype;
    this.count = count; this.cover = cover;
  }
}
