/**
 * 极简 WebDAV 客户端（备份目标需要的那几个动词）
 *
 * 设计取舍（对照 RzdMusic 的 WebDavBackupService）：
 * - 只支持 HTTP Basic 认证（Digest 先不做，NAS/网盘绝大多数两者都开）。
 * - 目录缺失自动 MKCOL 补建（RzdMusic 要求目录预存在，体验差，报错也难懂）。
 * - 上传带 If-None-Match: * —— 备份文件名含时间戳本就不会撞，再叠一层
 *   「绝不覆盖远端已有文件」的保护；412 明确报「远端已存在」而不是当失败。
 * - 文件名白名单校验（不允许路径分隔符），防止调用方把用户输入拼进 URL。
 * - 允许 http://（局域网 NAS 常见），但拒绝内嵌凭据与 query/fragment。
 */
import { httpClient } from '../http/HttpClient';
import { appLog as hilog } from '../../log/AppLogger';
import { base64Encode } from '../../../utils/CryptoUtils';

const DOMAIN: number = 0x0001;
const TAG: string = 'WebDavClient';

/** 连接/读取超时（备份文件很小，15s 足够；下载放宽到 30s） */
const TIMEOUT_MS: number = 15000;
const READ_TIMEOUT_MS: number = 30000;

/** 远端文件名的安全形态：不允许任何路径分隔符，扩展名限 json/enc */
const REMOTE_NAME_PATTERN: RegExp = /^[^/?#]+\.(json|enc)$/;

/** 连接目标（配置来自调用方，本模块不读设置） */
export interface WebDavTarget {
  /** 目录地址，如 https://nas.example.com/dav/lxmusic（不含文件名） */
  url: string;
  user: string;
  password: string;
}

/** PROPFIND 列出的一个远端文件 */
export interface WebDavEntry {
  /** 纯文件名（已 URL 解码） */
  name: string;
  /** 字节数；服务端没给就是 0 */
  size: number;
  /** 最后修改时间（毫秒）；服务端没给就是 0 */
  modifiedMs: number;
}

/**
 * 归一化并校验目录地址；不合法抛错。
 *
 * - 去掉首尾空白与末尾斜杠；
 * - 仅接受 http(s)（局域网 NAS 常用 http，不强制 https）；
 * - 拒绝 query/fragment 与内嵌凭据（这两种都会和我们自己的拼接/认证头打架）。
 */
export function normalizeWebDavUrl(raw: string): string {
  const url: string = raw.trim().replace(/\/+$/, '');
  if (!/^https?:\/\//i.test(url)) {
    throw new Error('WebDAV url must start with http(s)://');
  }
  if (/[?#]/.test(url)) {
    throw new Error('WebDAV url must not contain query or fragment');
  }
  if (/^https?:\/\/[^/]*@/i.test(url)) {
    throw new Error('WebDAV url must not embed credentials');
  }
  return url;
}

/** 认证头：有用户名就发 Basic；密码为空也发（部分服务端允许空密码账号） */
function authHeaders(target: WebDavTarget): Record<string, string> {
  const headers: Record<string, string> = {};
  if (target.user.length > 0) {
    headers['Authorization'] = 'Basic ' + base64Encode(`${target.user}:${target.password}`);
  }
  return headers;
}

function remoteUrl(target: WebDavTarget, name: string): string {
  if (!REMOTE_NAME_PATTERN.test(name)) {
    throw new Error(`unsafe remote file name: ${name}`);
  }
  return `${normalizeWebDavUrl(target.url)}/${encodeURIComponent(name)}`;
}

/** 统一错误映射：401/403 认证、412 已存在、其余带 HTTP 状态码 */
function fail(status: number, action: string): Error {
  if (status === 401 || status === 403) {
    return new Error(`WebDAV ${action} failed: auth rejected (HTTP ${status})`);
  }
  if (status === 412) {
    return new Error(`WebDAV ${action} aborted: remote file already exists (HTTP 412)`);
  }
  return new Error(`WebDAV ${action} failed: HTTP ${status}`);
}

/** PROPFIND 请求体：只取列目录需要的三个属性 */
const PROPFIND_BODY: string =
  '<?xml version="1.0" encoding="utf-8"?>' +
  '<propfind xmlns="DAV:"><prop><displayname/><getcontentlength/><getlastmodified/></prop></propfind>';

/** 目录不存在时补建（MKCOL 已存在返回 405，视为成功） */
async function ensureCollection(target: WebDavTarget): Promise<void> {
  const url: string = normalizeWebDavUrl(target.url);
  const headers: Record<string, string> = authHeaders(target);
  headers['Content-Type'] = 'application/xml; charset=utf-8';
  const probe = await httpClient.request<string>(url, {
    method: 'PROPFIND',
    headers: headers,
    data: PROPFIND_BODY,
    responseType: 'text',
    timeout: TIMEOUT_MS,
  });
  if (probe.status === 207) {
    return;
  }
  if (probe.status !== 404) {
    throw fail(probe.status, 'probe directory');
  }
  const mkcol = await httpClient.request<string>(url, {
    method: 'MKCOL',
    headers: authHeaders(target),
    responseType: 'text',
    timeout: TIMEOUT_MS,
  });
  if (mkcol.status === 201 || mkcol.status === 204 || mkcol.status === 405) {
    hilog.info(DOMAIN, TAG, 'collection ready: %{public}s', url);
    return;
  }
  throw fail(mkcol.status, 'create directory');
}

/** 上传文本内容（If-None-Match: *，绝不覆盖远端已有同名文件） */
export async function webDavUpload(target: WebDavTarget, name: string, content: string): Promise<void> {
  await ensureCollection(target);
  const headers: Record<string, string> = authHeaders(target);
  headers['Content-Type'] = 'application/json; charset=utf-8';
  headers['If-None-Match'] = '*';
  const response = await httpClient.request<string>(remoteUrl(target, name), {
    method: 'PUT',
    headers: headers,
    data: content,
    responseType: 'text',
    timeout: READ_TIMEOUT_MS,
  });
  if (response.status === 200 || response.status === 201 || response.status === 204) {
    return;
  }
  throw fail(response.status, 'upload');
}

/** 下载文本内容 */
export async function webDavDownload(target: WebDavTarget, name: string): Promise<string> {
  const response = await httpClient.request<string>(remoteUrl(target, name), {
    method: 'GET',
    headers: authHeaders(target),
    responseType: 'text',
    timeout: READ_TIMEOUT_MS,
  });
  if (response.status === 200) {
    return response.rawText;
  }
  throw fail(response.status, 'download');
}

/** 删除远端文件 */
export async function webDavDelete(target: WebDavTarget, name: string): Promise<void> {
  const response = await httpClient.request<string>(remoteUrl(target, name), {
    method: 'DELETE',
    headers: authHeaders(target),
    responseType: 'text',
    timeout: TIMEOUT_MS,
  });
  if (response.status === 200 || response.status === 202 || response.status === 204) {
    return;
  }
  throw fail(response.status, 'delete');
}

/**
 * 列目录（PROPFIND Depth:1），返回全部非集合文件。
 *
 * multistatus XML 没有现成解析器，手写最小提取：按 <...:response> 切块，
 * 块内取 href / getcontentlength / getlastmodified（命名空间前缀不假设）。
 */
export async function webDavList(target: WebDavTarget): Promise<WebDavEntry[]> {
  await ensureCollection(target);
  const headers: Record<string, string> = authHeaders(target);
  headers['Content-Type'] = 'application/xml; charset=utf-8';
  headers['Depth'] = '1';
  const response = await httpClient.request<string>(normalizeWebDavUrl(target.url), {
    method: 'PROPFIND',
    headers: headers,
    data: PROPFIND_BODY,
    responseType: 'text',
    timeout: TIMEOUT_MS,
  });
  if (response.status !== 207) {
    throw fail(response.status, 'list');
  }
  return parseMultistatus(response.rawText);
}

function tagText(block: string, localName: string): string {
  const pattern: RegExp = new RegExp(`<[^>]*:?${localName}[^>]*>([\\s\\S]*?)<\\/[^>]*:?${localName}>`);
  const match: RegExpMatchArray | null = block.match(pattern);
  return match === null ? '' : match[1].trim();
}

function parseMultistatus(xml: string): WebDavEntry[] {
  const entries: WebDavEntry[] = [];
  const blocks: string[] | null = xml.match(/<[^>]*:?response[^>]*>[\s\S]*?<\/[^>]*:?response>/g);
  if (blocks === null) {
    return entries;
  }
  for (let i: number = 0; i < blocks.length; i++) {
    const block: string = blocks[i];
    const href: string = tagText(block, 'href');
    if (href.length === 0 || href.endsWith('/')) {
      continue; // 目录自身与集合条目都不是文件
    }
    const rawName: string = href.split('/').pop() ?? '';
    let name: string = rawName;
    try {
      name = decodeURIComponent(rawName);
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'decode name failed: %{public}s', (e as Error).message);
    }
    const sizeText: string = tagText(block, 'getcontentlength');
    const modifiedText: string = tagText(block, 'getlastmodified');
    const size: number = sizeText.length > 0 ? parseInt(sizeText) : 0;
    const modifiedMs: number = modifiedText.length > 0 ? Date.parse(modifiedText) : 0;
    entries.push({ name: name, size: isNaN(size) ? 0 : size, modifiedMs: isNaN(modifiedMs) ? 0 : modifiedMs });
  }
  return entries;
}
