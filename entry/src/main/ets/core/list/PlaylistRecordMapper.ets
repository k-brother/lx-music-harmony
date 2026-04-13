/**
 * 将 JSON / 同步载荷中的松散对象适配为 MusicItem（Adapter）
 * 供导入歌单、同步合并等路径复用，避免在多个 Service/Page 中复制字段解析逻辑。
 */
import type { IMusicItem } from '../interfaces/IMusicItem';

export function musicItemFromPlainObject(raw: Object): IMusicItem {
  const m = raw as Record<string, Object>;
  const albumIdVal = m['albumId'];
  const lrcVal = m['lrc'];
  const item: IMusicItem = {
    id: String(m['id'] ?? ''),
    name: String(m['name'] ?? ''),
    singer: String(m['singer'] ?? ''),
    album: String(m['album'] ?? ''),
    albumId: albumIdVal !== undefined && albumIdVal !== null ? String(albumIdVal) : null,
    duration: Number(m['duration'] ?? 0),
    source: String(m['source'] ?? 'local'),
    pic: String(m['pic'] ?? ''),
    lrc: lrcVal !== undefined && lrcVal !== null ? String(lrcVal) : null
  };
  return item;
}

// Re-export IMusicItem as MusicItem for consumers
export { IMusicItem as MusicItem };
