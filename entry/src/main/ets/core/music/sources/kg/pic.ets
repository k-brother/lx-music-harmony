/**
 * 酷狗音乐 - 图片获取
 */
import { httpRequest } from '../../../../core/network/http';
import type { MusicInfo } from '../../../../types/MusicTypes';

const PIC_REQUEST_URL = 'http://media.store.kugou.com/v1/get_res_privilege';

const PIC_HEADERS: Map<string, string> = new Map([
  ['KG-RC', '1'],
  ['KG-THash', 'expand_search_manager.cpp:852736169:451'],
  ['User-Agent', 'KuGou2012-9020-ExpandSearchManager'],
]);

export const pic: PicInterface = {
  /**
   * 获取歌曲图片
   */
  getPic(songInfo: MusicInfo): Promise<string> {
    const songmid: string = songInfo.songmid || '';
    const albumAudioId: string = songmid.length === 32 ? songmid.split('_')[0] : songmid;

    const resourceItem: PicResourceItem = {
      album_audio_id: albumAudioId,
      album_id: songInfo.albumId || '',
      hash: songInfo.hash || '',
      id: 0,
      name: `${songInfo.singer} - ${songInfo.name}.mp3`,
      type: 'audio',
    };

    const body: KGPicRequest = {
      appid: 1001,
      area_code: '1',
      behavior: 'play',
      clientver: '9020',
      need_hash_offset: 1,
      relate: 1,
      resource: [resourceItem],
      token: '',
      userid: 2626431536,
      vip: 1,
    };

    return httpRequest(PIC_REQUEST_URL, {
      method: 'POST',
      header: PIC_HEADERS,
      extraData: body,
    }).promise.then((response) => {
      const body = JSON.parse(response.result as string) as KGPicResponse;

      if (body.error_code !== 0) {
        return Promise.reject(new Error('图片获取失败'));
      }

      const info = body.data[0].info;
      const img = info.imgsize ? info.image.replace('{size}', info.imgsize[0]) : info.image;

      if (!img) {
        return Promise.reject(new Error('Pic get failed'));
      }

      return img;
    });
  },
};

// 图片资源项
interface PicResourceItem {
  album_audio_id: string;
  album_id: string;
  hash: string;
  id: number;
  name: string;
  type: string;
}

// 图片请求体
interface KGPicRequest {
  appid: number;
  area_code: string;
  behavior: string;
  clientver: string;
  need_hash_offset: number;
  relate: number;
  resource: PicResourceItem[];
  token: string;
  userid: number;
  vip: number;
}

// 图片信息
interface PicInfo {
  image: string;
  imgsize?: string[];
}

// 图片数据项
interface PicDataItem {
  info: PicInfo;
}

// 图片响应
interface KGPicResponse {
  error_code: number;
  data: PicDataItem[];
}

// 图片接口
interface PicInterface {
  getPic: (songInfo: MusicInfo) => Promise<string>;
}
