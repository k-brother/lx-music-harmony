/**
 * 酷我 — 播放地址（多端点尝试），供 {@link KuwoMusicSource} 委托。
 */

import type { MusicInfo } from '../../../../types/MusicTypes';
import { httpGet, checkNetworkConnection } from '../../../../core/network/http';
import type { MusicUrlResult } from '../MusicSdkContracts';
import hilog from '@ohos.hilog';

const TAG = 'KwPlayUrl';
const DOMAIN = 0x0001;

interface ApiAttempt {
  name: string;
  url: string;
  headers: Record<string, string>;
}

interface KwMusicUrlResponse {
  code: number;
  data: KwMusicUrlData;
}

interface KwMusicUrlData {
  url: string;
}

export async function getKwMusicUrl(songInfo: MusicInfo, quality: string = '320k'): Promise<MusicUrlResult> {
  const isConnected = await checkNetworkConnection();
  if (!isConnected) {
    hilog.error(DOMAIN, TAG, 'Network not available');
    const empty: MusicUrlResult = { url: '', type: quality };
    return empty;
  }

  const songmid = songInfo.songmid || '';
  if (!songmid) {
    hilog.warn(DOMAIN, TAG, '歌曲ID为空，无法获取URL');
    const empty: MusicUrlResult = { url: '', type: quality };
    return empty;
  }

  const qualityMap: Map<string, string> = new Map([
    ['flac24bit', '2000k'],
    ['flac', '2000k'],
    ['320k', '320k'],
    ['192k', '192k'],
    ['128k', '128k'],
    ['96k', '96k'],
  ]);
  const br = qualityMap.get(quality) || '320k';

  const baseHeaders: Record<string, string> = {
    'Referer': 'https://www.kuwo.cn/',
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    'Accept': '*/*',
    'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
    'Accept-Encoding': 'gzip, deflate, br',
    'Connection': 'keep-alive',
    'Sec-Fetch-Dest': 'empty',
    'Sec-Fetch-Mode': 'cors',
    'Sec-Fetch-Site': 'same-origin',
  };

  const apiAttempts: ApiAttempt[] = [
    {
      // 老牌免登录接口，直接返回一个音频直链；rid 必须带 MUSIC_ 前缀
      name: 'anti_server',
      url: `http://antiserver.kuwo.cn/anti.s?type=convert_url&format=mp3&response=url&rid=MUSIC_${songmid}&br=${br}`,
      headers: {
        'Referer': 'https://www.kuwo.cn/',
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      }
    },
    {
      name: 'official_api_v1',
      url: `https://www.kuwo.cn/api/v1/www/music/playUrl?mid=${songmid}&type=convert_url&br=${br}`,
      headers: baseHeaders
    },
    {
      name: 'official_api_v2',
      url: `https://www.kuwo.cn/api/v1/www/music/playUrl?mid=${songmid}&type=convert_url2&br=${br}`,
      headers: baseHeaders
    },
    {
      name: 'wap_api',
      url: `http://wap.kuwo.cn/api/www/music/playUrl?mid=${songmid}&type=convert_url&br=${br}`,
      headers: {
        'Referer': 'http://www.kuwo.cn/',
        'User-Agent': 'Mozilla/5.0 (iPhone; CPU iPhone OS 14_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/14.0 Mobile/15E148 Safari/604.1',
      }
    },
    {
      name: 'by_music_id',
      url: `https://www.kuwo.cn/api/v1/www/music/playUrl?musicId=${songInfo.id || songmid}&type=convert_url&br=${br}`,
      headers: baseHeaders
    }
  ];

  for (const attempt of apiAttempts) {
    hilog.info(DOMAIN, TAG, '尝试酷我音乐API: %{public}s', attempt.name);

    try {
      // 响应可能是 JSON，也可能是一行纯文本直链：统一按文本取回，自己解析，
      // 避免 HTTP 层再做一次必然失败的 JSON.parse（会打出误导性的告警）
      const task = httpGet(attempt.url, { header: attempt.headers, responseType: 'text' });
      const response = await task.promise;

      // 统一用 rawText：responseType='json' 时 data 已经是解析后的对象
      const responseText = response.rawText;

      // 部分接口（anti_server）直接返回一个音频直链，先按纯文本处理避免误报解析异常
      if (responseText.length > 0 && responseText.trim().charAt(0) === 'h') {
        hilog.info(DOMAIN, TAG, '酷我音乐API %{public}s 成功获取URL (直接URL)', attempt.name);
        const result: MusicUrlResult = { url: responseText.trim(), type: quality };
        return result;
      }

      try {
        if (responseText.length > 0) {
          const data = JSON.parse(responseText) as KwMusicUrlResponse;
          if (data.code === 200 && data.data && data.data.url) {
            hilog.info(DOMAIN, TAG, '酷我音乐API %{public}s 成功获取URL', attempt.name);
            const result: MusicUrlResult = { url: data.data.url, type: quality };
            return result;
          }

          if (data.data && typeof data.data === 'string' && (data.data as string).charAt(0) === 'h') {
            hilog.info(DOMAIN, TAG, '酷我音乐API %{public}s 成功获取URL (字符串格式)', attempt.name);
            const result: MusicUrlResult = { url: data.data as string, type: quality };
            return result;
          }
        }
      } catch (e) {
        hilog.warn(DOMAIN, TAG, '酷我音乐API %{public}s 解析异常: %{public}s', attempt.name, (e as Error)?.message);
        if (responseText.length > 0 && responseText.charAt(0) === 'h') {
          hilog.info(DOMAIN, TAG, '酷我音乐API %{public}s 成功获取URL (直接URL)', attempt.name);
          const result: MusicUrlResult = { url: responseText, type: quality };
          return result;
        }

        const urlMatch = responseText.match(/https?:\/\/[^\s"]+/);
        if (urlMatch && urlMatch[0]) {
          hilog.info(DOMAIN, TAG, '酷我音乐API %{public}s 成功获取URL (正则匹配)', attempt.name);
          const result: MusicUrlResult = { url: urlMatch[0], type: quality };
          return result;
        }

        const xmlUrlMatch = responseText.match(/<url><!\[CDATA\[(.+?)\]\]><\/url>/);
        if (xmlUrlMatch && xmlUrlMatch[1]) {
          hilog.info(DOMAIN, TAG, '酷我音乐API %{public}s 成功获取URL (XML格式)', attempt.name);
          const result: MusicUrlResult = { url: xmlUrlMatch[1], type: quality };
          return result;
        }
      }

      hilog.warn(DOMAIN, TAG, '酷我音乐API %{public}s 解析失败', attempt.name);
      if (responseText.length === 0) {
        hilog.warn(DOMAIN, TAG, '酷我音乐API %{public}s 返回空响应: status=%{public}d',
          attempt.name, response.status);
      } else {
        hilog.warn(DOMAIN, TAG, '酷我音乐API %{public}s 响应片段: %{public}s',
          attempt.name, responseText.substring(0, Math.min(160, responseText.length)));
      }
    } catch (error) {
      const err = error as Error;
      hilog.error(DOMAIN, TAG, '酷我音乐API %{public}s 请求失败: %{public}s', attempt.name, err.message);
    }
  }

  hilog.warn(DOMAIN, TAG, '所有酷我音乐API尝试失败，使用备用方案');

  // 用原始文本解析：接口既可能返回 JSON，也可能直接返回一个 URL
  const parseUrlResponse = (txt: string): string => {
    if (!txt || txt.length === 0) {
      return '';
    }
    try {
      const parsed = JSON.parse(txt) as KwMusicUrlResponse;
      if (parsed.code === 200 && parsed.data && parsed.data.url) {
        return parsed.data.url;
      }
      if (parsed.data && typeof parsed.data === 'string' && (parsed.data as string).charAt(0) === 'h') {
        return parsed.data as string;
      }
    } catch (_e) {
      if (txt.length > 0 && txt.charAt(0) === 'h') {
        return txt;
      }
    }
    return '';
  };

  try {
    const httpUrl = `http://www.kuwo.cn/api/v1/www/music/playUrl?mid=${songmid}&type=convert_url&br=${br}`;
    const httpHeaders: Record<string, string> = {
      'Referer': 'http://www.kuwo.cn/',
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    };
    const task = httpGet(httpUrl, { header: httpHeaders });
    const response = await task.promise;
    const fallbackUrl = parseUrlResponse(response.rawText);
    if (fallbackUrl.length > 0) {
      hilog.info(DOMAIN, TAG, 'HTTP备用方案成功获取URL');
      const result: MusicUrlResult = { url: fallbackUrl, type: quality };
      return result;
    }
  } catch (httpError) {
    hilog.error(DOMAIN, TAG, 'HTTP备用方案失败: %{public}s', (httpError as Error).message);
  }

  try {
    const winWebUrl = `https://win-web.kuwo.cn/new/url?format=mp3&rid=${songmid}&type=convert_url&br=${br}`;
    const task = httpGet(winWebUrl, { header: baseHeaders });
    const response = await task.promise;
    const fallbackUrl = parseUrlResponse(response.rawText);
    if (fallbackUrl.length > 0) {
      hilog.info(DOMAIN, TAG, 'win-web备用方案成功获取URL');
      const result: MusicUrlResult = { url: fallbackUrl, type: quality };
      return result;
    }
  } catch (winWebError) {
    hilog.error(DOMAIN, TAG, 'win-web备用方案失败: %{public}s', (winWebError as Error).message);
  }

  try {
    const lowLevelUrl = `http://www.kuwo.cn/api/v1/www/music/playUrl?mid=${songmid}&type=music&br=${br}`;
    const task = httpGet(lowLevelUrl, { header: baseHeaders });
    const response = await task.promise;
    const fallbackUrl = parseUrlResponse(response.rawText);
    if (fallbackUrl.length > 0) {
      hilog.info(DOMAIN, TAG, '低级API备用方案成功获取URL');
      const result: MusicUrlResult = { url: fallbackUrl, type: quality };
      return result;
    }
  } catch (lowLevelError) {
    hilog.error(DOMAIN, TAG, '低级API备用方案失败: %{public}s', (lowLevelError as Error).message);
  }

  hilog.error(DOMAIN, TAG, '所有酷我音乐URL获取方案均失败');
  const result: MusicUrlResult = { url: '', type: quality };
  return result;
}
