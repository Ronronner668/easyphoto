import { curves } from '@kit.ArkUI';

export const UI_SPRING = curves.springMotion(0.28, 0.95);

// Full-screen fades use a fixed timeline. Physical springs ignore explicit duration.
export const FULL_SCREEN_FADE: PageTransitionOptions = {
  duration: 260,
  curve: curves.cubicBezierCurve(0.25, 0.15, 0.75, 0.85)
};
