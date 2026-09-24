# LX Music for HarmonyOS

洛雪音乐（LX Music）的 **HarmonyOS NEXT 原生实现**：用 ArkTS 写的第三方音乐播放器外壳，
支持多音源检索与播放、歌单/榜单、本地音乐、下载管理、系统级歌词（桌面歌词 / 播控中心 / 灵动岛胶囊）。

> **本项目只提供播放器本身，不内置、不托管、不传播任何音乐资源。**
> 歌曲均来自公开的第三方音源接口或用户自行导入的自定义源，请自行确认使用行为的合法性。

[![License](https://img.shields.io/badge/license-Apache--2.0-blue.svg)](LICENSE)
![Platform](https://img.shields.io/badge/platform-HarmonyOS%20NEXT-black)
![API](https://img.shields.io/badge/API-26-orange)
![Language](https://img.shields.io/badge/language-ArkTS-brightgreen)

---

## 功能

**多音源**

- 内置源：酷我、酷狗、咪咕、QQ 音乐、网易云
- 自定义源：支持导入 JS 插件（内置 QuickJS 引擎执行），可多源切换、启停、更新
- 播放地址 / 歌词 / 封面 / 歌单 / 榜单 / 热搜 全链路按源适配，单源失败自动跨源兜底

**播放**

- 后台播放与播控中心（AVSession）：锁屏、控制中心、耳机线控、循环档、收藏
- 系统原生桌面歌词（HarmonyOS 26 系统能力，与实况窗/灵动岛胶囊同源），可锁定、隐藏
- 歌词：逐字歌词、翻译、罗马音、简繁转换、偏移调节、手动滚动暂停跟随
- 播放队列（拖拽排序、插入下一首）、倍速、音量、定时退出

**曲库与内容**

- 搜索（含联想词、历史）、歌单广场、排行榜、歌手/专辑跳转
- 我的：我喜欢、播放历史、自建歌单，支持多选批量、排序、去重、整列表同步
- 本地音乐：扫描导入、元数据编辑、同名歌词文件、内嵌封面
- 下载：并发可配、后台队列、文件名规则、下载历史与备份
- 评论（楼层 + 图片预览）、分享、歌曲详情页链接

**体验**

- 深浅色各 16 套主题 + 跟随系统 + 动态背景/字体阴影开关
- 一多适配（手机 / 2in1）、长列表滚动记忆、下拉刷新
- 无障碍：纯图标按钮带朗读文案、键盘可操作（2in1）
- 应用内日志（可导出）、未捕获异常兜底（不闪退并落盘）、加密备份/恢复

## 环境要求

| 项 | 版本 |
|---|---|
| DevEco Studio | 6.x（支持 API 26） |
| HarmonyOS SDK | API 26（`compileSdkVersion` / `targetSdkVersion` = 26.0.0） |
| 设备 | HarmonyOS NEXT 手机 / 2in1（系统桌面歌词等能力需 API 26 真机） |

## 构建

用 DevEco Studio 打开本目录（`harmony/` 即工程根目录），首次打开后按提示配置签名：

```
File → Project Structure → Signing Configs → 勾选 Automatically generate signature
```

命令行构建（`hvigor.sh` / `hvigor.bat` 为随工程提供的 wrapper）：

```bash
./hvigor.sh assembleApp     # 打 App 包
./hvigor.sh assembleHap     # 只打 HAP
```

产物位于 `entry/build/<buildMode>/outputs/<product>/`。

> 签名材料（`.p12` / `.p7b` / `.cer` 与口令）**不在仓库里**，`build-profile.json5` 的
> `signingConfigs` 保持为空；使用自己的发布证书请在 DevEco 的 Signing Configs 面板导入。
> 仓库带了一道提交前检查（`scripts/check_no_secrets.py`），防止口令/证书被误提交。

### 自检

工程自带可执行的自检脚本（当前 370 项判据：资源引用、i18n 词条对齐、无障碍、面板与弹框规范、
播放与播控约定等），提交时由 `.githooks/pre-commit` 自动运行：

```bash
./scripts/check.sh         # 全量自检
SKIP_CHECKS=1 git commit … # 紧急时跳过钩子
```

## 目录结构

```
entry/src/main/ets/
├── app/           应用入口（EntryAbility、启动引导）
├── components/    可复用 UI（播放条、面板、通用行、空态等）
├── core/          与 UI 无关的核心层
│   ├── music/     音源适配（kw/kg/tx/wy/mg）、播放地址、歌词、本地音乐、下载
│   ├── search/    搜索聚合
│   ├── list/      歌单与列表领域逻辑
│   ├── theme/     16 套主题数据与主题工厂
│   ├── napi/      原生模块统一加载入口（QuickJS、zlib）
│   └── network/   网络请求封装
├── pages/         页面（首页、播放详情、歌单/榜单/评论/下载/设置…）
├── service/       服务层单一入口：设置、播放、播控、下载、同步、备份、日志…
├── store/         状态容器
└── utils/         工具函数
entry/src/main/cpp/  QuickJS / zlib 的 NAPI 原生实现（CMake）
scripts/             自检脚本（提交前自动执行）
```

## 架构要点

- **音源是插件式适配**：每个源实现同一组契约（搜索 / 取链 / 歌词 / 封面 / 歌单 / 榜单），
  上层只依赖抽象，新增音源无需改动业务代码。
- **服务层单一入口**：设置、播放、播控、下载等状态都只有一个写入方，避免多份状态漂移。
- **一份歌词喂三处**：时间轴与当前句由播放服务统一维护，播放页 / 系统播控 / 桌面歌词共用。
- **原生能力统一收口**：`.so` 只在 `core/napi/NativeModules.ets` 加载，句柄类型单点声明。
- **约定用脚本钉住**：容易被改回去的写法（面板规范、文案出口、资源引用等）都有对应自检项。

## 免责声明

- 本项目仅用于**技术学习与交流**，不提供、不存储、不分发任何音频文件或歌词内容。
- 所有内容来自第三方接口或用户自行配置的自定义源，版权归各自权利人所有；
  请勿用于商业用途，下载或传播受版权保护的内容可能违法，风险由使用者自负。
- 因使用本项目产生的任何后果（包括但不限于账号封禁、法律纠纷）由使用者自行承担。
- 若权利人认为本项目存在问题，请提 Issue，我们会配合处理。

## 开源协议

本项目以 **Apache License 2.0** 开源，详见 [LICENSE](LICENSE) 与 [NOTICE](NOTICE)。

本项目是 [LX Music（洛雪音乐）](https://github.com/lyswhut/lx-music-desktop) 的 HarmonyOS 移植实现，
音源解析逻辑与部分资源沿用上游，遵循其 Apache-2.0 协议并保留署名；
内置的 QuickJS 引擎来自 [QuickJS](https://bellard.org/quickjs/)（MIT）。

## 致谢

- [lyswhut/lx-music-desktop](https://github.com/lyswhut/lx-music-desktop) /
  [lyswhut/lx-music-mobile](https://github.com/lyswhut/lx-music-mobile)：本项目的上游
- QuickJS（Fabrice Bellard）：自定义源脚本运行环境
- 以及所有为第三方音源接口摸索付出过时间的开发者
