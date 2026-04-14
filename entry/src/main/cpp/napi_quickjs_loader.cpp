/**
 * QuickJS Native Loader Module
 *
 * This module handles loading the QuickJS native library from the application
 * sandbox at runtime using dlopen/dlsym.
 *
 * HarmonyOS 不支持从 ArkTS 直接 dlopen rawfile .so，
 * 因此需要一个 Loader 模块来完成这个工作。
 */

#include <node_api.h>
#include <string>
#include <cstdlib>
#include <cstring>
#include <dlfcn.h>
#include "hilog/log.h"

static constexpr char MODULE_NAME[] = "QuickJSLoader";
static constexpr unsigned int LOG_PRINT_ID = 0xFF00;

#define LOGI(fmt, ...) OH_LOG_INFO(LOG_APP, "%{public}s:" fmt, __FUNCTION__, ##__VA_ARGS__)
#define LOGW(fmt, ...) OH_LOG_WARN(LOG_APP, "%{public}s:" fmt, __FUNCTION__, ##__VA_ARGS__)
#define LOGE(fmt, ...) OH_LOG_ERROR(LOG_APP, "%{public}s:" fmt, __FUNCTION__, ##__VA_ARGS__)

// 保存已加载的模块句柄
static void* g_quickjsHandle = nullptr;
static bool g_quickjsLoaded = false;

// QuickJS 函数指针类型
typedef const char* (*LoadScriptFunc)(const char*);
typedef const char* (*CallJSFunc)(const char*, const char*);
typedef void (*DestroyFunc)();

// 函数指针
static LoadScriptFunc g_loadScript = nullptr;
static CallJSFunc g_callJS = nullptr;
static DestroyFunc g_destroy = nullptr;

/**
 * 加载 QuickJS 库并获取函数指针
 */
static bool loadQuickJSLibrary(const char* libraryPath) {
    if (g_quickjsLoaded && g_quickjsHandle) {
        LOGI("QuickJS library already loaded");
        return true;
    }

    LOGI("Loading QuickJS library from: %{public}s", libraryPath);

    // 使用 dlopen 加载库
    g_quickjsHandle = dlopen(libraryPath, RTLD_NOW);
    if (!g_quickjsHandle) {
        const char* err = dlerror();
        LOGE("Failed to dlopen QuickJS library: %{public}s", err ? err : "unknown error");
        return false;
    }

    // 使用 dlsym 获取函数指针
    g_loadScript = (LoadScriptFunc)dlsym(g_quickjsHandle, "napi_loadScript");
    g_callJS = (CallJSFunc)dlsym(g_quickjsHandle, "napi_callJS");
    g_destroy = (DestroyFunc)dlsym(g_quickjsHandle, "napi_destroy");

    if (!g_loadScript || !g_callJS || !g_destroy) {
        LOGE("Failed to dlsym QuickJS functions");
        dlclose(g_quickjsHandle);
        g_quickjsHandle = nullptr;
        return false;
    }

    g_quickjsLoaded = true;
    LOGI("QuickJS library loaded successfully");
    return true;
}

/**
 * NAPI 函数：设置 QuickJS 库路径并加载
 */
static napi_value LoadQuickJS(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value argv[1];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);

    if (argc < 1) {
        napi_throw_type_error(env, nullptr, "Expected library path argument");
        return nullptr;
    }

    size_t path_len;
    napi_get_value_string_utf8(env, argv[0], nullptr, 0, &path_len);
    char* path = new char[path_len + 1];
    napi_get_value_string_utf8(env, argv[0], path, path_len + 1, &path_len);

    LOGI("LoadQuickJS called with path: %{public}s", path);

    bool success = loadQuickJSLibrary(path);
    delete[] path;

    napi_value result;
    napi_get_boolean(env, success, &result);
    return result;
}

/**
 * NAPI 函数：调用 QuickJS loadScript
 */
static napi_value CallLoadScript(napi_env env, napi_callback_info info) {
    if (!g_quickjsLoaded || !g_loadScript) {
        napi_throw_error(env, nullptr, "QuickJS library not loaded");
        return nullptr;
    }

    size_t argc = 1;
    napi_value argv[1];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);

    if (argc < 1) {
        napi_throw_type_error(env, nullptr, "Expected script argument");
        return nullptr;
    }

    size_t script_len;
    napi_get_value_string_utf8(env, argv[0], nullptr, 0, &script_len);
    char* script = new char[script_len + 1];
    napi_get_value_string_utf8(env, argv[0], script, script_len + 1, &script_len);

    const char* error = g_loadScript(script);
    delete[] script;

    napi_value result;
    if (error && strlen(error) > 0) {
        napi_create_string_utf8(env, error, NAPI_AUTO_LENGTH, &result);
    } else {
        napi_create_string_utf8(env, "", NAPI_AUTO_LENGTH, &result);
    }
    return result;
}

/**
 * NAPI 函数：调用 QuickJS callJS
 */
static napi_value CallQuickJS(napi_env env, napi_callback_info info) {
    if (!g_quickjsLoaded || !g_callJS) {
        napi_throw_error(env, nullptr, "QuickJS library not loaded");
        return nullptr;
    }

    size_t argc = 2;
    napi_value argv[2];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);

    if (argc < 2) {
        napi_throw_type_error(env, nullptr, "Expected action and data arguments");
        return nullptr;
    }

    size_t action_len, data_len;
    napi_get_value_string_utf8(env, argv[0], nullptr, 0, &action_len);
    napi_get_value_string_utf8(env, argv[1], nullptr, 0, &data_len);

    char* action = new char[action_len + 1];
    char* data = new char[data_len + 1];

    napi_get_value_string_utf8(env, argv[0], action, action_len + 1, &action_len);
    napi_get_value_string_utf8(env, argv[1], data, data_len + 1, &data_len);

    const char* result = g_callJS(action, data);
    delete[] action;
    delete[] data;

    napi_value napi_result;
    napi_create_string_utf8(env, result ? result : "", NAPI_AUTO_LENGTH, &napi_result);
    return napi_result;
}

/**
 * NAPI 函数：卸载 QuickJS
 */
static napi_value UnloadQuickJS(napi_env env, napi_callback_info info) {
    LOGI("UnloadQuickJS called");

    if (g_quickjsHandle) {
        if (g_destroy) {
            g_destroy();
        }
        dlclose(g_quickjsHandle);
        g_quickjsHandle = nullptr;
        g_loadScript = nullptr;
        g_callJS = nullptr;
        g_destroy = nullptr;
        g_quickjsLoaded = false;
    }

    napi_value result;
    napi_get_undefined(env, &result);
    return result;
}

/**
 * 检查是否已加载
 */
static napi_value IsLoaded(napi_env env, napi_callback_info info) {
    napi_value result;
    napi_get_boolean(env, g_quickjsLoaded, &result);
    return result;
}

// ==================== Module Export ====================

static napi_value Export(napi_env env, napi_value exports) {
    napi_value loadFn;
    napi_create_function(env, "loadQuickJS", NAPI_AUTO_LENGTH, LoadQuickJS, nullptr, &loadFn);
    napi_set_named_property(env, exports, "loadQuickJS", loadFn);

    napi_value loadScriptFn;
    napi_create_function(env, "loadScript", NAPI_AUTO_LENGTH, CallLoadScript, nullptr, &loadScriptFn);
    napi_set_named_property(env, exports, "loadScript", loadScriptFn);

    napi_value callFn;
    napi_create_function(env, "callJS", NAPI_AUTO_LENGTH, CallQuickJS, nullptr, &callFn);
    napi_set_named_property(env, exports, "callJS", callFn);

    napi_value unloadFn;
    napi_create_function(env, "unload", NAPI_AUTO_LENGTH, UnloadQuickJS, nullptr, &unloadFn);
    napi_set_named_property(env, exports, "unload", unloadFn);

    napi_value isLoadedFn;
    napi_create_function(env, "isLoaded", NAPI_AUTO_LENGTH, IsLoaded, nullptr, &isLoadedFn);
    napi_set_named_property(env, exports, "isLoaded", isLoadedFn);

    LOGI("QuickJS Loader module exported");
    return exports;
}

NAPI_MODULE_INIT() {
    LOGI("QuickJS Loader module initializing");
    return Export(env, exports);
}