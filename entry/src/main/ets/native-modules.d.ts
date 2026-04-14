declare module 'libquickjs_loader.so' {
  interface QuickJSLoaderModule {
    loadQuickJS(path: string): boolean;
    loadScript(script: string): string;
    callJS(action: string, data: string): string;
    unload(): void;
  }
  const module: QuickJSLoaderModule;
  export default module;
}

declare module 'libquickjs_napi.so' {
  interface QuickJSNapiModule {
    loadScript(script: string): string;
    callJS(action: string, data: string): string;
    destroy(): void;
  }
  const module: QuickJSNapiModule;
  export default module;
}
