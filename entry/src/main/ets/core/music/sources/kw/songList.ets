import hilog from '@ohos.hilog';
import { httpRequest } from '../../../../core/network/http';
import type { MusicInfo, Quality, QualityDetail } from '../../../../types/MusicTypes';
import { formatPlayTime, decodeHtmlEntities, formatSinger, formatPlayCount } from '../../../../utils/CommonUtils';

const TAG = 'KwSongList';
const DOMAIN = 0x0001;

// 歌单标签
export interface SongListTag {
  id: string;
  name: string;
  parent_id?: string;
  parent_name?: string;
}

// 歌单标签分类
interface SongListTagCategory {
  name: string;
  id: string;
  list: SongListTag[];
}

// 歌单信息
export interface SongListInfo {
  id: string;
  name: string;
  author: string;
  img: string;
  play_count: string;
  desc: string;
  total: number;
  source: string;
}

// 歌单结果
export interface SongListResult {
  list: SongListInfo[];
  total: number;
  page: number;
  limit: number;
  source: string;
}

// 歌单详情信息
interface SongListDetailInfo {
  name: string;
  img: string;
  desc: string;
  author: string;
  play_count: string;
}

// 歌单详情结果
export interface SongListDetailResult {
  list: MusicInfo[];
  info: SongListDetailInfo;
  total: number;
  source: string;
}

// 歌单标签结果
export interface SongListTagsResult {
  tags: SongListTag[];
  hotTag: SongListTag[];
  source: string;
}

// 歌单排序项
export interface SortItem {
  name: string;
  tid: string;
  id: string;
}

// 热门歌单项
interface HotTagItem {
  id: string;
  name: string;
  bangId: string;
}

// 质量类型项
interface QualityTypeItem {
  type: Quality;
  size: string | null;
}

// 质量信息解析结果
interface QualityParseResult {
  types: QualityTypeItem[];
  _types: Map<Quality, QualityDetail>;
}

// 歌单模块
export interface SongListInterface {
  limit: number;
  limitSong: number;
  sortList: SortItem[];
  hotTags: HotTagItem[];
  getTags: () => Promise<SongListTagsResult>;
  getList: (sortId: string, tagId: string, page?: number) => Promise<SongListResult>;
  getListDetail: (listId: string, page?: number) => Promise<SongListDetailResult>;
  getDetailPageUrl: (listId: string) => string;
}

// 歌单列表API数据容器
interface KwSongListDataContainer {
  data?: KwSongListItem[];
  total?: string;
}

// 歌单列表API数据
interface KwSongListApiData {
  code?: number;
  data?: KwSongListDataContainer;
}

interface KwTagRawItem {
  id?: number | string;
  name?: string;
  digest?: number | string;
}

interface KwTagRawCategory {
  id?: number | string;
  name?: string;
  data?: KwTagRawItem[];
}

interface KwTagListApiData {
  code?: number;
  data?: KwTagRawCategory[];
}

// 酷我歌单项
interface KwSongListItem {
  id?: string | number;
  name?: string;
  uname?: string;
  img?: string;
  listencnt?: string;
  desc?: string;
  total?: string;
}

// 酷我歌单详情API数据
interface KwSongDetailApiData {
  result?: string;
  musiclist?: KwSongDetailItem[];
  title?: string;
  pic?: string;
  info?: string;
  uname?: string;
  playnum?: string;
  total?: string;
}

// 酷我歌单详情歌曲项
interface KwSongDetailItem {
  id?: string;
  name?: string;
  artist?: string;
  album?: string;
  albumid?: string;
  duration?: string;
  N_MINFO?: string;
}

// 构建空结果
function buildEmptyListResult(page: number, limit: number): SongListResult {
  return {
    list: [],
    total: 0,
    page,
    limit,
    source: 'kw',
  };
}

// 构建空详情结果
function buildEmptyDetailResult(): SongListDetailResult {
  return {
    list: [],
    info: { name: '', img: '', desc: '', author: '', play_count: '' },
    total: 0,
    source: 'kw',
  };
}

// 解析音质信息
function parseQualityInfo(nMinfo: string): QualityParseResult {
  const types: QualityTypeItem[] = [];
  const _types: Map<Quality, QualityDetail> = new Map();

  const infoArr: string[] = nMinfo.split(';');

  for (const info of infoArr) {
    const match: RegExpMatchArray | null = info.match(/level:(\w+),bitrate:(\d+),format:(\w+),size:([\w.]+)/);
    if (match) {
      const bitrate: string = match[2];
      const size: string = match[4].toUpperCase();

      switch (bitrate) {
        case '4000':
          types.push({ type: 'flac24bit', size });
          _types.set('flac24bit', { size });
          break;
        case '2000':
          types.push({ type: 'flac', size });
          _types.set('flac', { size });
          break;
        case '320':
          types.push({ type: '320k', size });
          _types.set('320k', { size });
          break;
        case '128':
          types.push({ type: '128k', size });
          _types.set('128k', { size });
          break;
      }
    }
  }

  types.reverse();
  return { types, _types };
}

// 构建歌曲信息
function buildMusicInfo(item: KwSongDetailItem): MusicInfo {
  const qualityResult: QualityParseResult = parseQualityInfo(item.N_MINFO || '');
  const typeUrl: Map<string, string> = new Map();

  return {
    name: decodeHtmlEntities(item.name || ''),
    singer: formatSinger(decodeHtmlEntities(item.artist || '')),
    source: 'kw',
    songmid: item.id || '',
    albumId: item.albumid || '',
    interval: formatPlayTime(parseInt(item.duration || '0')),
    albumName: decodeHtmlEntities(item.album || ''),
    img: null,
    lrc: null,
    types: qualityResult.types,
    _types: qualityResult._types,
    typeUrl,
    otherSource: null,
  };
}

/**
 * 标签接口不可用时的兜底标签。
 *
 * 分类接口（getTagList）会时不时抽风：返回非 200、字段缺失、请求直接失败三种情况下
 * 页面都必须还有内容可点，所以三处兜底共用同一份数据（原先复制了三份 16 行的字面量，
 * 改一处漏两处是迟早的事）。
 */
const KW_FALLBACK_TAGS: SongListTag[] = [
  { id: '37-10000', name: '华语' },
  { id: '35-10000', name: '欧美' },
  { id: '1093-10000', name: '韩语' },
  { id: '1091-10000', name: '日语' },
  { id: '393-10000', name: '流行' },
  { id: '392-10000', name: '民谣' },
  { id: '391-10000', name: '电子' },
  { id: '389-10000', name: '摇滚' },
];

const KW_FALLBACK_HOT_TAGS: SongListTag[] = [
  { id: '393-10000', name: '流行' },
  { id: '37-10000', name: '华语' },
  { id: '35-10000', name: '欧美' },
  { id: '1093-10000', name: '韩语' },
  { id: '1091-10000', name: '日语' },
];

/** 兜底标签结果（每次返回副本，避免调用方改动共享常量） */
function buildFallbackTagsResult(): SongListTagsResult {
  const result: SongListTagsResult = {
    tags: KW_FALLBACK_TAGS.slice(),
    hotTag: KW_FALLBACK_HOT_TAGS.slice(),
    source: 'kw',
  };
  return result;
}

/**
 * 把分类接口的分类列表拍平成可选标签。
 * 只保留 digest = 10000 的类型：其余类型走 getTagPlayList 拿不到数据，
 * 留在页面上会变成「点了没反应」的空壳入口。
 */
function flattenTagCategories(categories: KwTagRawCategory[]): SongListTag[] {
  const tags: SongListTag[] = [];
  for (let i = 0; i < categories.length; i++) {
    const cat = categories[i];
    const catName = cat.name || '';
    const catId = String(cat.id || '');
    const rows = cat.data || [];
    for (let j = 0; j < rows.length; j++) {
      const row = rows[j];
      const digest = String(row.digest || '');
      if (digest !== '10000') {
        continue;
      }
      tags.push({
        id: `${String(row.id || '')}-${digest}`,
        name: row.name || '',
        parent_id: catId,
        parent_name: catName,
      });
    }
  }
  return tags;
}

/** 热门标签：按语言/曲风关键字挑，最多 8 个 */
function pickHotTags(tags: SongListTag[]): SongListTag[] {
  const hotTag: SongListTag[] = [];
  for (let k = 0; k < tags.length && hotTag.length < 8; k++) {
    const t = tags[k];
    if (t.name && (t.name.includes('流行') || t.name.includes('华语') || t.name.includes('欧美')
      || t.name.includes('韩语') || t.name.includes('日语'))) {
      hotTag.push({ id: t.id, name: t.name });
    }
  }
  return hotTag;
}

export const songList: SongListInterface = {
  limit: 36,
  limitSong: 1000,

  // 排序列表
  sortList: [
    { name: '最新', tid: 'new', id: 'new' },
    { name: '最热', tid: 'hot', id: 'hot' },
  ],

  // 热门标签
  hotTags: [
    { id: 'kw__hot_1', name: '流行', bangId: '1' },
    { id: 'kw__hot_2', name: '华语', bangId: '2' },
    { id: 'kw__hot_3', name: '欧美', bangId: '3' },
    { id: 'kw__hot_4', name: '韩语', bangId: '4' },
    { id: 'kw__hot_5', name: '日语', bangId: '5' },
    { id: 'kw__hot_6', name: '流行', bangId: '6' },
  ],

  /**
   * 获取歌单标签
   */
  getTags(): Promise<SongListTagsResult> {
    const url =
      'http://wapi.kuwo.cn/api/pc/classify/playlist/getTagList?cmd=rcm_keyword_playlist&user=0&prod=kwplayer_pc_9.0.5.0&vipver=9.0.5.0&source=kwplayer_pc_9.0.5.0&loginUid=0&loginSid=0&appUid=76039576';
    return new Promise((resolve) => {
      const task = httpRequest(url, {
        responseType: 'text',
      });
      task.promise.then((response) => {
        try {
          const data: KwTagListApiData = JSON.parse(response.data as string) as KwTagListApiData;
          if (data.code !== 200 || !data.data) {
            resolve(buildFallbackTagsResult());
            return;
          }

          const tags: SongListTag[] = flattenTagCategories(data.data);
          resolve({
            tags,
            hotTag: pickHotTags(tags),
            source: 'kw',
          });
        } catch (e) {
          hilog.warn(DOMAIN, TAG, 'getTags parse failed: %{public}s', (e as Error)?.message);
          resolve(buildFallbackTagsResult());
        }
      }).catch(() => {
        resolve(buildFallbackTagsResult());
      });
    });
  },

  /**
   * 获取歌单列表
   */
  getList(sortId: string, tagId: string, page: number = 1): Promise<SongListResult> {
    const limit: number = songList.limit;
    // 构造请求 URL
    let url: string;
    if (!tagId) {
      // 推荐歌单
      url = `http://wapi.kuwo.cn/api/pc/classify/playlist/getRcmPlayList?loginUid=0&loginSid=0&appUid=76039576&pn=${page}&rn=${limit}&order=${sortId === 'new' ? 'new' : 'hot'}`;
    } else {
      // 分类歌单
      let id = '';
      let type = '';
      if (tagId.indexOf('-') > 0) {
        const parts = tagId.split('-');
        id = parts[0];
        type = parts[1] || '10000';
      } else if (tagId.indexOf('_') > 0) {
        // 兼容旧缓存 tagId（kw_lang_1）
        const parts = tagId.split('_');
        id = parts[parts.length - 1];
        type = '10000';
      } else {
        id = tagId;
        type = '10000';
      }
      if (type === '10000') {
        url = `http://wapi.kuwo.cn/api/pc/classify/playlist/getTagPlayList?loginUid=0&loginSid=0&appUid=76039576&pn=${page}&id=${id}&rn=${limit}`;
      } else {
        // 43 等类型接口返回形态不稳定，这里退化为推荐歌单，避免分类必空
        url = `http://wapi.kuwo.cn/api/pc/classify/playlist/getRcmPlayList?loginUid=0&loginSid=0&appUid=76039576&pn=${page}&rn=${limit}&order=${sortId === 'new' ? 'new' : 'hot'}`;
      }
    }

    return new Promise((resolve) => {
      const task = httpRequest(url, {
        responseType: 'text',
      });

      task.promise.then((response) => {
        try {
          const data: KwSongListApiData = JSON.parse(response.data as string) as KwSongListApiData;

          if (data.code !== 200) {
            resolve(buildEmptyListResult(page, limit));
            return;
          }

          const apiList: KwSongListItem[] = data.data?.data || [];
          const list: SongListInfo[] = [];
          for (const item of apiList) {
            list.push({
              id: `kw_${item.id}`,
              name: decodeHtmlEntities(item.name || ''),
              author: decodeHtmlEntities(item.uname || ''),
              img: item.img || '',
              play_count: formatPlayCount(parseInt(item.listencnt || '0')),
              desc: decodeHtmlEntities(item.desc || ''),
              total: parseInt(item.total || '0'),
              source: 'kw',
            });
          }

          resolve({
            list,
            total: parseInt(data.data?.total || '0'),
            page,
            limit,
            source: 'kw',
          });
        } catch (err) {
          resolve(buildEmptyListResult(page, limit));
        }
      }).catch(() => {
        resolve(buildEmptyListResult(page, limit));
      });
    });
  },

  /**
   * 获取歌单详情
   */
  getListDetail(listId: string, page: number = 1): Promise<SongListDetailResult> {
    // 从 listId 中提取 ID
    const match: RegExpMatchArray | null = listId.match(/kw_(\d+)/);
    const id: string = match ? match[1] : listId;
    const limitSong: number = songList.limitSong;

    const url = `http://nplserver.kuwo.cn/pl.svc?op=getlistinfo&pid=${id}&pn=${page - 1}&rn=${limitSong}&encode=utf8&keyset=pl2012&identity=kuwo&pcmp4=1&vipver=MUSIC_9.0.5.0_W1&newver=1`;

    return new Promise((resolve) => {
      const task = httpRequest(url, {
        responseType: 'text',
      });

      task.promise.then((response) => {
        try {
          const data: KwSongDetailApiData = JSON.parse(response.data as string) as KwSongDetailApiData;

          if (data.result !== 'ok') {
            resolve(buildEmptyDetailResult());
            return;
          }

          const apiList: KwSongDetailItem[] = data.musiclist || [];
          const list: MusicInfo[] = [];
          for (const item of apiList) {
            list.push(buildMusicInfo(item));
          }

          resolve({
            list,
            info: {
              name: decodeHtmlEntities(data.title || ''),
              img: data.pic || '',
              desc: decodeHtmlEntities(data.info || ''),
              author: decodeHtmlEntities(data.uname || ''),
              play_count: formatPlayCount(parseInt(data.playnum || '0')),
            },
            total: parseInt(data.total || '0'),
            source: 'kw',
          });
        } catch (err) {
          resolve(buildEmptyDetailResult());
        }
      }).catch(() => {
        resolve(buildEmptyDetailResult());
      });
    });
  },

  /**
   * 获取歌单详情页 URL
   */
  getDetailPageUrl(listId: string): string {
    const match: RegExpMatchArray | null = listId.match(/kw_(\d+)/);
    const id: string = match ? match[1] : listId;
    return `http://www.kuwo.cn/playlist_detail/${id}`;
  },
};

export default songList;
