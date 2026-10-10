/**
 * 桌面卡片封面工具：把封面 URL 变成可交给 formImages 的只读 fd。
 *
 * 约束（对方项目踩过的坑，这里直接做对）：
 * - 交给卡片的 fd 必须「只读、偏移在 0」：复用刚写完的读写 fd 会因偏移停在文件末尾，
 *   系统读图有概率拿到 0 字节（表现：换歌后卡片封面第一下是空的）。
 * - 本地音乐 / 自定义歌单的 cover 是沙箱文件 URI（file:// 或绝对路径），
 *   不能用 http 去下，直接只读打开原文件即可（也不需要拷一份）。
 * - fd 交给系统后必须保活：用保活列表兜底，超过上限关掉最旧的。
 *
 * 纯工具、无服务依赖：UIAbility 进程（CardFormService 推送）与
 * 卡片进程（CardFormAbility 首次渲染）都会用，放 utils 保持两边都能薄引入。
 */
import { fileIo } from '@kit.CoreFileKit';
import { http } from '@kit.NetworkKit';

export interface CardCoverFd {
  /** formImages 的键，也是卡片侧 memory:// 引用的名字 */
  name: string;
  /** 已按只读打开、登记保活的 fd（< 0 表示无效） */
  fd: number;
}

const MAX_KEEP_FDS: number = 8;
const DOWNLOAD_TIMEOUT_MS: number = 8000;

export class CardFormCover {
  private static seq: number = 0;
  private static cachedUrl: string = '';
  private static cachedPath: string = '';
  private static openFds: number[] = [];

  /**
   * 准备封面 fd。
   * @param tempDir 进程临时目录（下载文件落盘位置）
   * @param url 封面地址（http(s) / file:// / 绝对路径；其它 scheme 不支持）
   * @returns 无效时返回 null（卡片显示占位图）
   */
  static async prepare(tempDir: string, url: string): Promise<CardCoverFd | null> {
    const target: string = (url ?? '').trim();
    if (target.length === 0) {
      return null;
    }
    if (CardFormCover.isLocalPath(target)) {
      const fd: number = CardFormCover.openReadOnly(target);
      if (fd >= 0) {
        CardFormCover.cachedUrl = target;
        CardFormCover.cachedPath = '';
      }
      return fd >= 0 ? CardFormCover.makeResult(fd) : null;
    }
    if (!target.startsWith('http://') && !target.startsWith('https://')) {
      return null;
    }
    if (target === CardFormCover.cachedUrl && CardFormCover.cachedPath.length > 0 &&
        CardFormCover.exists(CardFormCover.cachedPath)) {
      const cachedFd: number = CardFormCover.openReadOnly(CardFormCover.cachedPath);
      return cachedFd >= 0 ? CardFormCover.makeResult(cachedFd) : null;
    }
    const bytes: ArrayBuffer | null = await CardFormCover.download(target);
    if (bytes === null) {
      if (CardFormCover.cachedPath.length > 0 && CardFormCover.exists(CardFormCover.cachedPath)) {
        const fallbackFd: number = CardFormCover.openReadOnly(CardFormCover.cachedPath);
        return fallbackFd >= 0 ? CardFormCover.makeResult(fallbackFd) : null;
      }
      return null;
    }
    CardFormCover.seq++;
    const path: string = tempDir + '/card_cover_' + CardFormCover.seq + '_' + Date.now() + '.img';
    try {
      const file: fileIo.File = fileIo.openSync(path,
        fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
      try {
        await fileIo.write(file.fd, bytes);
      } finally {
        fileIo.closeSync(file);
      }
      const previous: string = CardFormCover.cachedPath;
      CardFormCover.cachedUrl = target;
      CardFormCover.cachedPath = path;
      if (previous.length > 0 && previous !== path) {
        CardFormCover.unlink(previous);
      }
      const fd: number = CardFormCover.openReadOnly(path);
      return fd >= 0 ? CardFormCover.makeResult(fd) : null;
    } catch (_err) {
      CardFormCover.unlink(path);
      return null;
    }
  }

  private static makeResult(fd: number): CardCoverFd {
    CardFormCover.seq++;
    return { name: 'cover_' + CardFormCover.seq, fd: fd };
  }

  private static isLocalPath(url: string): boolean {
    return url.startsWith('file://') || url.startsWith('/');
  }

  private static openReadOnly(path: string): number {
    if (path.length === 0) {
      return -1;
    }
    try {
      const file: fileIo.File = fileIo.openSync(path, fileIo.OpenMode.READ_ONLY);
      CardFormCover.keepFd(file.fd);
      return file.fd;
    } catch (_err) {
      return -1;
    }
  }

  private static async download(url: string): Promise<ArrayBuffer | null> {
    const request = http.createHttp();
    try {
      const response: http.HttpResponse = await request.request(url, {
        method: http.RequestMethod.GET,
        header: { 'User-Agent': 'Mozilla/5.0' },
        connectTimeout: DOWNLOAD_TIMEOUT_MS,
        readTimeout: DOWNLOAD_TIMEOUT_MS,
        expectDataType: http.HttpDataType.ARRAY_BUFFER
      });
      if (response.responseCode === 200 && response.result !== undefined) {
        return response.result as ArrayBuffer;
      }
      return null;
    } catch (_err) {
      return null;
    } finally {
      request.destroy();
    }
  }

  private static exists(path: string): boolean {
    if (path.length === 0) {
      return false;
    }
    try {
      fileIo.accessSync(path);
      return true;
    } catch (_err) {
      return false;
    }
  }

  private static keepFd(fd: number): void {
    CardFormCover.openFds.push(fd);
    while (CardFormCover.openFds.length > MAX_KEEP_FDS) {
      const oldest: number = CardFormCover.openFds.shift() as number;
      try {
        fileIo.closeSync(oldest);
      } catch (_err) {
      }
    }
  }

  private static unlink(path: string): void {
    try {
      fileIo.unlinkSync(path);
    } catch (_err) {
    }
  }
}
