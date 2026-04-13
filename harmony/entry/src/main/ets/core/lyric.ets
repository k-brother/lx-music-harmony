// Lyric - 对应 src/core/lyric.ts
// 歌词功能：在线拉取走 musicSdk；LRC 解析与 `core/music/MusicParsingUtils` 单源对齐（避免与 parseLrc 重复实现）

import { musicSdk } from './music/MusicFeatureEntry';
import type { MusicInfo, LyricInfo } from '../types/MusicTypes';

export type { LyricLine } from './music/MusicParsingUtils';
export { parseLrc as parseLyric, getCurrentLyricIndex } from './music/MusicParsingUtils';

// 获取歌词
export async function getLyric(musicInfo: MusicInfo): Promise<LyricInfo> {
  try {
    let result: LyricInfo | null = null;
    switch (musicInfo.source) {
      case 'kw':
        result = await musicSdk.kw.getLyric(musicInfo);
        break;
      case 'kg':
        result = await musicSdk.kg.getLyric(musicInfo);
        break;
      case 'tx':
        result = await musicSdk.tx.getLyric(musicInfo);
        break;
      case 'wy':
        result = await musicSdk.wy.getLyric(musicInfo);
        break;
      case 'mg':
        result = await musicSdk.mg.getLyric(musicInfo);
        break;
    }
    if (result) {
      return result;
    }
  } catch {
    // 忽略错误
  }

  return {
    lyric: '',
    tlyric: null,
    rlyric: null,
    lxlyric: null,
  };
}
