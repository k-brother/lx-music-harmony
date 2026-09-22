/**
 * 歌单详情滚动位置记忆
 *
 * 「设置 → 列表 → 记住列表滚动位置」开启时，退出详情再进来要回到上次位置。
 * 这段逻辑与页面状态无关（只依赖 storage），从页面抽出来便于复用与单测。
 */
import { getStorageService } from '../../core/interfaces/IStorageService';
import { appLog as hilog } from '../../core/log/AppLogger';

const DOMAIN = 0x0001;
const TAG = 'SonglistScroll';

/** 存储键：按「源 + 列表 id」区分 */
function scrollKey(sourceId: string, listId: string): string {
  return `list.scroll.${sourceId}.${listId}`;
}

/** 读取上次滚动位置（无记录返回 0） */
export async function loadScrollOffset(sourceId: string, listId: string): Promise<number> {
  if (listId.length === 0) {
    return 0;
  }
  try {
    const offset = await getStorageService().getNumber(scrollKey(sourceId, listId), 0);
    return offset > 0 ? offset : 0;
  } catch (err) {
    hilog.warn(DOMAIN, TAG, 'load failed: %{public}s', JSON.stringify(err));
    return 0;
  }
}

/** 记录滚动位置（0 或加载未完成时不写） */
export async function saveScrollOffset(
  sourceId: string, listId: string, offset: number, enabled: boolean, loaded: boolean
): Promise<void> {
  if (!enabled || !loaded || listId.length === 0 || offset <= 0) {
    return;
  }
  try {
    await getStorageService().setNumber(scrollKey(sourceId, listId), Math.floor(offset));
  } catch (err) {
    hilog.warn(DOMAIN, TAG, 'save failed: %{public}s', JSON.stringify(err));
  }
}
