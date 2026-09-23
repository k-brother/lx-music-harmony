/**
 * 歌单广场的数据加载（按源取 SDK / 标签 / 分页列表）
 *
 * 从 SongListView 抽出：三个加载方法里都有一段「按 sourceId 选 SDK」的 if 链（重复三份），
 * 以及「字段怎么映射成卡片数据」的规则。抽出来之后页面只负责页码/加载态/滚动窗口这些 UI 状态。
 */
import { appLog as hilog } from '../../../core/log/AppLogger';
import { t } from '../../../service/LocalizationService';
import { musicSdk } from '../../../core/music/MusicSdkAggregate';
import type { SongListInfo } from '../../../core/music/sources/MusicSdkContracts';
import type { SongListItemData } from '../SongListTypes';

const TAG = 'SongListLoader';
const DOMAIN: number = 0x0001;

/** 标签选项（与页面一致：name + tid） */
export interface TagOption {
  name: string;
  tid: string;
}

/** 一页歌单的加载结果 */
export interface SongListPageResult {
  items: SongListItemData[];
  hasMore: boolean;
}

/** 标签原始项（各源字段不一） */
interface RawTag {
  name?: string;
  id?: string;
}

/** 标签接口返回 */
interface RawTagResult {
  tags: RawTag[];
}

/** 歌单列表接口返回 */
interface RawSongListResult {
  list: SongListInfo[];
  limit?: number;
}

/** 页面里的 SDK 结构（只用到 songList 一个能力） */
interface SongListSdkLike {
  songList?: SongListModule;
}

/** 歌单广场能力 */
interface SongListModule {
  getTags: () => Promise<RawTagResult>;
  getList: (sortId: string, tagId: string, page: number) => Promise<RawSongListResult>;
}

/** 按音源取 SDK（原先三处各写一遍 if 链） */
function sdkForSource(sourceId: string): SongListSdkLike | undefined {
  if (sourceId === 'kw') return musicSdk.kw as SongListSdkLike;
  if (sourceId === 'kg') return musicSdk.kg as SongListSdkLike;
  if (sourceId === 'tx') return musicSdk.tx as SongListSdkLike;
  if (sourceId === 'wy') return musicSdk.wy as SongListSdkLike;
  if (sourceId === 'mg') return musicSdk.mg as SongListSdkLike;
  return undefined;
}


/** 标签列表：首项固定为「全部」；失败返回只有「全部」的列表 */
export async function fetchSongListTags(sourceId: string): Promise<TagOption[]> {
  const all: TagOption = { name: t('filter_all'), tid: '' };
  const tags: TagOption[] = [all];
  try {
    const sdk = sdkForSource(sourceId);
    if (!sdk || !sdk.songList) {
      return tags;
    }
    const result = await sdk.songList.getTags();
    if (result && result.tags) {
      for (let i = 0; i < result.tags.length; i++) {
        const tag = result.tags[i];
        tags.push({ name: tag.name || '', tid: tag.id || '' });
      }
    }
  } catch (err) {
    hilog.error(DOMAIN, TAG, 'Load tags failed: %{public}s', JSON.stringify(err));
  }
  return tags;
}

/**
 * 拉一页歌单。
 * 不支持该源时返回 null（页面按「无数据」处理）。
 */
export async function fetchSongListPage(
  sourceId: string, sortId: string, tagId: string, page: number): Promise<SongListPageResult | null> {
  const sdk = sdkForSource(sourceId);
  if (!sdk || !sdk.songList) {
    return null;
  }
  const result = await sdk.songList.getList(sortId, tagId, page);
  const items: SongListItemData[] = [];
  for (let i = 0; i < result.list.length; i++) {
    const sl: SongListInfo = result.list[i];
    items.push({
      id: sl.id || '',
      name: sl.name || '',
      author: sl.author || '',
      img: sl.img || '',
      play_count: sl.play_count || '0',
      desc: sl.desc || '',
      total: sl.total || 0,
      // 以数据自身的来源为准：切源瞬间旧数据可能仍在屏幕上，
      // 用页面当前源会让详情页拿 A 源的 id 去问 B 源（真机表现为「该歌单暂无歌曲」）
      source: sl.source || sourceId,
    });
  }
  return { items: items, hasMore: items.length >= (result.limit || 20) };
}
