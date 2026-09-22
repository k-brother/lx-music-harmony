/*
 * 原生 zlib 解压模块（Node-API）
 *
 * 背景：酷我歌词接口 newlyric 返回的是 zlib 压缩体（魔数 78 9c），
 * ArkTS 侧只有基于文件的 zlib.decompressFile（且只认 zip），没有内存解压能力。
 * 这里直接调用系统 zlib 做内存解压，避免为了几 KB 歌词去落临时文件。
 */
#include <node_api.h>
#include <zlib.h>

#include <cstring>
#include <vector>

#include "hilog/log.h"

namespace {

constexpr size_t CHUNK_SIZE = 64 * 1024;
// 防御性上限：歌词解开后不可能有几十 MB，超过即认为数据异常
constexpr size_t MAX_OUTPUT_SIZE = 32 * 1024 * 1024;

napi_value Undefined(napi_env env) {
  napi_value value = nullptr;
  napi_get_undefined(env, &value);
  return value;
}

/** 取出入参的字节视图：同时兼容 ArrayBuffer 与 TypedArray */
bool ReadInput(napi_env env, napi_value arg, void **data, size_t *length) {
  bool isArrayBuffer = false;
  if (napi_is_arraybuffer(env, arg, &isArrayBuffer) == napi_ok && isArrayBuffer) {
    return napi_get_arraybuffer_info(env, arg, data, length) == napi_ok;
  }

  bool isTypedArray = false;
  if (napi_is_typedarray(env, arg, &isTypedArray) != napi_ok || !isTypedArray) {
    return false;
  }
  napi_typedarray_type type = napi_uint8_array;
  size_t elementLength = 0;
  void *elementData = nullptr;
  napi_value buffer = nullptr;
  size_t byteOffset = 0;
  if (napi_get_typedarray_info(env, arg, &type, &elementLength, &elementData, &buffer, &byteOffset) != napi_ok) {
    return false;
  }
  *data = elementData;
  *length = elementLength;
  return true;
}

/**
 * inflateBytes(ArrayBuffer|Uint8Array) -> ArrayBuffer | undefined
 * 自动识别 zlib / gzip 头；解压失败返回 undefined 由 ArkTS 侧兜底。
 */
napi_value InflateBytes(napi_env env, napi_callback_info info) {
  size_t argc = 1;
  napi_value args[1] = {nullptr};
  if (napi_get_cb_info(env, info, &argc, args, nullptr, nullptr) != napi_ok || argc < 1) {
    return Undefined(env);
  }

  void *input = nullptr;
  size_t inputLength = 0;
  if (!ReadInput(env, args[0], &input, &inputLength) || input == nullptr || inputLength == 0) {
    return Undefined(env);
  }

  z_stream stream;
  memset(&stream, 0, sizeof(stream));
  // 32 + MAX_WBITS：交给 zlib 自动判断 zlib 头还是 gzip 头
  if (inflateInit2(&stream, 32 + MAX_WBITS) != Z_OK) {
    OH_LOG_WARN(LOG_APP, "inflateInit2 failed");
    return Undefined(env);
  }

  stream.next_in = static_cast<Bytef *>(input);
  stream.avail_in = static_cast<uInt>(inputLength);

  std::vector<unsigned char> output;
  std::vector<unsigned char> chunk(CHUNK_SIZE);
  int status = Z_OK;
  while (true) {
    stream.next_out = chunk.data();
    stream.avail_out = static_cast<uInt>(chunk.size());
    status = inflate(&stream, Z_NO_FLUSH);
    if (status != Z_OK && status != Z_STREAM_END && status != Z_BUF_ERROR) {
      inflateEnd(&stream);
      OH_LOG_WARN(LOG_APP, "inflate failed: %{public}d", status);
      return Undefined(env);
    }

    const size_t produced = chunk.size() - stream.avail_out;
    if (produced > 0) {
      output.insert(output.end(), chunk.begin(), chunk.begin() + static_cast<long>(produced));
    }
    if (status == Z_STREAM_END) {
      break;
    }
    // 输入耗尽但仍未结束：没有更多数据可推进，直接结束并返回已解出的部分
    if (produced == 0) {
      break;
    }
    if (output.size() > MAX_OUTPUT_SIZE) {
      inflateEnd(&stream);
      OH_LOG_WARN(LOG_APP, "inflate output too large");
      return Undefined(env);
    }
  }
  inflateEnd(&stream);

  if (output.empty()) {
    return Undefined(env);
  }

  napi_value result = nullptr;
  void *outData = nullptr;
  if (napi_create_arraybuffer(env, output.size(), &outData, &result) != napi_ok || outData == nullptr) {
    return Undefined(env);
  }
  memcpy(outData, output.data(), output.size());
  return result;
}

}  // namespace

static napi_value Export(napi_env env, napi_value exports) {
  napi_value inflateFn = nullptr;
  napi_create_function(env, "inflateBytes", NAPI_AUTO_LENGTH, InflateBytes, nullptr, &inflateFn);
  napi_set_named_property(env, exports, "inflateBytes", inflateFn);
  return exports;
}

NAPI_MODULE_INIT() {
  return Export(env, exports);
}
