/**
 * 列表行文案（副标题 / 时长）的唯一出口
 *
 * 以前每个列表页各拼一遍「歌手 · 专辑 · 音源」，于是「设置 → 列表」里的
 * 显示音源 / 显示专辑 / 显示时长 只在歌单详情生效，别的列表照旧全显示。
 * 这里把拼装规则收成纯函数：行组件与页面都调它，设置一改全应用一致。
 */
import { formatPlayTime } from '../../utils/CommonUtils';
import { sourceLabel } from '../../service/LocalizationService';

/** 列表行副标题：`歌手 [· 专辑] [· 音源]`，带设置裁剪 */
export function composeRowSubtitle(
  singer: string, album: string, sourceId: string, showAlbum: boolean, showSource: boolean
): string {
  const parts: string[] = [];
  if (singer && singer.length > 0) {
    parts.push(singer);
  }
  if (showAlbum && album && album.length > 0) {
    parts.push(album);
  }
  if (showSource && sourceId && sourceId.length > 0) {
    parts.push(sourceLabel(sourceId));
  }
  return parts.join(' · ');
}

/**
 * 列表行右侧时长：关闭「显示时长」或时长未知时返回空串。
 * 单曲时长（秒）来自各页面自己的数据口径，格式化统一走 CommonUtils。
 */
export function composeRowDurationText(durationSeconds: number, showDuration: boolean): string {
  if (!showDuration || !(durationSeconds > 0)) {
    return '';
  }
  return formatPlayTime(durationSeconds);
}
