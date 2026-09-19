# LX Music Mobile (洛雪音乐)

A cross-platform music player application supporting multiple music source platforms.

## Project Overview

LX Music Mobile is a music player app built with two parallel implementations:

- **HarmonyOS NEXT** - ArkTS-based implementation in `harmony/` (current active development)
- **React Native (Android)** - TypeScript implementation in `src/` (planned)

## Music Sources

The app integrates with 5 major Chinese music platforms:

| Source | Code | Description |
|--------|------|-------------|
| Kuwo | `kw` | 酷我音乐 |
| Kugou | `kg` | 酷狗音乐 |
| Migu | `mg` | 咪咕音乐 |
| QQ Music | `tx` | QQ音乐 |
| Netease | `wy` | 网易云音乐 |

Each source implements common interfaces for:
- Music search
- Play URL retrieval
- Lyrics
- Song lists
- Leaderboards
- Hot search

## Project Structure

```
harmony/                          # HarmonyOS implementation
└── entry/src/main/ets/
    ├── app/                      # Application entry and config
    ├── components/               # Reusable UI components
    │   ├── common/               # Common components (ListItem, Dialog, etc.)
    │   ├── media/                # Media-related components
    │   └── player/               # Player components (PlayerBar)
    ├── core/                     # Core business logic
    │   ├── interfaces/           # Interface definitions
    │   ├── list/                 # List operations
    │   ├── music/sources/       # Music source implementations (kg, kw, mg, tx, wy)
    │   ├── network/              # Network utilities
    │   └── playback/             # Playback control
    ├── pages/                    # Screen pages
    │   ├── Home/                 # Home page components
    │   ├── HomePage.ets          # Home page
    │   ├── PlayDetailPage.ets   # Play detail page
    │   ├── SonglistDetailPage.ets # Song list detail page
    │   ├── BoardDetailPage.ets  # Leaderboard detail page
    │   ├── CommentPage.ets      # Comment page
    │   └── DownloadPage.ets     # Download management page
    ├── service/                  # Services (HTTP, Storage, List, EventBus)
    ├── store/                    # State management
    ├── types/                    # TypeScript type definitions
    └── utils/                    # Utilities
```

## Building

### HarmonyOS

```bash
cd harmony

# App package build (macOS/Linux/Windows)
./hvigor.sh assembleApp
# 或 Windows CMD:
hvigor.bat assembleApp

# Release build (需配置签名)
./hvigor.sh assembleRelease
```

构建产物位于 `harmony/.hvigor/outputs/`。

## Architecture

### Music Source Abstraction

All music sources implement the `IMusicSource` interface defined in `core/music/sources/IMusicSource.ets`:

```typescript
interface IMusicSource {
  search(keyword: string): Promise<MusicItem[]>
  getPlayUrl(songmid: string): Promise<string>
  getLyric(songmid: string): Promise<LyricData>
  getSongList(listId: string): Promise<SongList>
  getLeaderboard(): Promise<BoardList>
  getHotSearch(): Promise<HotSearchItem[]>
}
```

### State Management

HarmonyOS uses `@State` / `@StorageProp` decorators with event-based communication via `EventBus`.

### 设置与持久化（重要约定）

**所有设置项只有一个入口**：`entry/src/main/ets/service/SettingsService.ets`

- 设置项统一持久化在 `StorageService` 使用的 Preferences 实例（`lx_music_preferences`）中，
  键名统一为 `setting.*`（见 `StorageService.StorageKeys`）。
- 首次启动会自动迁移历史版本写在 `music_settings` / `download_settings` / `sync_config`
  里的旧值，用户设置不会丢。
- 写入路径统一为 `settingsService.update(patch)`，内部会：更新内存快照 → 镜像到
  `AppStorage`（驱动 `@StorageProp` 刷新）→ 广播 `EventTypes.SETTING_CHANGED`
  （驱动服务层刷新，如播放器音质/播放模式、下载目录、列表插入位置等）。
- 读设置用同步的 `settingsService.get()`，不要在各页面里
  `preferences.getPreferences(context, 'music_settings')`。

新增设置项的步骤：在 `AppSettings` / `SettingsPatch` 中加字段 → 在 `createDefaultSettings`、
`loadFromStorage`、`update`、`copyOf` 中补齐 → 在 `StorageKeys` 中加键 → 由使用方读取。

### 定时退出（睡眠定时）

设置页与播放详情页共用 `service/SleepTimerService.ets`，不要再各自 `setTimeout`。

### 歌词架构（系统歌词 / 桌面歌词 / 播放页共用一份数据）

`service/PlayerService.ets` 是**唯一的歌词中枢**：

- 切歌时自动拉取歌词（走 `ResolvePlayback` 的歌词缓存，重复播放不重复请求），
  用 `parseLrc` 建立时间轴；播放进度推进时由它计算"当前句/下一句"。
- 对外只暴露三件事：
  - `onLyricLineChange(listener)`：订阅 `{hasLyric, index, current, next}`；
  - `setLyricData(lrc)`：播放页已经取到歌词时回灌，避免重复请求；
  - `getLyricState()` / `getLyricText()`：同步读取当前状态。
- 系统歌词：每次"当前句"变化时把整段 LRC 与当前单句写入 AVSession 元数据
  （`AVMetadata.lyric` + `AVMetadata.singleLyricText`），锁屏/控制中心/灵动岛因此能显示歌词。
  这是本 SDK（HarmonyOS 6.0.2 / API 23）提供的系统级歌词通道——该 SDK 没有 LiveViewKit（实况窗）。
- 桌面歌词：`components/common/DesktopLyric.ets` 只负责把上面的状态渲染到子窗口，
  默认**全透明**（靠文字阴影保证可读性），支持拖动改位置、锁定穿透、字号/颜色/背景不透明度/单双行设置。

新增歌词消费方时，请订阅 `onLyricLineChange`，不要各自再解析一遍 LRC。

### 系统桌面歌词（HarmonyOS 26 / API 26）

`build-profile.json5` 已升级到 `targetSdkVersion/compatibleSdkVersion = 26.0.0`，
因此可以使用 AVSession 的原生桌面歌词能力：

- 支持性探测：`avSession.isDesktopLyricSupported()`
- 开关：`session.enableDesktopLyric(enable)`
- 显示/隐藏：`session.setDesktopLyricVisible(visible)`
- 锁定（不可拖动 + 点击穿透）：`session.setDesktopLyricState({ isLocked })`
- 状态回调：`session.onDesktopLyricStateChanged(cb)`

`DesktopLyricManager.setEnabled()` 会**优先使用系统歌词**，设备/系统不支持时自动降级为
内置悬浮窗（`pages/DesktopLyricPage.ets`）。系统歌词的外观与位置由系统负责，
内置悬浮窗则支持颜色/字号/背景不透明度/单双行等自定义项。

其余系统级歌词通道：`AVMetadata.lyric`（整段 LRC）+ `AVMetadata.singleLyricText`
（当前句），锁屏/控制中心据此显示歌词。

### 本地音乐

- `core/music/ResolvePlayback.ets`：`scanLocalMusic(dir)` 用 `AVMetadataExtractor`
  读取标题/歌手/专辑/时长；`readEmbeddedPic()` 提取内嵌封面并缓存为 `*<file>.cover.jpg`。
- `service/LocalMusicService.ets`：导入（`AudioViewPicker` → 复制进沙盒
  `${filesDir}/localMusic`）、曲库持久化（`local.music.list`）、删除、转 `SongInfo`。
- 页面：`pages/LocalMusicPage.ets`（我的 → 本地音乐），播放走 `file://`，不依赖网络。

### 歌单搜索

各源按需实现 `SongListSdkInterface.searchList`（当前网易云、QQ音乐可用；
酷我/酷狗/咪咕的公开接口需要签名或已失效）。聚合入口
`MusicSdkAggregate.searchSongLists()`，统一搜索入口 `core/search.searchSonglist()`：
当前源不支持时会自动回退为全源聚合。UI 在首页搜索面板的「单曲 / 歌单」切换里。

### 下载备份

`BackupService` 现在会把已完成/失败的下载任务（含歌曲信息与文件路径）写入备份，
恢复时通过 `restoreDownloadTasksFromBackup()` 重新登记，下载页可见且可直接播放。

## 设备验收清单（需要真机确认，代码侧已按此实现）

> 这些能力依赖真机系统服务或物理设备，构建通过 ≠ 设备可用，逐项勾选即可。

### 系统级歌词
- [ ] 播放页 / 设置页打开「桌面歌词」后，出现的是**系统原生歌词**（不是应用自绘的悬浮条）
- [ ] 若设备不支持系统桌面歌词，能自动**降级**为内置悬浮窗（透明浮字、可拖动、可锁定）
- [ ] 锁屏 / 控制中心出现歌词（来自 `AVMetadata.lyric` + `singleLyricText`）
- [ ] 内置悬浮窗设置项生效：颜色、字号、背景不透明度、显示下一句、锁定穿透

### 本地音乐
- [ ] 「我的 → 本地音乐」导入设备音频后列表出现曲目，标题/歌手/时长正确
- [ ] 内嵌封面能显示（首次会解码并缓存为 `*.cover.jpg`）
- [ ] 点击直接播放（`file://`，不依赖网络）；长按出现「播放 / 从本地曲库移除」

### 搜索与歌单
- [ ] 搜索面板切到「歌单」，用网易云 / QQ 源能搜到歌单并进入详情
- [ ] 当前源（如酷我）不支持歌单搜索时，能自动回退为全源聚合

### 播放与下载
- [ ] 拖动进度条时时间跟着手指走，**松手才跳转**
- [ ] 长按播放页封面：收藏 / 下载 / 分享 / 保存封面 / 评论 均可用
- [ ] 分享后可在别处粘贴出 `[平台] 歌名 - 歌手 · 专辑 · 00:42`
- [ ] 关闭「自动开始下载」后新任务进入「等待中」，可手动开始
- [ ] 暂停 / 继续下载是真的中断与续传（走系统 downloadFile 的 pause/resume）
- [ ] 备份 → 恢复后，歌单与设置**无需重启**即可生效

### 冷启动与性能
- [ ] 首屏出现后，本地曲库与图片索引在后台补齐（不阻塞首帧）
- [ ] 切歌、切换 Tab、滚动长列表无可感知卡顿

### 兼容性
- [ ] 深浅色模式下，弹窗（Dialog / ActionMenu）、卡片、空态颜色正确
- [ ] 英文语言下界面无残留中文（i18n 358 键中英对齐）

### 已移除的功能

- **均衡器（Equalizer）**：HarmonyOS 6.0.2（API 23）没有公开的音频均衡器接口，
  原先的实现只是创建了一个与其无关的 `AudioRenderer`（既不生效又占用音频流），
  已删除组件、服务与设置入口。

### Services

- **HttpService** - HTTP request handling
- **StorageService** - Persistent storage
- **ListService** - Playlist management
- **EventBus** - Inter-component communication

## Dependencies

### Core Dependencies
- HarmonyOS SDK
- ArkTS language

### Key Modules
- `@ohos.media` - Media playback
- `@ohos.storage` - Local storage
- `@ohos.http` - Network requests
