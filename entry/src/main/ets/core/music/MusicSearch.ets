/**
 * 多源搜索
 *
 * 从 ResolvePlayback 抽出：搜索只依赖 SDK 聚合与相似度工具，与「取链/取歌词/取封面」无关。
 * 搜索结果按源分组返回，供搜索面板与跨源匹配复用。
 */
import { musicSdk } from './MusicSdkAggregate';
import { appLog as hilog } from '../log/AppLogger';
import type { MusicInfo } from '../../types/MusicTypes';
import { SUPPORTED_SOURCES } from '../../types/MusicSource';

const TAG = 'ONLINE_MUSIC';
const DOMAIN = 0x0003;

/**
 * 搜索音乐（多源搜索）
 */
export interface SearchMusicParams {
  name: string;
  singer?: string;
  limit?: number;
}


export async function searchMusic(params: SearchMusicParams): Promise<MusicInfo[]> {
  const name = params.name;
  const singer = params.singer;
  const limit = params.limit ?? 25;
  const keyword = `${name} ${singer || ''}`.trim();

  if (!keyword) {
    return [];
  }

  // 源列表与顺序统一在 types/MusicSource，新增源只需改一处
  const sources: string[] = SUPPORTED_SOURCES;
  const results: MusicInfo[][] = [];

  // 并行搜索所有源
  const searchPromises: Promise<MusicInfo[]>[] = sources.map(async (source) => {
    try {
      const result = await searchFromSource(source, keyword, 1, limit);
      return result;
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'searchFromSource failed for %{public}s: %{public}s', source, (err as Error).message);
      return [];
    }
  });

  const searchResults = await Promise.all(searchPromises);

  // 合并结果
  for (const result of searchResults) {
    if (result && result.length > 0) {
      results.push(result);
    }
  }

  // 返回第一个搜索结果（通常是最好的匹配）
  return results[0] || [];
}

/**
 * 从指定源搜索音乐
 */
async function searchFromSource(source: string, keyword: string, page: number, limit: number): Promise<MusicInfo[]> {
  const sdk = getSdkBySource(source);
  if (!sdk || !sdk.musicSearch) {
    return [];
  }

  const result = await sdk.musicSearch.search(keyword, page, limit);
  if (result && result.list) {
    return result.list;
  }

  return [];
}

/**
 * 根据源获取SDK
 */
function getSdkBySource(source: string): SdkSearchInterface | null {
  switch (source) {
    case 'kw':
      return musicSdk.kw as SdkSearchInterface;
    case 'kg':
      return musicSdk.kg as SdkSearchInterface;
    case 'tx':
      return musicSdk.tx as SdkSearchInterface;
    case 'wy':
      return musicSdk.wy as SdkSearchInterface;
    case 'mg':
      return musicSdk.mg as SdkSearchInterface;
    default:
      return null;
  }
}

/**
 * 音乐搜索接口
 */
interface MusicSearchModule {
  search: (keyword: string, page: number, limit: number) => Promise<SearchResultLocal | null>;
}

interface SearchResultLocal {
  list: MusicInfo[];
}

/**
 * SDK接口（避免使用any）
 */
interface SdkSearchInterface {
  musicSearch: MusicSearchModule;
}
