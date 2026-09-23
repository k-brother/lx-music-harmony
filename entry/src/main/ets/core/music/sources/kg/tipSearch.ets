/**
 * 酷狗 - 搜索联想
 * 对应安卓源码: src/utils/musicSdk/kg/tipSearch.js
 */
import { hilog } from '@kit.PerformanceAnalysisKit';
import { httpRequest, parseHttpBodyJson, type HttpRequestConfig, type HttpResponse } from '../../../../core/network/http';

const TAG = 'KgTipSearch';
const DOMAIN = 0x0001;

interface KgTipRecord {
  HintInfo?: string;
}

interface KgTipGroup {
  RecordDatas?: KgTipRecord[];
}

export function searchTips(keyword: string): Promise<string[]> {
  const url = `https://searchtip.kugou.com/getSearchTip?MusicTipCount=10&keyword=${encodeURIComponent(keyword)}`;
  const reqOpts: HttpRequestConfig = {
    responseType: 'text',
    readTimeout: 8000,
    headers: {
      'referer': 'https://www.kugou.com/',
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    },
  };

  return httpRequest(url, reqOpts).promise.then((response: HttpResponse<Object>) => {
    const groups = parseHttpBodyJson<KgTipGroup[]>(
      response.data as string | Object | ArrayBuffer | undefined | null
    );
    const records = groups && groups.length > 0 ? groups[0].RecordDatas : undefined;
    if (!records || records.length === 0) {
      return [];
    }
    const tips: string[] = [];
    for (const record of records) {
      const word = (record.HintInfo ?? '').trim();
      if (word.length > 0) {
        tips.push(word);
      }
    }
    return tips;
  }).catch((err: Error) => {
    hilog.warn(DOMAIN, TAG, 'searchTips failed: %{public}s', err?.message);
    return [];
  });
}
