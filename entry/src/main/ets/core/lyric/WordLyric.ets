/**
 * 逐字歌词解析
 *
 * 各源的逐字歌词长得很像，但只有「行头 + 逐字标记」这一个共同结构：
 * - 酷狗（kg）：`[mm:ss.mmm]<起始ms,时长ms>字<起始ms,时长ms>字...`（krc 转来的，已去掉第三个字段）
 * - 酷我（kw）：`[mm:ss.xx]<起始,时长>字...`（lrcx=1 通道返回）
 * - 网易云（wy）：`[起始ms,时长ms](起始ms,时长ms,0)字(起始ms,时长ms,0)字...`（yrc）
 *
 * 三个源的逐字时间有一个坑：有的是**相对行首**的偏移（酷我/洛雪自家的 lxlyric），
 * 有的是**绝对时间**（krc/yrc）。这里用「第一个字的时间是否不小于行首时间」判断，
 * 两种格式都能吃（行首为 0 时两种解释结果一致，不会误判）。
 */

/** 一行歌词里的一个字（或一个词） */
export interface LyricWord {
  text: string;
  /** 绝对开始时间（秒） */
  startSec: number;
  /** 持续时长（秒），可能为 0（源里没给时长） */
  durationSec: number;
}

/** 逐字歌词的一行 */
export interface WordLyricLine {
  /** 行开始时间（秒） */
  timeSec: number;
  words: LyricWord[];
}

/** 行头：`[mm:ss.xx]` / `[mm:ss.xxx]` / `[起始ms,时长ms]` */
const LINE_HEAD_EXP: RegExp = /^\[(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?\]|^\[(\d+),(\d+)\]/;
/** 逐字标记：`<起始,时长>` / `<起始,时长,0>` / `(起始,时长,0)` */
const WORD_TAG_EXP: RegExp = /[<(](\d+),(-?\d+)(?:,-?\d+)?[>)]/g;

/** 行头时间 → 毫秒；解析不出返回 -1 */
function readLineStartMs(line: string): number {
  const match = LINE_HEAD_EXP.exec(line);
  if (!match) {
    return -1;
  }
  // 形式一：mm:ss(.xx|.xxx)
  if (match[1] !== undefined) {
    const minutes: number = parseInt(match[1], 10);
    const seconds: number = parseInt(match[2], 10);
    const fraction: string = match[3] !== undefined ? match[3] : '0';
    // 两位按百分秒、三位按毫秒（与 LRC 习惯一致）
    const ms: number = fraction.length === 1 ? parseInt(fraction, 10) * 100
      : (fraction.length === 2 ? parseInt(fraction, 10) * 10 : parseInt(fraction, 10));
    return minutes * 60000 + seconds * 1000 + ms;
  }
  // 形式二：起始毫秒
  return parseInt(match[4], 10);
}

/**
 * 解析逐字歌词。
 * 只保留「有逐字标记且文字不为空」的行；一行里有几个字就返回几个字。
 */
export function parseWordLyric(lxlyric: string | null | undefined): WordLyricLine[] {
  const text: string = lxlyric ?? '';
  if (text.length === 0) {
    return [];
  }
  const result: WordLyricLine[] = [];
  const rawLines: string[] = text.split(/\r\n|\r|\n/);
  for (let i = 0; i < rawLines.length; i++) {
    const raw: string = rawLines[i].trim();
    if (raw.length === 0) {
      continue;
    }
    const lineStartMs: number = readLineStartMs(raw);
    if (lineStartMs < 0) {
      continue;
    }
    const parsed = parseWordsOfLine(stripLineHeads(raw), lineStartMs);
    if (parsed.length === 0) {
      continue;
    }
    result.push({ timeSec: lineStartMs / 1000, words: parsed });
  }
  result.sort((a: WordLyricLine, b: WordLyricLine): number => a.timeSec - b.timeSec);
  return result;
}

/** 去掉行首所有 `[..]`（歌词行可能挂多个时间戳），剩下的才是逐字内容 */
function stripLineHeads(line: string): string {
  let body: string = line;
  const headExp: RegExp = /^\s*\[[^\]]*\]/;
  let guard: number = 0;
  while (headExp.test(body) && guard < 8) {
    body = body.replace(headExp, '');
    guard += 1;
  }
  return body;
}

/**
 * 解析一行里的逐字标记。
 * `body` 是去掉行头之后的剩余内容（仍带标记），`lineStartMs` 用来判断标记是绝对时间还是行内偏移。
 */
function parseWordsOfLine(body: string, lineStartMs: number): LyricWord[] {
  const starts: number[] = [];
  const durations: number[] = [];
  WORD_TAG_EXP.lastIndex = 0;
  let match: RegExpExecArray | null = WORD_TAG_EXP.exec(body);
  while (match !== null) {
    starts.push(parseInt(match[1], 10));
    durations.push(parseInt(match[2], 10));
    match = WORD_TAG_EXP.exec(body);
  }
  if (starts.length === 0) {
    return [];
  }

  // 绝对时间 vs 行内偏移：见文件头说明。
  // 用「首个字的时间是否达到行首时间的一半」判断，比严格比较更耐源侧的小偏移
  // （有些源把行首给成第一个字的下一拍，严格比较会误判成相对偏移，整行时间就全错了）。
  const isAbsolute: boolean = lineStartMs === 0 || starts[0] * 2 >= lineStartMs;
  const segments: string[] = splitByWordTags(body, starts.length);
  const words: LyricWord[] = [];
  for (let i = 0; i < starts.length; i++) {
    const wordText: string = i < segments.length ? segments[i] : '';
    if (wordText.length === 0) {
      continue;
    }
    const startMs: number = isAbsolute ? starts[i] : lineStartMs + starts[i];
    const durationMs: number = durations[i] > 0 ? durations[i] : 0;
    words.push({
      text: wordText,
      startSec: startMs / 1000,
      durationSec: durationMs / 1000,
    });
  }
  return words;
}

/** 按逐字标记切出每个标记后面跟着的文字（标记本身不保留） */
function splitByWordTags(body: string, expectedCount: number): string[] {
  const tagStarts: number[] = [];
  const tagEnds: number[] = [];
  WORD_TAG_EXP.lastIndex = 0;
  let match: RegExpExecArray | null = WORD_TAG_EXP.exec(body);
  while (match !== null) {
    tagStarts.push(match.index);
    tagEnds.push(WORD_TAG_EXP.lastIndex);
    match = WORD_TAG_EXP.exec(body);
  }
  const segments: string[] = [];
  for (let i = 0; i < tagEnds.length; i++) {
    const from: number = tagEnds[i];
    const to: number = i + 1 < tagStarts.length ? tagStarts[i + 1] : body.length;
    segments.push(body.substring(from, to));
  }
  while (segments.length > expectedCount) {
    segments.pop();
  }
  return segments;
}

/**
 * 当前时刻已经唱到第几个字（返回值含义：0 = 还没开始唱，n = 前 n 个字已唱完）。
 * 传入 null 或没有逐字数据时返回 -1，调用方据此走普通歌词渲染。
 */
export function playedWordCount(line: WordLyricLine | null, positionSec: number): number {
  if (!line || line.words.length === 0) {
    return -1;
  }
  let count: number = 0;
  for (let i = 0; i < line.words.length; i++) {
    if (positionSec >= line.words[i].startSec) {
      count += 1;
    } else {
      break;
    }
  }
  return count;
}
