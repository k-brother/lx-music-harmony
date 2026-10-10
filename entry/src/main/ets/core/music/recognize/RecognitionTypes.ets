/**
 * 听歌识曲：领域类型与错误定义
 *
 * 移植自 RzdMusic 的 recognize 模块，按本仓约定精简：
 * - 只保留酷狗单引擎所需的形状（无多引擎 Group/Report）
 * - 记录持久化用普通接口而非 class record 互转
 */

/** 一条识别结果（trackId 形如 "kg:<hash>"，hash 为 32 位十六进制时可直接走酷狗取链） */
export interface RecognizedSong {
  id: string;
  title: string;
  artist: string;
  album: string;
  coverUrl: string;
  /** 识别来源标识，当前固定 'kg' */
  source: string;
  /** 酷狗文件 hash（可能为空，为空时只能用关键词回退搜索播放） */
  hash: string;
  /** 服务端曲目标识（kg:hash 或 kg:songid） */
  trackId: string;
  recognizedAt: number;
}

/** 识别流程错误基类（页面按 name 区分兜底文案） */
export class RecognitionError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'RecognitionError';
  }
}

/** 酷狗指纹接口网络层失败（超时 / 非 2xx / 返回体异常） */
export class RecognitionNetworkError extends RecognitionError {
  constructor(message: string) {
    super(message);
    this.name = 'RecognitionNetworkError';
  }
}

/** 麦克风权限未授予 */
export class MicPermissionError extends RecognitionError {
  constructor(message: string) {
    super(message);
    this.name = 'MicPermissionError';
  }
}

/** 用户主动停止采集 */
export class MicCancelledError extends RecognitionError {
  constructor() {
    super('mic capture cancelled');
    this.name = 'MicCancelledError';
  }
}
