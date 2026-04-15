declare module 'libquickjs_loader.so' {
  export interface QuickJSLoaderModule {
    loadQuickJS(path: string): boolean;
    loadScript(script: string): string;
    callJS(action: string, data: string): string;
    unload(): void;
  }

  const quickjsLoader: QuickJSLoaderModule;
  export default quickjsLoader;
}

declare module 'libquickjs_napi.so' {
  export interface QuickJSNapiModule {
    loadScript(script: string): string;
    callJS(action: string, data: string): string;
    destroy(): void;
  }

  const quickjsNapi: QuickJSNapiModule;
  export default quickjsNapi;
}
