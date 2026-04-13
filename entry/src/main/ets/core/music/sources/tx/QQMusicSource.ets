import { musicSearch } from './musicSearch';
import { lyric } from './lyric';
import { leaderboard } from './leaderboard';
import { hotSearch } from './hotSearch';
import { songList } from './songList';
import { getTxMusicUrl } from './txPlayUrl';
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

/** QQ 音乐 — 平台入口（源 id `tx`，兼容既有数据字段） */
export class QQMusicSource extends AbstractMusicSource {
  readonly sourceId: string = 'tx';
  protected readonly logTag: string = 'QQMusicSource';

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
    const albumId: string | undefined = songInfo.albumId;
    if (albumId && albumId !== '空') {
      return Promise.resolve(`https://y.gtimg.cn/music/photo_new/T002R500x500M000${albumId}.jpg`);
    }
    return Promise.resolve('');
  }

  getMusicUrl(songInfo: MusicInfo, quality: string): Promise<MusicUrlResult> {
    return getTxMusicUrl(songInfo, quality);
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
    const inst = new QQMusicSource();
    void inst.initialize();
    return inst.toSingleMusicSdkInterface();
  }
}
