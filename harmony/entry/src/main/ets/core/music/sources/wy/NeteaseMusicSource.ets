import { musicSearch } from './musicSearch';
import { lyric } from './lyric';
import { leaderboard } from './leaderboard';
import { hotSearch } from './hotSearch';
import { songList } from './songList';
import { getWyMusicUrl } from './wyPlayUrl';
import type { SingleMusicSdkInterface, SongListSdkInterface } from '../MusicSdkContracts';
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

const wySongList: SongListSdkInterface = songList as SongListSdkInterface;

/** 网易云音乐 — 平台入口（源 id `wy`） */
export class NeteaseMusicSource extends AbstractMusicSource {
  readonly sourceId: string = 'wy';
  protected readonly logTag: string = 'NeteaseMusicSource';

  getConfig(): MusicSourceClientConfig {
    return { timeoutMs: 15000 };
  }

  search(keyword: string, page: number, limit: number): Promise<SearchResult | null> {
    return musicSearch.search(keyword, page, limit);
  }

  getLyric(songInfo: MusicInfo): Promise<LyricInfo> {
    return lyric.getLyric(songInfo.songmid || '');
  }

  getPic(songInfo: MusicInfo): Promise<string> {
    return Promise.resolve(songInfo.img || '');
  }

  getMusicUrl(songInfo: MusicInfo, quality: string): Promise<MusicUrlResult> {
    return getWyMusicUrl(songInfo, quality);
  }

  getLeaderboards(): Promise<LeaderboardResult> {
    return leaderboard.getBoards();
  }

  getLeaderboardSongs(bangId: string, page: number): Promise<LeaderboardListResult> {
    return leaderboard.getList(bangId, page);
  }

  getSongListTags(): Promise<SongListTagsResult> {
    return wySongList.getTags();
  }

  getSongList(sortId: string, tagId: string, page: number): Promise<SongListResult> {
    return wySongList.getList(sortId, tagId, page);
  }

  getSongListDetail(listId: string, page: number): Promise<SongListDetailResult> {
    return wySongList.getListDetail(listId, page);
  }

  getHotSearch(): Promise<HotSearchResult> {
    return hotSearch.search();
  }

  static createSdk(): SingleMusicSdkInterface {
    const inst = new NeteaseMusicSource();
    void inst.initialize();
    return inst.toSingleMusicSdkInterface();
  }
}
