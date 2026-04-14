'use strict';

// User API Preload Script for HarmonyOS
// This script is loaded into QuickJS before user plugin scripts

// Some third-party scripts assume a browser/node-like console exists.
if (!globalThis.console) {
  globalThis.console = {
    log: function() {},
    info: function() {},
    warn: function() {},
    error: function() {},
    debug: function() {},
    group: function() {},
    groupEnd: function() {},
  };
}

globalThis.lx_setup = function(key, id, name, description, version, author, homepage, rawScript) {
  // Remove the setup function to prevent re-setup
  delete globalThis.lx_setup;

  // Store the security key for native callbacks
  const SECURITY_KEY = key;

  // Native call function - communicates with our NAPI wrapper
  const _nativeCall = globalThis.__lx_native_call__;
  delete globalThis.__lx_native_call__;

  // Length check utility to prevent memory exhaustion attacks
  const checkLength = function(str, length) {
    length = length || 1048576; // 1MB default
    if (typeof str === 'string' && str.length > length) {
      throw new Error('Input too long');
    }
    return str;
  };

  // Native function names that are available
  const nativeFuncNames = [
    '__lx_native_call__set_timeout',
    '__lx_native_call__utils_str2b64',
    '__lx_native_call__utils_b642buf',
    '__lx_native_call__utils_str2md5',
    '__lx_native_call__utils_aes_encrypt',
    '__lx_native_call__utils_rsa_encrypt',
  ];

  // Store native functions with length checking
  const nativeFuncs = {};
  for (var i = 0; i < nativeFuncNames.length; i++) {
    var name = nativeFuncNames[i];
    var nativeFunc = globalThis[name];
    delete globalThis[name];
    var baseName = name.replace('__lx_native_call__', '');
    nativeFuncs[baseName] = (function(fn) {
      return function() {
        for (var j = 0; j < arguments.length; j++) {
          checkLength(arguments[j]);
        }
        return fn.apply(null, arguments);
      };
    })(nativeFunc);
  }

  // Constants for crypto operations
  var RSA_PADDING = {
    OAEPWithSHA1AndMGF1Padding: 'RSA/ECB/OAEPWithSHA1AndMGF1Padding',
    NoPadding: 'RSA/ECB/NoPadding',
  };

  var AES_MODE = {
    CBC_128_PKCS7Padding: 'AES/CBC/PKCS7Padding',
    ECB_128_NoPadding: 'AES',
  };

  // Main native call function
  var nativeCall = function(action, data) {
    data = JSON.stringify(data);
    checkLength(data, 2097152); // 2MB max
    _nativeCall(SECURITY_KEY, action, data);
  };

  // Callback storage for setTimeout
  var callbacks = {};
  var timeoutId = 0;

  // setTimeout implementation
  var _setTimeout = function(callback, timeout) {
    if (typeof callback !== 'function') {
      throw new Error('callback required a function');
    }
    if (typeof timeout !== 'number' || timeout < 0) {
      throw new Error('timeout required a number');
    }
    if (timeoutId > 90000000000) {
      throw new Error('max timeout');
    }
    var id = timeoutId++;
    callbacks[id] = {
      callback: callback,
      params: Array.prototype.slice.call(arguments, 2),
    };
    nativeFuncs.set_timeout(id, parseInt(timeout));
    return id;
  };

  // clearTimeout implementation
  var _clearTimeout = function(id) {
    var target = callbacks[id];
    if (!target) return;
    delete callbacks[id];
  };

  // Handle setTimeout callbacks from native
  var handleSetTimeout = function(id) {
    var target = callbacks[id];
    if (!target) return;
    delete callbacks[id];
    target.callback.apply(null, target.params);
  };

  // UTF-8 encoding/decoding utilities
  function bytesToString(bytes) {
    var result = '';
    var i = 0;
    while (i < bytes.length) {
      var byte = bytes[i];
      if (byte < 128) {
        result += String.fromCharCode(byte);
        i++;
      } else if (byte >= 192 && byte < 224) {
        result += String.fromCharCode(((byte & 31) << 6) | (bytes[i + 1] & 63));
        i += 2;
      } else {
        result += String.fromCharCode(((byte & 15) << 12) | ((bytes[i + 1] & 63) << 6) | (bytes[i + 2] & 63));
        i += 3;
      }
    }
    return result;
  }

  function stringToBytes(inputString) {
    var bytes = [];
    for (var i = 0; i < inputString.length; i++) {
      var charCode = inputString.charCodeAt(i);
      if (charCode < 128) {
        bytes.push(charCode);
      } else if (charCode < 2048) {
        bytes.push((charCode >> 6) | 192);
        bytes.push((charCode & 63) | 128);
      } else {
        bytes.push((charCode >> 12) | 224);
        bytes.push(((charCode >> 6) & 63) | 128);
        bytes.push((charCode & 63) | 128);
      }
    }
    return bytes;
  }

  // Native event names
  var NATIVE_EVENTS_NAMES = {
    init: 'init',
    showUpdateAlert: 'showUpdateAlert',
    request: 'request',
    cancelRequest: 'cancelRequest',
    response: 'response',
  };

  // Event names exposed to plugins
  var EVENT_NAMES = {
    request: 'request',
    inited: 'inited',
    updateAlert: 'updateAlert',
  };

  var eventNames = Object.values(EVENT_NAMES);
  var events = {
    request: null,
  };

  // Supported sources
  var allSources = ['kw', 'kg', 'tx', 'wy', 'mg', 'local'];

  // Quality support per source
  var supportQualitys = {
    kw: ['128k', '320k', 'flac', 'flac24bit'],
    kg: ['128k', '320k', 'flac', 'flac24bit'],
    tx: ['128k', '320k', 'flac', 'flac24bit'],
    wy: ['128k', '320k', 'flac', 'flac24bit'],
    mg: ['128k', '320k', 'flac', 'flac24bit'],
    local: [],
  };

  // Actions supported per source
  var supportActions = {
    kw: ['musicUrl'],
    kg: ['musicUrl'],
    tx: ['musicUrl'],
    wy: ['musicUrl'],
    mg: ['musicUrl'],
    xm: ['musicUrl'],
    local: ['musicUrl', 'lyric', 'pic'],
  };

  // Verify lyric info format
  var verifyLyricInfo = function(info) {
    if (typeof info !== 'object' || typeof info.lyric !== 'string') {
      throw new Error('failed');
    }
    if (info.lyric.length > 51200) {
      throw new Error('failed');
    }
    return {
      lyric: info.lyric,
      tlyric: (typeof info.tlyric === 'string' && info.tlyric.length < 5120) ? info.tlyric : null,
      rlyric: (typeof info.rlyric === 'string' && info.rlyric.length < 5120) ? info.rlyric : null,
      lxlyric: (typeof info.lxlyric === 'string' && info.lxlyric.length < 8192) ? info.lxlyric : null,
    };
  };

  // Request queue for managing async requests
  var requestQueue = {};
  var isInitedApi = false;
  var isShowedUpdateAlert = false;

  // Send request to native layer
  var sendNativeRequest = function(url, options, callback) {
    var requestKey = Math.random().toString();
    var requestInfo = {
      aborted: false,
      abort: function() {
        nativeCall(NATIVE_EVENTS_NAMES.cancelRequest, requestKey);
      },
    };
    requestQueue[requestKey] = {
      callback: callback,
      requestInfo: requestInfo,
    };

    nativeCall(NATIVE_EVENTS_NAMES.request, {
      requestKey: requestKey,
      url: url,
      options: options,
    });
    return requestInfo;
  };

  // Handle native response
  var handleNativeResponse = function(data) {
    var requestKey = data.requestKey;
    var targetRequest = requestQueue[requestKey];
    if (!targetRequest) return;
    delete requestQueue[requestKey];
    targetRequest.requestInfo.aborted = true;
    if (data.error == null) {
      targetRequest.callback(null, data.response);
    } else {
      targetRequest.callback(new Error(data.errorMessage), null);
    }
  };

  // Handle requests from native layer
  var handleRequest = function(data) {
    if (!events.request) {
      nativeCall(NATIVE_EVENTS_NAMES.response, {
        requestKey: data.requestKey,
        status: false,
        errorMessage: 'Request event is not defined',
      });
      return;
    }
    try {
      var promise = events.request.call(globalThis.lx, {
        source: data.source,
        action: data.action,
        info: data.info,
      });
      promise.then(function(response) {
        var result;
        switch (data.action) {
          case 'musicUrl':
            if (typeof response !== 'string' || response.length > 2048 || !/^https?:/.test(response)) {
              throw new Error('failed');
            }
            result = {
              source: data.source,
              action: data.action,
              data: {
                type: data.info.type,
                url: response,
              },
            };
            break;
          case 'lyric':
            result = {
              source: data.source,
              action: data.action,
              data: verifyLyricInfo(response),
            };
            break;
          case 'pic':
            if (typeof response !== 'string' || response.length > 2048 || !/^https?:/.test(response)) {
              throw new Error('failed');
            }
            result = {
              source: data.source,
              action: data.action,
              data: response,
            };
            break;
        }
        nativeCall(NATIVE_EVENTS_NAMES.response, {
          requestKey: data.requestKey,
          status: true,
          result: result,
        });
      }).catch(function(err) {
        nativeCall(NATIVE_EVENTS_NAMES.response, {
          requestKey: data.requestKey,
          status: false,
          errorMessage: err.message,
        });
      });
    } catch (err) {
      nativeCall(NATIVE_EVENTS_NAMES.response, {
        requestKey: data.requestKey,
        status: false,
        errorMessage: err.message,
      });
    }
  };

  // JS call handler - dispatches calls from native
  var jsCall = function(action, data) {
    switch (action) {
      case '__run_error__':
        if (!isInitedApi) isInitedApi = true;
        return;
      case '__set_timeout__':
        handleSetTimeout(data);
        return;
      case 'request':
        handleRequest(data);
        return;
      case 'response':
        handleNativeResponse(data);
        return;
    }
    return 'Unknown action: ' + action;
  };

  // Create the __lx_native__ function that native code calls
  Object.defineProperty(globalThis, '__lx_native__', {
    enumerable: false,
    configurable: false,
    writable: false,
    value: function(_key, action, data) {
      if (key !== _key) return 'Invalid key';
      return data == null ? jsCall(action) : jsCall(action, JSON.parse(data));
    },
  });

  // Initialize handler
  var handleInit = function(info) {
    if (!info) {
      nativeCall(NATIVE_EVENTS_NAMES.init, {
        info: null,
        status: false,
        errorMessage: 'Missing required parameter init info',
      });
      return;
    }
    var sourceInfo = {
      sources: {},
    };
    try {
      for (var i = 0; i < allSources.length; i++) {
        var source = allSources[i];
        var userSource = info.sources[source];
        if (!userSource || userSource.type !== 'music') continue;
        var qualitys = supportQualitys[source];
        var actions = supportActions[source];
        sourceInfo.sources[source] = {
          type: 'music',
          actions: actions.filter(function(a) {
            return userSource.actions.indexOf(a) !== -1;
          }),
          qualitys: qualitys.filter(function(q) {
            return userSource.qualitys.indexOf(q) !== -1;
          }),
        };
      }
    } catch (error) {
      nativeCall(NATIVE_EVENTS_NAMES.init, {
        info: null,
        status: false,
        errorMessage: error.message,
      });
      return;
    }
    nativeCall(NATIVE_EVENTS_NAMES.init, {
      info: sourceInfo,
      status: true,
    });
  };

  // Update alert handler
  var handleShowUpdateAlert = function(data, resolve, reject) {
    if (!data || typeof data !== 'object') return reject(new Error('parameter format error.'));
    if (!data.log || typeof data.log !== 'string') return reject(new Error('log is required.'));
    if (data.updateUrl && !/^https?:\/\/[^\s$.?#].[^\s]*$/.test(data.updateUrl) && data.updateUrl.length > 1024) {
      delete data.updateUrl;
    }
    if (data.log.length > 1024) data.log = data.log.substring(0, 1024) + '...';
    nativeCall(NATIVE_EVENTS_NAMES.showUpdateAlert, {
      log: data.log,
      updateUrl: data.updateUrl,
      name: name,
    });
    resolve();
  };

  // Buffer utilities
  var dataToB64 = function(data) {
    if (typeof data === 'string') return nativeFuncs.utils_str2b64(data);
    else if (Array.isArray(data) || (typeof Uint8Array !== 'undefined' && data instanceof Uint8Array)) {
      return nativeFuncs.utils_b642buf(Array.from(data));
    }
    throw new Error('data type error: ' + typeof data + ' raw data: ' + data);
  };

  // Create the lx global object
  var utils = {
    crypto: {
      aesEncrypt: function(buffer, mode, key, iv) {
        switch (mode) {
          case 'aes-128-cbc':
            return nativeFuncs.utils_aes_encrypt(dataToB64(buffer), dataToB64(key), dataToB64(iv), AES_MODE.CBC_128_PKCS7Padding);
          case 'aes-128-ecb':
            return nativeFuncs.utils_aes_encrypt(dataToB64(buffer), dataToB64(key), '', AES_MODE.ECB_128_NoPadding);
          default:
            throw new Error('Binary encoding is not supported for input strings');
        }
      },
      rsaEncrypt: function(buffer, key) {
        if (typeof key !== 'string') throw new Error('Invalid RSA key');
        key = key.replace('-----BEGIN PUBLIC KEY-----', '')
          .replace('-----END PUBLIC KEY-----', '');
        return nativeFuncs.utils_rsa_encrypt(dataToB64(buffer), key, RSA_PADDING.NoPadding);
      },
      randomBytes: function(size) {
        var byteArray = new Uint8Array(size);
        for (var i = 0; i < size; i++) {
          byteArray[i] = Math.floor(Math.random() * 256);
        }
        return byteArray;
      },
      md5: function(str) {
        if (typeof str !== 'string') throw new Error('param required a string');
        return nativeFuncs.utils_str2md5(encodeURIComponent(str));
      },
    },
    buffer: {
      from: function(input, encoding) {
        if (typeof input === 'string') {
          switch (encoding) {
            case 'binary':
              throw new Error('Binary encoding is not supported for input strings');
            case 'base64':
              return new Uint8Array(JSON.parse(nativeFuncs.utils_b642buf(input)));
            case 'hex':
              return new Uint8Array(input.match(/.{1,2}/g).map(function(byte) {
                return parseInt(byte, 16);
              }));
            default:
              return new Uint8Array(stringToBytes(input));
          }
        } else if (Array.isArray(input)) {
          return new Uint8Array(input);
        } else {
          throw new Error('Unsupported input type: ' + input + ' encoding: ' + encoding);
        }
      },
      bufToString: function(buf, format) {
        if (Array.isArray(buf) || (typeof Uint8Array !== 'undefined' && buf instanceof Uint8Array)) {
          switch (format) {
            case 'binary':
              return buf;
            case 'hex':
              return Array.from(buf).map(function(byte) {
                return byte.toString(16).padStart(2, '0');
              }).join('');
            case 'base64':
              return nativeFuncs.utils_str2b64(bytesToString(Array.from(buf)));
            case 'utf8':
            case 'utf-8':
            default:
              return bytesToString(Array.from(buf));
          }
        } else {
          throw new Error('Input is not a valid buffer: ' + buf + ' format: ' + format);
        }
      },
    },
  };

  // Create the lx object
  globalThis.lx = {
    EVENT_NAMES: EVENT_NAMES,

    request: function(url, options, callback) {
      var opts = { headers: options.headers || {}, binary: options.binary === true };
      if (options.timeout && typeof options.timeout === 'number' && options.timeout > 0) {
        opts.timeout = Math.min(options.timeout, 60000);
      }

      var request = sendNativeRequest(url, {
        method: options.method || 'get',
        body: options.body,
        form: options.form,
        formData: options.formData,
        ...opts,
      }, function(err, resp) {
        if (err) {
          callback(err, null, null);
        } else {
          callback(err, {
            statusCode: resp.statusCode,
            statusMessage: resp.statusMessage,
            headers: resp.headers,
            body: resp.body,
          }, resp.body);
        }
      });

      return function() {
        if (!request.aborted) request.abort();
        request = null;
      };
    },

    send: function(eventName, data) {
      var self = this;
      return new Promise(function(resolve, reject) {
        if (eventNames.indexOf(eventName) === -1) {
          return reject(new Error('The event is not supported: ' + eventName));
        }
        switch (eventName) {
          case EVENT_NAMES.inited:
            if (isInitedApi) return reject(new Error('Script is inited'));
            isInitedApi = true;
            handleInit(data);
            resolve();
            break;
          case EVENT_NAMES.updateAlert:
            if (isShowedUpdateAlert) return reject(new Error('The update alert can only be called once.'));
            isShowedUpdateAlert = true;
            handleShowUpdateAlert(data, resolve, reject);
            break;
          default:
            reject(new Error('Unknown event name: ' + eventName));
        }
      });
    },

    on: function(eventName, handler) {
      if (eventNames.indexOf(eventName) === -1) {
        return Promise.reject(new Error('The event is not supported: ' + eventName));
      }
      switch (eventName) {
        case EVENT_NAMES.request:
          events.request = handler;
          break;
        default:
          return Promise.reject(new Error('The event is not supported: ' + eventName));
      }
      return Promise.resolve();
    },

    utils: utils,

    currentScriptInfo: {
      name: name,
      description: description,
      version: version,
      author: author,
      homepage: homepage,
      rawScript: rawScript,
    },

    version: '2.0.0',
    env: 'mobile',
  };

  // Set global timeout functions
  globalThis.setTimeout = _setTimeout;
  globalThis.clearTimeout = _clearTimeout;

  // Freeze the lx object for security
  var freezeObject = function(obj) {
    if (typeof obj !== 'object') return;
    Object.freeze(obj);
    for (var key in obj) {
      if (obj.hasOwnProperty(key)) {
        freezeObject(obj[key]);
      }
    }
  };
  freezeObject(globalThis.lx);

  // Disable eval and Function constructor for security
  var _toString = Function.prototype.toString;
  Function.prototype.toString = function() {
    var descriptors = Object.getOwnPropertyDescriptors(this);
    return descriptors.name && descriptors.name.configurable
      ? _toString.apply(this)
      : 'function ' + (this.name || '') + '() { [native code] }';
  };

  // Block eval (keep compatibility if host disallows redefining)
  // eslint-disable-next-line no-extend-native
  try {
    globalThis.eval = function() {
      throw new Error('eval is not available');
    };
  } catch (e) {}

  // Block Function constructor (best-effort, avoid hard failure)
  try {
    var ctorDesc = Object.getOwnPropertyDescriptor(Function.prototype, 'constructor');
    if (!ctorDesc || ctorDesc.configurable) {
      var proxyFunctionConstructor = new Proxy(Function.prototype.constructor, {
        apply: function() {
          throw new Error('Dynamic code execution is not allowed.');
        },
        construct: function() {
          throw new Error('Dynamic code execution is not allowed.');
        },
      });
      // eslint-disable-next-line no-extend-native
      Object.defineProperty(Function.prototype, 'constructor', {
        value: proxyFunctionConstructor,
        writable: false,
        configurable: false,
        enumerable: false,
      });
      globalThis.Function = proxyFunctionConstructor;
    } else {
      globalThis.Function = Function.prototype.constructor;
    }
  } catch (e) {}

  console.log('Preload finished.');
};
