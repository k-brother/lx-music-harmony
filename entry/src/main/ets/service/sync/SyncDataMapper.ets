/**
 * 同步数据映射：本地数据 ↔ 同步数据体
 *
 * 从 SyncService 抽出：这里全是「把本地歌单/设置打包出去」与「把远端数据合并回来」的搬运逻辑，
 * 与连接、重连、状态机无关。只依赖 ListService / SettingsService，因此合并规则可以单独核对。
 *
 * 合并策略（沿用拆分前行为）：自建歌单按 id 判断是否已存在，不存在才创建并灌入歌曲；
 * 系统歌单（默认/我喜欢）按条追加；设置只覆盖「用户偏好」字段，本机连接配置不参与覆盖。
 */
import { appLog as hilog } from '../../core/log/AppLogger';
import {
  addMusicToList,
  createUserList,
  getDefaultList,
  getLoveList,
  getUserList,
  LIST_IDS,
} from '../ListService';
import { musicItemFromPlainObject } from '../../core/list/PlaylistRecordMapper';
import { settingsService, type SettingsPatch } from '../SettingsService';
import type { SyncConfig, SyncData, SyncJsonValue, SyncListExport } from './SyncTypes';

const TAG = 'SyncDataMapper';
const DOMAIN: number = 0x0001;

/** 打包本地歌单（默认列表 / 我喜欢 / 自建歌单） */
export function collectLocalLists(): SyncListExport[] {
  try {
    hilog.info(DOMAIN, TAG, '获取本地歌单数据');
    const result: SyncListExport[] = [];

    const now = Date.now();
    const defaultList: SyncListExport = {
      id: LIST_IDS.DEFAULT,
      name: '默认列表',
      type: 'default',
      musicCount: getDefaultList().length,
      musicList: getDefaultList(),
      createTime: now,
      updateTime: now,
    };
    result.push(defaultList);

    const loveList: SyncListExport = {
      id: LIST_IDS.LOVE,
      name: '我喜欢',
      type: 'love',
      musicCount: getLoveList().length,
      musicList: getLoveList(),
      createTime: now,
      updateTime: now,
    };
    result.push(loveList);

    const userLists = getUserList();
    for (let i = 0; i < userLists.length; i++) {
      const list = userLists[i];
      const userListData: SyncListExport = {
        id: list.id,
        name: list.name,
        type: 'user',
        source: list.source,
        desc: list.desc,
        pic: list.pic,
        count: list.count,
        createTime: list.createTime,
        updateTime: list.updateTime,
      };
      result.push(userListData);
    }
    hilog.info(DOMAIN, TAG, '获取到 %{public}d 个本地歌单', result.length);
    return result;
  } catch (err) {
    hilog.error(DOMAIN, TAG, '获取本地歌单数据失败: %{public}s',
      err instanceof Error ? err.message : JSON.stringify(err));
    return [];
  }
}

/**
 * 打包本地设置：应用设置整体序列化为一个字段，避免逐键同步时键名漂移；
 * 同步相关字段单独带上，便于对端了解本机同步配置。
 */
export function collectLocalSettings(
  config: SyncConfig, lastSyncTime: number): Record<string, SyncJsonValue> {
  try {
    hilog.info(DOMAIN, TAG, '获取本地设置');
    const result: Record<string, SyncJsonValue> = {};
    result['app_settings'] = JSON.stringify(settingsService.get());
    result['sync_enabled'] = config.enabled;
    result['sync_server'] = config.serverUrl;
    result['sync_mode'] = config.mode;
    result['sync_auto'] = config.autoSync;
    result['sync_interval'] = config.syncInterval;
    result['last_sync_time'] = lastSyncTime;
    hilog.info(DOMAIN, TAG, '获取到 %{public}d 个本地设置', Object.keys(result).length);
    return result;
  } catch (err) {
    hilog.error(DOMAIN, TAG, '获取本地设置失败: %{public}s',
      err instanceof Error ? err.message : JSON.stringify(err));
    return {};
  }
}

/** 组装同步数据体 */
export function collectLocalData(config: SyncConfig, lastSyncTime: number): SyncData {
  const lists: SyncListExport[] = collectLocalLists();
  const settings: Record<string, SyncJsonValue> = collectLocalSettings(config, lastSyncTime);
  const result: SyncData = {
    lists: lists,
    settings: settings,
    lastSyncTime: lastSyncTime,
  };
  return result;
}

/** 把远端同步数据合并到本地 */
export async function mergeDataToLocal(syncData: SyncData): Promise<void> {
  hilog.info(DOMAIN, TAG, '开始合并数据到本地');
  if (syncData.lists && syncData.lists.length > 0) {
    await mergeLists(syncData.lists);
  }
  if (syncData.settings) {
    await mergeSettings(syncData.settings);
  }
  hilog.info(DOMAIN, TAG, '数据合并完成');
}

async function mergeLists(remoteLists: SyncListExport[]): Promise<void> {
  try {
    hilog.info(DOMAIN, TAG, '合并歌单数据，数量: %{public}d', remoteLists.length);
    const localUserLists = getUserList();

    for (let r = 0; r < remoteLists.length; r++) {
      const remoteList = remoteLists[r];
      const listId = remoteList.id;
      const listName = remoteList.name;
      const listType = remoteList.type;
      const musicList = remoteList.musicList ?? [];

      if (listType === 'user') {
        const localList = localUserLists.find((list): boolean => list.id === listId);
        if (!localList) {
          try {
            const newList = await createUserList(listName);
            hilog.info(DOMAIN, TAG, '创建新歌单: %{public}s', listName);
            for (let m = 0; m < musicList.length; m++) {
              try {
                await addMusicToList(newList.id, musicItemFromPlainObject(musicList[m]));
              } catch (musicErr) {
                hilog.warn(DOMAIN, TAG, '添加歌曲失败: %{public}s', JSON.stringify(musicErr));
              }
            }
          } catch (createErr) {
            hilog.error(DOMAIN, TAG, '创建歌单失败: %{public}s', JSON.stringify(createErr));
          }
        } else {
          hilog.info(DOMAIN, TAG, '歌单 %{public}s 已存在（本地 %{public}d 首 / 远端 %{public}d 首）',
            listName, localList.count || 0, musicList.length);
        }
      } else if (listType === 'default' || listType === 'love') {
        hilog.info(DOMAIN, TAG, '合并系统歌单: %{public}s', listName);
        for (let m = 0; m < musicList.length; m++) {
          try {
            await addMusicToList(listId, musicItemFromPlainObject(musicList[m]));
          } catch (musicErr) {
            hilog.warn(DOMAIN, TAG, '添加歌曲到系统歌单失败: %{public}s', JSON.stringify(musicErr));
          }
        }
      }
    }
    hilog.info(DOMAIN, TAG, '歌单数据合并完成');
  } catch (err) {
    const errorMsg = err instanceof Error ? err.message : JSON.stringify(err);
    hilog.error(DOMAIN, TAG, '合并歌单数据失败: %{public}s', errorMsg);
    throw new Error(errorMsg);
  }
}

async function mergeSettings(remoteSettings: Record<string, SyncJsonValue>): Promise<void> {
  try {
    hilog.info(DOMAIN, TAG, '合并设置数据');
    const payload = remoteSettings['app_settings'];
    if (typeof payload !== 'string' || payload.length === 0) {
      hilog.warn(DOMAIN, TAG, '远端未提供 app_settings，跳过设置合并');
      return;
    }
    const remote = JSON.parse(payload) as SettingsPatch;
    // ArkTS 不支持 delete，这里显式只挑「用户偏好」字段：
    // 同步开关 / 服务器 / 密钥等本机连接配置不参与覆盖。
    const patch: SettingsPatch = {
      language: remote.language,
      startupPage: remote.startupPage,
      showExitDialog: remote.showExitDialog,
      themeMode: remote.themeMode,
      themeId: remote.themeId,
      autoPlay: remote.autoPlay,
      highQuality: remote.highQuality,
      playMode: remote.playMode,
      volume: remote.volume,
      sleepTimerEnabled: remote.sleepTimerEnabled,
      sleepTimerMinutes: remote.sleepTimerMinutes,
      showDesktopLyric: remote.showDesktopLyric,
      desktopLyricPosition: remote.desktopLyricPosition,
      desktopLyricColor: remote.desktopLyricColor,
      searchSource: remote.searchSource,
      showHotSearch: remote.showHotSearch,
      searchHistoryCount: remote.searchHistoryCount,
      addMusicLocation: remote.addMusicLocation,
      autoCleanPlayedList: remote.autoCleanPlayedList,
      fontSize: remote.fontSize,
      showAnimation: remote.showAnimation,
    };
    await settingsService.update(patch);
    hilog.info(DOMAIN, TAG, '设置数据合并完成');
  } catch (err) {
    const errorMsg = err instanceof Error ? err.message : JSON.stringify(err);
    hilog.error(DOMAIN, TAG, '合并设置数据失败: %{public}s', errorMsg);
    throw new Error(errorMsg);
  }
}
