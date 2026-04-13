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

// 音乐源名称映射
export const SOURCE_NAMES: Record<MusicSource, string> = {
  'kw': '酷我音乐',
  'kg': '酷狗音乐',
  'tx': 'QQ音乐',
  'wy': '网易云音乐',
  'mg': '咪咕音乐',
  'all': '全部',
};

// 判断是否为有效音乐源
export function isValidSource(source: string): boolean {
  return source === 'kw' || source === 'kg' || source === 'tx' ||
         source === 'wy' || source === 'mg' || source === 'all';
}
