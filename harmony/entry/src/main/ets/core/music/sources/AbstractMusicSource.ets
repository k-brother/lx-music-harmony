/**
 * 抽象音乐源：实现 {@link IMusicSource} 的共性（组装旧 SDK 形状、重试骨架），子类实现各平台差异。
 * 受保护 HTTP 入口对应图中的 `#fetch`；`retryRun` 对应 `#retry`。
 */

import type {
  SingleMusicSdkInterface,
  MusicSearchSdkInterface,
  LeaderboardResult,
  LeaderboardListResult,
  SongListTagsResult,
  SongListResult,
  SongListDetailResult,
  HotSearchResult,
  MusicUrlResult,
} from './MusicSdkContracts';
import type { MusicInfo, LyricInfo, SearchResult } from '../../../types/MusicTypes';
import type { IMusicSource, MusicSourceClientConfig } from './IMusicSource';
import type { HttpRequestConfig } from '../../../core/network/http';
import { BaseMusicSource } from './BaseMusicSource';

export abstract class AbstractMusicSource extends BaseMusicSource implements IMusicSource {
  protected clientConfig: MusicSourceClientConfig = {};
  private initDone: boolean = false;

  abstract readonly sourceId: string;

  getConfig(): MusicSourceClientConfig {
    return this.clientConfig;
  }

  applyClientConfig(cfg: MusicSourceClientConfig): void {
    this.clientConfig = {
      timeoutMs: cfg.timeoutMs !== undefined ? cfg.timeoutMs : this.clientConfig.timeoutMs,
      userAgent: cfg.userAgent !== undefined ? cfg.userAgent : this.clientConfig.userAgent,
    };
  }

  async initialize(): Promise<void> {
    if (this.initDone) {
      return;
    }
    this.initDone = true;
    await this.onInitialize();
  }

  /** 子类可覆盖：连接探测、加载证书等 */
  protected async onInitialize(): Promise<void> {
    return;
  }

  /**
   * 受保护 HTTP GET JSON（图中 #fetch 的同步语义封装，基于 {@link BaseMusicSource#fetchJson}）
   */
  protected fetch(url: string, cfg?: HttpRequestConfig): Promise<Object> {
    return this.fetchJson<Object>(url, cfg ?? {});
  }

  /**
   * 简单重试包装（指数退避由子类按需调整）
   */
  protected async retryRun<T>(fn: () => Promise<T>, maxAttempts: number = 3): Promise<T> {
    let lastErr: Error = new Error('retryRun: unknown');
    for (let i = 0; i < maxAttempts; i++) {
      try {
        return await fn();
      } catch (e) {
        lastErr = e instanceof Error ? e : new Error(String(e));
        if (i < maxAttempts - 1) {
          await AbstractMusicSource.sleepMs(300 * (i + 1));
        }
      }
    }
    throw lastErr;
  }

  private static sleepMs(ms: number): Promise<void> {
    return new Promise<void>((resolve: (v: void) => void) => {
      setTimeout((): void => {
        resolve();
      }, ms);
    });
  }

  abstract search(keyword: string, page: number, limit: number): Promise<SearchResult | null>;

  abstract getLyric(songInfo: MusicInfo): Promise<LyricInfo>;

  abstract getPic(songInfo: MusicInfo): Promise<string>;

  abstract getMusicUrl(songInfo: MusicInfo, quality: string): Promise<MusicUrlResult>;

  abstract getLeaderboards(): Promise<LeaderboardResult>;

  abstract getLeaderboardSongs(bangId: string, page: number): Promise<LeaderboardListResult>;

  abstract getSongListTags(): Promise<SongListTagsResult>;

  abstract getSongList(sortId: string, tagId: string, page: number): Promise<SongListResult>;

  abstract getSongListDetail(listId: string, page: number): Promise<SongListDetailResult>;

  abstract getHotSearch(): Promise<HotSearchResult>;

  /** 子类若支持搜索联想，覆盖为返回函数；默认无 */
  protected getSearchTipBinder(): ((keyword: string) => Promise<string[]>) | undefined {
    return undefined;
  }

  toSingleMusicSdkInterface(): SingleMusicSdkInterface {
    const self = this;
    const tipBinder = self.getSearchTipBinder();
    const musicSearch: MusicSearchSdkInterface = {
      search: (keyword: string, page: number, limit: number): Promise<SearchResult | null> => {
        return self.search(keyword, page, limit);
      },
    };
    if (tipBinder !== undefined) {
      musicSearch.tip = (keyword: string): Promise<string[]> => {
        return tipBinder(keyword);
      };
    }
    const out: SingleMusicSdkInterface = {
      getLyric: (songInfo: MusicInfo): Promise<LyricInfo> => {
        return self.getLyric(songInfo);
      },
      getPic: (songInfo: MusicInfo): Promise<string> => {
        return self.getPic(songInfo);
      },
      getMusicUrl: (songInfo: MusicInfo, quality: string): Promise<MusicUrlResult> => {
        return self.getMusicUrl(songInfo, quality);
      },
      musicSearch: musicSearch,
      leaderboard: {
        getBoards: (): Promise<LeaderboardResult> => {
          return self.getLeaderboards();
        },
        getList: (bangId: string, page: number): Promise<LeaderboardListResult> => {
          return self.getLeaderboardSongs(bangId, page);
        },
      },
      songList: {
        getTags: (): Promise<SongListTagsResult> => {
          return self.getSongListTags();
        },
        getList: (sortId: string, tagId: string, page: number): Promise<SongListResult> => {
          return self.getSongList(sortId, tagId, page);
        },
        getListDetail: (listId: string, page: number): Promise<SongListDetailResult> => {
          return self.getSongListDetail(listId, page);
        },
      },
      hotSearch: {
        search: (): Promise<HotSearchResult> => {
          return self.getHotSearch();
        },
      },
    };
    return out;
  }
}
