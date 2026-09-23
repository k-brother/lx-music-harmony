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
import { appActionMenu, type ActionMenuOptions } from '../../service/DialogService';
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
  /** 调整歌曲在该列表中的位置（仅本地/自建列表可用） */
  onMovePosition: (song: SongItem) => void;
  /** 把歌曲移动到另一个自建列表 */
  onMoveToList: (song: SongItem) => void;
}

/**
 * 单曲菜单能力开关
 *
 * 在线歌单是只读的：位置调整/移动只对本地（我的）列表开放，
 * 用开关控制，避免菜单里出现点了没反应的动作。
 */
export interface SongItemMenuOptions {
  canEditPosition: boolean;
  canMoveToList: boolean;
}

/** 菜单项：用 key 分发比下标分发更抗改动 */
interface MenuEntry {
  key: string;
  label: string;
}

/**
 * 单曲菜单（长按行 / 点行尾 ⋮）
 * 顺序按"越常用越靠前"排列：
 * 下一首播放 / 添加到列表 / 下载 / 分享 / 多选 / 调整位置 / 移动到列表 /
 * 不喜欢 / 来源详情 / 查看歌手 / 查看专辑
 */
export async function showSongItemMenu(
  song: SongItem, handlers: SongItemMenuHandlers, options?: SongItemMenuOptions
): Promise<void> {
  const entries: MenuEntry[] = [
    { key: 'play_later', label: t('play_later') },
    { key: 'add_to_list', label: t('player_add_to_list') },
    { key: 'download', label: t('player_download') },
    { key: 'share', label: t('player_share') },
    { key: 'select_mode', label: t('list_select_mode') },
  ];

  if (options?.canEditPosition) {
    entries.push({ key: 'move_position', label: t('list_change_position') });
  }
  if (options?.canMoveToList) {
    entries.push({ key: 'move_to_list', label: t('list_move_to') });
  }

  entries.push({ key: 'dislike', label: t('dislike_title') });
  entries.push({ key: 'source_detail', label: t('music_source_detail') });
  entries.push({ key: 'view_artist', label: t('player_view_artist') });
  entries.push({ key: 'view_album', label: t('player_view_album') });

  const labels: string[] = entries.map((entry: MenuEntry): string => entry.label);
  const dangerIndex = entries.findIndex((entry: MenuEntry): boolean => entry.key === 'dislike');
  const menuOptions: ActionMenuOptions = {
    dangerIndexes: dangerIndex >= 0 ? [dangerIndex] : [],
  };
  const picked = await appActionMenu(`${song.name} - ${song.singer}`, labels, menuOptions);
  if (picked < 0) {
    return;
  }
  const entry = entries[picked];
  if (!entry) {
    return;
  }

  switch (entry.key) {
    case 'play_later':
      handlers.onPlayLater(song);
      break;
    case 'add_to_list':
      handlers.onAddToList(song);
      break;
    case 'download':
      handlers.onDownload(song);
      break;
    case 'share':
      handlers.onShare(song);
      break;
    case 'select_mode':
      handlers.onSelectMode(song);
      break;
    case 'move_position':
      handlers.onMovePosition(song);
      break;
    case 'move_to_list':
      handlers.onMoveToList(song);
      break;
    case 'dislike':
      handlers.onDislike(song);
      break;
    case 'source_detail':
      handlers.onSourceDetail(song);
      break;
    case 'view_artist':
      handlers.onViewArtist(song);
      break;
    case 'view_album':
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
  /** 下载整张歌单（逐首提交，进度实时反馈） */
  onDownloadAll: () => void;
}

/** 歌单级「更多」菜单：排序 / 去重 / 多选 / 下载全部 / 同步到本地歌单 */
export async function showSonglistMoreMenu(title: string, handlers: SonglistMenuHandlers): Promise<void> {
  const items: string[] = [
    t('list_sort'),
    t('list_dedupe'),
    t('list_select_mode'),
    t('download_songlist_all'),
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
    handlers.onDownloadAll();
  } else if (picked === 4) {
    handlers.onSyncLocal();
  }
}
