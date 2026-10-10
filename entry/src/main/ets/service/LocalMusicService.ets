/**
 * 本地音乐服务
 *
 * 职责：
 * - 把用户选择的音频文件复制进应用沙箱（避免后续权限失效、文件被移动）
 * - 用系统 AVMetadataExtractor 读取标题/歌手/专辑/时长（见 ResolvePlayback.scanLocalMusic）
 * - 维护本地曲库列表并持久化，供页面展示与播放
 *
 * 播放走 PlayerService：`file://` 路径由播放器直接打开，不依赖网络。
 */
// 日志经由应用日志门面，既输出 hilog 也进入「设置 → 运行日志」
import { appLog as hilog } from '../core/log/AppLogger';
import { fileIo as fs } from '@kit.CoreFileKit';
import { picker as filePicker } from '@kit.CoreFileKit';
import type { common } from '@kit.AbilityKit';
import type { BusinessError } from '@kit.BasicServicesKit';
import storageService, { StorageKeys } from './StorageService';
import { scanLocalMusic, getLocalPicUrl, type LocalMusicInfo } from '../core/music/local/LocalPlayback';
import { getLyricInfo } from '../core/music/MusicFeatureEntry';
import { setLocalMatchLyricResolver } from '../core/music/ResolvePlayback';
import {
  autoMatchLyric,
  infoFromJson,
  infoToJson,
  toPlatformMusicInfo,
  type MatchSongInfo
} from '../core/music/local/LyricMatch';
import { orderedEnabledSources } from '../core/music/SourcePolicy';
import { httpRequestBinary } from '../core/network/http/HttpClient';
import { settingsService } from './SettingsService';
import type { SongInfo } from './PlayerService';
import type { LyricInfo, MusicInfo } from '../types/MusicTypes';

const TAG = 'LocalMusicService';
const DOMAIN = 0x0005;
const LOCAL_DIR_NAME = 'localMusic';

/**
 * 一条本地歌的在线匹配记录（存 local.music.matches）。
 *
 * 存成数组而不是 Record：ArkTS 对 Record 的动态键写入有限制，
 * 数组 + 线性查找在这个量级（本地曲库通常几百首以内）完全没有性能问题。
 *
 * matchAt 有三态语义：
 * - 0：从没搜过（自动匹配会尝试）
 * - >0 且有 matchJson：匹配成功（直接用）
 * - >0 且无 matchJson：搜过了但没找到（自动匹配不再重试，手动匹配仍可用）
 */
export interface LocalMatchRecord {
  trackId: string;
  /** 平台 id（'kw' | 'kg' | 'tx' | 'wy' | 'mg'），空串 = 无匹配 */
  source: string;
  /** MatchSongInfo 的 JSON；空串 = 无匹配 */
  matchJson: string;
  /** 首次搜索/成功匹配的时间戳；0 = 从没搜过 */
  matchAt: number;
}

/** 「全部匹配」的统计结果 */
export interface MatchAllSummary {
  ok: number;
  fail: number;
  total: number;
}

/** 建目录：已存在（13900015）不算失败，其它错误才记日志 */
function ensureLocalDir(dir: string): void {
  try {
    fs.mkdirSync(dir, true);
  } catch (err) {
    const code: number = (err as BusinessError)?.code ?? 0;
    // 13900015 = 目录已存在
    if (code !== 13900015) {
      hilog.warn(DOMAIN, TAG, 'mkdir local dir failed: code=%{public}d', code);
    }
  }
}

/**
 * 把选择器返回的 URI 复制进沙箱。
 *
 * 关键点：选择器给的是 `file://docs/...` 这类 **URI**，不是文件系统路径。
 * 直接 `copyFileSync(uri, dest)` 会报 "No such file or directory"（真机上就是
 * 「选了歌却一首都没进来」）。正确做法是先用 openSync 把 URI 打开成 fd，再按 fd 复制。
 */
function copyUriToSandbox(uri: string, destPath: string): void {
  const src: fs.File = fs.openSync(uri, fs.OpenMode.READ_ONLY);
  try {
    fs.copyFileSync(src.fd, destPath);
  } finally {
    fs.closeSync(src);
  }
}

class LocalMusicServiceImpl {
  private context: common.UIAbilityContext | null = null;
  private library: LocalMusicInfo[] = [];
  private matches: LocalMatchRecord[] = [];
  private initialized: boolean = false;

  setContext(context: common.UIAbilityContext): void {
    this.context = context;
  }

  async init(): Promise<void> {
    if (this.initialized) {
      return;
    }
    this.initialized = true;
    try {
      const raw = await storageService.getString(StorageKeys.LOCAL_MUSIC_LIST, '');
      this.library = raw.length > 0 ? JSON.parse(raw) as LocalMusicInfo[] : [];
      hilog.info(DOMAIN, TAG, 'Local library loaded: %{public}d tracks', this.library.length);
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'load local library failed: %{public}s', JSON.stringify(err));
      this.library = [];
    }
    try {
      const rawMatches = await storageService.getString(StorageKeys.LOCAL_MUSIC_MATCHES, '');
      this.matches = rawMatches.length > 0 ? JSON.parse(rawMatches) as LocalMatchRecord[] : [];
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'load local matches failed: %{public}s', JSON.stringify(err));
      this.matches = [];
    }
    // 本地歌没有平台身份，歌词中枢取词时经过这里做在线匹配（见 ResolvePlayback 的 local 分支）。
    // core 不能依赖 service，所以由 service 在启动时把解析器注册进 core。
    setLocalMatchLyricResolver((musicInfo: MusicInfo): Promise<LyricInfo | null> =>
      this.resolveLocalMatchLyric(musicInfo));
  }

  getLibrary(): LocalMusicInfo[] {
    return this.library;
  }

  /** 应用沙箱内的本地音乐目录 */
  getLocalDir(): string {
    if (!this.context) {
      return '';
    }
    return `${this.context.filesDir}/${LOCAL_DIR_NAME}`;
  }

  /**
   * 通过系统文件选择器导入音频文件（多选）。
   * @returns 新增曲目数
   */
  async importFromPicker(): Promise<number> {
    if (!this.context) {
      hilog.warn(DOMAIN, TAG, 'importFromPicker: context not set');
      return 0;
    }
    try {
      const picker = new filePicker.AudioViewPicker(this.context);
      const options = new filePicker.AudioSelectOptions();
      options.maxSelectNumber = 100;
      const uris: string[] = await picker.select(options);
      if (!uris || uris.length === 0) {
        return 0;
      }
      return await this.importUris(uris);
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'importFromPicker failed: %{public}s',
        err instanceof Error ? err.message : JSON.stringify(err));
      return 0;
    }
  }

  /** 把选中的 URI 复制进沙箱并登记到曲库 */
  async importUris(uris: string[]): Promise<number> {
    const dir = this.getLocalDir();
    if (dir.length === 0) {
      return 0;
    }
    ensureLocalDir(dir);

    let copied = 0;
    // 先全部复制进沙箱，再统一扫描一次（避免每导入一首就重扫整个目录）
    for (let i = 0; i < uris.length; i++) {
      const uri = uris[i];
      const fileName = this.buildSafeFileName(uri);
      const destPath = `${dir}/${fileName}`;
      try {
        if (fs.accessSync(destPath)) {
          continue;
        }
        copyUriToSandbox(uri, destPath);
        copied += 1;
      } catch (err) {
        hilog.warn(DOMAIN, TAG, 'import %{public}s failed: %{public}s',
          uri, err instanceof Error ? err.message : JSON.stringify(err));
      }
    }
    const before = this.library.length;
    this.library = await scanLocalMusic(dir);
    const added = Math.max(0, this.library.length - before);
    await this.persist();
    hilog.info(DOMAIN, TAG, 'Imported %{public}d tracks (copied %{public}d/%{public}d), library size=%{public}d',
      added, copied, uris.length, this.library.length);
    return added;
  }

  /**
   * 从「文件管理」里选音频导入。
   *
   * 系统音频选择器（AudioViewPicker）由华为音乐提供，部分设备上会打开一片空白/无内容，
   * 这里给一条不依赖它的通路：文件管理里按扩展名筛音频，多选后同样复制进沙箱。
   */
  async importFromFilePicker(): Promise<number> {
    if (!this.context) {
      hilog.warn(DOMAIN, TAG, 'importFromFilePicker: context not set');
      return 0;
    }
    try {
      const picker = new filePicker.DocumentViewPicker(this.context);
      const options = new filePicker.DocumentSelectOptions();
      options.maxSelectNumber = 100;
      options.fileSuffixFilters = ['.mp3', '.flac', '.m4a', '.aac', '.wav', '.ogg', '.opus', '.wma', '.ape'];
      const uris: string[] = await picker.select(options);
      if (!uris || uris.length === 0) {
        return 0;
      }
      return await this.importUris(uris);
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'importFromFilePicker failed: %{public}s',
        err instanceof Error ? err.message : JSON.stringify(err));
      return 0;
    }
  }

  /** 重新扫描沙箱目录（文件被删除/新增后刷新曲库） */
  async rescan(): Promise<number> {
    const dir = this.getLocalDir();
    if (dir.length === 0) {
      return 0;
    }
    this.library = await scanLocalMusic(dir);
    await this.persist();
    await this.pruneMatches();
    return this.library.length;
  }

  /**
   * 更新曲目的元数据（歌名/歌手/专辑）。
   * 只改应用内的曲库记录，不改动音频文件本身的内嵌标签——
   * 这样既避免破坏原始文件，也让用户能自由整理本地曲库。
   */
  async updateMetadata(trackId: string, name: string, singer: string, album: string): Promise<boolean> {
    const index = this.indexOf(trackId);
    if (index < 0) {
      hilog.warn(DOMAIN, TAG, 'updateMetadata: track not found %{public}s', trackId);
      return false;
    }
    const track = this.library[index];
    const nextName = name.trim();
    if (nextName.length === 0) {
      // 歌名不允许为空，否则列表无法辨认
      return false;
    }
    track.name = nextName;
    track.singer = singer.trim();
    track.album = album.trim();
    await this.persist();
    hilog.info(DOMAIN, TAG, 'Metadata updated: %{public}s', nextName);
    return true;
  }

  /**
   * 设置自定义封面：把选中的图片复制为 `<音频路径>.cover.jpg`，
   * 与内嵌封面共用同一缓存路径，后续读取无需特殊分支。
   */
  async setCustomCover(trackId: string, sourceUri: string): Promise<boolean> {
    const index = this.indexOf(trackId);
    if (index < 0) {
      return false;
    }
    const track = this.library[index];
    const coverPath = `${track.filePath}.cover.jpg`;
    try {
      const src: fs.File = fs.openSync(sourceUri, fs.OpenMode.READ_ONLY);
      try {
        const dst: fs.File = fs.openSync(coverPath, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY);
        try {
          fs.copyFileSync(src.fd, dst.fd);
          fs.fsyncSync(dst.fd);
        } finally {
          fs.closeSync(dst);
        }
      } finally {
        fs.closeSync(src);
      }
      track.picUrl = coverPath;
      await this.persist();
      hilog.info(DOMAIN, TAG, 'Custom cover saved: %{public}s', coverPath);
      return true;
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'setCustomCover failed: %{public}s',
        err instanceof Error ? err.message : JSON.stringify(err));
      return false;
    }
  }

  async remove(trackId: string): Promise<void> {
    const index = this.indexOf(trackId);
    if (index < 0) {
      return;
    }
    const track = this.library[index];
    this.library.splice(index, 1);
    await this.persist();
    const recordIndex = this.matchRecordIndexOf(track.id);
    if (recordIndex >= 0) {
      this.matches.splice(recordIndex, 1);
      await this.persistMatches();
    }
    // 删除沙箱内的文件与封面缓存（失败不影响列表）
    try {
      if (fs.accessSync(track.filePath)) {
        fs.unlinkSync(track.filePath);
      }
      const coverPath = `${track.filePath}.cover.jpg`;
      if (fs.accessSync(coverPath)) {
        fs.unlinkSync(coverPath);
      }
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'remove local file failed: %{public}s', JSON.stringify(err));
    }
  }

  /** 曲目 -> 播放器 SongInfo（file:// 直接播） */
  toSongInfo(track: LocalMusicInfo): SongInfo {
    return {
      id: track.id,
      url: `file://${track.filePath}`,
      title: track.name,
      artist: track.singer,
      album: track.album,
      artwork: track.picUrl ?? null,
      duration: Math.floor(track.duration / 1000),
      source: 'local',
    };
  }

  /** 曲目 -> MusicInfo（歌词/封面/播控元数据用） */
  toMusicInfo(track: LocalMusicInfo): MusicInfo {
    return {
      id: track.id,
      songmid: track.id,
      name: track.name,
      singer: track.singer,
      album: track.album,
      albumName: track.album,
      source: 'local',
      interval: track.interval,
      img: track.picUrl ?? null,
      lrc: null,
    };
  }

  /** 读取内嵌封面路径（首次会解码并生成缓存文件） */
  async loadCover(track: LocalMusicInfo): Promise<string> {
    if (track.picUrl && track.picUrl.length > 0) {
      return track.picUrl;
    }
    try {
      const pic = await getLocalPicUrl({
        musicInfo: track,
        isRefresh: false,
        allowToggleSource: false,
      });
      if (pic && pic.length > 0) {
        track.picUrl = pic;
        return pic;
      }
    } catch (err) {
      hilog.info(DOMAIN, TAG, 'loadCover failed: %{public}s',
        err instanceof Error ? err.message : '');
    }
    return '';
  }

  // ------------------------------------------------------------ 在线匹配

  /** 曲目已保存的匹配结果（没有返回 null） */
  matchOf(trackId: string): MatchSongInfo | null {
    const index = this.matchRecordIndexOf(trackId);
    if (index < 0) {
      return null;
    }
    const json = this.matches[index].matchJson;
    return json.length > 0 ? infoFromJson(json) : null;
  }

  /** 手动匹配面板选中一条：落盘（下次直接用它的歌词与封面）+ 异步补封面 */
  async applyPickedMatch(trackId: string, source: string, info: MatchSongInfo): Promise<void> {
    await this.saveMatch(trackId, source, info);
    void this.applyMatchCover(trackId, info);
  }

  /** 曲目是否搜过（成功或确认无结果都算） */
  matchTried(trackId: string): boolean {
    const index = this.matchRecordIndexOf(trackId);
    return index >= 0 && this.matches[index].matchAt > 0;
  }

  /** 保存用户选中 / 自动匹配的在线歌曲（下次直接用它的歌词与封面） */
  async saveMatch(trackId: string, source: string, info: MatchSongInfo): Promise<void> {
    const json = infoToJson(info);
    const index = this.matchRecordIndexOf(trackId);
    if (index >= 0) {
      this.matches[index].source = source;
      this.matches[index].matchJson = json;
      this.matches[index].matchAt = Date.now();
    } else {
      this.matches.push({ trackId: trackId, source: source, matchJson: json, matchAt: Date.now() });
    }
    await this.persistMatches();
  }

  /** 清除匹配：保留 matchAt（表示搜过了），自动匹配不会因此重试 */
  async clearMatch(trackId: string): Promise<void> {
    const index = this.matchRecordIndexOf(trackId);
    if (index < 0) {
      return;
    }
    this.matches[index].source = '';
    this.matches[index].matchJson = '';
    if (this.matches[index].matchAt === 0) {
      this.matches[index].matchAt = Date.now();
    }
    await this.persistMatches();
  }

  /**
   * core 取词入口（ResolvePlayback 的 local 分支回调到这里）。
   *
   * 顺序：已保存的匹配直接用 → 设置关了/搜过了就不动 → 按用户启用的平台顺序自动匹配。
   * 自动匹配是「宁缺勿错」的（打分规则见 core/music/local/LyricMatch），
   * 匹配成功会顺手把封面也补上。
   */
  private async resolveLocalMatchLyric(musicInfo: MusicInfo): Promise<LyricInfo | null> {
    const trackId = musicInfo.id ?? musicInfo.songmid ?? '';
    if (trackId.length === 0) {
      return null;
    }
    const saved = this.matchOf(trackId);
    if (saved) {
      return this.fetchMatchedLyric(saved);
    }
    const settings = settingsService.get();
    if (!settings.autoMatchLocalLyric || this.matchTried(trackId)) {
      return null;
    }
    const track = this.libraryItem(trackId);
    const name = track ? track.name : musicInfo.name;
    const singer = track ? track.singer : musicInfo.singer;
    const durationMs = track ? track.duration : 0;
    const platforms = orderedEnabledSources(settings.sourceOrder, settings.disabledSources);
    const result = await autoMatchLyric(name, singer, durationMs, platforms);
    if (result.match) {
      await this.saveMatch(trackId, result.match.source, result.match.info);
      void this.applyMatchCover(trackId, result.match.info);
      return this.fetchMatchedLyric(result.match.info);
    }
    // 有平台应答过但没找到：记下来，避免每次播放都重搜。
    // 全部平台都失败（断网）时不记 —— 不能因第一次恰好没网就永久失去歌词。
    if (result.searched) {
      await this.markMatchTried(trackId);
    }
    return null;
  }

  /** 拿匹配到的平台歌去走正常歌词链路（翻译/罗马音/缓存/简繁全部生效） */
  private async fetchMatchedLyric(info: MatchSongInfo): Promise<LyricInfo | null> {
    try {
      const lyric = await getLyricInfo({ musicInfo: toPlatformMusicInfo(info) });
      if (lyric.lyric && lyric.lyric.length > 0) {
        return lyric;
      }
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'fetch matched lyric failed: %{public}s',
        err instanceof Error ? err.message : JSON.stringify(err));
    }
    return null;
  }

  /** 匹配成功但本地没有封面时，把平台封面下载为封面缓存（失败不影响主流程） */
  private async applyMatchCover(trackId: string, info: MatchSongInfo): Promise<void> {
    const track = this.libraryItem(trackId);
    if (!track || (track.picUrl && track.picUrl.length > 0) || info.img.length <= 8) {
      return;
    }
    try {
      const data = await httpRequestBinary(info.img);
      if (!data || data.byteLength < 100) {
        return;
      }
      const coverPath = `${track.filePath}.cover.jpg`;
      const dst: fs.File = fs.openSync(coverPath, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY);
      try {
        fs.writeSync(dst.fd, data);
        fs.fsyncSync(dst.fd);
      } finally {
        fs.closeSync(dst);
      }
      track.picUrl = coverPath;
      await this.persist();
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'apply matched cover failed: %{public}s',
        err instanceof Error ? err.message : JSON.stringify(err));
    }
  }

  /**
   * 「全部匹配」：给曲库里还没有匹配的本地歌逐首自动匹配。
   * 跳过已有匹配的（含手动匹配的，不能覆盖用户的选择）。
   */
  async matchAllTracks(onProgress?: (done: number, total: number, name: string) => void): Promise<MatchAllSummary> {
    const settings = settingsService.get();
    const platforms = orderedEnabledSources(settings.sourceOrder, settings.disabledSources);
    const targets: LocalMusicInfo[] = [];
    for (const track of this.library) {
      if (!this.matchOf(track.id)) {
        targets.push(track);
      }
    }
    let ok = 0;
    let fail = 0;
    for (let i = 0; i < targets.length; i++) {
      const track = targets[i];
      onProgress?.(i, targets.length, track.name);
      const result = await autoMatchLyric(track.name, track.singer, track.duration, platforms);
      if (result.match) {
        await this.saveMatch(track.id, result.match.source, result.match.info);
        void this.applyMatchCover(track.id, result.match.info);
        ok += 1;
      } else {
        fail += 1;
        if (result.searched) {
          await this.markMatchTried(track.id);
        }
      }
      onProgress?.(i + 1, targets.length, track.name);
    }
    hilog.info(DOMAIN, TAG, 'match all done: %{public}d ok, %{public}d fail', ok, fail);
    return { ok: ok, fail: fail, total: targets.length };
  }

  private async markMatchTried(trackId: string): Promise<void> {
    const index = this.matchRecordIndexOf(trackId);
    if (index >= 0) {
      if (this.matches[index].matchAt === 0) {
        this.matches[index].matchAt = Date.now();
        await this.persistMatches();
      }
      return;
    }
    this.matches.push({ trackId: trackId, source: '', matchJson: '', matchAt: Date.now() });
    await this.persistMatches();
  }

  private matchRecordIndexOf(trackId: string): number {
    for (let i = 0; i < this.matches.length; i++) {
      if (this.matches[i].trackId === trackId) {
        return i;
      }
    }
    return -1;
  }

  private libraryItem(trackId: string): LocalMusicInfo | null {
    const index = this.indexOf(trackId);
    return index >= 0 ? this.library[index] : null;
  }

  /** 重扫后丢掉已不存在曲目的匹配记录 */
  private async pruneMatches(): Promise<void> {
    const before = this.matches.length;
    this.matches = this.matches.filter((record: LocalMatchRecord) => this.indexOf(record.trackId) >= 0);
    if (this.matches.length !== before) {
      await this.persistMatches();
    }
  }

  private async persistMatches(): Promise<void> {
    try {
      await storageService.setString(StorageKeys.LOCAL_MUSIC_MATCHES, JSON.stringify(this.matches));
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'persist local matches failed: %{public}s', JSON.stringify(err));
    }
  }

  private indexOf(trackId: string): number {
    for (let i = 0; i < this.library.length; i++) {
      if (this.library[i].id === trackId || this.library[i].filePath === trackId) {
        return i;
      }
    }
    return -1;
  }

  /** 从 URI 推导一个安全且唯一的文件名 */
  private buildSafeFileName(uri: string): string {
    const raw = uri.substring(uri.lastIndexOf('/') + 1);
    const decoded = decodeURIComponent(raw.length > 0 ? raw : `local_${Date.now()}`);
    const cleaned = decoded.replace(/[\\/:*?"<>|]/g, '_');
    return cleaned.length > 0 ? cleaned : `local_${Date.now()}.mp3`;
  }

  private async persist(): Promise<void> {
    try {
      await storageService.setString(StorageKeys.LOCAL_MUSIC_LIST, JSON.stringify(this.library));
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'persist local library failed: %{public}s', JSON.stringify(err));
    }
  }
}

export const localMusicService = new LocalMusicServiceImpl();
export default localMusicService;
