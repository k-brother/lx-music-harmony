/**
 * QuickJS NAPI Native Module Interface
 *
 * This module provides TypeScript bindings for the native QuickJS engine.
 * It enables execution of JavaScript plugin code within the HarmonyOS app.
 */

import { hilog } from '@kit.PerformanceAnalysisKit';
import quickjsLoaderSo from 'libquickjs_loader.so';
import quickjsNapiSo from 'libquickjs_napi.so';
import { utf8Decode } from '../../utils/TextCodec';
import type { common } from '@kit.AbilityKit';

// QuickJS NAPI native module interface
// These methods are implemented in C++ and exposed via NAPI
interface QuickJSNAPI {
  /**
   * Load a JavaScript script into the QuickJS engine
   * @param script The JavaScript source code to execute
   * @returns Empty string on success, error message on failure
   */
  loadScript(script: string): string;

  /**
   * Call a JavaScript function in the loaded script context
   * @param action The action name to invoke
   * @param data JSON stringified data to pass to the action
   * @returns Result string from the JavaScript function
   */
  callJS(action: string, data: string): string;

  /**
   * Destroy the QuickJS context and free resources
   */
  destroy(): void;
}

interface QuickJSLoaderNAPI {
  loadQuickJS(path: string): boolean;
  loadScript(script: string): string;
  callJS(action: string, data: string): string;
  unload(): void;
}

function formatErrorMessage(err: Object): string {
  const e = err as Error;
  if (e && e.message && e.message.length > 0) {
    return e.message;
  }
  const text = String(err);
  if (text && text !== '[object Object]') {
    return text;
  }
  const json = JSON.stringify(err);
  if (json && json !== '{}') {
    return json;
  }
  return 'unknown error object';
}

// Module tag for logging
const MODULE_TAG = 'QuickJSNAPI';
const DOMAIN = 0xFF01;

// Native module instance - loaded via dlopen
let quickjsModule: QuickJSNAPI | null = null;
let isInitialized = false;

// Loaded script content for re-initialization
let loadedPreloadScript: string = '';
let abilityContext: common.UIAbilityContext | null = null;

export function setQuickJSContext(context: common.UIAbilityContext): void {
  abilityContext = context;
}

function getQuickJSContext(): common.UIAbilityContext {
  if (abilityContext) {
    return abilityContext;
  }
  throw new Error('QuickJS context not set');
}

// Loader module reference for calling NAPI functions
let loaderModule: QuickJSNAPI | null = null;

// Native function type definitions
type LoadScriptFn = (script: string) => string;
type CallJSFn = (action: string, data: string) => string;
type DestroyFn = () => void;

// Function handles from native library
let loadScriptFn: LoadScriptFn | null = null;
let callJSFn: CallJSFn | null = null;
let destroyFn: DestroyFn | null = null;

class QuickJSFunctionAdapter implements QuickJSNAPI {
  loadScript(script: string): string {
    hilog.info(DOMAIN, MODULE_TAG, 'QuickJS loadScript called, length: %{public}d', script.length);
    if (loadScriptFn) {
      return loadScriptFn(script);
    }
    return '';
  }

  callJS(action: string, data: string): string {
    hilog.info(DOMAIN, MODULE_TAG, 'QuickJS callJS called: %{public}s', action);
    if (callJSFn) {
      return callJSFn(action, data);
    }
    return '{"error":"stub"}';
  }

  destroy(): void {
    hilog.info(DOMAIN, MODULE_TAG, 'QuickJS destroy called');
    if (destroyFn) {
      destroyFn();
    }
  }
}

/**
 * Load the native library and get the QuickJS NAPI interface
 */
function loadNativeModule(): boolean {
  hilog.info(DOMAIN, MODULE_TAG, 'Loading QuickJS native module');

  // 1) 优先使用外部注入的 loader
  if (loaderModule !== null) {
    hilog.info(DOMAIN, MODULE_TAG, 'Using injected loaderModule');
    loadScriptFn = loaderModule.loadScript;
    callJSFn = loaderModule.callJS;
    destroyFn = loaderModule.destroy;
    return true;
  }

  // 2) 直接使用静态导入的 quickjs_napi.so
  const directNapi = quickjsNapiSo as QuickJSNAPI;
  if (directNapi &&
      typeof directNapi.loadScript === 'function' &&
      typeof directNapi.callJS === 'function' &&
      typeof directNapi.destroy === 'function') {
    hilog.info(DOMAIN, MODULE_TAG, 'Using direct quickjs_napi.so module');
    loadScriptFn = (script: string): string => directNapi.loadScript(script);
    callJSFn = (action: string, data: string): string => directNapi.callJS(action, data);
    destroyFn = (): void => directNapi.destroy();
    return true;
  }

  // 3) 通过 quickjs_loader.so 按路径加载 quickjs_napi.so
  const loaderSo = quickjsLoaderSo as QuickJSLoaderNAPI;
  if (loaderSo && typeof loaderSo.loadQuickJS === 'function') {
    const context = getQuickJSContext();
    const bundleCodeDir = context.bundleCodeDir;
    const candidates: string[] = [
      `${bundleCodeDir}/libs/arm64-v8a/libquickjs_napi.so`,
      `${bundleCodeDir}/libs/libquickjs_napi.so`,
      `${bundleCodeDir}/libs/arm64-v8a/liblibquickjs_napi.so`,
      `${bundleCodeDir}/libs/liblibquickjs_napi.so`,
    ];
    for (let i = 0; i < candidates.length; i++) {
      const path = candidates[i];
      try {
        hilog.info(DOMAIN, MODULE_TAG, 'Loader trying path: %{public}s', path);
        if (loaderSo.loadQuickJS(path)) {
          hilog.info(DOMAIN, MODULE_TAG, 'Loader loaded quickjs_napi.so successfully');
          loadScriptFn = (script: string): string => loaderSo.loadScript(script);
          callJSFn = (action: string, data: string): string => loaderSo.callJS(action, data);
          destroyFn = (): void => loaderSo.unload();
          return true;
        }
      } catch (e) {
        hilog.warn(DOMAIN, MODULE_TAG, 'Loader path failed: %{public}s', formatErrorMessage(e as Object));
      }
    }
  }

  hilog.warn(DOMAIN, MODULE_TAG, 'Native QuickJS module not available');
  return false;
}

/**
 * Initialize the QuickJS native module
 */
export function initQuickJS(): boolean {
  if (isInitialized && quickjsModule) {
    hilog.info(DOMAIN, MODULE_TAG, 'QuickJS already initialized');
    return true;
  }

  hilog.info(DOMAIN, MODULE_TAG, 'Initializing QuickJS native module');

  // Try to load native module
  if (!loadNativeModule()) {
    hilog.error(DOMAIN, MODULE_TAG, 'Failed to load QuickJS native module');
    return false;
  }

  try {
    quickjsModule = new QuickJSFunctionAdapter();

    isInitialized = true;
    hilog.info(DOMAIN, MODULE_TAG, 'QuickJS initialized successfully');
    return true;
  } catch (e) {
    hilog.error(DOMAIN, MODULE_TAG, 'Exception during QuickJS init: %{public}s', formatErrorMessage(e as Object));
    return false;
  }
}

/**
 * Load the preload script (user-api-preload.js) into QuickJS
 * This sets up the lx global object and native callbacks
 */
export async function loadPreloadScript(): Promise<boolean> {
  if (!isInitialized || !quickjsModule) {
    hilog.error(DOMAIN, MODULE_TAG, 'QuickJS not initialized');
    return false;
  }

  try {
    const context = getQuickJSContext();
    const rawMgr = context.resourceManager;
    if (!rawMgr || typeof rawMgr.getRawFileContent !== 'function') {
      hilog.warn(DOMAIN, MODULE_TAG, 'ResourceManager.getRawFileContent is unavailable');
      return false;
    }
    const preloadBytes = await rawMgr.getRawFileContent('user-api-preload.js');
    if (!preloadBytes || preloadBytes.length === 0) {
      hilog.warn(DOMAIN, MODULE_TAG, 'user-api-preload.js is empty');
      return false;
    }
    loadedPreloadScript = utf8Decode(preloadBytes);
    hilog.info(DOMAIN, MODULE_TAG, 'Preload script loaded, length: %{public}d', loadedPreloadScript.length);
    return loadedPreloadScript.length > 0;
  } catch (e) {
    hilog.error(DOMAIN, MODULE_TAG, 'Exception loading preload: %{public}s', formatErrorMessage(e as Object));
    return false;
  }
}

/**
 * Load JavaScript plugin source code
 * @param script The JavaScript source code from the plugin
 * @returns true if loaded successfully
 */
export function loadPluginScript(script: string): boolean {
  if (!isInitialized) {
    hilog.error(DOMAIN, MODULE_TAG, 'QuickJS not initialized');
    return false;
  }

  if (!quickjsModule) {
    hilog.error(DOMAIN, MODULE_TAG, 'QuickJS module not available');
    return false;
  }

  try {
    hilog.info(DOMAIN, MODULE_TAG, 'Loading plugin script, length: %{public}d', script.length);

    // First load the preload script
    if (loadedPreloadScript.length > 0) {
      const preloadResult = quickjsModule.loadScript(loadedPreloadScript);
      if (preloadResult && preloadResult.length > 0) {
        hilog.error(DOMAIN, MODULE_TAG, 'Failed to load preload: %{public}s', preloadResult);
        return false;
      }
    }

    // Then load the plugin script
    const result = quickjsModule.loadScript(script);
    if (result && result.length > 0) {
      hilog.error(DOMAIN, MODULE_TAG, 'Failed to load plugin script: %{public}s', result);
      return false;
    }

    hilog.info(DOMAIN, MODULE_TAG, 'Plugin script loaded successfully');
    return true;
  } catch (e) {
    hilog.error(DOMAIN, MODULE_TAG, 'Exception loading plugin script: %{public}s', formatErrorMessage(e as Object));
    return false;
  }
}

/**
 * Call a function in the JavaScript plugin context
 * @param action The action to perform (e.g., 'search', 'musicUrl', 'lyric')
 * @param data The data to pass to the action
 * @returns The result from the JavaScript plugin
 */
export function callPluginAction(action: string, data: string): string {
  if (!isInitialized) {
    hilog.error(DOMAIN, MODULE_TAG, 'QuickJS not initialized');
    return '';
  }

  if (!quickjsModule) {
    hilog.error(DOMAIN, MODULE_TAG, 'QuickJS module not available');
    return '';
  }

  try {
    hilog.debug(DOMAIN, MODULE_TAG, 'Calling action: %{public}s', action);
    const result = quickjsModule.callJS(action, data);
    return result ?? '';
  } catch (e) {
    hilog.error(DOMAIN, MODULE_TAG, 'Exception calling action: %{public}s', formatErrorMessage(e as Object));
    return '';
  }
}

/**
 * Destroy the QuickJS context and release resources
 */
export function destroyQuickJS(): void {
  if (!isInitialized) {
    return;
  }

  try {
    hilog.info(DOMAIN, MODULE_TAG, 'Destroying QuickJS');

    if (quickjsModule) {
      quickjsModule.destroy();
    }

    quickjsModule = null;
    isInitialized = false;
    loadedPreloadScript = '';

    hilog.info(DOMAIN, MODULE_TAG, 'QuickJS destroyed');
  } catch (e) {
    hilog.error(DOMAIN, MODULE_TAG, 'Exception destroying QuickJS: %{public}s', formatErrorMessage(e as Object));
  }
}





// Re-export types for external use
export type { QuickJSNAPI };