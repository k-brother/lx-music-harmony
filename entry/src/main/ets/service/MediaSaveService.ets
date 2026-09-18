// 媒体保存服务
// 用于保存歌词和封面图片到本地

import hilog from '@ohos.hilog';
import fs from '@ohos.file.fs';
import { http } from '@kit.NetworkKit';
import { common } from '@kit.AbilityKit';
import { utf8Encode } from '../utils/TextCodec';
import type { MusicInfo } from '../types/MusicTypes';

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
          message: '歌词内容为空'
        };
      }

      // 创建文件名
      const fileName = this.sanitizeFileName(`${musicInfo.singer} - ${musicInfo.name}.lrc`);
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
        message: '歌词保存成功',
        filePath
      };

    } catch (err) {
      const errorMsg = err instanceof Error ? err.message : JSON.stringify(err);
      hilog.error(DOMAIN, TAG, '保存歌词失败: %{public}s', errorMsg);
      
      return {
        success: false,
        message: '保存歌词失败',
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
          message: '图片URL为空'
        };
      }

      // 下载图片
      const imageData = await this.downloadImage(imageUrl);
      if (!imageData) {
        return {
          success: false,
          message: '下载图片失败'
        };
      }

      // 创建文件名
      const fileExtension = this.getImageExtension(imageUrl);
      const fileName = this.sanitizeFileName(`${musicInfo.singer} - ${musicInfo.name}.${fileExtension}`);
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
        message: '封面保存成功',
        filePath
      };

    } catch (err) {
      const errorMsg = err instanceof Error ? err.message : JSON.stringify(err);
      hilog.error(DOMAIN, TAG, '保存封面失败: %{public}s', errorMsg);
      
      return {
        success: false,
        message: '保存封面失败',
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
      await fs.mkdir(dirPath);
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

  // 批量保存歌词
  async saveLyricsBatch(musicList: MusicInfo[], lyrics: string[]): Promise<SaveResult[]> {
    const results: SaveResult[] = [];
    
    for (let i = 0; i < musicList.length; i++) {
      if (i < lyrics.length && lyrics[i]) {
        const result = await this.saveLyricToFile(musicList[i], lyrics[i]);
        results.push(result);
      } else {
        results.push({
          success: false,
          message: '歌词内容为空'
        });
      }
    }
    
    return results;
  }

  // 批量保存封面
  async saveCoversBatch(musicList: MusicInfo[], imageUrls: string[]): Promise<SaveResult[]> {
    const results: SaveResult[] = [];
    
    for (let i = 0; i < musicList.length; i++) {
      if (i < imageUrls.length && imageUrls[i]) {
        const result = await this.saveCoverToFile(musicList[i], imageUrls[i]);
        results.push(result);
      } else {
        results.push({
          success: false,
          message: '图片URL为空'
        });
      }
    }
    
    return results;
  }

  // 获取已保存的歌词列表
  async getSavedLyrics(): Promise<string[]> {
    try {
      const lyricsDir = `${this.getContext().filesDir}/LxMusic/Lyrics`;
      
      // 确保目录存在
      await this.ensureDirectoryExists(lyricsDir);
      
      const names: string[] = fs.listFileSync(lyricsDir);
      const files: string[] = [];
      for (let i = 0; i < names.length; i++) {
        const name = names[i];
        if (name.endsWith('.lrc')) {
          files.push(name);
        }
      }
      
      return files;
    } catch (err) {
      hilog.error(DOMAIN, TAG, '获取已保存歌词列表失败: %{public}s', JSON.stringify(err));
      return [];
    }
  }

  // 获取已保存的封面列表
  async getSavedCovers(): Promise<string[]> {
    try {
      const coversDir = `${this.getContext().filesDir}/LxMusic/Covers`;
      
      // 确保目录存在
      await this.ensureDirectoryExists(coversDir);
      
      const names: string[] = fs.listFileSync(coversDir);
      const files: string[] = [];
      for (let i = 0; i < names.length; i++) {
        const name = names[i];
        if (this.isImageFile(name)) {
          files.push(name);
        }
      }
      
      return files;
    } catch (err) {
      hilog.error(DOMAIN, TAG, '获取已保存封面列表失败: %{public}s', JSON.stringify(err));
      return [];
    }
  }

  // 检查是否为图片文件
  private isImageFile(fileName: string): boolean {
    const lowerName = fileName.toLowerCase();
    return lowerName.endsWith('.jpg') || 
           lowerName.endsWith('.jpeg') || 
           lowerName.endsWith('.png') || 
           lowerName.endsWith('.gif') || 
           lowerName.endsWith('.webp');
  }

  // 删除保存的歌词
  async deleteLyricFile(fileName: string): Promise<boolean> {
    try {
      const filePath = `${this.getContext().filesDir}/LxMusic/Lyrics/${fileName}`;
      await fs.unlink(filePath);
      hilog.info(DOMAIN, TAG, '删除歌词文件: %{public}s', fileName);
      return true;
    } catch (err) {
      hilog.error(DOMAIN, TAG, '删除歌词文件失败: %{public}s', JSON.stringify(err));
      return false;
    }
  }

  // 删除保存的封面
  async deleteCoverFile(fileName: string): Promise<boolean> {
    try {
      const filePath = `${this.getContext().filesDir}/LxMusic/Covers/${fileName}`;
      await fs.unlink(filePath);
      hilog.info(DOMAIN, TAG, '删除封面文件: %{public}s', fileName);
      return true;
    } catch (err) {
      hilog.error(DOMAIN, TAG, '删除封面文件失败: %{public}s', JSON.stringify(err));
      return false;
    }
  }
}

// 导出单例
export const mediaSaveService = MediaSaveService.getInstance();
