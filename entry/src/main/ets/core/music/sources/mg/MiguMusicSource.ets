import { musicSearch } from './musicSearch';
import { lyric } from './lyric';
import { leaderboard } from './leaderboard';
import { hotSearch } from './hotSearch';
import { songList } from './songList';
import { getMgMusicUrl } from './mgPlayUrl';
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

const mgSongList: SongListSdkInterface = songList as SongListSdkInterface;

/** 咪咕音乐 — 平台入口 */
export class MiguMusicSource extends AbstractMusicSource {
  readonly sourceId: string = 'mg';
  protected readonly logTag: string = 'MiguMusicSource';

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
    return Promise.resolve(songInfo.img || '');
  }

  getMusicUrl(songInfo: MusicInfo, quality: string): Promise<MusicUrlResult> {
    return getMgMusicUrl(songInfo, quality);
  }

  getLeaderboards(): Promise<LeaderboardResult> {
    return leaderboard.getBoards();
  }

  getLeaderboardSongs(bangId: string, page: number): Promise<LeaderboardListResult> {
    return leaderboard.getList(bangId, page);
  }

  getSongListTags(): Promise<SongListTagsResult> {
    return mgSongList.getTags();
  }

  getSongList(sortId: string, tagId: string, page: number): Promise<SongListResult> {
    return mgSongList.getList(sortId, tagId, page);
  }

  getSongListDetail(listId: string, page: number): Promise<SongListDetailResult> {
    return mgSongList.getListDetail(listId, page);
  }

  getHotSearch(): Promise<HotSearchResult> {
    return hotSearch.search();
  }

  static createSdk(): SingleMusicSdkInterface {
    const inst = new MiguMusicSource();
    void inst.initialize();
    return inst.toSingleMusicSdkInterface();
  }
}
