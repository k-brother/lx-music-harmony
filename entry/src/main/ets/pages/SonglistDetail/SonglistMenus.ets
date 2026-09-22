/**
 * 歌单详情的命令式菜单
 *
 * 菜单是「动作集合 + 弹层」的组合，写在页面里会淹没业务逻辑：
 * 这里把菜单定义集中到一处，页面只传回调（每个回调就是页面上的一个动作）。
 *
 * 依赖 DialogService.appActionMenu：超过 5 项会自动折叠成「更多…」，
 * 所以这里直接列出全部动作，不需要再手写二级菜单。
 */
import { t } from '../../service/LocalizationService';
import { appActionMenu } from '../../service/DialogService';
import type { SongItem } from './SonglistTypes';

/** 单曲菜单回调集合 */
export interface SongItemMenuHandlers {
  onPlayLater: (song: SongItem) => void;
  onAddToList: (song: SongItem) => void;
  onDownload: (song: SongItem) => void;
  onShare: (song: SongItem) => void;
  onSelectMode: (song: SongItem) => void;
  onDislike: (song: SongItem) => void;
  onSourceDetail: (song: SongItem) => void;
  onViewArtist: (song: SongItem) => void;
  onViewAlbum: (song: SongItem) => void;
}

/**
 * 单曲菜单（长按行 / 点行尾 ⋮）
 * 顺序按"越常用越靠前"排列：
 * 下一首播放 / 添加到列表 / 下载 / 分享 / 多选 / 不喜欢 / 来源详情 / 查看歌手 / 查看专辑
 */
export async function showSongItemMenu(song: SongItem, handlers: SongItemMenuHandlers): Promise<void> {
  const items: string[] = [
    t('play_later'),
    t('player_add_to_list'),
    t('player_download'),
    t('player_share'),
    t('list_select_mode'),
    t('dislike_title'),
    t('music_source_detail'),
    t('player_view_artist'),
    t('player_view_album'),
  ];
  const picked = await appActionMenu(`${song.name} - ${song.singer}`, items, { dangerIndexes: [5] });
  if (picked < 0) {
    return;
  }
  switch (picked) {
    case 0:
      handlers.onPlayLater(song);
      break;
    case 1:
      handlers.onAddToList(song);
      break;
    case 2:
      handlers.onDownload(song);
      break;
    case 3:
      handlers.onShare(song);
      break;
    case 4:
      handlers.onSelectMode(song);
      break;
    case 5:
      handlers.onDislike(song);
      break;
    case 6:
      handlers.onSourceDetail(song);
      break;
    case 7:
      handlers.onViewArtist(song);
      break;
    case 8:
      handlers.onViewAlbum(song);
      break;
    default:
      break;
  }
}

/** 歌单级「更多」菜单回调集合 */
export interface SonglistMenuHandlers {
  onSort: () => void;
  onDedupe: () => void;
  onSelectMode: () => void;
  onSyncLocal: () => void;
}

/** 歌单级「更多」菜单：排序 / 去重 / 多选 / 同步到本地歌单 */
export async function showSonglistMoreMenu(title: string, handlers: SonglistMenuHandlers): Promise<void> {
  const items: string[] = [
    t('list_sort'),
    t('list_dedupe'),
    t('list_select_mode'),
    t('list_sync_local'),
  ];
  const picked = await appActionMenu(title, items);
  if (picked === 0) {
    handlers.onSort();
  } else if (picked === 1) {
    handlers.onDedupe();
  } else if (picked === 2) {
    handlers.onSelectMode();
  } else if (picked === 3) {
    handlers.onSyncLocal();
  }
}
