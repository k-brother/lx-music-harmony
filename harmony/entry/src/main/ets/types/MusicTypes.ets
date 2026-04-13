// MusicTypes - 统一音乐相关类型定义
// 对应安卓源码: src/types/music.d.ts

// 音乐源类型
export type MusicSource = 'kw' | 'kg' | 'tx' | 'wy' | 'mg' | 'local';

// 音质类型
export type Quality = '128k' | '320k' | 'flac' | 'flac24bit';

// 音乐音质信息
export interface MusicQualityType {
  type: Quality;
  size: string | null;
}

// 音乐音质信息（酷狗特有）
export interface MusicQualityTypeKg extends MusicQualityType {
  hash: string;
}

// 音质详情信息（用于替代 inline object literals）
export interface QualityDetailInfo {
  size: string | null;
}

// 音乐信息元数据基础
export interface MusicInfoMetaBase {
  songId: string | number;  // 歌曲ID
  albumName: string;        // 专辑名称
  picUrl: string | null;   // 歌曲图片链接
}

// 在线音乐元数据
export interface MusicInfoMetaOnline extends MusicInfoMetaBase {
  qualitys: MusicQualityType[];
  albumId?: string | number; // 专辑ID
}

// 酷狗音乐元数据
export interface MusicInfoMetaKg extends MusicInfoMetaOnline {
  qualitys: MusicQualityTypeKg[];
  hash: string;             // 歌曲hash
}

// QQ音乐元数据
export interface MusicInfoMetaTx extends MusicInfoMetaOnline {
  strMediaMid: string;      // 歌曲strMediaMid
  id?: number;              // 歌曲songId
  albumMid?: string;        // 歌曲albumMid
}

// 咪咕音乐元数据
export interface MusicInfoMetaMg extends MusicInfoMetaOnline {
  copyrightId: string;      // 歌曲copyrightId
  lrcUrl?: string;          // 歌词URL
  mrcUrl?: string;          // 逐字歌词URL
  trcUrl?: string;          // 翻译歌词URL
}

// 音乐信息基础
export interface MusicInfoBase {
  id: string;
  name: string;             // 歌曲名
  singer: string;          // 艺术家名
  source: MusicSource;      // 音乐源
  interval: string | null; // 格式化后的歌曲时长，例：03:55
  meta: MusicInfoMetaBase;
}

// 音质详情类型（用于替代 Record<Quality, { size: string | null }>）
export interface QualityDetail {
  size: string | null;
}

// 其他来源信息（替代 unknown）
export interface OtherSourceInfo {
  name: string;
  singer: string;
  source: string;
}

// 歌曲搜索结果项（兼容各音乐源）
export interface MusicInfo {
  // 基础信息
  id?: string;               // 歌曲ID
  name: string;             // 歌曲名
  singer: string;          // 歌手
  source: MusicSource;     // 音乐源
  // 酷我特有
  songmid?: string;        // 歌曲ID
  albumId?: string;        // 专辑ID
  albumName?: string;      // 专辑名
  album?: string;          // 专辑名（兼容）
  // 酷狗特有
  hash?: string;           // 歌曲hash
  // QQ音乐特有
  strMediaMid?: string;     // strMediaMid
  songId?: number;          // 歌曲ID
  albumMid?: string;        // 专辑Mid
  // 咪咕特有
  copyrightId?: string;     // 版权ID
  // 通用
  interval: string | null; // 时长
  img: string | null;       // 封面图
  pic?: string;             // 封面图（兼容）
  lrc: string | null;       // 歌词
  tlrc?: string | null;     // 翻译歌词
  rlrc?: string | null;     // 罗马音歌词
  lxlrc?: string | null;    // 逐字歌词
  rawlrc?: string | null;   // 原始歌词
  // 音质信息
  types?: MusicQualityType[]; // 支持的音质
  _types?: Map<Quality, QualityDetail>; // 音质详情 - 使用 Map 替代 Record
  typeUrl?: Map<string, string>; // 各音质URL - 使用 Map 替代 Record
  // 其他来源
  otherSource?: OtherSourceInfo[] | null;
}

// 播放音乐信息
export interface PlayMusicInfo {
  musicInfo: MusicInfo | null;
  listId: string | null;
  isTempPlay: boolean;
}

// 播放信息
export interface PlayInfo {
  playIndex: number;
  playerListId: string | null;
  playerPlayIndex: number;
}

// 进度信息
export interface Progress {
  nowPlayTime: number;
  maxPlayTime: number;
  progress: number;
  nowPlayTimeStr: string;
  maxPlayTimeStr: string;
}

// 音乐项（歌曲）
export interface MusicItem {
  id: string;
  name: string;
  singer: string;
  album: string;
  pic: string;
  duration: number;
  url: string;
}

// 歌词信息
export interface LyricInfo {
  lyric: string;            // 原歌词
  tlyric?: string | null;   // 翻译歌词
  rlyric?: string | null;   // 罗马音歌词
  lxlyric?: string | null;  // 逐字歌词
}

// 搜索结果
export interface SearchResult {
  list: MusicInfo[];
  allPage: number;
  total: number;
  limit: number;
  source: string;
}