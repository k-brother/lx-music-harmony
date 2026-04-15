/**
 * 全局 HTTP 唯一入口：业务与音乐源请 `import { ... } from '../core/network/http'`
 * 统一使用 HttpClient，支持 Promise + cancel
 */
export { withQuery, flattenHeaders } from './HttpShared';

export { HttpClient, httpClient, httpRequest, httpGet, httpPost, checkNetworkConnection } from './HttpClient';
export type { HttpRequestConfig, HttpResponse, HttpTask } from './HttpClient';

export { parseHttpBodyJson } from './parseHttpBodyJson';
