/**
 * 酷我音乐 URL 获取功能单元测试
 */

import { describe, it, expect } from '@ohos/hypium';
import { getMusicSourceFactory } from '../../../main/ets/core/music/MusicFeatureEntry';
import type { MusicInfo } from '../../../main/ets/types/MusicTypes';

const testSongs: MusicInfo[] = [
  {
    id: '62355680',
    songmid: '62355680',
    name: '起风了',
    singer: '买辣椒也用券',
    album: '起风了',
    img: null,
    source: 'kw',
    interval: '00:00',
    albumId: '',
    albumMid: '',
    songId: 62355680,
    lrc: null,
    otherSource: null,
    types: [],
    _types: new Map(),
    typeUrl: new Map(),
  },
];

export default function kwMusicUrlTest() {
  describe('KwMusicUrlTest', () => {
    it('should_get_music_url_128k', async () => {
      const song = testSongs[0];
      const result = await getMusicSourceFactory().getSdk('kw').getMusicUrl(song, '128k');
      expect(!!result.url).assertTrue();
    }, 1);

    it('should_get_music_url_320k', async () => {
      const song = testSongs[0];
      const result = await getMusicSourceFactory().getSdk('kw').getMusicUrl(song, '320k');
      expect(!!result.url).assertTrue();
    }, 1);

    it('should_get_music_url_flac', async () => {
      const song = testSongs[0];
      const result = await getMusicSourceFactory().getSdk('kw').getMusicUrl(song, 'flac');
      expect(!!result.url).assertTrue();
    }, 1);
  });
}
