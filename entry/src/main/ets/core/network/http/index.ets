/**
 * 全局 HTTP 唯一入口：业务与音乐源请 `import { ... } from '../core/network/http'`
 * 统一使用 HttpClient，支持 Promise + cancel
 */
export { withQuery, flattenHeaders, parseHttpBodyJson, httpResponseBody } from './HttpShared';
export type { HttpResponseBodyHolder } from './HttpShared';

export {
  HttpClient,
  httpClient,
  httpRequest,
  httpRequestBinary,
  httpGet,
  httpPost,
  checkNetworkConnection,
} from './HttpClient';
export type { HttpRequestConfig, HttpResponse, HttpTask } from './HttpClient';
