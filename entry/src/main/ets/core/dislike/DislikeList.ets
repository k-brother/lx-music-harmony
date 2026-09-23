/**
 * 不喜欢列表（屏蔽规则）
 *
 * 与安卓版语义对齐：规则是纯文本，一行一条，三种形式
 *   1) `歌名`            → 屏蔽该歌名（任意歌手）
 *   2) `歌名@歌手`       → 屏蔽该「歌名 + 歌手」组合
 *   3) `@歌手`           → 屏蔽该歌手
 * 匹配时统一转小写并 trim，避免大小写/空格差异导致漏判。
 *
 * 存储走统一的 StorageService（键 dislike.rules），与其它数据一致。
 */
import { hilog } from '@kit.PerformanceAnalysisKit';
import { getStorageService } from '../interfaces/IStorageService';

const TAG = 'DislikeList';
const DOMAIN = 0x0006;
/** 规则分隔符（与安卓版一致，用 @ 分隔歌名与歌手） */
const RULE_SPLIT = '@';
const STORAGE_KEY = 'dislike.rules';


class DislikeListImpl {
  private musicNames: Set<string> = new Set();
  private singerNames: Set<string> = new Set();
  private pairs: Set<string> = new Set();
  private rulesText: string = '';
  private loaded: boolean = false;

  /** 从存储加载（首次调用时读取，之后走内存缓存） */
  async load(): Promise<void> {
    if (this.loaded) {
      return;
    }
    try {
      const raw = await getStorageService().getString(STORAGE_KEY, '');
      this.applyRules(raw);
      this.loaded = true;
      hilog.info(DOMAIN, TAG, 'Loaded %{public}d rules', this.count());
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'load failed: %{public}s',
        err instanceof Error ? err.message : JSON.stringify(err));
    }
  }

  /** 规则条数 */
  count(): number {
    return this.musicNames.size + this.singerNames.size + this.pairs.size;
  }

  /** 判断一首歌是否被屏蔽 */
  isDisliked(name: string, singer: string): boolean {
    if (!this.loaded || this.count() === 0) {
      return false;
    }
    const n = normalize(name);
    const s = normalize(singer);
    if (n.length > 0 && this.musicNames.has(n)) {
      return true;
    }
    if (s.length > 0 && this.singerNames.has(s)) {
      return true;
    }
    if (n.length > 0 && s.length > 0 && this.pairs.has(`${n}${RULE_SPLIT}${s}`)) {
      return true;
    }
    return false;
  }

  /** 添加规则并持久化 */
  async add(name: string, singer: string): Promise<void> {
    const n = normalize(name);
    const s = normalize(singer);
    if (n.length === 0 && s.length === 0) {
      return;
    }
    const lines = this.rulesText.length > 0 ? this.rulesText.split('\n') : [];
    lines.push(`${n}${RULE_SPLIT}${s}`);
    await this.overwrite(lines.join('\n'));
  }

  /** 覆盖整份规则（导入/编辑用） */
  async overwrite(rules: string): Promise<void> {
    this.applyRules(rules);
    try {
      await getStorageService().setString(STORAGE_KEY, this.rulesText);
      hilog.info(DOMAIN, TAG, 'Saved %{public}d rules', this.count());
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'save failed: %{public}s',
        err instanceof Error ? err.message : JSON.stringify(err));
    }
  }

  /** 清空 */
  async clear(): Promise<void> {
    await this.overwrite('');
  }

  /** 解析规则文本到三个集合 */
  private applyRules(rules: string): void {
    this.musicNames.clear();
    this.singerNames.clear();
    this.pairs.clear();
    const kept: string[] = [];
    const raw = (rules ?? '').split('\n');
    for (let i = 0; i < raw.length; i++) {
      const line = raw[i].trim();
      if (line.length === 0) {
        continue;
      }
      const parts = line.split(RULE_SPLIT);
      const n = normalize(parts[0] ?? '');
      const s = normalize(parts.length > 1 ? parts[1] : '');
      if (n.length > 0 && s.length > 0) {
        const rule = `${n}${RULE_SPLIT}${s}`;
        if (!this.pairs.has(rule)) {
          this.pairs.add(rule);
          kept.push(rule);
        }
      } else if (n.length > 0) {
        if (!this.musicNames.has(n)) {
          this.musicNames.add(n);
          kept.push(n);
        }
      } else if (s.length > 0) {
        if (!this.singerNames.has(s)) {
          this.singerNames.add(s);
          kept.push(`${RULE_SPLIT}${s}`);
        }
      }
    }
    this.rulesText = kept.join('\n');
  }
}

function normalize(text: string): string {
  return (text ?? '').replace(/\s+/g, ' ').trim().toLowerCase();
}

export const dislikeList = new DislikeListImpl();
export default dislikeList;
