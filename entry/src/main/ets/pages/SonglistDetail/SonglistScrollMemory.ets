/**
 * 歌单详情的滚动位置记忆（薄封装）
 *
 * 「设置 → 列表 → 记住列表滚动位置」开启时，退出详情再进来要回到上次位置。
 * 通用实现已上移到 service/ScrollMemoryService（多个列表页共用同一套读写），
 * 这里只保留歌单详情的 key 口径，调用方不必知道 key 怎么拼。
 */
import {
  loadScrollOffset as loadByKey,
  saveScrollOffset as saveByKey,
  songlistScrollKey,
} from '../../service/ScrollMemoryService';

/** 读取某个歌单的滚动位置（无记录返回 0） */
export async function loadScrollOffset(sourceId: string, listId: string): Promise<number> {
  if (listId.length === 0) {
    return 0;
  }
  return loadByKey(songlistScrollKey(sourceId, listId));
}

/** 记录某个歌单的滚动位置（关闭记忆 / 数据未就绪 / 位置为 0 时不写） */
export async function saveScrollOffset(
  sourceId: string, listId: string, offset: number, enabled: boolean, loaded: boolean
): Promise<void> {
  if (listId.length === 0) {
    return;
  }
  await saveByKey(songlistScrollKey(sourceId, listId), offset, enabled, loaded);
}
