import { httpRequest } from '../../../../core/network/http';
import type { MusicInfo, Quality, QualityDetail } from '../../../../types/MusicTypes';
import { formatPlayTime, decodeHtmlEntities, formatSinger, formatPlayCount } from '../../../../utils/CommonUtils';

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
    // 使用预定义的标签
    const categories: SongListTagCategory[] = [
      { name: '语种', id: 'kw_lang', list: [
        { id: 'kw_lang_1', name: '华语', parent_id: 'kw_lang', parent_name: '语种' },
        { id: 'kw_lang_2', name: '欧美', parent_id: 'kw_lang', parent_name: '语种' },
        { id: 'kw_lang_3', name: '日本', parent_id: 'kw_lang', parent_name: '语种' },
        { id: 'kw_lang_4', name: '韩国', parent_id: 'kw_lang', parent_name: '语种' },
      ]},
      { name: '风格', id: 'kw_style', list: [
        { id: 'kw_style_1', name: '流行', parent_id: 'kw_style', parent_name: '风格' },
        { id: 'kw_style_2', name: '摇滚', parent_id: 'kw_style', parent_name: '风格' },
        { id: 'kw_style_3', name: '民谣', parent_id: 'kw_style', parent_name: '风格' },
        { id: 'kw_style_4', name: '电子', parent_id: 'kw_style', parent_name: '风格' },
      ]},
      { name: '场景', id: 'kw_scene', list: [
        { id: 'kw_scene_1', name: '清晨', parent_id: 'kw_scene', parent_name: '场景' },
        { id: 'kw_scene_2', name: '夜晚', parent_id: 'kw_scene', parent_name: '场景' },
        { id: 'kw_scene_3', name: '午后', parent_id: 'kw_scene', parent_name: '场景' },
      ]},
    ];

    const tags: SongListTag[] = [];
    for (const cat of categories) {
      for (const tag of cat.list) {
        tags.push(tag);
      }
    }

    const hotTag: SongListTag[] = [
      { id: 'kw__hot_1', name: '流行' },
      { id: 'kw__hot_2', name: '华语' },
      { id: 'kw__hot_3', name: '欧美' },
      { id: 'kw__hot_4', name: '韩语' },
      { id: 'kw__hot_5', name: '日语' },
    ];

    const result: SongListTagsResult = {
      tags,
      hotTag,
      source: 'kw',
    };
    return Promise.resolve(result);
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
      const parts: string[] = tagId.split('_');
      const parentId: string = parts[parts.length - 2];
      const childId: string = parts[parts.length - 1];
      url = `http://wapi.kuwo.cn/api/pc/classify/playlist/getTagPlayList?loginUid=0&loginSid=0&appUid=76039576&pn=${page}&id=${childId || parentId}&rn=${limit}`;
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
