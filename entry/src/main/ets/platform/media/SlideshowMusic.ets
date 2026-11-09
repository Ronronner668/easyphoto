import { media } from '@kit.MediaKit';
import { audio } from '@kit.AudioKit';
import { fileIo } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

export class SlideshowMusic {
  private player?: media.AVPlayer;
  private file?: fileIo.File;
  private generation: number = 0;
  private wanted: boolean = false;
  private volume: number = 0.4;
  private queue: Promise<void> = Promise.resolve();
  interrupted: () => void = () => {};
  failed: () => void = () => {};

  async load(path: string, volume: number): Promise<void> {
    await this.close();
    const version = this.generation;
    const file = await fileIo.open(path, fileIo.OpenMode.READ_ONLY);
    let player: media.AVPlayer | undefined;
    let adopted = false;
    try {
      player = await media.createAVPlayer();
      if (version !== this.generation) { throw new Error('音乐已关闭'); }
      this.player = player; this.file = file; this.volume = volume;
      adopted = true;
      const active = player;
      await new Promise<void>((resolve, reject) => {
        const timeout = setTimeout(() => reject(new Error('音乐准备超时')), 10000);
        active.on('error', () => {
          clearTimeout(timeout); reject(new Error('音乐格式不可播放'));
          if (version === this.generation) { this.failed(); }
        });
        active.on('stateChange', (state: string) => {
          try {
            if (version !== this.generation) { clearTimeout(timeout); reject(new Error('音乐已关闭')); return; }
            if (state === 'initialized') {
              active.audioRendererInfo = { usage: audio.StreamUsage.STREAM_USAGE_MUSIC, rendererFlags: 0 };
              active.prepare().catch(() => { clearTimeout(timeout); reject(new Error('音乐准备失败')); });
            }
            if (state === 'prepared') {
              clearTimeout(timeout); active.loop = true; active.setVolume(this.volume); resolve();
            }
          } catch (_) { clearTimeout(timeout); reject(new Error('音乐状态准备失败')); }
        });
        active.on('audioInterrupt', (event: audio.InterruptEvent) => {
          if (version === this.generation && event.hintType !== audio.InterruptHint.INTERRUPT_HINT_RESUME) { this.interrupted(); }
        });
        active.on('audioOutputDeviceChangeWithInfo', (event: audio.AudioStreamDeviceChangeInfo) => {
          if (version === this.generation && event.changeReason === audio.AudioStreamDeviceChangeReason.REASON_OLD_DEVICE_UNAVAILABLE) { this.interrupted(); }
        });
        active.fdSrc = { fd: file.fd, offset: 0, length: -1 };
      });
    } catch (error) {
      if (adopted && this.player === player) { await this.close(); }
      else if (!adopted) {
        try { if (player) { await player.release(); } }
        finally { await fileIo.close(file.fd); }
      }
      throw error as Error;
    }
  }

  setPlaying(playing: boolean, volume: number = this.volume): void {
    this.wanted = playing; this.volume = volume;
    const version = this.generation;
    this.queue = this.queue.then(async () => {
      const player = this.player;
      if (!player || version !== this.generation) { return; }
      if (['prepared', 'playing', 'paused', 'completed'].includes(player.state)) { player.setVolume(this.volume); }
      if (this.wanted && ['prepared', 'paused', 'completed'].includes(player.state)) { await player.play(); }
      if (!this.wanted && player.state === 'playing') { await player.pause(); }
    }).catch(() => { if (version === this.generation) { this.failed(); } });
  }

  async close(): Promise<void> {
    this.generation++; this.wanted = false;
    const player = this.player; const file = this.file;
    this.player = undefined; this.file = undefined;
    await this.queue;
    try { if (player) { await player.release(); } }
    catch (_) { hilog.warn(0, 'Slideshow', 'Music player release failed'); }
    finally { if (file) { await fileIo.close(file.fd); } }
  }
}
