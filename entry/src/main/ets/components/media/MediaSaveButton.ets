// 媒体保存按钮组件
// 用于保存歌词和封面的按钮

import hilog from '@ohos.hilog';
import { mediaSaveService, MusicInfo, SaveResult } from '../../service/MediaSaveService';
import { common } from '@kit.AbilityKit';

const DOMAIN: number = 0x0001;
const TAG: string = 'MediaSaveButton';

// 保存类型
export enum SaveType {
  LYRIC = 'lyric',
  COVER = 'cover',
  BOTH = 'both'
}

// 组件属性
export interface MediaSaveButtonProps {
  musicInfo: MusicInfo;
  lyricContent?: string;
  imageUrl?: string;
  saveType?: SaveType;
  onSaveComplete?: (result: SaveResult) => void;
  onSaveError?: (error: string) => void;
}

@Component
export struct MediaSaveButton {
  // 属性
  @Prop musicInfo: MusicInfo;
  @Prop lyricContent?: string;
  @Prop imageUrl?: string;
  @Prop saveType: SaveType = SaveType.BOTH;
  @Prop onSaveComplete?: (result: SaveResult) => void;
  @Prop onSaveError?: (error: string) => void;

  // 状态
  @State isSaving: boolean = false;
  @State saveResult: SaveResult | null = null;
  @State errorMessage: string = '';

  // 生命周期
  aboutToAppear() {
    // 设置服务上下文
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      mediaSaveService.setContext(context);
    } catch (err) {
      hilog.error(DOMAIN, TAG, '设置服务上下文失败: %{public}s', JSON.stringify(err));
    }
  }

  // 保存媒体
  async saveMedia(): Promise<void> {
    if (this.isSaving) {
      return;
    }

    this.isSaving = true;
    this.saveResult = null;
    this.errorMessage = '';

    try {
      let result: SaveResult | null = null;

      switch (this.saveType) {
        case SaveType.LYRIC:
          result = await this.saveLyric();
          break;
        case SaveType.COVER:
          result = await this.saveCover();
          break;
        case SaveType.BOTH:
          result = await this.saveBoth();
          break;
      }

      if (result) {
        this.saveResult = result;
        
        if (result.success) {
          hilog.info(DOMAIN, TAG, '保存成功: %{public}s', result.message);
          if (this.onSaveComplete) {
            this.onSaveComplete(result);
          }
        } else {
          this.errorMessage = result.error || result.message;
          hilog.error(DOMAIN, TAG, '保存失败: %{public}s', this.errorMessage);
          if (this.onSaveError) {
            this.onSaveError(this.errorMessage);
          }
        }
      }
    } catch (err) {
      const errorMsg = err instanceof Error ? err.message : JSON.stringify(err);
      this.errorMessage = errorMsg;
      hilog.error(DOMAIN, TAG, '保存过程发生错误: %{public}s', errorMsg);
      if (this.onSaveError) {
        this.onSaveError(errorMsg);
      }
    } finally {
      this.isSaving = false;
    }
  }

  // 保存歌词
  private async saveLyric(): Promise<SaveResult> {
    if (!this.lyricContent) {
      return {
        success: false,
        message: '歌词内容为空'
      };
    }

    return await mediaSaveService.saveLyricToFile(this.musicInfo, this.lyricContent);
  }

  // 保存封面
  private async saveCover(): Promise<SaveResult> {
    if (!this.imageUrl) {
      return {
        success: false,
        message: '图片URL为空'
      };
    }

    return await mediaSaveService.saveCoverToFile(this.musicInfo, this.imageUrl);
  }

  // 同时保存歌词和封面
  private async saveBoth(): Promise<SaveResult> {
    const results: SaveResult[] = [];
    
    // 保存歌词
    if (this.lyricContent) {
      const lyricResult = await mediaSaveService.saveLyricToFile(this.musicInfo, this.lyricContent);
      results.push(lyricResult);
    }
    
    // 保存封面
    if (this.imageUrl) {
      const coverResult = await mediaSaveService.saveCoverToFile(this.musicInfo, this.imageUrl);
      results.push(coverResult);
    }
    
    // 检查结果
    const successCount = results.filter(r => r.success).length;
    const totalCount = results.length;
    
    if (totalCount === 0) {
      return {
        success: false,
        message: '没有可保存的内容'
      };
    }
    
    if (successCount === totalCount) {
      return {
        success: true,
        message: `成功保存 ${successCount} 项内容`,
        filePath: results[0].filePath // 返回第一个文件的路径
      };
    } else {
      return {
        success: false,
        message: `保存了 ${successCount}/${totalCount} 项内容`,
        error: '部分保存失败'
      };
    }
  }

  // 获取按钮文本
  private getButtonText(): string {
    if (this.isSaving) {
      return '保存中...';
    }
    
    switch (this.saveType) {
      case SaveType.LYRIC:
        return '保存歌词';
      case SaveType.COVER:
        return '保存封面';
      case SaveType.BOTH:
        return '保存歌词和封面';
      default:
        return '保存';
    }
  }

  // 获取按钮图标
  private getButtonIcon(): Resource {
    if (this.isSaving) {
      return $r('sys.symbol.arrow_down_circle');
    }
    
    switch (this.saveType) {
      case SaveType.LYRIC:
        return $r('sys.symbol.textformat');
      case SaveType.COVER:
        return $r('sys.symbol.square_and_arrow_down');
      case SaveType.BOTH:
        return $r('sys.symbol.square_and_arrow_down');
      default:
        return $r('sys.symbol.square_and_arrow_down');
    }
  }

  // 构建按钮
  @Builder
  BuildButton() {
    Button(this.getButtonText())
      .width(120)
      .height(40)
      .fontSize(14)
      .fontColor('#FFFFFF')
      .backgroundColor(this.isSaving ? '#999999' : '#2196F3')
      .borderRadius(8)
      .enabled(!this.isSaving)
      .onClick(() => {
        this.saveMedia();
      })
  }

  // 构建结果提示
  @Builder
  BuildResult() {
    if (this.saveResult) {
      Column() {
        Text(this.saveResult.success ? '保存成功' : '保存失败')
          .fontSize(12)
          .fontColor(this.saveResult.success ? '#4CAF50' : '#F44336')
          .margin({ top: 8 })
        
        if (this.saveResult.message) {
          Text(this.saveResult.message)
            .fontSize(10)
            .fontColor('#666666')
            .margin({ top: 4 })
            .maxLines(2)
        }
        
        if (this.saveResult.filePath) {
          Text(`路径: ${this.saveResult.filePath}`)
            .fontSize(9)
            .fontColor('#999999')
            .margin({ top: 2 })
            .maxLines(1)
        }
      }
    }
  }

  // 构建错误提示
  @Builder
  BuildError() {
    if (this.errorMessage) {
      Text(this.errorMessage)
        .fontSize(11)
        .fontColor('#F44336')
        .margin({ top: 8 })
        .maxLines(2)
    }
  }

  build() {
    Column() {
      // 保存按钮
      this.BuildButton()
      
      // 保存结果
      this.BuildResult()
      
      // 错误信息
      this.BuildError()
    }
    .width('100%')
    .padding(8)
  }
}