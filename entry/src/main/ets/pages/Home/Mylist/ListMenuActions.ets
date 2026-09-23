/**
 * 自建歌单的动作菜单（「我的」页卡片 / 全部歌单页共用）
 *
 * 两处都要「打开 / 更新内容 / 重命名 / 删除」，菜单项文案与危险色必须一致；
 * 这里只负责弹菜单并返回动作名，具体副作用交给调用页面（它们的上下文不同）。
 */
import { t } from '../../../service/LocalizationService';
import { appActionMenu } from '../../../service/DialogService';

/**
 * 菜单需要的最小信息
 *
 * 两处调用方各自有自己的 UserListRow 声明（ArkTS 不允许结构化类型互相赋值），
 * 所以约定一个显式类型，调用方按字段构造即可。
 */
export interface PlaylistMenuTarget {
  name: string;
  /** 绑定的在线歌单 id（非空时提供「更新内容」） */
  bindingListId: string;
}

/** 菜单动作 */
export type PlaylistMenuAction = 'open' | 'sync' | 'rename' | 'delete' | 'none';

/**
 * 弹出歌单动作菜单
 * @param list 目标歌单（绑定在线歌单时才有「更新内容」）
 */
export async function showPlaylistActionMenu(list: PlaylistMenuTarget): Promise<PlaylistMenuAction> {
  const hasBinding = list.bindingListId.length > 0;
  const actions: PlaylistMenuAction[] = ['open'];
  const labels: string[] = [t('open_list')];
  if (hasBinding) {
    actions.push('sync');
    labels.push(t('list_sync_content'));
  }
  actions.push('rename');
  labels.push(t('list_rename_title'));
  actions.push('delete');
  labels.push(t('delete'));

  const picked = await appActionMenu(list.name, labels, { dangerIndexes: [labels.length - 1] });
  if (picked < 0 || picked >= actions.length) {
    return 'none';
  }
  return actions[picked];
}
