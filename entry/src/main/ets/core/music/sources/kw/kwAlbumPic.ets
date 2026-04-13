/**
 * 酷我 — 封面图，供 {@link KuwoMusicSource} 委托。
 */

import type { MusicInfo } from '../../../../types/MusicTypes';
import { httpGet, checkNetworkConnection } from '../../../../core/network/http';
import hilog from '@ohos.hilog';

const TAG = 'KwAlbumPic';
const DOMAIN = 0x0001;

interface RequestObj {
  cancel: () => void;
}

interface KwMusicPicResponse {
  code: number;
  msg: string;
  data: KwMusicPicData;
}

interface KwMusicPicData {
  pic: string;
}

let musicPicRequestObj: RequestObj | null = null;

export async function getKwAlbumPic(songInfo: MusicInfo): Promise<string> {
  if (songInfo.img) {
    return Promise.resolve(songInfo.img);
  }

  const isConnected = await checkNetworkConnection();
  if (!isConnected) {
    hilog.error(DOMAIN, TAG, 'Network not available');
    throw new Error('网络连接不可用，请检查网络设置');
  }

  if (musicPicRequestObj) {
    musicPicRequestObj.cancel();
  }

  const songmid = songInfo.songmid || '';
  const url = `http://www.kuwo.cn/api/www/music/pic?mid=${songmid}&size=500`;
  const task = httpGet(url);

  const cancelObj: RequestObj = {
    cancel: task.cancel,
  };
  musicPicRequestObj = cancelObj;

  return new Promise<string>((resolve, reject) => {
    task.promise.then((response) => {
      try {
        const data = JSON.parse(response.data as string) as KwMusicPicResponse;
        if (data.code === 200) {
          resolve(data.data.pic || '');
        } else {
          reject(new Error(data.msg || '获取图片失败'));
        }
      } catch {
        reject(new Error('解析图片信息失败'));
      }
    }).catch(() => {
      reject(new Error('请求失败'));
    });
  });
}
