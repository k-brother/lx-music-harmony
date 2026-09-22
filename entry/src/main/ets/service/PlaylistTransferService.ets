/**
 * 歌单导入 / 导出（设置 → 备份与恢复）
 *
 * 把原先写在设置页里的 250 行数据搬运逻辑下沉到服务层：
 * - 导出：把默认列表 / 我喜欢 / 自建歌单（含绑定信息）打包成 JSON
 * - 导入：校验结构后写回列表，返回成功导入的歌单数
 * - 文件读写：只接受调用方给出的 URI（文件选择器仍留在 UI 层）
 */
import fs from '@ohos.file.fs';
import hilog from '@ohos.hilog';
import { util } from '@kit.ArkTS';
import {
  LIST_IDS,
  addMusicToList,
  createUserList,
  getDefaultList,
  getLoveList,
  getUserList,
  getUserListMusic,
  type MusicItem,
} from './ListService';
import { musicItemFromPlainObject } from '../core/list/PlaylistRecordMapper';
import { t } from './LocalizationService';

const TAG = 'PlaylistTransfer';
const DOMAIN = 0x0005;
const FORMAT_VERSION = '1.0.0';

/** 导出的单个歌单 */
export interface ExportedPlaylistRow {
  id: string;
  name: string;
  type: string;
  source?: string;
  desc?: string;
  pic?: string;
  count?: number;
  musicCount: number;
  musicList: MusicItem[];
  createTime?: number;
  updateTime?: number;
  /** 绑定在线歌单信息（收藏歌单可再次同步） */
  bindingSource?: string;
  bindingListId?: string;
}

/** 导出文件根结构 */
export interface PlaylistsExportRoot {
  appVersion: string;
  exportTime: string;
  playlists: ExportedPlaylistRow[];
}

/** 收集全部歌单数据（默认列表 / 我喜欢 / 自建歌单） */
export function buildPlaylistsExport(): PlaylistsExportRoot {
  const root: PlaylistsExportRoot = {
    appVersion: FORMAT_VERSION,
    exportTime: new Date().toISOString(),
    playlists: [],
  };
  try {
    const defaultMusic = getDefaultList();
    root.playlists.push({
      id: LIST_IDS.DEFAULT,
      name: t('default_list_label'),
      type: 'default',
      musicCount: defaultMusic.length,
      musicList: defaultMusic,
    });

    const loveMusic = getLoveList();
    root.playlists.push({
      id: LIST_IDS.LOVE,
      name: t('love_title'),
      type: 'love',
      musicCount: loveMusic.length,
      musicList: loveMusic,
    });

    const userLists = getUserList();
    for (let i = 0; i < userLists.length; i++) {
      const list = userLists[i];
      const songs = getUserListMusic(list.id);
      root.playlists.push({
        id: list.id,
        name: list.name,
        type: 'user',
        source: list.source,
        desc: list.desc,
        pic: list.pic,
        count: list.count,
        musicCount: songs.length,
        musicList: songs,
        createTime: list.createTime,
        updateTime: list.updateTime,
        bindingSource: list.bindingSource,
        bindingListId: list.bindingListId,
      });
    }
    hilog.info(DOMAIN, TAG, 'Collected %{public}d playlists', root.playlists.length);
  } catch (err) {
    hilog.error(DOMAIN, TAG, 'buildPlaylistsExport failed: %{public}s', JSON.stringify(err));
  }
  return root;
}

/** 校验导入文件结构 */
export function isValidPlaylistsExport(data: Record<string, Object>): boolean {
  try {
    if (!data.appVersion || !data.exportTime || !Array.isArray(data.playlists)) {
      return false;
    }
    const playlists = data.playlists as Array<Record<string, Object>>;
    for (let i = 0; i < playlists.length; i++) {
      const row = playlists[i];
      if (!row.id || !row.name || !row.type) {
        return false;
      }
    }
    return true;
  } catch (err) {
    return false;
  }
}

/**
 * 导入歌单数据
 * @returns 成功导入的歌单数量
 */
export async function importPlaylistsPayload(data: Record<string, Object>): Promise<number> {
  let imported = 0;
  try {
    const playlists = data.playlists as Array<Record<string, Object>>;
    for (let p = 0; p < playlists.length; p++) {
      const playlist = playlists[p];
      const listType = playlist.type as string;
      const songs: Array<Record<string, Object>> =
        Array.isArray(playlist.musicList) ? playlist.musicList as Array<Record<string, Object>> : [];
      try {
        if (listType === 'default' || listType === 'love') {
          const targetListId = listType === 'default' ? LIST_IDS.DEFAULT : LIST_IDS.LOVE;
          for (let m = 0; m < songs.length; m++) {
            await addMusicToList(targetListId, musicItemFromPlainObject(songs[m] as Object));
          }
          imported++;
        } else {
          const created = await createUserList(playlist.name as string);
          for (let m = 0; m < songs.length; m++) {
            await addMusicToList(created.id, musicItemFromPlainObject(songs[m] as Object));
          }
          imported++;
        }
      } catch (err) {
        hilog.error(DOMAIN, TAG, 'Import playlist failed (%{public}s): %{public}s',
          playlist.name as string, JSON.stringify(err));
      }
    }
  } catch (err) {
    hilog.error(DOMAIN, TAG, 'importPlaylistsPayload failed: %{public}s', JSON.stringify(err));
  }
  return imported;
}

/** 把导出数据写入指定 URI（文件选择器返回的保存位置） */
export function writePlaylistsToUri(uri: string, data: PlaylistsExportRoot): boolean {
  try {
    const json = JSON.stringify(data, null, 2);
    const file = fs.openSync(uri, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
    try {
      const encoder = new util.TextEncoder();
      fs.writeSync(file.fd, encoder.encodeInto(json).buffer as ArrayBuffer);
      fs.fsyncSync(file.fd);
    } finally {
      fs.closeSync(file.fd);
    }
    return true;
  } catch (err) {
    hilog.error(DOMAIN, TAG, 'writePlaylistsToUri failed: %{public}s', JSON.stringify(err));
    return false;
  }
}

/** 从指定 URI 读取导入数据；解析失败返回 null */
export function readPlaylistsFromUri(uri: string): Record<string, Object> | null {
  try {
    const file = fs.openSync(uri, fs.OpenMode.READ_ONLY);
    try {
      const stat = fs.statSync(file.fd);
      const buffer = new ArrayBuffer(stat.size);
      fs.readSync(file.fd, buffer);
      const decoder = util.TextDecoder.create('utf-8');
      const json = decoder.decodeToString(new Uint8Array(buffer));
      return JSON.parse(json) as Record<string, Object>;
    } finally {
      fs.closeSync(file.fd);
    }
  } catch (err) {
    hilog.error(DOMAIN, TAG, 'readPlaylistsFromUri failed: %{public}s', JSON.stringify(err));
    return null;
  }
}
