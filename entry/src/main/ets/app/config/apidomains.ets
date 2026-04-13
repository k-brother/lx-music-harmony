// API域名配置 - 对应 src/utils/musicSdk/ 中的API配置
// 所有API域名聚合配置，每个域名在一套配置中只能存在一个

// API域名枚举
export enum ApiDomain {
  // 酷我音乐 (kw)
  KW_SEARCH = 'http://search.kuwo.cn/r.s',
  KW_PLAYER = 'http://player.kuwo.cn/webmusic/sj/dtflagdate',
  KW_MOBILE = 'http://mobile.kuwo.cn/mpage/html5/songinfoandlrc',
  KW_SONGLIST = 'http://nplserver.kuwo.cn/pl.svc',
  KW_BANG = 'http://kbangserver.kuwo.cn',

  // 酷狗音乐 (kg)
  KG_SEARCH = 'https://songsearch.kugou.com/song_search_v2',
  KG_PLAY = 'https://www.kugou.com/yy/index.php',
  KG_LYRIC_SEARCH = 'http://lyrics.kugou.com/search',
  KG_LYRIC_DOWNLOAD = 'http://lyrics.kugou.com/download',

  // QQ音乐 (tx)
  TX_CGI = 'https://u.y.qq.com/cgi-bin/musics.fcg',

  // 网易云音乐 (wy)
  WY_EAPI = 'http://interface.music.163.com/eapi/batch',

  // 咪咕音乐 (mg)
  MG_PD = 'http://pd.musicapp.migu.cn/MIGUM2.0/v1.0/content',
  MG_JADE = 'http://jadeite.migu.cn:7090/music_search/v2',
  MG_APP = 'https://app.c.nf.migu.cn/MIGUM2.0/v1.0/content',

  // 通用CDN
  COMMON_CDN = 'https://y.gtmsc.cn',
}

// 音乐源配置
export interface MusicSourceConfig {
  id: string;
  name: string;
  searchDomain: string;
  apiDomains: string[];
}

// 音乐源配置项接口
interface MusicSourceConfigItem extends MusicSourceConfig {
  id: string;
  name: string;
  searchDomain: string;
  apiDomains: string[];
}

// 音乐源配置列表
export const musicSourceConfigs: MusicSourceConfigItem[] = [
  {
    id: 'kw',
    name: '酷我音乐',
    searchDomain: ApiDomain.KW_SEARCH,
    apiDomains: [
      ApiDomain.KW_SEARCH,
      ApiDomain.KW_PLAYER,
      ApiDomain.KW_MOBILE,
      ApiDomain.KW_SONGLIST,
      ApiDomain.KW_BANG,
    ],
  },
  {
    id: 'kg',
    name: '酷狗音乐',
    searchDomain: ApiDomain.KG_SEARCH,
    apiDomains: [
      ApiDomain.KG_SEARCH,
      ApiDomain.KG_PLAY,
      ApiDomain.KG_LYRIC_SEARCH,
      ApiDomain.KG_LYRIC_DOWNLOAD,
    ],
  },
  {
    id: 'tx',
    name: 'QQ音乐',
    searchDomain: ApiDomain.TX_CGI,
    apiDomains: [
      ApiDomain.TX_CGI,
    ],
  },
  {
    id: 'wy',
    name: '网易云音乐',
    searchDomain: ApiDomain.WY_EAPI,
    apiDomains: [
      ApiDomain.WY_EAPI,
    ],
  },
  {
    id: 'mg',
    name: '咪咕音乐',
    searchDomain: ApiDomain.MG_PD,
    apiDomains: [
      ApiDomain.MG_PD,
      ApiDomain.MG_JADE,
      ApiDomain.MG_APP,
    ],
  },
];

// 获取音乐源配置
export function getMusicSourceConfig(source: string): MusicSourceConfig | null {
  for (const config of musicSourceConfigs) {
    if (config.id === source) {
      return config;
    }
  }
  return null;
}

// 搜索请求头接口
interface SearchHeaders {
  'User-Agent': string;
}

// 搜索请求头
export const searchHeaders: SearchHeaders = {
  'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/69.0.3497.100 Safari/537.36',
};

// 请求超时时间（毫秒）
export const requestTimeout = 15000;

// 获取搜索URL
export function getSearchUrl(source: string): string {
  const config = getMusicSourceConfig(source);
  return config ? config.searchDomain : '';
}
