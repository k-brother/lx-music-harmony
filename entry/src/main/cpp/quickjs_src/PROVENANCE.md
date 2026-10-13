# 内置的 QuickJS 源码（来源与升级办法）

本目录是工程**内置**的 QuickJS 引擎源码，`entry/src/main/cpp/CMakeLists.txt` 用其中
`quickjs.c` / `cutils.c` / `dtoa.c` / `libunicode.c` / `libregexp.c` 编出
`libquickjs_napi.so`（ArkTS 侧的入口见 `core/napi/NativeModules.ets`）。

## 来源与版本

- 上游：[QuickJS](https://bellard.org/quickjs/)（作者 Fabrice Bellard），MIT 许可，见本目录 `LICENSE`
- 快照：**2025-09-13 正式发布之后的开发态**（`Changelog` 最上面那节是尚未发布的改动）
- 本目录内每个文件都与上游某个提交的内容**逐字节一致，没有本地改动**（下表）。
  唯一例外是本目录的 `.gitignore`：保留上游原有规则，另追加了一段「上游 tarball 里有、
  但本工程不内置的文件」的忽略规则（见文件末尾注释），只为让工作区干净，不影响编译。

| 文件 | 上游提交 |
| --- | --- |
| `quickjs.c` | `d38eea9` |
| `quickjs.h` | `99e9181` |
| `quickjs-atom.h` | `e182e3d` |
| `quickjs-opcode.h` | `31ef02b` |
| `cutils.c` | `9b90125` |
| `cutils.h` | `0d4cd2d` |
| `dtoa.c` | `dbbca3d` |
| `dtoa.h` | `9936606` |
| `libregexp.c` | `a479eff` |
| `libregexp.h` | `f113949` |
| `libregexp-opcode.h` | `f113949` |
| `libunicode.c` | `1f50b39` |
| `libunicode.h` | `d417caf` |
| `libunicode-table.h` | `7693ca9` |
| `list.h` | `37bd4ae` |

## 为什么是"内置"而不是子模块

早期这里挂的是一个 git **submodule**，但 `.gitmodules` 没入库、记录的 gitlink commit
（`6b5577ac`）在上游根本不存在。结果是：**新克隆下来的仓库里 `quickjs_src/` 是空目录，
构建必然失败**（CMake 直接报 `No SOURCES given to target: quickjs_napi`），
只有最初那台手工塞过源码的机器能编过。

所以改成把编译需要的源码直接内置：克隆即能构建，也不依赖网络与子模块。

## 升级办法

1. 从上游取一份新快照：`https://bellard.org/quickjs/quickjs-<version>.tar.xz`
2. 覆盖本目录下的这些文件（上游其它东西如 `doc/ tests/ examples/ fuzz/ qjs.c qjsc.c
   run-test262.c quickjs-libc.* unicode_gen* release.sh` 不需要内置）：

   - `.c`：`quickjs.c cutils.c dtoa.c libunicode.c libregexp.c`
   - `.h`：`quickjs.h quickjs-atom.h quickjs-opcode.h cutils.h dtoa.h libregexp.h
     libregexp-opcode.h libunicode.h libunicode-table.h list.h`
   - 附带：`LICENSE` `Changelog` `readme.txt`

3. 更新本文件的版本说明与上表（`git hash-object <file>` 比对上游客积即可定位提交）
4. `./scripts/release.sh` 重新出包；JS 引擎版本变化属运行时行为，需真机走一遍

## 已知小瑕疵（有意不改）

`CMakeLists.txt` 里的 `-DCONFIG_VERSION="2024-12-31"` 与实际源码版本（2025-09-13 之后）
不一致。它只影响 `JS_GetVersion()` 报出的字符串，工程内没有任何地方消费这个字符串，
因此保持原样（改动等于动原生构建输入，应与真机回归一起做）。

`scripts/check_native_sources.py` 会守住"源码在位"，避免再出现空目录导致的构建失败。
