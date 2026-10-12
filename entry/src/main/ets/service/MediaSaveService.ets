// 媒体保存服务
// 用于保存歌词和封面图片到本地

// 日志经由应用日志门面，既输出 hilog 也进入「设置 → 运行日志」
import { appLog as hilog } from '../core/log/AppLogger';
import { fileIo as fs } from '@kit.CoreFileKit';
import { http } from '@kit.NetworkKit';
import { common } from '@kit.AbilityKit';
import { utf8Encode } from '../utils/TextCodec';
import type { MusicInfo } from '../types/MusicTypes';
import { t } from './LocalizationService';

const DOMAIN: number = 0x0001;
const TAG: string = 'MediaSaveService';

// 供 UI 层复用的音乐信息类型
export type { MusicInfo } from '../types/MusicTypes';

// 保存结果
export interface SaveResult {
  success: boolean;
  message: string;
  filePath?: string;
  error?: string;
}

// 媒体保存服务类
export class MediaSaveService {
  private static instance: MediaSaveService;
  private uiContext: common.UIAbilityContext | null = null;

  private constructor() {}

  // 单例获取
  static getInstance(): MediaSaveService {
    if (!MediaSaveService.instance) {
      MediaSaveService.instance = new MediaSaveService();
    }
    return MediaSaveService.instance;
  }

  // 设置上下文
  setContext(context: common.UIAbilityContext): void {
    this.uiContext = context;
  }

  // 获取上下文
  private getContext(): common.UIAbilityContext {
    if (!this.uiContext) {
      throw new Error('UIContext not set. Call setContext first.');
    }
    return this.uiContext;
  }

  // 保存歌词到文件
  async saveLyricToFile(musicInfo: MusicInfo, lyricContent: string): Promise<SaveResult> {
    try {
      if (!lyricContent || lyricContent.trim().length === 0) {
        return {
          success: false,
          message: t('media_lyric_empty')
        };
      }

      // 创建文件名
      const fileName = this.sanitizeFileName(`${musicInfo.name} - ${musicInfo.singer}.lrc`);
      const saveDir = `${this.getContext().filesDir}/LxMusic/Lyrics`;
      const filePath = `${saveDir}/${fileName}`;

      // 确保目录存在
      await this.ensureDirectoryExists(saveDir);

      // 写入歌词文件
      const file = await fs.open(filePath, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE);
      try {
        const data = utf8Encode(lyricContent);
        await fs.write(file.fd, data);
        await fs.fsync(file.fd);
      } finally {
        await fs.close(file.fd);
      }

      hilog.info(DOMAIN, TAG, '歌词保存成功: %{public}s', filePath);
      
      return {
        success: true,
        message: t('media_save_success'),
        filePath
      };

    } catch (err) {
      const errorMsg = err instanceof Error ? err.message : JSON.stringify(err);
      hilog.error(DOMAIN, TAG, '保存歌词失败: %{public}s', errorMsg);
      
      return {
        success: false,
        message: t('media_save_fail'),
        error: errorMsg
      };
    }
  }

  // 保存封面图片到文件
  async saveCoverToFile(musicInfo: MusicInfo, imageUrl: string): Promise<SaveResult> {
    try {
      if (!imageUrl || imageUrl.trim().length === 0) {
        return {
          success: false,
          message: t('media_url_empty')
        };
      }

      // 下载图片
      const imageData = await this.downloadImage(imageUrl);
      if (!imageData) {
        return {
          success: false,
          message: t('media_save_fail')
        };
      }

      // 创建文件名
      const fileExtension = this.getImageExtension(imageUrl);
      const fileName = this.sanitizeFileName(`${musicInfo.name} - ${musicInfo.singer}.${fileExtension}`);
      const saveDir = `${this.getContext().filesDir}/LxMusic/Covers`;
      const filePath = `${saveDir}/${fileName}`;

      // 确保目录存在
      await this.ensureDirectoryExists(saveDir);

      // 写入图片文件
      const file = await fs.open(filePath, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE);
      try {
        await fs.write(file.fd, imageData);
        await fs.fsync(file.fd);
      } finally {
        await fs.close(file.fd);
      }

      hilog.info(DOMAIN, TAG, '封面保存成功: %{public}s', filePath);
      
      return {
        success: true,
        message: t('media_save_success'),
        filePath
      };

    } catch (err) {
      const errorMsg = err instanceof Error ? err.message : JSON.stringify(err);
      hilog.error(DOMAIN, TAG, '保存封面失败: %{public}s', errorMsg);
      
      return {
        success: false,
        message: t('media_save_fail'),
        error: errorMsg
      };
    }
  }

  // 下载图片
  private async downloadImage(url: string): Promise<ArrayBuffer | null> {
    const httpReq = http.createHttp();
    try {
      const requestOptions: http.HttpRequestOptions = {
        method: http.RequestMethod.GET,
        connectTimeout: 10000,
        readTimeout: 10000,
        header: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
        }
      };

      const response = await httpReq.request(url, requestOptions);

      if (response.responseCode === 200) {
        return response.result as ArrayBuffer;
      } else {
        hilog.error(DOMAIN, TAG, '下载图片失败，HTTP状态码: %{public}d', response.responseCode);
        return null;
      }
    } catch (err) {
      hilog.error(DOMAIN, TAG, '下载图片失败: %{public}s', JSON.stringify(err));
      return null;
    } finally {
      httpReq.destroy();
    }
  }

  // 确保目录存在（递归创建，HarmonyOS fs.mkdir 无 recursive 参数）
  private async ensureDirectoryExists(dirPath: string): Promise<void> {
    try {
      await fs.access(dirPath);
    } catch (err) {
      // 目录不存在，先确保父目录存在再创建
      const parentPath = dirPath.substring(0, dirPath.lastIndexOf('/'));
      if (parentPath) {
        await this.ensureDirectoryExists(parentPath);
      }
      // 建目录本身也可能失败（权限/路径非法）：这里只记日志，是否可用交给调用方判断
      try {
        await fs.mkdir(dirPath);
      } catch (mkdirErr) {
        hilog.warn(DOMAIN, TAG, 'mkdir failed: %{public}s',
          mkdirErr instanceof Error ? mkdirErr.message : JSON.stringify(mkdirErr));
      }
    }
  }

  // 清理文件名（移除非法字符）
  private sanitizeFileName(fileName: string): string {
    // 移除或替换文件名中的非法字符
    return fileName
      .replace(/[<>:"/\\|?*]/g, '_')  // 替换Windows非法字符
      .replace(/\s+/g, ' ')           // 合并多个空格
      .trim()                         // 去除首尾空格
      .substring(0, 100);             // 限制长度
  }

  // 获取图片扩展名
  private getImageExtension(url: string): string {
    const urlLower = url.toLowerCase();
    
    if (urlLower.includes('.jpg') || urlLower.includes('.jpeg')) {
      return 'jpg';
    } else if (urlLower.includes('.png')) {
      return 'png';
    } else if (urlLower.includes('.gif')) {
      return 'gif';
    } else if (urlLower.includes('.webp')) {
      return 'webp';
    } else {
      // 默认使用jpg
      return 'jpg';
    }
  }

}

// 导出单例
export const mediaSaveService = MediaSaveService.getInstance();
