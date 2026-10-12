/**
 * 麦克风采集：48kHz S16LE 单声道 → 16kHz Int16 PCM
 *
 * 移植自 RzdMusic MicRecorder，适配本仓约定：
 * - 日志走 AppLogger 门面；catch 不允许静默（空 catch 补 hilog.warn）
 * - 权限拒绝抛出 MicPermissionError，由页面转成引导文案
 *
 * 酷狗指纹接口要求 s16le mono 8kHz，最后一步 16k→8k 降采样在 KugouRecognizer 里做。
 */
import { audio } from '@kit.AudioKit';
import type { BusinessError } from '@kit.BasicServicesKit';
import { appLog as hilog } from '../../log/AppLogger';
import { MicCancelledError, MicPermissionError } from './RecognitionTypes';

const TAG = 'MicRecorder';
const DOMAIN: number = 0x0001;

const SOURCE_SAMPLE_RATE: number = 48000;
const TARGET_SAMPLE_RATE: number = 16000;
const TARGET_SECONDS: number = 12;
const TARGET_SAMPLES: number = TARGET_SECONDS * TARGET_SAMPLE_RATE;
const DOWNSAMPLE_STEP: number = SOURCE_SAMPLE_RATE / TARGET_SAMPLE_RATE;
/** 采集超过该时长仍无数据 → 判定麦克风不可用（模拟器常见） */
const WATCHDOG_MS: number = 4000;

export class MicRecorder {
  private capturer: audio.AudioCapturer | undefined = undefined;
  private chunks: number[] = [];
  private cancelled: boolean = false;
  private targetReached: boolean = false;
  private onProgressCb: ((progress: number) => void) | undefined = undefined;
  private finishResolve: ((samples: Int16Array) => void) | undefined = undefined;
  private finishReject: ((reason: Object) => void) | undefined = undefined;
  private watchdogTimer: number = -1;

  /** 采集 12 秒环境音频；onProgress 回调 0→1 用于驱动录制进度环 */
  async capture(onProgress: (progress: number) => void): Promise<Int16Array> {
    this.chunks = [];
    this.cancelled = false;
    this.targetReached = false;
    this.onProgressCb = onProgress;
    this.finishResolve = undefined;
    this.finishReject = undefined;

    // 录音能力不是所有设备都有（平板/PC 可能没有麦克风）：先问系统再建采集器，
    // 不支持时直接抛出可识别的错误，比让它抛一个底层异常更容易给用户提示
    if (!canIUse('SystemCapability.Multimedia.Audio.Capture')) {
      hilog.warn(DOMAIN, TAG, 'audio capture not supported on this device');
      throw new Error('mic unavailable (audio capture unsupported)');
    }

    const options: audio.AudioCapturerOptions = {
      streamInfo: {
        samplingRate: audio.AudioSamplingRate.SAMPLE_RATE_48000,
        channels: audio.AudioChannel.CHANNEL_1,
        sampleFormat: audio.AudioSampleFormat.SAMPLE_FORMAT_S16LE,
        encodingType: audio.AudioEncodingType.ENCODING_TYPE_RAW,
      },
      capturerInfo: {
        source: audio.SourceType.SOURCE_TYPE_MIC,
        capturerFlags: 0,
      },
    };

    let capturer: audio.AudioCapturer;
    try {
      capturer = await audio.createAudioCapturer(options);
    } catch (err) {
      const businessError = err as BusinessError;
      hilog.error(DOMAIN, TAG, 'createAudioCapturer failed, code=%{public}d', businessError.code);
      if (businessError.code === 201) {
        throw new MicPermissionError('microphone permission denied');
      }
      throw new Error(`mic unavailable (${businessError.code})`);
    }
    this.capturer = capturer;

    return new Promise<Int16Array>((resolve: (value: Int16Array) => void, reject: (reason: Object) => void): void => {
      this.finishResolve = resolve;
      this.finishReject = reject;
      capturer.on('readData', (buffer: ArrayBuffer): void => {
        this.handleBuffer(buffer);
      });
      capturer.start().then((): void => {
        this.watchdogTimer = setTimeout((): void => {
          if (!this.targetReached && !this.cancelled && this.chunks.length === 0) {
            hilog.warn(DOMAIN, TAG, 'no audio data within watchdog window');
            this.forceFinishWithError('mic produced no audio data');
          }
        }, WATCHDOG_MS);
      }).catch((err: BusinessError): void => {
        hilog.error(DOMAIN, TAG, 'capturer start failed, code=%{public}d', err.code);
        reject(new Error('mic start failed'));
      });
    });
  }

  /** 主动停止：capture 的 Promise 会以 MicCancelledError 拒绝 */
  stop(): void {
    this.cancelled = true;
    clearTimeout(this.watchdogTimer);
    const capturer = this.capturer;
    if (capturer !== undefined) {
      try {
        capturer.off('readData');
      } catch (err) {
        hilog.warn(DOMAIN, TAG, 'capturer off failed: %{public}s', JSON.stringify(err));
      }
      capturer.stop().then((): void => {
      }).catch((err: Object): void => {
        hilog.warn(DOMAIN, TAG, 'capturer stop failed: %{public}s', JSON.stringify(err));
      });
    }
    this.finish();
  }

  /** RMS 门限：低于该值视为「没采到有效声音」（RzdMusic 用 32/32768） */
  static computeRms(samples: Int16Array): number {
    if (samples.length === 0) {
      return 0;
    }
    let sum = 0;
    for (let i = 0; i < samples.length; i++) {
      const v: number = samples[i] / 32768;
      sum += v * v;
    }
    return Math.sqrt(sum / samples.length);
  }

  private handleBuffer(buffer: ArrayBuffer): void {
    if (this.targetReached || this.cancelled) {
      return;
    }
    const dataView = new DataView(buffer);
    const sampleCount: number = buffer.byteLength / 2;
    for (let i = 0; i < sampleCount; i += DOWNSAMPLE_STEP) {
      this.chunks.push(dataView.getInt16(i * 2, true) / 32768);
    }
    if (this.onProgressCb !== undefined) {
      this.onProgressCb(Math.min(this.chunks.length / TARGET_SAMPLES, 1));
    }
    if (this.chunks.length >= TARGET_SAMPLES) {
      this.targetReached = true;
      hilog.info(DOMAIN, TAG, 'capture done samples=%{public}d', this.chunks.length);
      this.finish();
    }
  }

  private forceFinishWithError(message: string): void {
    clearTimeout(this.watchdogTimer);
    const reject = this.finishReject;
    this.finishReject = undefined;
    this.finishResolve = undefined;
    if (reject !== undefined) {
      reject(new Error(message));
    }
    this.cancelled = true;
    this.finish();
  }

  private finish(): void {
    clearTimeout(this.watchdogTimer);
    const capturer = this.capturer;
    if (capturer !== undefined) {
      this.capturer = undefined;
      try {
        capturer.off('readData');
      } catch (err) {
        hilog.warn(DOMAIN, TAG, 'capturer off failed: %{public}s', JSON.stringify(err));
      }
      capturer.stop().then((): Promise<void> => {
        return capturer.release();
      }).then((): void => {
      }).catch((err: Object): void => {
        hilog.warn(DOMAIN, TAG, 'capturer stop/release failed: %{public}s', JSON.stringify(err));
      });
    }
    const resolve = this.finishResolve;
    const reject = this.finishReject;
    this.finishResolve = undefined;
    this.finishReject = undefined;
    if (this.cancelled) {
      if (reject !== undefined) {
        reject(new MicCancelledError());
      }
      return;
    }
    if (resolve !== undefined) {
      resolve(this.buildSamples());
    }
  }

  private buildSamples(): Int16Array {
    const total: number = Math.min(this.chunks.length, TARGET_SAMPLES);
    const out = new Int16Array(total);
    for (let i = 0; i < total; i++) {
      const value: number = this.chunks[i] * 32768;
      out[i] = Math.max(-32768, Math.min(32767, Math.round(value)));
    }
    hilog.info(DOMAIN, TAG, 'pcm samples=%{public}d duration=%{public}fs', out.length, out.length / TARGET_SAMPLE_RATE);
    this.chunks = [];
    return out;
  }
}
