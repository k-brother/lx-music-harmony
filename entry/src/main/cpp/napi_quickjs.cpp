#include <node_api.h>
#include <string>
#include <pthread.h>
#include <unistd.h>
#include <cstdlib>
#include <cstring>
#include <ctime>
#include <sys/time.h>
#include "quickjs.h"
#include "hilog/log.h"

static constexpr char MODULE_NAME[] = "QuickJSNAPI";
static constexpr unsigned int LOG_PRINT_ID = 0xFF00;
static constexpr const char* DEFAULT_SECURITY_KEY = "lxmusic_harmony_key";

#define LOGI(fmt, ...) OH_LOG_INFO(LOG_APP, "%{public}s:" fmt, __FUNCTION__, ##__VA_ARGS__)
#define LOGW(fmt, ...) OH_LOG_WARN(LOG_APP, "%{public}s:" fmt, __FUNCTION__, ##__VA_ARGS__)
#define LOGE(fmt, ...) OH_LOG_ERROR(LOG_APP, "%{public}s:" fmt, __FUNCTION__, ##__VA_ARGS__)

// Global runtime and context
static JSRuntime *runtime = nullptr;
static JSContext *context = nullptr;

// Mutex for thread safety
static pthread_mutex_t js_mutex = PTHREAD_MUTEX_INITIALIZER;

// Security key for native callbacks
static std::string security_key;

static std::string GetExceptionMessageWithStack(JSContext* ctx, JSValueConst exception) {
    const char* msg_c = JS_ToCString(ctx, exception);
    std::string msg = msg_c ? msg_c : "Unknown QuickJS exception";
    if (msg_c) {
        JS_FreeCString(ctx, msg_c);
    }

    JSValue stack_val = JS_GetPropertyStr(ctx, exception, "stack");
    if (!JS_IsUndefined(stack_val) && !JS_IsNull(stack_val)) {
        const char* stack_c = JS_ToCString(ctx, stack_val);
        if (stack_c && strlen(stack_c) > 0) {
            msg += " | stack: ";
            msg += stack_c;
        }
        if (stack_c) {
            JS_FreeCString(ctx, stack_c);
        }
    }
    JS_FreeValue(ctx, stack_val);
    return msg;
}

// ==================== Crypto Utilities ====================

// Simple MD5 implementation (RFC 1321)
static void md5_encode(const char *input, size_t len, char *output) {
    // MD5 constants
    static const unsigned int S[64] = {
        7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22,
        5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20,
        4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23,
        6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21
    };

    static const unsigned int K[64] = {
        0xd76aa478, 0xe8c7b756, 0x242070db, 0xc1bdceee, 0xf57c0faf, 0x4787c62a, 0xa8304613, 0xfd469501,
        0x698098d8, 0x8b44f7af, 0xffff5bb1, 0x895cd7be, 0x6b901122, 0xfd987193, 0xa679438e, 0x49b40821,
        0xf61e2562, 0xc040b340, 0x265e5a51, 0xe9b6c7aa, 0xd62f105d, 0x02441453, 0xd8a1e681, 0xe7d3fbc8,
        0x21e1cde6, 0xc33707d6, 0xf4d50d87, 0x455a14ed, 0xa9e3e905, 0xfcefa3f8, 0x676f02d9, 0x8d2a4c8a,
        0xfffa3942, 0x8771f681, 0x6d9d6122, 0xfde5380c, 0xa4beea44, 0x4bdecfa9, 0xf6bb4b60, 0xbebfbc70,
        0x289b7ec6, 0xeaa127fa, 0xd4ef3085, 0x04881d05, 0xd9d4d039, 0xe6db99e5, 0x1fa27cf8, 0xc4ac5665,
        0xf4292244, 0x432aff97, 0xab9423a7, 0xfc93a039, 0x655b59c3, 0x8f0ccc92, 0xffeff47d, 0x85845dd1,
        0x6fa87e4f, 0xfe2ce6e0, 0xa3014314, 0x4e0811a1, 0xf7537e82, 0xbd3af235, 0x2ad7d2bb, 0xeb86d391
    };

    // Initialize variables
    unsigned int a0 = 0x67452301, b0 = 0xefcdab89, c0 = 0x98badcfe, d0 = 0x10325476;

    // Pre-processing: adding padding bits
    size_t original_len = len;
    size_t padded_len = ((len + 8) / 64 + 1) * 64;
    unsigned char *padded = new unsigned char[padded_len];
    memset(padded, 0, padded_len);
    memcpy(padded, input, len);
    padded[len] = 0x80;

    // Append length
    unsigned long long bit_len = original_len * 8;
    memcpy(padded + padded_len - 8, &bit_len, 8);

    // Process each 512-bit block
    for (size_t i = 0; i < padded_len; i += 64) {
        unsigned int M[16];
        for (int j = 0; j < 16; j++) {
            M[j] = padded[i + j * 4] | (padded[i + j * 4 + 1] << 8) |
                   (padded[i + j * 4 + 2] << 16) | (padded[i + j * 4 + 3] << 24);
        }

        unsigned int A = a0, B = b0, C = c0, D = d0;

        for (int j = 0; j < 64; j++) {
            unsigned int F, g;
            if (j < 16) {
                F = (B & C) | ((~B) & D);
                g = j;
            } else if (j < 32) {
                F = (D & B) | ((~D) & C);
                g = (5 * j + 1) % 16;
            } else if (j < 48) {
                F = B ^ C ^ D;
                g = (3 * j + 5) % 16;
            } else {
                F = C ^ (B | (~D));
                g = (7 * j) % 16;
            }

            F = F + A + K[j] + M[g];
            A = D;
            D = C;
            C = B;
            B = B + ((F << S[j]) | (F >> (32 - S[j])));
        }

        a0 += A;
        b0 += B;
        c0 += C;
        d0 += D;
    }

    delete[] padded;

    // Output
    sprintf(output, "%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x",
            a0 & 0xff, (a0 >> 8) & 0xff, (a0 >> 16) & 0xff, (a0 >> 24) & 0xff,
            b0 & 0xff, (b0 >> 8) & 0xff, (b0 >> 16) & 0xff, (b0 >> 24) & 0xff,
            c0 & 0xff, (c0 >> 8) & 0xff, (c0 >> 16) & 0xff, (c0 >> 24) & 0xff,
            d0 & 0xff, (d0 >> 8) & 0xff, (d0 >> 16) & 0xff, (d0 >> 24) & 0xff);
}

// Simple Base64 encoding
static void base64_encode(const char *input, size_t input_len, char *output) {
    const char *base64_chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    size_t i = 0;
    size_t j = 0;

    while (i < input_len) {
        unsigned char b1 = i < input_len ? input[i++] : 0;
        unsigned char b2 = i < input_len ? input[i++] : 0;
        unsigned char b3 = i < input_len ? input[i++] : 0;

        output[j++] = base64_chars[(b1 >> 2) & 0x3F];
        output[j++] = base64_chars[((b1 << 4) | (b2 >> 4)) & 0x3F];
        output[j++] = (i > input_len + 1) ? '=' : base64_chars[((b2 << 2) | (b3 >> 6)) & 0x3F];
        output[j++] = (i > input_len) ? '=' : base64_chars[b3 & 0x3F];
    }
    output[j] = '\0';
}

// Simple Base64 decoding
static size_t base64_decode(const char *input, size_t input_len, unsigned char *output) {
    const char *base64_chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    size_t i = 0;
    size_t j = 0;
    unsigned int temp = 0;

    while (input_len > 0 && input[input_len - 1] == '=') {
        input_len--;
    }

    for (size_t k = 0; k < input_len; k++) {
        const char *pos = strchr(base64_chars, input[k]);
        if (!pos) return 0;
        temp = (temp << 6) | (pos - base64_chars);

        if ((k + 1) % 4 == 0) {
            output[j++] = (temp >> 16) & 0xFF;
            if (j < 4096) output[j++] = (temp >> 8) & 0xFF;
            if (j < 4096) output[j++] = temp & 0xFF;
            temp = 0;
        }
    }

    return j;
}

// Simple hex to bytes conversion
static size_t hex_to_bytes(const char *hex, size_t hex_len, unsigned char *out) {
    for (size_t i = 0; i < hex_len / 2; i++) {
        sscanf(hex + 2 * i, "%2hhx", &out[i]);
    }
    return hex_len / 2;
}

// Simple bytes to hex conversion
static void bytes_to_hex(const unsigned char *bytes, size_t len, char *out) {
    for (size_t i = 0; i < len; i++) {
        sprintf(out + 2 * i, "%02x", bytes[i]);
    }
    out[len * 2] = '\0';
}

// ==================== Native Callbacks ====================

// Native callback: String to Base64
static JSValue Native_str2b64(JSContext *ctx, JSValueConst this_val, int argc, JSValueConst *argv) {
    if (argc < 1 || !JS_IsString(argv[0])) {
        return JS_NewString(ctx, "");
    }

    const char *input = JS_ToCString(ctx, argv[0]);
    if (!input) return JS_NewString(ctx, "");

    size_t input_len = strlen(input);
    size_t output_len = ((input_len + 2) / 3) * 4 + 1;

    char *output = new char[output_len];
    memset(output, 0, output_len);

    base64_encode(input, input_len, output);

    JSValue result = JS_NewString(ctx, output);
    delete[] output;
    JS_FreeCString(ctx, input);
    return result;
}

// Native callback: Base64 to Buffer (returns array of bytes)
static JSValue Native_b642buf(JSContext *ctx, JSValueConst this_val, int argc, JSValueConst *argv) {
    if (argc < 1 || !JS_IsString(argv[0])) {
        return JS_NewArray(ctx);
    }

    const char *input = JS_ToCString(ctx, argv[0]);
    if (!input) return JS_NewArray(ctx);

    size_t input_len = strlen(input);
    unsigned char output[4096];
    memset(output, 0, sizeof(output));

    size_t out_len = base64_decode(input, input_len, output);

    JSValue result_array = JS_NewArray(ctx);
    for (size_t i = 0; i < out_len; i++) {
        JS_SetPropertyUint32(ctx, result_array, i, JS_NewInt32(ctx, output[i]));
    }

    JS_FreeCString(ctx, input);
    return result_array;
}

// Native callback: String to MD5
static JSValue Native_str2md5(JSContext *ctx, JSValueConst this_val, int argc, JSValueConst *argv) {
    if (argc < 1 || !JS_IsString(argv[0])) {
        return JS_NewString(ctx, "");
    }

    const char *input = JS_ToCString(ctx, argv[0]);
    if (!input) return JS_NewString(ctx, "");

    char md5_string[33];
    md5_encode(input, strlen(input), md5_string);

    JSValue result = JS_NewString(ctx, md5_string);
    JS_FreeCString(ctx, input);
    return result;
}

// Native callback: AES encryption (simplified - pass through)
static JSValue Native_aes_encrypt(JSContext *ctx, JSValueConst this_val, int argc, JSValueConst *argv) {
    if (argc < 4) {
        return JS_NewString(ctx, "");
    }

    const char *data = JS_ToCString(ctx, argv[0]);
    if (!data) return JS_NewString(ctx, "");

    // Simplified: just return hex of input for demo
    JSValue result = JS_NewString(ctx, data);
    JS_FreeCString(ctx, data);
    return result;
}

// Native callback: RSA encryption (not implemented)
static JSValue Native_rsa_encrypt(JSContext *ctx, JSValueConst this_val, int argc, JSValueConst *argv) {
    return JS_NewString(ctx, "");
}

// Native callback: setTimeout handler
static JSValue Native_set_timeout(JSContext *ctx, JSValueConst this_val, int argc, JSValueConst *argv) {
    return JS_NewInt32(ctx, 0);
}

// Native callback: main entry point for JS -> Native calls
static JSValue Native_call(JSContext *ctx, JSValueConst this_val, int argc, JSValueConst *argv) {
    if (argc < 2) {
        return JS_NewString(ctx, "{\"error\":\"Invalid arguments\"}");
    }

    const char *key = JS_ToCString(ctx, argv[0]);
    const char *action = JS_ToCString(ctx, argv[1]);
    if (!key || !action) {
        if (key) JS_FreeCString(ctx, key);
        if (action) JS_FreeCString(ctx, action);
        return JS_NewString(ctx, "{\"error\":\"Invalid key or action\"}");
    }

    if (security_key.empty() || strcmp(key, security_key.c_str()) != 0) {
        JS_FreeCString(ctx, key);
        JS_FreeCString(ctx, action);
        return JS_NewString(ctx, "{\"error\":\"Invalid key\"}");
    }

    LOGI("Native_call action=%s", action);

    std::string data_str = "";
    if (argc > 2 && JS_IsString(argv[2])) {
        const char *data = JS_ToCString(ctx, argv[2]);
        if (data) {
            data_str = data;
            JS_FreeCString(ctx, data);
        }
    }

    if (strcmp(action, "init") == 0) {
        JS_FreeCString(ctx, key);
        JS_FreeCString(ctx, action);
        return JS_NewString(ctx, "{\"status\":\"ok\"}");
    } else if (strcmp(action, "request") == 0) {
        JS_FreeCString(ctx, key);
        JS_FreeCString(ctx, action);
        return JS_NewString(ctx, "{\"error\":\"Request not implemented\"}");
    }

    JS_FreeCString(ctx, key);
    JS_FreeCString(ctx, action);
    return JS_NewString(ctx, "{\"error\":\"Unknown action\"}");
}

// ==================== QuickJS Setup ====================

static bool InitJSContext() {
    pthread_mutex_lock(&js_mutex);
    if (runtime == nullptr) {
        runtime = JS_NewRuntime();
        if (runtime == nullptr) {
            LOGE("Failed to create JS runtime");
            pthread_mutex_unlock(&js_mutex);
            return false;
        }
        LOGI("JS Runtime created");
    }
    if (context == nullptr) {
        context = JS_NewContext(runtime);
        if (context == nullptr) {
            LOGE("Failed to create JS context");
            pthread_mutex_unlock(&js_mutex);
            return false;
        }
        LOGI("JS Context created");

        JSValue global = JS_GetGlobalObject(context);

        JS_SetPropertyStr(context, global, "__lx_native_call__",
            JS_NewCFunction(context, Native_call, "__lx_native_call__", 3));
        JS_SetPropertyStr(context, global, "__lx_native_call__str2b64",
            JS_NewCFunction(context, Native_str2b64, "__lx_native_call__str2b64", 1));
        JS_SetPropertyStr(context, global, "__lx_native_call__utils_str2b64",
            JS_NewCFunction(context, Native_str2b64, "__lx_native_call__utils_str2b64", 1));
        JS_SetPropertyStr(context, global, "__lx_native_call__b642buf",
            JS_NewCFunction(context, Native_b642buf, "__lx_native_call__b642buf", 1));
        JS_SetPropertyStr(context, global, "__lx_native_call__utils_b642buf",
            JS_NewCFunction(context, Native_b642buf, "__lx_native_call__utils_b642buf", 1));
        JS_SetPropertyStr(context, global, "__lx_native_call__str2md5",
            JS_NewCFunction(context, Native_str2md5, "__lx_native_call__str2md5", 1));
        JS_SetPropertyStr(context, global, "__lx_native_call__utils_str2md5",
            JS_NewCFunction(context, Native_str2md5, "__lx_native_call__utils_str2md5", 1));
        JS_SetPropertyStr(context, global, "__lx_native_call__aes_encrypt",
            JS_NewCFunction(context, Native_aes_encrypt, "__lx_native_call__aes_encrypt", 4));
        JS_SetPropertyStr(context, global, "__lx_native_call__utils_aes_encrypt",
            JS_NewCFunction(context, Native_aes_encrypt, "__lx_native_call__utils_aes_encrypt", 4));
        JS_SetPropertyStr(context, global, "__lx_native_call__rsa_encrypt",
            JS_NewCFunction(context, Native_rsa_encrypt, "__lx_native_call__rsa_encrypt", 3));
        JS_SetPropertyStr(context, global, "__lx_native_call__utils_rsa_encrypt",
            JS_NewCFunction(context, Native_rsa_encrypt, "__lx_native_call__utils_rsa_encrypt", 3));
        JS_SetPropertyStr(context, global, "__lx_native_call__set_timeout",
            JS_NewCFunction(context, Native_set_timeout, "__lx_native_call__set_timeout", 2));

        JS_FreeValue(context, global);
    }
    pthread_mutex_unlock(&js_mutex);
    return true;
}

// ==================== NAPI Functions ====================

static napi_value LoadScript(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value argv[1];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);

    if (argc < 1) {
        napi_value result_val;
        napi_create_string_utf8(env, "Expected script string argument", NAPI_AUTO_LENGTH, &result_val);
        return result_val;
    }

    size_t script_len;
    napi_get_value_string_utf8(env, argv[0], nullptr, 0, &script_len);
    char *script = new char[script_len + 1];
    napi_get_value_string_utf8(env, argv[0], script, script_len + 1, &script_len);

    LOGI("Loading script, length: %zu", script_len);

    if (!InitJSContext()) {
        delete[] script;
        napi_value result_val;
        napi_create_string_utf8(env, "Failed to initialize JS context", NAPI_AUTO_LENGTH, &result_val);
        return result_val;
    }

    pthread_mutex_lock(&js_mutex);

    if (security_key.empty()) {
        security_key = DEFAULT_SECURITY_KEY;
    }

    JSValue result = JS_Eval(context, script, script_len, "<script>", JS_EVAL_TYPE_GLOBAL);
    delete[] script;

    if (JS_IsException(result)) {
        JSValue exception = JS_GetException(context);
        std::string error_text = GetExceptionMessageWithStack(context, exception);
        LOGE("Script error: %s", error_text.c_str());
        JS_FreeValue(context, exception);
        JS_FreeValue(context, result);
        pthread_mutex_unlock(&js_mutex);
        napi_value result_val;
        napi_create_string_utf8(env, error_text.c_str(), NAPI_AUTO_LENGTH, &result_val);
        return result_val;
    }

    JS_FreeValue(context, result);
    pthread_mutex_unlock(&js_mutex);

    napi_value result_val;
    napi_create_string_utf8(env, "", NAPI_AUTO_LENGTH, &result_val);
    return result_val;
}

static napi_value CallJS(napi_env env, napi_callback_info info) {
    size_t argc = 2;
    napi_value argv[2];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);

    if (argc < 2) {
        napi_value result_val;
        napi_create_string_utf8(env, "{\"error\":\"Expected action and data arguments\"}", NAPI_AUTO_LENGTH, &result_val);
        return result_val;
    }

    size_t action_len;
    napi_get_value_string_utf8(env, argv[0], nullptr, 0, &action_len);
    char *action = new char[action_len + 1];
    napi_get_value_string_utf8(env, argv[0], action, action_len + 1, &action_len);

    size_t data_len;
    napi_get_value_string_utf8(env, argv[1], nullptr, 0, &data_len);
    char *data = new char[data_len + 1];
    napi_get_value_string_utf8(env, argv[1], data, data_len + 1, &data_len);

    LOGI("CallJS action=%s data_len=%zu", action, data_len);

    pthread_mutex_lock(&js_mutex);
    if (context == nullptr) {
        pthread_mutex_unlock(&js_mutex);
        delete[] action;
        delete[] data;
        napi_value result_val;
        napi_create_string_utf8(env, "{\"error\":\"JS context not initialized\"}", NAPI_AUTO_LENGTH, &result_val);
        return result_val;
    }

    JSValue global_obj = JS_GetGlobalObject(context);
    JSValue func = JS_GetPropertyStr(context, global_obj, "__lx_native__");

    if (!JS_IsFunction(context, func)) {
        JS_FreeValue(context, global_obj);
        JS_FreeValue(context, func);
        pthread_mutex_unlock(&js_mutex);
        delete[] action;
        delete[] data;
        napi_value result;
        napi_get_null(env, &result);
        return result;
    }

    JSValue args[3] = {
        JS_NewString(context, security_key.c_str()),
        JS_NewString(context, action),
        JS_NewString(context, data)
    };

    JSValue js_result = JS_Call(context, func, global_obj, 3, args);

    JS_FreeValue(context, global_obj);
    JS_FreeValue(context, func);
    // JS_NewString returns values that don't need to be freed separately - they are managed by GC

    delete[] action;
    delete[] data;

    if (JS_IsException(js_result)) {
        JSValue exception = JS_GetException(context);
        std::string error_text = GetExceptionMessageWithStack(context, exception);
        LOGE("CallJS error: %s", error_text.c_str());
        JS_FreeValue(context, exception);
        JS_FreeValue(context, js_result);
        pthread_mutex_unlock(&js_mutex);
        std::string json_error = "{\"error\":\"" + error_text + "\"}";
        napi_value result_val;
        napi_create_string_utf8(env, json_error.c_str(), NAPI_AUTO_LENGTH, &result_val);
        return result_val;
    }

    napi_value result_val;
    if (JS_IsString(js_result)) {
        const char *result_str = JS_ToCString(context, js_result);
        napi_create_string_utf8(env, result_str, NAPI_AUTO_LENGTH, &result_val);
        JS_FreeCString(context, result_str);
    } else if (JS_IsNumber(js_result)) {
        double num;
        JS_ToFloat64(context, &num, js_result);
        napi_create_double(env, num, &result_val);
    } else if (JS_IsBool(js_result)) {
        int bval = JS_ToBool(context, js_result);
        napi_get_boolean(env, bval != 0, &result_val);
    } else {
        napi_get_null(env, &result_val);
    }

    JS_FreeValue(context, js_result);
    pthread_mutex_unlock(&js_mutex);

    return result_val;
}

static napi_value Destroy(napi_env env, napi_callback_info info) {
    LOGI("Destroy called");

    pthread_mutex_lock(&js_mutex);
    if (context != nullptr) {
        JS_FreeContext(context);
        context = nullptr;
        LOGI("JS Context freed");
    }
    if (runtime != nullptr) {
        JS_FreeRuntime(runtime);
        runtime = nullptr;
        LOGI("JS Runtime freed");
    }
    security_key.clear();
    pthread_mutex_unlock(&js_mutex);

    napi_value result;
    napi_get_undefined(env, &result);
    return result;
}

// ==================== Plain C API for dlopen/dlsym ====================
// These functions can be called from the loader module via dlsym

extern "C" {

/**
 * Load a JavaScript script (plain C version)
 * @param script The JavaScript source code
 * @return Error message or empty string on success
 */
const char* napi_loadScript(const char* script) {
    if (!script || !context) {
        return "Invalid arguments or JS context not initialized";
    }

    pthread_mutex_lock(&js_mutex);

    size_t script_len = strlen(script);
    JSValue result = JS_Eval(context, script, script_len, "<script>", JS_EVAL_TYPE_GLOBAL);

    if (JS_IsException(result)) {
        JSValue exception = JS_GetException(context);
        std::string error_text = GetExceptionMessageWithStack(context, exception);
        JS_FreeValue(context, exception);
        JS_FreeValue(context, result);
        pthread_mutex_unlock(&js_mutex);

        static thread_local char error_buffer[512];
        strncpy(error_buffer, error_text.c_str(), sizeof(error_buffer) - 1);
        error_buffer[sizeof(error_buffer) - 1] = '\0';
        return error_buffer;
    }

    JS_FreeValue(context, result);
    pthread_mutex_unlock(&js_mutex);
    return "";
}

/**
 * Call a JavaScript function (plain C version)
 * @param action The action name
 * @param data JSON stringified data
 * @return Result string
 */
const char* napi_callJS(const char* action, const char* data) {
    if (!action || !data || !context) {
        return "{\"error\":\"Invalid arguments or JS context not initialized\"}";
    }

    pthread_mutex_lock(&js_mutex);

    JSValue global_obj = JS_GetGlobalObject(context);
    JSValue func = JS_GetPropertyStr(context, global_obj, "__lx_native__");

    if (!JS_IsFunction(context, func)) {
        JS_FreeValue(context, global_obj);
        JS_FreeValue(context, func);
        pthread_mutex_unlock(&js_mutex);
        return "{\"error\":\"__lx_native__ function not found\"}";
    }

    JSValue args[3] = {
        JS_NewString(context, security_key.c_str()),
        JS_NewString(context, action),
        JS_NewString(context, data)
    };

    JSValue js_result = JS_Call(context, func, global_obj, 3, args);

    JS_FreeValue(context, global_obj);
    JS_FreeValue(context, func);
    for (int i = 0; i < 3; i++) {
        JS_FreeValue(context, args[i]);
    }

    if (JS_IsException(js_result)) {
        JSValue exception = JS_GetException(context);
        std::string error_text = GetExceptionMessageWithStack(context, exception);
        JS_FreeValue(context, exception);
        JS_FreeValue(context, js_result);
        pthread_mutex_unlock(&js_mutex);

        static thread_local char error_buffer[512];
        snprintf(error_buffer, sizeof(error_buffer), "{\"error\":\"%s\"}", error_text.c_str());
        return error_buffer;
    }

    const char* result_str = JS_ToCString(context, js_result);
    JS_FreeValue(context, js_result);
    pthread_mutex_unlock(&js_mutex);

    static thread_local char result_buffer[8192];
    strncpy(result_buffer, result_str ? result_str : "", sizeof(result_buffer) - 1);
    result_buffer[sizeof(result_buffer) - 1] = '\0';
    if (result_str) {
        JS_FreeCString(context, result_str);
    }

    return result_buffer;
}

/**
 * Destroy the QuickJS context (plain C version)
 */
void napi_destroy(void) {
    LOGI("napi_destroy called");
    pthread_mutex_lock(&js_mutex);

    if (context != nullptr) {
        JS_FreeContext(context);
        context = nullptr;
    }
    if (runtime != nullptr) {
        JS_FreeRuntime(runtime);
        runtime = nullptr;
    }
    security_key.clear();

    pthread_mutex_unlock(&js_mutex);
}

} // extern "C"

// ==================== Module Export ====================

static napi_value Export(napi_env env, napi_value exports) {
    napi_value loadScriptFn;
    napi_create_function(env, "loadScript", NAPI_AUTO_LENGTH, LoadScript, nullptr, &loadScriptFn);
    napi_set_named_property(env, exports, "loadScript", loadScriptFn);

    napi_value callJSFn;
    napi_create_function(env, "callJS", NAPI_AUTO_LENGTH, CallJS, nullptr, &callJSFn);
    napi_set_named_property(env, exports, "callJS", callJSFn);

    napi_value destroyFn;
    napi_create_function(env, "destroy", NAPI_AUTO_LENGTH, Destroy, nullptr, &destroyFn);
    napi_set_named_property(env, exports, "destroy", destroyFn);

    LOGI("QuickJS NAPI module exported");
    return exports;
}

NAPI_MODULE_INIT() {
    LOGI("QuickJS NAPI module initializing");
    return Export(env, exports);
}