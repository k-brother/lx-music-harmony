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
import type { SongInfo } from './PlayerService';
import type { MusicInfo } from '../types/MusicTypes';

const TAG = 'LocalMusicService';
const DOMAIN = 0x0005;
const LOCAL_DIR_NAME = 'localMusic';

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
