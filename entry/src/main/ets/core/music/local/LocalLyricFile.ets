/**
 * 本地歌词文件（同名 .lrc）读取
 *
 * 单文件、无外部依赖：播放链路（ResolvePlayback）与本地模块（LocalPlayback）
 * 都要「先看磁盘上有没有同名歌词」，实现只保留这一份。
 *
 * 编码策略：先按 UTF-8 解；出现替换字符（U+FFFD）说明是 GB18030 的老歌词，
 * 再解一次。时间轴是 ASCII，只看「有没有 '['」分辨不出编码。
 */
import { fileIo as fs } from '@kit.CoreFileKit';
import { appLog as hilog } from '../../log/AppLogger';
import { utf8Decode } from '../../../utils/TextCodec';

const TAG = 'LOCAL_LYRIC';
const DOMAIN: number = 0x0003;

/** 同名歌词文件路径：`a/b/song.mp3` -> `a/b/song.lrc` */
export function lyricPathFor(filePath: string): string {
  const slash = filePath.lastIndexOf('/');
  const dot = filePath.lastIndexOf('.');
  if (dot <= slash) {
    // 没有扩展名（或点落在目录名里）：直接追加
    return `${filePath}.lrc`;
  }
  return `${filePath.substring(0, dot)}.lrc`;
}

/**
 * 读取同名歌词文件的文本；文件不存在、为空或读失败时返回 null。
 */
export async function readSidecarLyric(filePath: string): Promise<string | null> {
  if (!filePath || filePath.length === 0) {
    return null;
  }
  const lrcPath = lyricPathFor(filePath);
  let bytes: Uint8Array | null = null;
  try {
    if (!fs.accessSync(lrcPath)) {
      return null;
    }
    const stat = fs.statSync(lrcPath);
    if (stat.size <= 0) {
      return null;
    }
    const file = fs.openSync(lrcPath, fs.OpenMode.READ_ONLY);
    try {
      const buffer = new ArrayBuffer(stat.size);
      const readLen = fs.readSync(file.fd, buffer);
      bytes = new Uint8Array(buffer, 0, readLen > 0 ? readLen : 0);
    } finally {
      fs.closeSync(file);
    }
  } catch (err) {
    hilog.warn(DOMAIN, TAG, 'read %{public}s failed: %{public}s',
      lrcPath, err instanceof Error ? err.message : JSON.stringify(err));
    return null;
  }

  if (bytes === null || bytes.length === 0) {
    return null;
  }
  let text = utf8Decode(bytes);
  if (text.includes('\uFFFD')) {
    text = utf8Decode(bytes, 'gb18030');
  }
  if (text.trim().length === 0) {
    return null;
  }
  return text;
}
