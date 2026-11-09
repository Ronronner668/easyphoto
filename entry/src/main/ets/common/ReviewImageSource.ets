export function practiceImage(reference: string): Resource | undefined {
  switch (reference) {
    case 'practice-architecture-one': return $r('app.media.practice_architecture_one');
    case 'practice-architecture-two': return $r('app.media.practice_architecture_two');
    case 'practice-portrait': return $r('app.media.practice_portrait');
    case 'practice-animal': return $r('app.media.practice_animal');
    case 'practice-nature': return $r('app.media.practice_nature');
    default: return undefined;
  }
}

export function reviewImageSource(reference: string): Resource | string {
  return practiceImage(reference) ?? reference;
}
