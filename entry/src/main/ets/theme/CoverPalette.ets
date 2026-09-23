/**
 * 封面占位渐变色板
 *
 * 榜单卡片、歌单卡片在没有封面图时用「按 id 稳定取色」的渐变块兜底，
 * 保证同一张榜/歌单每次进来颜色一致、不同榜之间可区分。
 * 色板与取色算法集中在这里，避免各处各写一份调色板。
 */
export class CoverPalette {
  /** 品牌红系起始色（取色失败时的兜底） */
  private static readonly PAIRS: string[][] = [
    ['#E63946', '#B5171F'],
    ['#F2845C', '#C9552E'],
    ['#5C7CFA', '#3B54B8'],
    ['#2FA36B', '#1C7248'],
    ['#8E5CF2', '#5F35B8'],
    ['#E0A33B', '#B27322'],
  ];

  /** 兜底色（品牌红） */
  static defaultPair(): string[] {
    return CoverPalette.PAIRS[0];
  }

  /** 全部色板（顺序即取色顺序） */
  static pairs(): string[][] {
    return CoverPalette.PAIRS;
  }

  /**
   * 按任意稳定 key（如 `source__id`）取一组渐变起止色。
   * 同一 key 永远得到同一组颜色；空 key 返回品牌红兜底。
   */
  static pairFor(key: string): string[] {
    if (key.length === 0) {
      return CoverPalette.defaultPair();
    }
    let hash = 0;
    for (let i = 0; i < key.length; i++) {
      hash = (hash * 31 + key.charCodeAt(i)) % 9973;
    }
    return CoverPalette.PAIRS[hash % CoverPalette.PAIRS.length];
  }
}
