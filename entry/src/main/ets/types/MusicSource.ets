/**
 * 统一音乐源类型定义
 * 所有音乐源相关类型应从此处导入
 */

// 音乐源类型
export type MusicSource = 'kw' | 'kg' | 'tx' | 'wy' | 'mg' | 'all';

// 所有支持的源列表（不含 all）
export const SUPPORTED_SOURCES: MusicSource[] = [
  'kw', 'kg', 'tx', 'wy', 'mg',
];

// 音乐源信息
export interface SourceInfo {
  id: MusicSource;
  name: string;
}


