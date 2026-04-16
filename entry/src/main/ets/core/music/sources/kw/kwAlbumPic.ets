/**
 * 酷我 — 封面图，供 {@link KuwoMusicSource} 委托。
 */

import type { MusicInfo } from '../../../../types/MusicTypes';
import { httpGet, checkNetworkConnection } from '../../../../core/network/http';
import type { HttpRequestConfig } from '../../../../core/network/http';
import hilog from '@ohos.hilog';
import { normalizeCoverUrl } from '../../../../utils/CommonUtils';

const TAG = 'KwAlbumPic';
const DOMAIN = 0x0001;

interface RequestObj {
  cancel: () => void;
}

interface KwPicRequestConfig extends HttpRequestConfig {
  responseType: 'text';
  header: Map<string, string>;
  readTimeout: number;
}

interface KwMusicPicResponse {
  code?: number | string;
  msg?: string;
  data?: KwMusicPicData;
}

interface KwMusicPicData {
  pic?: string;
}

interface KwMobileSongInfo {
  pic?: string;
  pic120?: string;
  pic300?: string;
  albumpic?: string;
}

interface KwMobilePicResponse {
  data?: KwMobilePicData;
}

interface KwMobilePicData {
  songinfo?: KwMobileSongInfo;
}

let musicPicRequestObj: RequestObj | null = null;

// normalizeCoverUrl 已移至 CommonUtils

async function tryGetPicFromPrimaryApi(songmid: string): Promise<string> {
  const url = `https://www.kuwo.cn/api/www/music/pic?mid=${songmid}&size=500`;
  const requestHeader: Map<string, string> = new Map<string, string>();
  requestHeader.set('Referer', 'https://www.kuwo.cn/');
  requestHeader.set('User-Agent', 'Mozilla/5.0');
  const requestConfig: KwPicRequestConfig = {
    responseType: 'text',
    header: requestHeader,
    readTimeout: 10000,
  };
  const task = httpGet(url, requestConfig);
  const cancelObj: RequestObj = {
    cancel: task.cancel,
  };
  musicPicRequestObj = cancelObj;
  const response = await task.promise;
  const bodyText = typeof response.data === 'string' ? response.data : JSON.stringify(response.data);
  const data = JSON.parse(bodyText) as KwMusicPicResponse;
  const code = Number(data.code ?? 0);
  if (code === 200 && data.data && data.data.pic) {
    return normalizeCoverUrl(data.data.pic);
  }
  return '';
}

async function tryGetPicFromMobileApi(songmid: string): Promise<string> {
  const url = `https://m.kuwo.cn/newh5/singles/songinfoandlrc?musicId=${songmid}`;
  const requestHeader: Map<string, string> = new Map<string, string>();
  requestHeader.set('Referer', 'https://m.kuwo.cn/');
  requestHeader.set('User-Agent', 'Mozilla/5.0');
  const requestConfig: KwPicRequestConfig = {
    responseType: 'text',
    header: requestHeader,
    readTimeout: 10000,
  };
  const task = httpGet(url, requestConfig);
  const response = await task.promise;
  const bodyText = typeof response.data === 'string' ? response.data : JSON.stringify(response.data);
  const data = JSON.parse(bodyText) as KwMobilePicResponse;
  const song = data.data?.songinfo;
  if (!song) {
    return '';
  }
  return normalizeCoverUrl(song.pic || song.pic300 || song.pic120 || song.albumpic || '');
}

export async function getKwAlbumPic(songInfo: MusicInfo): Promise<string> {
  const inlinePic = normalizeCoverUrl(songInfo.img || songInfo.pic || '');
  if (inlinePic.length > 0) {
    return inlinePic;
  }
  const isConnected = await checkNetworkConnection();
  if (!isConnected) {
    hilog.error(DOMAIN, TAG, 'Network not available');
    throw new Error('网络连接不可用，请检查网络设置');
  }

  if (musicPicRequestObj) {
    musicPicRequestObj.cancel();
  }

  const songmid = songInfo.songmid || songInfo.id || '';
  if (!songmid || songmid.length === 0) {
    return '';
  }

  try {
    const primaryPic = await tryGetPicFromPrimaryApi(songmid);
    if (primaryPic.length > 0) {
      return primaryPic;
    }
  } catch (err) {
    hilog.warn(DOMAIN, TAG, 'Primary pic api failed: %{public}s', JSON.stringify(err));
  }

  try {
    const mobilePic = await tryGetPicFromMobileApi(songmid);
    if (mobilePic.length > 0) {
      return mobilePic;
    }
  } catch (err) {
    hilog.warn(DOMAIN, TAG, 'Mobile pic api failed: %{public}s', JSON.stringify(err));
  }

  return '';
}
