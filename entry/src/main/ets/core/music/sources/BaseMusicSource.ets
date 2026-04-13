/**
 * HTTP 工具基类：统一走 core `httpClient`。
 * 业务契约见 {@link IMusicSource} / {@link AbstractMusicSource}；各平台实现见 `kw/KuwoMusicSource` 等同目录入口。
 */

import hilog from '@ohos.hilog';
import { httpClient, type HttpRequestConfig } from '../../../core/network/http';

const DOMAIN: number = 0x0001;

/** 子类 HTTP 调用可选参数 */
export interface SourceHttpOptions {
  headers?: Record<string, string>;
  timeout?: number;
}

export abstract class BaseMusicSource {
  protected abstract readonly logTag: string;

  public constructor() {
    // 需 public：工厂 `new XxxMusicSource()` 在 ArkTS 中不可调用 `protected` 基类构造
  }

  protected info(message: string): void {
    hilog.info(DOMAIN, this.logTag, message);
  }

  protected warn(message: string): void {
    hilog.warn(DOMAIN, this.logTag, message);
  }

  protected error(message: string): void {
    hilog.error(DOMAIN, this.logTag, message);
  }

  /** GET JSON，单次请求不重试（由各源自身策略决定是否再包一层） */
  protected async fetchJson<T>(url: string, cfg: HttpRequestConfig = {}): Promise<T> {
    const merged: HttpRequestConfig = {
      method: 'GET',
      responseType: 'json',
      retryCount: 0,
      loggingEnabled: true,
      headers: cfg.headers,
      params: cfg.params,
      data: cfg.data,
      timeout: cfg.timeout,
    };
    const resp = await httpClient.request<T>(url, merged);
    return resp.data;
  }

  /** 任意方法请求，返回 ArkTS 友好后的 data */
  protected async fetchData<T>(url: string, cfg: HttpRequestConfig = {}): Promise<T> {
    const mergedCfg: HttpRequestConfig = {
      method: cfg.method,
      headers: cfg.headers,
      header: cfg.header,
      params: cfg.params,
      data: cfg.data,
      timeout: cfg.timeout,
      responseType: cfg.responseType,
      retryCount: 0,
      loggingEnabled: true,
    };
    const resp = await httpClient.request<T>(url, mergedCfg);
    return resp.data;
  }
}
