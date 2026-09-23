/**
 * 播放页资源加载器（封面 / 歌词）
 *
 * 从 PlayDetailPage 拆出的原因：
 * - 页面里原本有 12 个和「请求守卫」相关的私有字段（loading / 已尝试 key / 序号 / 重试计数 / 定时器），
 *   和 UI 状态混在一起，读代码时很难分清「哪些是页面状态、哪些只是加载器的内部簿记」；
 * - 封面与歌词的规则完全对称（进行中跳过、同一首失败过就跳过、序号过期丢弃、失败退避重试两次），
 *   抽成一个类后两条链路共用同一套守卫，改一处两边都受益。
 *
 * 与页面的契约：只通过回调上报结果，页面负责把结果写进 @State。
 * 回调可能被调用多次（第一次失败 → 重试成功），页面侧的应用函数保证幂等。
 */
import { appLog as hilog } from '../../core/log/AppLogger';
import { getLyricInfo, getPicPath } from '../../core/music/MusicFeatureEntry';
import { playerService } from '../../service/PlayerService';
import { settingsService } from '../../service/SettingsService';
import { convertChinese } from '../../core/lyric/ChineseConvert';
import { getCurrentLyricIndex, parseLrc, type LyricLine } from '../../core/music/MusicParsingUtils';
import type { MusicInfo } from '../../types/MusicTypes';

const DOMAIN: number = 0x0001;
const TAG = 'PlayMediaAssets';
/** 同一首歌失败后的重试次数与间隔（封面 / 歌词各自退避） */
const MAX_RETRY = 2;
const COVER_RETRY_DELAY_MS = 600;
const LYRIC_RETRY_DELAY_MS = 700;

/** 封面加载结果 */
export interface CoverOutcome {
  /** loaded=拿到可用封面；cleared=确认没有封面（应显示占位）；failed=这次没成功（可能还会重试） */
  status: 'loaded' | 'cleared' | 'failed';
  url: string;
}

/** 歌词数据（一次解析后的完整结果） */
export interface LyricPayload {
  rawText: string;
  timeline: LyricLine[];
  lines: string[];
  secondaryLines: string[];
  currentIndex: number;
}

/** 歌词加载结果：empty=纯音乐；failed=拉取失败；loaded=正常 */
export interface LyricOutcome {
  status: 'loaded' | 'empty' | 'failed';
  payload?: LyricPayload;
}

/** 页面回调：可能与 retry 一起被多次调用 */
export interface LyricCallbacks {
  /** 开始加载（页面可显示「歌词加载中」） */
  onLoading?: () => void;
  onOutcome: (outcome: LyricOutcome) => void;
}

export class PlayMediaAssets {
  private alive: boolean = false;
  private coverLoading: boolean = false;
  private coverAttemptKey: string = '';
  private coverRetryCount: number = 0;
  private coverRetryTimer: number = -1;
  private picSeq: number = 0;
  /** 页面注册的结果回调：重试成功时也要能推给同一处，所以由加载器持有 */
  private coverHandler: ((outcome: CoverOutcome) => void) | null = null;
  private lyricLoading: boolean = false;
  private lyricSongKey: string = '';
  private lyricFailedKey: string = '';
  private lyricRetryCount: number = 0;
  private lyricRetryTimer: number = -1;
  private lyricSeq: number = 0;
  private lyricHandler: LyricCallbacks | null = null;

  /** 页面可见性：不可见时丢弃结果与定时器（避免离开页面后还在改状态） */
  setAlive(alive: boolean): void {
    this.alive = alive;
    if (!alive) {
      this.clearTimers();
    }
  }

  private clearTimers(): void {
    if (this.coverRetryTimer !== -1) {
      clearTimeout(this.coverRetryTimer);
      this.coverRetryTimer = -1;
    }
    if (this.lyricRetryTimer !== -1) {
      clearTimeout(this.lyricRetryTimer);
      this.lyricRetryTimer = -1;
    }
  }

  /** 歌曲身份 key：守卫与去重都按它比较 */
  static musicKey(info: MusicInfo): string {
    return [
      info?.source ?? '',
      info?.id ?? '',
      info?.songmid ?? '',
      info?.name ?? '',
      info?.singer ?? '',
    ].join('|');
  }

  /** 空串 / 'null' / 非 http(s) 都视为不可渲染 */
  static canRenderCover(url: string): boolean {
    const value = (url ?? '').trim();
    if (value.length === 0 || value === 'null' || value === 'undefined') {
      return false;
    }
    return value.startsWith('http://') || value.startsWith('https://') || value.startsWith('//');
  }

  /** 补协议、去空白；不可用返回空串 */
  static normalizeCoverUrl(rawUrl: string): string {
    const url = (rawUrl ?? '').trim();
    if (!url) {
      return '';
    }
    if (url.startsWith('//')) {
      return `http:${url}`;
    }
    if (url.startsWith('http://') || url.startsWith('https://')) {
      return url;
    }
    return '';
  }

  /** https 封面拉不到时的降级（部分源只支持 http） */
  static downgradeCoverUrl(url: string): string {
    const value = (url ?? '').trim();
    if (!value.startsWith('https://')) {
      return '';
    }
    return `http://${value.substring(8)}`;
  }

  /**
   * 确保封面可用。
   * @param hasUsableCover 页面当前是否已有可渲染封面（有则非强制情况下跳过）
   */
  async ensureCover(
    info: MusicInfo, force: boolean, hasUsableCover: boolean,
    onOutcome: (outcome: CoverOutcome) => void): Promise<void> {
    if (!this.alive || !info || !info.name) {
      return;
    }
    this.coverHandler = onOutcome;
    if (!force && hasUsableCover) {
      return;
    }
    // 同一首歌已试过且失败 / 已有请求在飞：跳过。
    // onMusicInfoChange 是高频回调，不拦会变成「封面拉不到就逐帧重试」的请求风暴。
    const attemptKey = PlayMediaAssets.musicKey(info);
    if (this.coverLoading || (!force && this.coverAttemptKey === attemptKey)) {
      return;
    }
    this.coverLoading = true;
    const seq = ++this.picSeq;
    try {
      const picPath = await getPicPath({ musicInfo: info, isRefresh: force });
      if (!this.alive || seq !== this.picSeq) {
        return;
      }
      const normalized = PlayMediaAssets.normalizeCoverUrl(picPath ?? '');
      if (normalized.length > 0) {
        this.coverRetryCount = 0;
        this.coverAttemptKey = '';
        onOutcome({ status: 'loaded', url: normalized });
      } else {
        // 明确置空以触发默认封面显示，避免无效旧值残留导致空白
        this.coverAttemptKey = attemptKey;
        onOutcome({ status: 'cleared', url: '' });
      }
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'ensureCover failed: %{public}s', JSON.stringify(err));
      this.coverAttemptKey = attemptKey;
      onOutcome({ status: 'failed', url: '' });
      this.scheduleCoverRetry();
    } finally {
      this.coverLoading = false;
    }
  }

  private scheduleCoverRetry(): void {
    if (this.coverRetryCount >= MAX_RETRY || !this.alive) {
      return;
    }
    this.coverRetryCount += 1;
    if (this.coverRetryTimer !== -1) {
      clearTimeout(this.coverRetryTimer);
    }
    this.coverRetryTimer = setTimeout(() => {
      this.coverRetryTimer = -1;
      // 重试用页面当时正在播的那首（可能已经切歌）
      const latest = playerService.getCurrentMusicInfo();
      const handler = this.coverHandler;
      if (!handler) {
        return;
      }
      void this.ensureCover(latest, true, false, handler);
    }, COVER_RETRY_DELAY_MS);
  }

  /**
   * 确保歌词可用。
   * @param hasUsableLyric 页面当前是否已有可用歌词（有则后台刷新不抢 UI）
   */
  async ensureLyric(
    info: MusicInfo, force: boolean, hasUsableLyric: boolean,
    callbacks: LyricCallbacks): Promise<void> {
    if (!this.alive || !info || !info.name) {
      callbacks.onOutcome({ status: 'empty' });
      return;
    }
    this.lyricHandler = callbacks;
    const targetKey = PlayMediaAssets.musicKey(info);
    // 同一首已拿到歌词或已试过失败且非强制：跳过（同上，防请求风暴）
    if (this.lyricLoading ||
      (!force && (this.lyricSongKey === targetKey || this.lyricFailedKey === targetKey))) {
      return;
    }
    this.lyricLoading = true;
    if ((force || !hasUsableLyric) && !hasUsableLyric && callbacks.onLoading) {
      callbacks.onLoading();
    }
    const seq = ++this.lyricSeq;
    try {
      const lyricInfo = await getLyricInfo({ musicInfo: info, isRefresh: force });
      if (!this.alive || seq !== this.lyricSeq) {
        return;
      }
      // 歌词交给播放器统一维护：系统播控 / 桌面歌词 / 播放页共用同一份数据
      // setLyricData 内部按设置做简繁转换，这里读回转好的文本，保证主/译文一致
      playerService.setLyricData(lyricInfo.lyric || '');
      const rawText = playerService.getLyricText();
      const primaryLines = parseLrc(rawText);
      const secondaryLines = parseLrc(convertChinese(lyricInfo.tlyric || '', settingsService.get().s2tMode));
      if (primaryLines.length === 0) {
        this.lyricSongKey = targetKey;
        this.lyricFailedKey = '';
        this.lyricRetryCount = 0;
        callbacks.onOutcome({ status: 'empty' });
        return;
      }
      const secondaries: string[] = [];
      let sIdx = 0;
      for (let i = 0; i < primaryLines.length; i++) {
        const line = primaryLines[i];
        while (sIdx + 1 < secondaryLines.length && secondaryLines[sIdx + 1].time <= line.time) {
          sIdx += 1;
        }
        if (sIdx < secondaryLines.length && Math.abs(secondaryLines[sIdx].time - line.time) <= 0.35) {
          secondaries.push(secondaryLines[sIdx].text);
        } else {
          secondaries.push('');
        }
      }
      this.lyricSongKey = targetKey;
      this.lyricFailedKey = '';
      this.lyricRetryCount = 0;
      callbacks.onOutcome({
        status: 'loaded',
        payload: {
          rawText: rawText,
          timeline: primaryLines,
          lines: primaryLines.map((line: LyricLine): string => line.text),
          secondaryLines: secondaries,
          currentIndex: getCurrentLyricIndex(primaryLines, playerService.getProgress().nowPlayTime),
        },
      });
    } catch (err) {
      if (!this.alive || seq !== this.lyricSeq) {
        return;
      }
      hilog.warn(DOMAIN, TAG, 'ensureLyric failed: %{public}s', JSON.stringify(err));
      this.lyricFailedKey = targetKey;
      callbacks.onOutcome({ status: 'failed' });
      this.scheduleLyricRetry(targetKey);
    } finally {
      this.lyricLoading = false;
    }
  }

  private scheduleLyricRetry(targetKey: string): void {
    if (this.lyricRetryCount >= MAX_RETRY || !this.alive) {
      return;
    }
    this.lyricRetryCount += 1;
    if (this.lyricRetryTimer !== -1) {
      clearTimeout(this.lyricRetryTimer);
    }
    this.lyricRetryTimer = setTimeout(() => {
      this.lyricRetryTimer = -1;
      const latest = playerService.getCurrentMusicInfo();
      if (PlayMediaAssets.musicKey(latest) !== targetKey) {
        return;
      }
      const handler = this.lyricHandler;
      if (!handler) {
        return;
      }
      void this.ensureLyric(latest, true, false, handler);
    }, LYRIC_RETRY_DELAY_MS);
  }
}
