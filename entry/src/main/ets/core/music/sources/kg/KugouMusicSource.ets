import { musicSearch } from './musicSearch';
import { lyric } from './lyric';
import { leaderboard } from './leaderboard';
import { songList } from './songList';
import { hotSearch } from './hotSearch';
import { pic } from './pic';
import { getKgMusicUrl } from './kgPlayUrl';
import { searchTips } from './tipSearch';
import type { SingleMusicSdkInterface } from '../MusicSdkContracts';
import type { MusicInfo, LyricInfo, SearchResult } from '../../../../types/MusicTypes';
import type {
  LeaderboardResult,
  LeaderboardListResult,
  SongListTagsResult,
  SongListResult,
  SongListDetailResult,
  HotSearchResult,
  MusicUrlResult,
} from '../MusicSdkContracts';
import type { MusicSourceClientConfig } from '../IMusicSource';
import { AbstractMusicSource } from '../AbstractMusicSource';

/** 酷狗音乐 — 平台入口；子模块见同目录 `*.ets` */
export class KugouMusicSource extends AbstractMusicSource {
  readonly sourceId: string = 'kg';
  protected readonly logTag: string = 'KugouMusicSource';

  protected getSearchTipBinder(): ((keyword: string) => Promise<string[]>) | undefined {
    return searchTips;
  }

  getConfig(): MusicSourceClientConfig {
    return { timeoutMs: 15000 };
  }

  search(keyword: string, page: number, limit: number): Promise<SearchResult | null> {
    return musicSearch.search(keyword, page, limit);
  }

  getLyric(songInfo: MusicInfo): Promise<LyricInfo> {
    return lyric.getLyric(songInfo);
  }

  getPic(songInfo: MusicInfo): Promise<string> {
    return pic.getPic(songInfo);
  }

  getMusicUrl(songInfo: MusicInfo, quality: string): Promise<MusicUrlResult> {
    return getKgMusicUrl(songInfo, quality);
  }

  getLeaderboards(): Promise<LeaderboardResult> {
    return leaderboard.getBoards();
  }

  getLeaderboardSongs(bangId: string, page: number): Promise<LeaderboardListResult> {
    return leaderboard.getList(bangId, page);
  }

  getSongListTags(): Promise<SongListTagsResult> {
    return songList.getTags();
  }

  getSongList(sortId: string, tagId: string, page: number): Promise<SongListResult> {
    return songList.getList(sortId, tagId, page);
  }

  getSongListDetail(listId: string, page: number): Promise<SongListDetailResult> {
    return songList.getListDetail(listId, page);
  }

  getHotSearch(): Promise<HotSearchResult> {
    return hotSearch.search();
  }

  static createSdk(): SingleMusicSdkInterface {
    const inst = new KugouMusicSource();
    void inst.initialize();
    return inst.toSingleMusicSdkInterface();
  }
}
