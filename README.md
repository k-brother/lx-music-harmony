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

### 缓存管理（分项 + 精确统计）

`service/CacheService.ets` 把缓存分成两类，设置页「通用 → 缓存」可分别查看占用并清理：

- **元数据缓存**：歌曲播放链接、歌词（含"无歌词"负缓存）。写入方在 `ResolvePlayback`
  落库时调用 `trackMetadataKey(key, length)` 登记，`cache.metadata.keys` 里保存
  key→字节数的登记表，因此统计是 O(1)、清理能精确删除而不误伤用户数据
  （删除缓存条目时要同步调用 `untrackMetadataKey`）。
- **资源缓存**：封面等图片文件，由 `utils/ImageCache.ets` 管理，对外暴露
  `getEntryCount()` / `getSizeBytes()` 供统计。
- 「清除缓存」按钮走 `cacheService.clearAll()`，并额外清理历史遗留的
  `cacheDir/images`、`tempDir` 与搜索/播放历史。

### 运行日志（设置 → 运行日志）

- `core/log/LogStore.ets` 是内存环形缓冲（默认 1200 条）；`core/log/AppLogger.ets`
  与 `hilog` **完全同签名**，因此业务代码只需把 `import hilog from '@ohos.hilog'`
  换成 `import { appLog as hilog } from '../log/AppLogger'`，日志就同时进入
  系统 hilog 与应用内日志页（播放器、播放解析、音源、插件、HTTP、同步、评论、
  媒体保存等关键链路已接入）。
- `service/LogService.ets` 负责落盘（`filesDir/logs/app.log`，512KB 滚动一份备份）、
  启动时回读最近 300 条、导出为 txt；页面 `pages/LogPage.ets` 支持
  全部 / 警告 / 错误筛选、复制到剪贴板、导出、清空。
- 记录策略：WARN/ERROR 始终记录；DEBUG/INFO 需在设置里开启「记录详细日志」
  （`settings.enableVerboseLog`），避免高频日志占满缓冲。

### 简繁转换（歌词）

`core/lyric/S2TTable.ets`（与安卓版 `simplify-chinese-main` 同源，2537 字对）
 + `core/lyric/ChineseConvert.ets` 提供 `toTraditional` / `toSimplified` /
 `convertChinese(text, mode)`。设置项 `settings.s2tMode`（off / s2t / t2s）在
 `PlayerService.setLyricData()` 内部统一套用，原始歌词单独保存在 `lyricSourceText`，
 所以切换设置时调用 `playerService.applyLyricConversion()` 即可即时生效，
 桌面歌词、系统歌词、播放页共用同一份转换结果。

### 列表能力（排序 / 去重 / 多选 / 同步）

`utils/ListTools.ets` 提供纯函数：`sortSongs`、`dedupeSongs`、`countDuplicateGroups`、
`findDuplicateIndexes`、`normalizeSongName`（可选忽略 Live/伴奏等版本后缀）。
歌单详情页顶部「⋯ → 排序 / 查找重复歌曲 / 多选 / 同步到本地歌单」，
长按单曲为 ActionMenu（添加到歌单 / 下载 / 分享 / 多选 / 查看歌手 / 查看专辑，
后两者通过 `EventTypes.SEARCH_REQUEST` 让首页发起搜索）。多选态底部为批量操作栏，
在线歌单为只读（移出会提示先同步到本地歌单），本地歌单的排序/去重会写回存储
（`ListService.replaceUserListMusic`）。

### 评论（楼层 + 图片 + 归属地）

`service/CommentService.ets` 的 `Comment` 统一带 `images` / `location` / `replies`：
酷我（`mpic` + `child_comments`）、QQ（`Pic` / `Location` / `SubComments`）、
网易云（`beReplied` + `ipLocation`）、酷狗（`images[].url` + `location`）、
咪咕（`replyComments`）。页面按需渲染缩略图（点击全屏预览）与楼层回复块，
并用 `List.onReachEnd` 做真正的分页加载。

### 许可协议（首次启动必须同意）

对齐安卓版 `PactModal` + `common.isAgreePact`：

- 正文（Apache 2.0 补充协议九章）放在 `core/legal/PactText.ets` 按语言整篇维护，
  不拆成大量 i18n 键，便于和法律原文逐条比对；
- `components/common/PactDialog.ets` 首启全屏拦截，「接受」按钮带 20 秒倒计时，
  「拒绝」调用 `terminateSelf()` 退出应用（与安卓版 `exitApp` 一致）；
- 「设置 → 关于 → 许可协议」可随时以只读模式回看。

### 音质 / 分享 / 源名 / 自动主题（本轮补齐的设置项）

| 设置 | 安卓对应 | 实现要点 |
|---|---|---|
| 播放音质 | `player.playQuality` | 四档 128k / 320k / flac / flac24bit；`getPlayQuality` 按音源支持情况向下取；旧版只有「高品质」开关，首次读取时自动迁移 |
| 分享方式 | `common.shareType` | `service/ShareService.ets`：`system` 走 `ACTION_SEND_TO_DATA`（API 26 的 `contentTitle/shareAbstract/shareUrl` 参数字段）拉起系统分享，无分享目标时自动回退剪贴板；`clipboard` 只复制 |
| 分享内容 | — | `core/music/MusicDetailUrl.ets` 生成各平台详情页链接（酷我/QQ/网易/酷狗/咪咕），分享文本与安卓版拼装规则一致 |
| 源名显示 | `common.sourceNameType` | `sourceLabel()` 统一出口，别名（小蜗音乐…）与原名（酷我音乐…）随设置切换 |
| 自动跟随系统 | `common.isAutoTheme` | `themeService.setSystemDarkMode()` + `EntryAbility.onConfigurationUpdate`，浅色/深色主题可分别指定（`theme.lightId` / `theme.darkId`） |
| 动态背景 / 字体阴影 / 深色隐藏背景 | `theme.dynamicBg` / `fontShadow` / `hideBgDark` | 播放页封面模糊背景开关 + 文字阴影；深色主题下可隐藏背景 |
| 播控封面 | `player.isShowNotificationImage` | 关闭后不再向 AVSession 写入 `mediaImage` |
| 蓝牙/车机歌词 | `player.isShowBluetoothLyric` | 开启后把整段 LRC 写入 `AVMetadata.lyric`；关闭时只推送当前句（锁屏单行歌词不受影响） |
| 定时退出「播完再退」 | `player.timeoutExitPlayed` | `SleepTimerService` 在到点且正在播放时等待整首播完（`PlayerService.onTrackCompleted`），播放页可「取消退出」 |
| 允许拖动进度条 | `common.allowProgressBarSeek` | 关闭后播放页进度条不响应拖动，只在手势开始/结束提示一次 |
| 显示搜索历史 | `search.isShowHistorySearch` | 搜索面板历史区开关 |
| 点击列表项播放整个列表 | `list.isClickPlayList` | 歌单详情 / 排行榜详情 / 搜索结果三处按开关决定入队范围；「播放全部」始终整列表入队 |
| 桌面歌词单行 / 文字位置 / 当前句颜色 | `desktopLyric.isSingleLine` / `textPosition.x·y` / `lyricPlayedColor` | 单行模式只显示当前句并按 1 行计算窗口高度；文字位置支持左中右 + 上中下；当前句与未播放行分别取色 |

### 播放器细节补齐（第三轮核对）

- **播放页音量/静音**：安卓播放页设置弹窗有 `SettingVolume`，鸿蒙原先只能在设置页改音量。
  现在「播放页 → 更多 → 音量」打开音量面板：滑杆拖动即时生效、一键静音/取消静音
  （静音会记住原音量，取消时恢复）。
- **播放队列面板**：「更多 → 播放队列」列出当前队列（高亮正在播放的一首），点击任意一首直接切歌。
  功能上覆盖安卓 mini 播放条长按 `jumpListPosition()` 的意图，且对搜索结果/本地音乐这类
  没有「所属列表 id」的队列同样可用；`PlayerService` 为此新增 `getPlayList()` / `getCurrentIndex()`。

### 列表行为对齐修正（第三轮核对）

前两轮把 `list.isClickPlayList` 理解成了「整列表 vs 单曲」，对照安卓源码后发现语义是：

- 安卓 `handlePlay()`：先把**整张歌单**放进临时列表并从该曲开始播，随后后台拉全量页替换队列
  （渐进式 temp list）；`isClickPlayList` 只在「直接用当前列表」与「重新取全量」之间切换，
  **两种情况的队列都是整张歌单**。本轮据此修正：
  - 歌单详情点击行 → 整张歌单入队并立即播放；`listClickPlay=false`（默认）时后台调用
    `fetchAllOnlineSongs()` + `PlayerService.refineQueueWithFullList()` 补全全部页；
  - 榜单详情点击行 → 始终整榜单入队（原先关闭开关时退化成单曲队列，next/prev 直接失效）；
  - 搜索结果点击行 → 用当前结果列表作为临时队列（不静默写入「默认列表」，也不再有单曲队列）；
- 行菜单补齐安卓有的三项：**下一首播放**（`PlayerService.insertNext()` 插到当前曲目之后）、
  **查看来源详情**（`getMusicDetailPageUrl()` + `startAbility(viewData)` 打开平台页）、
  **不喜欢**（歌曲/歌手/歌名三种粒度，与播放页同一套规则）；原有的下载/分享/多选/查看歌手/专辑
  移入二级「更多操作」菜单，一级菜单保持 6 项内。

### 版本检查 / 同步历史 / 自定义源本地导入（本轮补齐的“有服务没入口”）

- **版本检查**：`service/VersionCheckService.ets` 新增 `checkVersionNow()` / `compareVersion()` /
  `APP_VERSION`，启动延迟检查的结果通过 `stateEvent.versionInfoUpdated` 推给
  「设置 → 关于 → 版本信息」：显示当前版本、检查更新（转圈 → 已是最新 / 发现新版本 + 说明）、
  有新版本时可打开发布页；GitHub 仓库行也改为真正 `startAbility(viewData)` 打开。
  （此前只发事件、没有任何 UI 消费，属于死角。）
- **同步历史**：`SyncService` 记录使用过的服务器地址（`sync.serverHistory`，最近 10 条，
  同地址合并），设置页「同步历史」用选择弹窗列出（带最后使用时间、当前项打勾），
  选中即切换服务器、可一键清空服务器地址历史。
- **自定义源本地导入**：自定义源页新增「本地 JS 源文件」入口（DocumentViewPicker 选 .js），
  与在线链接导入并列，导入后同样进入多源列表可启用/更新/删除。

### 收藏歌单与列表级同步

对齐安卓版「收藏歌单 / `syncSourceList`」：

- **收藏在线歌单 = 创建绑定的自建歌单**（`service/UserListSyncService.ets`）：
  全量分页拉取歌曲后，通过 `ListService.createUserListWithSongs(name, songs, source, listId)`
  建列表并记录 `bindingSource` / `bindingListId`，因此在「我的 → 歌单」里可见、可播放；
- **列表级同步**：歌单详情点「收藏」时若已收藏，弹菜单「更新歌单内容 / 取消收藏」；
  「我的」页与自建歌单管理页的绑定列表带「来自xxx」角标与同步按钮，
  调用 `syncUserListFromOnline()` 重新拉取在线内容并覆盖本地（`replaceUserListMusic`）；
- **迁移**：旧版本「收藏」只写了 `collection.songlists` 标记（别处看不到、也无法更新），
  `initAllServices()` 启动时一次性迁移成绑定列表并清空旧标记。

### 自定义源多源管理

对齐安卓版的「userApi 列表」：`core/plugin/PluginStore.ets` 持久化
`plugin.customSources`（id / url / 名称 / 版本 / 作者 / 脚本正文 / 启用状态），
脚本一并保存，所以重启后离线也能直接激活，不必重新下载。

`PluginManager` 对外提供 `getStoredSources()` / `setSourceEnabled()` /
`updateSource()` / `removeSource()` / `restoreEnabledSource()`；
设置页「自定义源」列出全部已导入源，支持启用停用（开关）、更新（重新拉脚本）、
删除（二次确认），并显示「使用中」角标。启动时由 `AppBootstrap` 延迟 3s 恢复
上次启用的源；旧版本只存了一个 URL 的数据会自动迁移成一条记录。

### 与安卓版设置的差异说明（有意保留，不是缺失）

| 安卓设置 | 鸿蒙处理 |
|---|---|
| `common.autoHidePlayBar`（键盘弹出隐藏播放条） | 鸿蒙的搜索是覆盖式全屏面板，播放条本就被遮挡，无需该开关 |
| `common.homePageScroll`（PagerView 横向滑动切 Tab） | 鸿蒙首页用条件渲染 + 底部 Tab 点击切换：Swiper 会一次性实例化 4 个重页面，冷启动更慢，故保留点击切换（切换 Tab 的能力不缺） |
| `common.drawerLayoutPosition` / `showBackBtn` / `alwaysKeepStatusbarHeight` | 抽屉导航与状态栏高度补偿是 Android 布局专有；鸿蒙用底部 Tab + `expandSafeArea` |
| `common.useSystemFileSelector` | Android SAF（`ACTION_OPEN_DOCUMENT`）专有；鸿蒙用 `AudioViewPicker` / `PhotoViewPicker`（本地音乐、封面、下载目录） |

## 架构与 UI 设计系统（Phase 1：底座已落地）

### 设计系统 token

`theme/DesignTokens.ets` 是全应用唯一的视觉出口，除原有颜色/圆角/字号外，本轮补齐了三类 token，
新页面**只允许引用 token，不允许写魔法数字**：

- **度量**：`rowHeight/rowHeightTwoLine/rowInset/rowCover/touchTarget/navBarHeight/radiusSheet`
  （触控目标统一 ≥ 44vp，符合 HarmonyOS/iOS 人因规范）
- **动效**：`motionFast(160) / motionNormal(240) / motionSlow(320)` + `pressedOpacity(0.65)`
  （此前各页 220/240/260/300 混用，手感不一致）
- **层次**：`cardShadow(theme)`（浅色给一点浮起感，深色靠描边，避免深色下发灰）

### UI Kit（`components/ui/`）

| 组件 | 取代的重复实现 | 说明 |
|---|---|---|
| `NavBar` | 10 处手写「Row + 返回按钮 + Text + Blank」 | 支持常规/大标题两种形态、右侧动作 `@BuilderParam`、沉浸式安全区、收缩时补分隔线 |
| `ListRow` | 各页自拼的列表行 | 序号/封面 + 标题 + 副标题 + 右侧内容 + 按压态 + 分割线内缩，`onTap/onLongPress` 由调用方传 |
| `BottomSheet` | 6 处手写遮罩 + 居中弹窗 | 遮罩点击关闭、拖拽把手、统一圆角与底部安全区、出现动效 |
| `StateView` | 各页手写 loading/空/错误 | 三态统一尺寸与文案，错误态可带重试按钮 |

### 服务层统一入口

- `service/DialogService.ets`：`appConfirm()` / `appActionMenu()` / `appToast()`
  - **Promise 化**，页面不再写 `new Promise(resolve => showActionMenu(...))` 样板；
  - 自动处理 ActionMenu「最多 6 个按钮」的限制：超过 5 项折叠为「前 4 项 + 更多…」，
    返回值始终是原始下标，调用方无感；
  - 支持 `dangerIndexes`（危险色）与 `confirmed/danger` 选项，删除类操作不再各页自己配色。
- `service/UiContext.ets`：根页面注入一次 UIContext，让上述能力无需逐层传参。

### 设置页重构（Phase 2 进行中）

`SettingView` 原来是 2971 行的"巨页"（~40 个 @State + 12 个分组构造器 + 备份导入导出 + 缓存清理 + 弹层），
本轮把它拆成「薄编排 + 分组组件」：

```
pages/Home/SettingView.ets      # 编排：Scroll + 分组组件（已从 2971 → 1756 行）
pages/Home/Setting/
├── BasicSection.ets            # 语言 / 启动页 / 退出确认 / 源名 / 分享 / 进度条拖动
├── SearchSection.ets           # 默认源 / 热搜 / 历史开关 / 历史条数
├── ListSection.ets             # 添加位置 / 不喜欢列表 / 自动清理 / 点击行为 / 显示项
├── StorageSection.ets          # 缓存分项 + 一键清理
├── SyncSection.ets             # 同步配置 / 立即同步 / 服务器历史
├── AppearanceSection.ets       # 主题 16 套 / 自动跟随 / 深色 / 动态背景 / 文字阴影 / 字号 / 动画
├── DownloadSection.ets         # 下载目录 / 自动开始 / 并发数
└── AboutSection.ets            # 运行日志 / 关于 / 许可协议 / 版本
```

分组组件约定（后续所有设置分组一致）：

1. **状态自持**：进入时从 `settingsService.get()` 读，变更直接 `settingsService.update()`，
   由设置服务负责镜像 AppStorage 与广播事件 → 页面不再需要「一次性 loadSettings + saveSettings 反写」，
   也不会出现「某个分组忘了写回」的漏项；
2. **不写视觉**：统一交给 `SettingsSection`（分组卡片 + 44vp 行高 + 按压反馈 + 内缩分隔线），
   选择/输入行自带 `SelectSheet` / `InputSheet`，分组组件不需要再写弹层与回调透传；
3. **不写提示**：确认/菜单/轻提示统一 `appConfirm / appActionMenu / appToast`；
4. **逻辑下沉**：清缓存规则下沉到 `CacheService.clearEverything()`（含历史遗留图片/临时目录、搜索历史、播放历史），
   版本比较在 `VersionCheckService`，同步历史在 `SyncService`。

**Phase 2-a 已完成**：`SettingView` 全部 12 个分组拆完，页面 **2971 → 57 行**（纯编排）：

```
pages/Home/Setting/
├── BasicSection / PlaybackSection / DownloadSection / SearchSection / ListSection
├── StorageSection / BackupSection / SyncSection / AppearanceSection
└── DesktopLyricSection / CustomSourceSection / AboutSection
```

配套服务层下沉：

- `service/PlaylistTransferService.ets`：歌单导出/导入（数据收集、结构校验、写回列表、文件读写），
  设置页不再包含 250 行搬运逻辑；导出文件带 `bindingSource/bindingListId`，收藏歌单可再次同步；
- `CacheService.clearEverything()`：一键清理规则（元数据 + 资源 + 历史遗留图片/临时目录 + 搜索历史 + 播放历史）；
- `service/SettingsWatcher.ets`：`watchSettings()` 让分组在**外部改动**（恢复备份、同步下发、其它入口改设置）
  时自动刷新 —— 解决「分组自持状态后外部改了不刷新」的问题，取代旧页面的
  「一次性 loadSettings + saveSettings 反写」模式。

**Phase 2-b 已完成**：`SonglistDetailPage` **2011 → 1523 行**，抽出：

```
pages/SonglistDetail/
├── SonglistDetailHeader.ets   193   头部（展开/收缩两态 + 播放全部/收藏）
├── SonglistBatchBar.ets        92   多选批量栏（添加/下载/移出，本地歌单才可移出）
├── SonglistSortSheet.ets      135   排序面板（字段 × 方式，底部面板）
├── SonglistMenus.ets          107   单曲菜单 + 歌单「更多」菜单（动作集合 + 回调）
└── SonglistTypes.ets           28   SongItem / SonglistInfo（页面与组件共用）
core/list/SongMappers.ets      104   行 ↔ 播放项 ↔ 平台对象的统一转换（原散落 5 处）
```

顺带解决的重复：

- 单曲菜单原来手写两级 ActionMenu（一级 6 项 + 二级 6 项），现在由
  `DialogService.appActionMenu` 自动折叠「更多…」，**一份动作列表搞定 9 个动作**；
- 行渲染改用统一 `ListRow`（序号/勾选/标题/副标题/时长/行尾 ⋮ 一致），多选态勾选圆点也在组件内；
- 顶栏换 `NavBar`，`SongItem` 显式 `extends SongRowLike`（ArkTS 不支持结构化类型，必须显式继承才能复用统一转换器）。

**Phase 2-c 已完成**：`PlayDetailPage` **1915 → 1508 行**，抽出：

```
pages/PlayDetail/
├── AlbumCover.ets            52   封面（展示/手势；失败重试与降级由页面处理）
├── MoreActionsSheet.ets      81   「更多操作」面板（动作列表由页面构造后传入）
├── VolumeSheet.ets           96   音量面板（滑杆 + 静音）
├── QueueSheet.ets            97   播放队列面板（高亮当前曲、点击切歌）
├── SourceSwitchSheet.ets    106   手动换源面板（候选列表来自 ResolvePlayback）
└── PlayDetailMenus.ets      107   倍速 / 歌词显示 / 歌词偏移 / 不喜欢 菜单
```

顺带解决的重复与隐患：

- 「更多操作」原来是 14 行手写按钮元组 + 下标分发（`ix === 0/1/2…`），现在改成
  **动作列表（key + 图标 + 文案）+ key 分发**，加动作不会错位，也摆脱了 ActionMenu 6 项限制；
- 四个面板从「自绘遮罩 + 圆角容器」改成统一 `BottomSheet`（拖拽把手、遮罩点击关闭、出现动效），
  与设置页、歌单详情完全一致；
- 四个命令式菜单（倍速/歌词显示/歌词偏移/不喜欢）合并进 `PlayDetailMenus`，
  全部走 `appActionMenu`（超 5 项自动折叠），页面只接返回值；
- 封面失败处理从内联 `onError` 抽成 `handleCoverLoadError()`（降级 URL → 重试一次 → 占位图），
  逻辑可读、可单测。

**Phase 2-d 已完成**：`PlayerService` **1637 → 1516 行**，按职责抽出两个纯逻辑模块：

```
service/player/
├── LyricHub.ets      185   歌词中枢：LRC 解析/时间轴/当前句/简繁转换/订阅/拉取（走缓存）
└── QueueRules.ets    102   队列推进规则（纯函数）：下一首/上一首/随机/移除后下标/随机历史裁剪
```

- **LyricHub**：PlayerService 原来同时承担"播控 + 歌词时间轴"，现在歌词只通过
  `LyricHubHost`（当前播放位置 / 当前歌曲 key / 状态变化回调）与播放器交互，
  系统播控、桌面歌词、播放页仍然只订阅同一份状态（行为不变）；
  歌词状态类型也统一由 hub 定义、`PlayerService` 转出，避免两份结构（ArkTS 不支持结构化类型）。
- **QueueRules**：4 种播放模式 × 边界条件的推进规则集中到纯函数里
  （`nextIndexFor` / `prevIndexFor` / `pickRandomIndex` / `indexAfterRemoval` / `trimRandomHistory`），
  服务只保留"取下一首 → 播放"的编排；随机播放同时接入"避开最近一半已播"的策略，
  随机历史超过上限自动裁剪（原来会无限增长）。

**Phase 2-e 已完成**：`ResolvePlayback` **1598 → 1000 行**，按"在线/本地/缓存/匹配"切成四块：

```
core/music/local/LocalPlayback.ets        434  本地音乐：扫描/元数据/取链/封面/歌词/内嵌封面
core/music/playback/PlaybackCache.ets     134  播放链接缓存 + 歌词缓存（含 24h"无歌词"负缓存）
core/music/playback/CandidateMatch.ets     85  歌手字段归一、标题松弛匹配、候选打分、链路标识
core/music/ResolvePlayback.ets           1000  在线解析编排（取链/换源/歌词/封面/搜索）
```

顺带处理的三件事：

- **本地与在线彻底分离**：本地走文件系统、在线走音源 SDK，拆开后互不影响；
  本地模块自持 `local` 模块对象，`MusicFeatureEntry` 只做聚合转出，消费方（本地音乐页/服务）改从新模块导入；
- **`createEmptyLyricInfo()` 上移到 `MusicParsingUtils`**：原来只在 ResolvePlayback 里私有，
  拆模块后两处都要用，顺势变成公共工厂（避免各模块各 `new` 一份空歌词结构）；
- **`musicInfoTrace` 并入 `CandidateMatch`**：它本质是"归一后的链路标识"，和候选匹配同源，
  而不是单独一个日志模块（先建了 `Trace.ets` 又并回去，避免碎片化模块）。

**Phase 3 开始（UI/UX 商业化重构）**：先从「我的」页入手（`MylistView` **926 → 526 行**）：

```
pages/Home/Mylist/
├── MylistQuickCard.ets       52   快捷入口卡（我喜欢 / 播放历史，等宽两列 + 按压反馈）
├── MylistEntryRow.ets        62   功能入口行（本地音乐；图标 + 标题 + 描述 + 箭头）
├── MylistSectionHeader.ets   82   区块标题（大标题 + 描述 + 「查看全部」/ 主按钮）
├── UserPlaylistCard.ets     120   自建歌单卡（封面 + 名称 + 数量 + 来源角标 + 播放/同步）
├── SongRowList.ets           39   歌曲行列表（我喜欢/历史共用，基于统一 ListRow）
└── MylistTypes.ets           31   页面与组件共用的行类型
```

界面与交互上的实际变化：

- 快捷入口从「自绘渐变卡」改成**等宽双列卡片**（图标 + 标题 + 数量，统一 14pt 内边距与卡片阴影）；
- 新建歌单从**居中弹窗**改成**底部面板**（与设置页、歌单详情、播放页一致）；
- 歌曲行统一用 `ListRow`（序号/标题/副标题/内边距/分割线一套规则），我自己改样式不会再漏第二处；
- 空态统一 `StateView`（我喜欢 / 播放历史 / 自建歌单三处），加载态也统一；
- 卡片统一 `cardShadow`（浅色给浮起感、深色靠描边），与设置页观感对齐。

**Phase 3 续（首页，`HomePage` 1082 → 942 行）**：

```
pages/Home/Home/
├── SourceTabBar.ets         63   音源切换条（横向滚动标签 + 选中下划线指示）
├── HomeBottomTabBar.ets     69   底部 Tab（选中态强调色 + 图标轻微放大动效）
└── SearchResultLists.ets   172   单曲结果列表（统一 ListRow + 音源徽章）/ 歌单结果列表
```

界面与交互变化：

- **音源切换条**：从"5 个音源等宽硬塞一行"改成**横向可滚动标签 + 选中下划线**（文案变长不再挤压变形，切源时下划线有过渡动效）；
- **底部 Tab**：选中态除了颜色变化，图标带 1.08 倍放大过渡（`motionFast`），观感与商业 App 一致；
- **单曲搜索结果**：改用统一 `ListRow`（序号 + 标题 + 副标题 + 右侧音源徽章 + 内缩分隔线），
  替换原先手写的 60 行行样式；歌单结果行也统一为「封面 + 名称 + 作者·播放量 + 箭头」，播放量按亿/万分级；
- 搜索结果空态/加载态统一 `StateView`；
- 切源逻辑抽成 `onSourceSelected()`（含 180ms 防连点锁），顶栏 builder 不再内联 60 行。

**Phase 2 收尾（巨型文件拆分，已完成）**：

| 原文件 | 原行数 | 现行数 | 拆出的模块 |
| --- | --- | --- | --- |
| `SettingView` | 2971 | **57** | `pages/Home/Setting/*`（12 个分组组件） |
| `SonglistDetailPage` | 2011 | 1660 | `pages/SonglistDetail/*`（Header / BatchBar / SortSheet / Menus / Types） |
| `PlayDetailPage` | 1915 | 1508 | `pages/PlayDetail/*`（封面 / 面板 / 菜单） |
| `PlayerService` | 1637 | 1516 | `service/player/{LyricHub,QueueRules}.ets` |
| `ResolvePlayback` | 1598 | 1000 | `core/music/local/LocalPlayback`、`playback/{PlaybackCache,CandidateMatch}` |
| `SongListView` / `LeaderboardView` | 1216 | — | 首页筛选条统一到 `pages/Home/Home/FilterPillBar` |
| `MylistView` | 926 | 526 | `pages/Home/Mylist/*` |
| `HomePage` | 1082 | 942 | `pages/Home/Home/*`（Tab 条 / 搜索结果） |

**仍未拆分**：`CommentService`(960)。

**Phase 3（UI/UX 商业化）**：把首页/我的/下载/本地音乐/排行榜/评论页逐个套 UI Kit，
统一大标题滚动收缩、Tab 切换动效、骨架屏与空态、深色层次、触控目标校验。

### 迁移进度

- 已完成：`HistoryListPage`、`LoveListPage`、`UserListsPage`（三页从「手写顶栏 + 手写确认框 + 手写遮罩」
  改为 UI Kit + DialogService，行尾统一 ⋮ 菜单，空/加载态统一）
- 已完成：`SettingView`、`SonglistDetailPage`、`PlayDetailPage`、`MylistView`、`HomePage`、
  `LeaderboardView`、`PlayerService`、`ResolvePlayback` 的拆分（见上表）
- 待迁移：`DownloadPage`、`LocalMusicPage`、`CommentPage`、`BoardDetailPage`、`UserListsPage` 的 UI Kit 收口

### 本轮修正（真机日志暴露的问题 + 对齐补口）

- **酷我歌词失败（真机日志 `lyric source result kw ... lyricLen=14` → 暂无歌词）**：
  `core/music/sources/kw/lyric.ets` 重写为双通道 —— 优先 `newlyric`（zlib 压缩体，实测 6/6 稳定），
  失败再走移动端 `songinfoandlrc`（实测服务端约 1/3 概率返回空，**带 3 次重试**）。
  同时按安卓版 `sortLrcArr` 规则把「同时间戳的第二行」拆到 `tlyric`，翻译歌词不再混进正文。
  关键结论（已实测写入注释）：`m.kuwo.cn` **带 Referer 会固定返回「音乐查询失败」**，两个通道都只带移动端 UA。
- **新增原生解压模块**：`entry/src/main/cpp/napi_inflate.cpp` + `core/napi/napi_inflate.ets`。
  ArkTS 只有基于文件、且只认 zip 的 `zlib.decompressFile`，拿不到内存解压能力；
  该模块用系统 `libz` 做内存 inflate，酷我歌词的压缩体由此解开（GB18030 文本用 `util.TextDecoder` 解码）。
- **误导性 JSON 告警**：`HttpClient` / `HttpShared` 对「正文里没有花括号/方括号」的纯文本响应
  （例如酷我 `anti_server` 直接返回音频直链）不再打 `JSON.parse failed`，只在真正像 JSON 却解析失败时告警。
- **搜索联想词**：服务层早有 `getTipListInfo()` 却没有入口，现在首页搜索框输入即出联想列表
  （260ms 防抖 + 请求版本号丢弃过期响应，点击直接搜索），对齐安卓版 `TipList`。
- **歌单内「调整位置 / 移动到其他列表」**：`ListService.moveMusicInList()` + 歌单行菜单两项动作，
  只对本地（我的）列表开放；在线歌单保持只读。菜单改为「按 key 分发」而不是按下标分发，后续插入动作不会错位。
- **修复：歌单排序面板没挂载**（`SortSheet` Builder 定义了但 `build()` 里从未调用，点「排序」无反应），
  同时本地列表排序结果落库（此前只改内存，退出再进又变回原顺序）。
- **列表容器统一**：`ListService` 里 `add/remove/move` 各自复制的一份「默认/我喜欢/用户列表」switch
  收敛成 `resolveListContainer()`，并删掉两处只赋值不使用的 `key` 变量。
- **i18n 清理**：清掉 `more_actions` 重复词条、补上英文缺失的 `history_count`（现在中英一一对齐、无重复、无闲置）。

**真机回归时又揪出三个「定义了但没接上」的缺陷（都已修复并复验）**：

- **底部面板没有脱离文档流**：`components/ui/BottomSheet.ets` 无论 `visible` 真假都会渲染一个
  满屏 `Stack`，被放进页面 `Column` 后会把正文挤扁、面板自身被顶到屏幕外
  （真机表现为：歌单详情只剩上半屏可点，点「排序」毫无反应）。现改为
  `visible` 条件渲染 + `position({x:0,y:0})` 绝对定位，与 `components/common/Dialog.ets` 的既有做法一致。
- **歌单排序面板从未挂载**：`SonglistDetailPage` 里 `@Builder SortSheet()` 定义了却没有在 `build()`
  中调用（点「排序」没反应）；同时本地列表排序只改内存、不落库，退出再进又变回原顺序。两者都已修复。
- **下载页多选批量栏从未挂载**：`DownloadPage.buildToolbar()` 同样漏挂，勾选后没有批量暂停/继续/取消入口。

为避免同类问题再次溜过，`scripts/verify_features.py` 增加了「面板/工具条是否真的挂载」这类结构断言。

### 搜索联想（本轮补齐）

此前只有酷我用「搜索接口的歌名」凑联想词，酷狗/QQ/网易云干脆没有实现，咪咕的联想接口已失效。
现在每个源各自拥有 `core/music/sources/<源>/tipSearch.ets`（与安卓版 `tipSearch.js` 一一对应），
通过既有的 `AbstractMusicSource.getSearchTipBinder()` 挂到 `musicSearch.tip`：

| 源 | 接口 | 备注 |
| --- | --- | --- |
| 酷我 | `tips.kuwo.cn/t.s` | 专用联想服务，返回关键词（不再拿搜索接口凑数） |
| 酷狗 | `searchtip.kugou.com/getSearchTip` | `RecordDatas[].HintInfo` |
| QQ | `c.y.qq.com/.../smartbox_new.fcg` | 返回「歌名 - 歌手」 |
| 网易云 | `music.163.com/api/search/suggest/web` | 明文接口即可，省掉 weapi 加密 |
| 咪咕 | 无 | 官方联想接口返回 HTML，直接返回空，不打扰用户 |

首页搜索框输入后 260ms 防抖拉取，点击联想词直接搜索（安卓版 `TipList` 的对应能力）。

### 商业化交互与鸿蒙系统能力（本轮）

**系统原生桌面歌词（华为音乐同款）**

桌面歌词此前永远退化成应用自绘的黑色浮条——真机日志是
`enableSystemDesktopLyric skipped: session not created` 后直接降级。三处根因与修法：

| 根因 | 修法 |
| --- | --- |
| 启动恢复时 AVSession 还没建，enable 失败即永久降级 | 记住待挂意图，`onSessionReady` 后补挂；`DesktopLyricManager` 再自动把内置浮窗升级成系统歌词并销毁浮窗 |
| 只 `enableDesktopLyric` 没置可见 → 系统歌词窗口不显示 | 补 `setDesktopLyricVisible(true)`，并回读 `isDesktopLyricVisible` 打日志 |
| 整段 LRC 只在「蓝牙歌词」开关开启时才下发 | 元数据按 `蓝牙歌词 \|\| 系统桌面歌词` 决定是否带 LRC，同一首歌重复 setMetadata 时继承已有歌词，避免被覆盖 |

真机验证：系统 `mediacontroller` 拉起自己的 `DesktopLyricPage` 在桌面渲染歌词行，
应用侧日志 `lrc=true, single=true`。设置页在系统接管时给出模式提示，避免"改外观没反应"的困惑。

**触感反馈（`service/HapticService.ets`）**

统一语义化 API（`selection/light/medium/heavy/success/warning`）+ 系统预设效果 + 时长兜底 +
24ms 节流 + 跟随「设置 → 基本 → 触感反馈」；权限 `ohos.permission.VIBRATE` 已声明。
接入点：底部 Tab、播放/暂停、上/下一曲、长按动作菜单、设置开关。

**下拉刷新（`components/ui/RefreshContainer.ets`）**

歌单、榜单、下载管理、我的列表四页支持下拉刷新（刷新触发同时给一次触感）。

**统一分段控件（`components/ui/SegmentedBar.ets`）**

`track`（轨道 + 浮起滑块）/ `chip`（等宽胶囊）两种变体，替换歌单排序、运行日志筛选、
播放页封面/歌词切换、下载页状态筛选四处手写实现，分段样式现在只在一处维护。

**触控热区（`DesignTokens.touchRegion`）**

图标往往只有 16~30vp，直接放大图标会破坏视觉层次，于是用 `responseRegion` 把热区补到 44×44vp；
已覆盖返回按钮、播放页更多、下载页任务操作图标、榜单展开/进入、我的歌单同步/播放、本地音乐重扫等。

**系统符号渲染（`SymbolGlyph`）**

真机确认 `Image($r('sys.symbol.*'))` 不会渲染任何内容（系统符号是字体字形资源），
此前全项目 45 处图标（底部 Tab、空态、列表箭头、下载操作、播放量角标）都是空白的。
现统一改用 `SymbolGlyph(...)`，`width/height` 换成 `fontSize`、`fillColor` 换成 `fontColor([...])`；
`scripts/check_symbols.py` 会拦住回退写法。

**底部浮层（`bindSheet` + 全局面板宿主）**

自行绘制的浮层有两个真机缺陷：挂在页面 `Column` 里会把正文挤扁；改成绝对定位后又被 `Scroll`
裁剪（表现为「设置里点选项没反应」）。现在 `BottomSheet` 底层用系统 `bindSheet`
（窗口级浮层，不参与布局、不被裁剪，自带遮罩/圆角/下拉关闭/安全区；
注意锚点必须是 1×1 有效尺寸，0×0 不会挂载）。

设置分组则通过 `service/SheetService` + `components/ui/SheetHost` 命令式调用：

```ts
const theme = await sheetService.select('浅色主题', options, current); // 取消返回 ''
const size = await sheetService.input('字体大小', '14', { numberOnly: true });
```

宿主挂在 `NavIndex` 根节点，任何页面/分组都能安全弹出面板。

### 自检脚本

每轮改完在 `harmony/` 下跑一遍（脚本在 `scripts/`，不依赖网络）：

```bash
./scripts/check.sh            # 依次跑下面四项
python3 scripts/check_imports.py       # 未使用的 import = 0
python3 scripts/check_dead.py          # 未被引用的私有方法 = 0
python3 scripts/check_i18n.py          # 中英词条一一对应、无重复、无闲置
python3 scripts/verify_features.py     # 与安卓版的功能对齐清单
```

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
- [ ] 英文语言下界面无残留中文（i18n 513 键中英一一对齐、无闲置键）

### 本轮新增能力
- [ ] 设置 → 缓存：元数据/资源缓存分别显示占用与条数，清理后数值刷新
- [ ] 设置 → 运行日志：筛选、复制、导出（`filesDir/logs/`）、清空均生效
- [ ] 播放中切换「简繁转换」，歌词（含桌面歌词/系统歌词）立即切换
- [ ] 歌单详情「⋯」：排序（5 字段 × 升/降/随机）、去重、多选批量（添加/下载/移出）
- [ ] 歌单详情长按单曲：ActionMenu 六项可用，「查看歌手/专辑」回首页搜索
- [ ] 评论页：带图评论可点击看大图；楼层回复内联展示；滑到底加载下一页
- [ ] 首次启动弹出许可协议，20 秒后才可「接受」；拒绝退出应用；设置内可回看
- [ ] 音质切到 320k/FLAC 后，音源不支持时自动向下取值且不报错
- [ ] 分享方式选「系统分享」能拉起系统分享；无目标时提示已复制
- [ ] 源名显示切「原名/别名」，首页源切换与列表角标同步变化
- [ ] 打开「自动跟随系统」后，切换系统深色模式，界面主题立即跟随
- [ ] 打开「动态背景」播放页出现封面模糊背景；「字体阴影」让文字更清晰
- [ ] 桌面歌词「单行模式」「文字位置」「当前歌词颜色」三项即时生效

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
