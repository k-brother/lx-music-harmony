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

**拆分已完成**：`CommentService` 也早已拆到 90 行（适配器在 `service/comment/sources/*`）。
当前超过 1000 行的文件只剩三个，且都是「编排 + 状态」为主体、不宜再拆：
`PlayerService`(1282) / `PlayDetailPage`(1007) / `SonglistDetailPage`(1002)。

### Phase 2-f：死代码收敛与「服务有、界面没有」补口（本轮）

这轮的重点是**用静态扫描替代人工记忆**：先写出扫描脚本，再让脚本告诉我哪里有问题。
七个脚本全部挂进 `scripts/check.sh`，任一不通过即 `exit 1`，出包脚本 `scripts/release.sh`
会先跑自检再打包。

| 脚本 | 守什么 | 本轮发现并处理 |
| --- | --- | --- |
| `check_imports.py` | 未使用的 import | 持续保持 0 |
| `check_dead.py` | 私有方法/函数 + **类成员**（ArkUI 生命周期豁免） | 新增类成员扫描后揪出 41 个无人调用成员，其中 3 处是真缺口（见下） |
| `check_unused_exports.py` | 导出但全项目零引用 | 清理 49 个（音源契约残留、播放插件里与 config 重复的焦点/音量函数、各种历史遗留） |
| `check_reachable.py` | 入口可达性（死模块） | 删掉 9 个不可达文件：`core/index` barrel 及它唯一导出的 `core/songlist`(423 行)/`hotSearch`/`lyric`、三个子目录 barrel、0 字节空文件 |
| `check_i18n.py` | 重复/中英不一致/未使用/未定义词条（本轮改为硬门禁） | 修掉 `sync_msg_connect_fail` 拼错导致界面显示原始 key；清掉 5 条死词条 |
| `check_symbols.py` | `sys.symbol` 必须用 SymbolGlyph + **符号名必须在 SDK 名单里** | 新增符号名校验（拼错名字真机上同样什么都不显示） |
| `check_settings_copy.py` / `check_settings_reset.py` | 设置快照与「恢复默认设置」的字段完整性 | 后半是新增：`resetToDefaults` 漏了 6 个字段（桌面歌词坐标 / 下载目录等） |
| `check_duplicate_impls.py` | 「函数体完全相同」的重复实现 | 24 → 7（剩下的都是设置分组的 2 行样板） |
| `check_routes.py` | 路由一致性：用到的路由必须有页面分支、分支必须有枚举、枚举必须有人用 | 清掉 4 个死路由（网络测试/酷我测试/下载测试/下载页）与 1 个孤儿分支 |
| `check_storage_bindings.py` | AppStorage 绑定闭环：有人读的键必须有人写 | 顺带发现 25 个「镜像了但没人读」的设置项，镜像从 61 个收敛到 36 个 |
| `check_permissions.py` | 权限声明与实际调用一致（上架审核项） | 4 个权限全部对得上，没有过度声明 |
| `verify_features.py` | 212 条功能/结构断言（含「面板是否真的挂载」） | 随拆分同步更新判据 |

**顺带修掉的真缺陷**（都是扫描出来的，不是猜的）：

- 本地音乐**读不到同名 `.lrc`**：`ResolvePlayback` 对 `source=local` 直接返回空歌词，
  而 `core/music/local` 里的 `readLyricFile` 是个 `return null` 的空桩 ——
  「音频与歌词放一起」这个最常用的用法在鸿蒙版等于没有歌词。现在优先读同名文件
  （UTF-8 / GB18030 自适应），读不到再回退在线匹配。
- **同步历史菜单点了没反应**：弹「使用历史服务器 / 清空同步历史」时，服务器列表算出来了却没人用。
  改为直接列出历史地址、选中即切换，清空拆成独立危险色行。
- **备份出来就找不到了**：`createBackup` 写的是应用沙箱目录，而界面上没有任何入口能看到/恢复/删除，
  只能靠系统文件选择器碰运气。新增「本地备份」行（列表 · 恢复 · 删除）与自动备份开关/间隔。
- **同步状态从来没显示过**：`SyncService` 的状态消息（连接中/服务器不可用/同步完成…）只在自己内部流转，
  现在设置页有「同步状态」只读行（为此给 `SettingsSection` 补上一直空缺的 `info` 行类型）。
- **恢复默认设置改了语言要重启才生效**：只有设置页手动切语言会调 `setLanguage()`，
  恢复默认设置/恢复备份/同步下发都会改 `settings.language` 却不经过设置页。
  现在 `AppBootstrap` 订阅一次设置变化自动跟随。
- 界面上的 10 处硬编码中文（评论相对时间、匿名用户、锁屏「未知歌曲/歌手」、自定义源默认元信息、
  同步错误兜底、歌单空提示、播放量里的「万」）全部走词条。
- 「回复」按钮用的是音符列表图标（语义错）、试听历史空态用的是刷新箭头（语义错）：换成
  `text_bubble_left_2` / `clock`；6 处可点行/卡片补上按压反馈。
- 首页下载 Tab 的大标题与副标题是同一句话（`download_title` 写了两遍）。
- 榜单详情头部的「播放全部」按钮写了两份（展开态/收缩态），抽成 `BoardDetailHeader` 共用一份。

**本轮拆分**（页面回到「状态 + 编排」，业务动作各归其位）：

| 文件 | 原行数 | 现行数 | 拆出的模块 |
| --- | --- | --- | --- |
| `SonglistDetailPage` | 1197 | **1002** | `SonglistDetail/{SonglistPlayActions, SonglistLocalLibrary, SonglistRowActions, SonglistSelection}` |
| `PlayDetailPage` | 1095 | **1007** | `PlayDetail/PlaySettingsActions`（歌词显示/定时退出/播放模式）；build 拆成 DynamicBackdrop / PlayerStage / PlaySheets |
| `BoardDetailPage` | 531 | **415** | `pages/Board/BoardDetailHeader` |
| `LocalMusicPage` | 535 | **334** | `pages/LocalMusic/{EditMetadataSheet, LocalMusicActions, TrackRow}` |
| `PlayerService` | 1340 | **1282** | `service/player/PlaybackInputs`（播放入参映射与校验） |
| `EventBus` | 300 | **226** | 删掉 10 个无人订阅的旧事件与 8 个无人调用的发射器 |
| `utils/Utils` | 94 | **18** | 6 个与 `CommonUtils` 重复的数组/判空/深拷贝实现 |

另外清理了资源与镜像里的死物：6 个没人引用的图片（含 816KB 的 `myzcbg.jpg`，
图标与启动图现在都走 `layered_image`）、1 个只写不读的 `@State`、
25 个没人读的 AppStorage 镜像键。

**出包**：`./scripts/release.sh` = 全量自检 + `product=release` 构建（`signingConfig=LXMusic`），
产物 `entry/build/release/outputs/default/entry-default-signed.hap`（约 8MB，已签名）。

### Phase 4：鸿蒙特性与商业级体验（一多 / 无障碍 / 长列表 / 手势）

这一轮不再只看代码结构，而是对着「鸿蒙系统能做什么、主流音乐 App 长什么样」逐项对齐。
每一项都有可核查的落点，不靠印象：

| 能力 | 之前 | 现在 |
| --- | --- | --- |
| **一多（响应式）** | `module.json5` 声明了 phone/2in1，代码里没有任何窗口尺寸处理，大屏就是拉宽的手机布局 | `WindowService` 订阅 `windowSizeChange` → 广播 `breakpoint`/`windowWidthVp`；断点按鸿蒙规范 sm<600≤md<840≤lg；`theme/Breakpoints` 提供纯计算出口 |
| **播放页大屏形态** | 只有「封面/歌词」二选一的 Swiper | md 及以上改双栏：左封面 + 右歌词同屏，顶部不再出现切换控件（窄屏形态不变，共用同一个 LyricSection） |
| **首页大屏形态** | 底部 Tab 拉满整屏 | 宽屏改「左侧 96vp 导航栏 + 右侧顶栏/内容/播放条」，同一组件的 vertical 形态，选中态与动效共用 |
| **我的页 / 设置页大屏** | 单列长滚动 | lg 分两列（左列常用、右列进阶），两列顺序与单列一致；分组声明只写一份（LeftSections/RightSections） |
| **搜索浮层大屏** | 搜索框与结果横跨整屏 | 内容列居中（背景仍通栏）；歌单广场的搜索条/筛选条也与下方网格对齐 |
| **播放控制区大屏** | 进度条与三个按钮被拉到整屏宽 | 限宽 640vp 居中 |
| **内容列宽** | 单行文字横跨整屏 | 设置/评论/下载/本地音乐/历史/我喜欢/日志/我的/榜单/歌单详情/榜单详情 统一 1200vp 内容列居中，顶栏底栏仍通栏 |
| **网格列数** | 手机 3 列写死 | 手机 3 / 折叠屏展开 4 / 平板横屏与 PC 6，骨架列数同档避免跳变 |
| **长列表** | 全项目 0 处 LazyForEach，上千首歌一次性建满组件树 | 新增 `utils/LazyDataSource`（reload / notifyChanged），歌单详情、榜单详情、历史、我喜欢、本地音乐、评论、歌单广场、播放队列共 8 处改为 LazyForEach + cachedCount(6) |
| **侧滑手势** | 只有长按菜单 | 播放队列与本地音乐支持侧滑删除（`ListItem.swipeAction`），本地音乐带二次确认 |
| **鼠标态（2in1）** | 只有按压态 | 列表行统一 `hoverEffect(HoverEffect.Highlight)` |
| **无障碍** | 全项目 `accessibilityText` 数量为 0 | 33 处纯图标点击目标全部可朗读（含随状态变化的播放/暂停、展开/收起），新增 18 条 a11y_* 词条 |
| **返回键** | 5 个页面写的 `onBackPressed()` 名字不对，从未被调用 | 删掉死方法；`AppDestination` 接真正的 `.onBackPressed()` → `NavigationService` 返回拦截栈；歌单多选态按返回先退出多选 |
| **加载态** | 评论/我喜欢/历史/本地音乐是转圈 | 统一骨架屏（新增 `SkeletonCommentItem`） |
| **评论刷新** | `onRefresh`/`isRefreshing` 定义了没有入口 | 接上 `RefreshContainer`，下拉刷新第一页 |
| **导航栏大标题** | `collapsed` 从未被传过，「滚动收缩」是死功能 | 三个大标题页面接上滚动监听，下滚收缩、回顶展开 |
| **播放页交互** | 歌词只能看、封面点不动、迷你条只有封面可点 | 点歌词行跳转到该句（扣歌词偏移）；窄屏点封面翻到歌词；迷你播放条点歌名区域也能进详情 |
| **评论图片** | 点多图只能看一张 | Swiper 多图预览 + 页码指示 + 关闭按钮（单图行为不变） |
| **焦点** | 全项目 0 处焦点管理，点搜索要再点一次输入框 | 搜索框/设置输入面板/元数据编辑弹窗打开即聚焦并弹键盘（`utils/FocusTools`） |
| **评论区** | 楼层回复一次全铺开 | 默认折叠前两条 + 「展开全部 N 条回复 / 收起」 |
| **设计 token** | 字号裸数值 234 处、颜色字面量散落 | 字阶补成 16 档命名并全部 token 化；颜色最后一批（歌词层次/预览底/透明底）收口；新增 `fontBadge/lyricXxx/translucentOnImage/transparent/floatingShadow` 等，并由脚本守住 |

新增/强化的自检：`check_accessibility.py`（纯图标按钮必须可朗读）、
`check_routes.py`（路由一致性）、`check_storage_bindings.py`（AppStorage 绑定闭环）、
`check_permissions.py`（权限声明与实际调用一致）、`check_settings_reset.py`（恢复默认设置字段完整性）、
`check_reachable.py`（入口可达性）、`check_unused_exports.py`（零引用导出）、
`check_duplicate_impls.py`（函数体相同的重复实现）。全部挂进 `scripts/check.sh`。

Phase 4 续（第二轮）又补了四道只在真机才会暴露的缺陷门禁：

| 脚本 | 拦什么 |
| --- | --- |
| `check_builder_state_args.py` | `@Builder` 参数里传状态字段（本工程踩过多次的刷新坑），当场抓出 5 处并改成 `@Component + @Prop` |
| `check_i18n_placeholders.py` | 中英占位符不一致、含 `{0}` 却用 `t()` 调用、`tf()` 实参个数不匹配 |
| `check_timer_cleanup.py` / `check_subscription_cleanup.py` | 组件里的定时器与订阅必须能清理（歌单详情的滚动恢复定时器就是这样被揪出来的） |
| `check_design_tokens.py` / `check_resources.py` | 不许裸字号与写死颜色；media/string/rawfile 资源不许没人引用 |

Phase 4 续（第三轮）：把「能读」这条件落到最长的那批函数上，并抽出一个设置页工厂。

**设置行工厂** `components/ui/SettingsRows.ets`：`selectRow / toggleRow / buttonRow /
inputRow / infoRow` 五个工厂把「一行 = 标题 + 值 + 选项 + 回调」的 12~20 行样板收成一行。
7 个设置分组共 70 个设置行改用工厂，最长函数逐个数收敛：

| 文件 | buildItems 原行数 | 现行数 | 拆法 |
| --- | --- | --- | --- |
| `DesktopLyricSection` | 272 | **8** | 拆成 状态 / 位置颜色 / 文字样式 / 行为 四组（最大单函数 86） |
| `PlaybackSection` | 176 | 108 | 工厂改写 14 行 |
| `SyncSection` | 144 | 91 | 工厂改写 10 行 |
| `AppearanceSection` | 139 | 81 | 工厂改写 10 行 |
| `BasicSection` | 106 | 63 | 工厂改写 7 行 |
| `ListSection` | 93 | 50 | 工厂改写 8 行 |
| `SearchSection` | 44 | 39 | 工厂改写 4 行 |

**长函数拆分**（只改结构、代码原样搬移，逐个编译 + 全量检查）：

| 文件 | 函数 | 前 → 后 | 拆出的具名段 |
| --- | --- | --- | --- |
| `Comment/CommentRow` | build | 184 → **30** | Avatar / AuthorLine / CommentBody / ImageGrid / ReplyBlock / ActionRow |
| `Home/CustomSourceView` | build | 252 → **29** | TopBar / Builtin / Saved / Entry / UrlImport / PluginInfoCard / LocalImport / Help |
| `ui/SettingsSection` | build | 113 → **12** | SectionTitle / ItemList / ItemRow / ItemLabels / ItemTrailing |
| `Home/Home/SearchInputContent` | build | 153 → **11** | TipsList / HistorySection / HotSection（并去掉一层多余 Column） |
| `player/PlayerBar` | BarCore | 125 → **22** | MiniCover / MiniTitle / MiniControls |
| `Home/Mylist/UserPlaylistCard` | build | 106 → **25** | Cover / Info / Actions |
| `SonglistDetail/SonglistDetailHeader` | build | 95 → **20** | ExpandedRow / CompactRow |
| `Home/LeaderboardView` | loadPreviewForBoardId | 90 → **20** | indexOfCard / isStalePreview / patchCard / applyPreviewReady / applyPreviewError |

`LeaderboardView` 那次拆分顺带把「同一段过期判断重复 4 次、findIndex 重复 3 次」
收成三个小工具方法，并给卡片加载态加了 `CardLoadState` 类型别名（不再用裸 string）。

**Phase 3（UI/UX 商业化）**：把首页/我的/下载/本地音乐/排行榜/评论页逐个套 UI Kit，
统一大标题滚动收缩、Tab 切换动效、骨架屏与空态、深色层次、触控目标校验。

### 迁移进度

- 已完成：`HistoryListPage`、`LoveListPage`、`UserListsPage`（三页从「手写顶栏 + 手写确认框 + 手写遮罩」
  改为 UI Kit + DialogService，行尾统一 ⋮ 菜单，空/加载态统一）
- 已完成：`SettingView`、`SonglistDetailPage`、`PlayDetailPage`、`MylistView`、`HomePage`、
  `LeaderboardView`、`PlayerService`、`ResolvePlayback` 的拆分（见上表）
- 已收口：`DownloadPage`（拆成 `Download/{DownloadView,DownloadTaskRow,DownloadSelectionBar}`）；
  `LocalMusicPage` / `CommentPage` / `BoardDetailPage` / `UserListsPage` 已用 NavBar + StateView，
  剩下的自有布局（编辑弹层、评论楼层、榜单头部）按需继续收敛
- 已收口（Phase 2-f）：`LocalMusicPage` 的编辑弹层 -> `LocalMusic/EditMetadataSheet`；
  `BoardDetailPage` 头部 -> `Board/BoardDetailHeader`；评论页楼层已在 `Comment/CommentRow` 内成组件。
  也就是说「自有布局」清单已经清空，剩余的只是各页面自己的状态编排。

### 自检与出包（一条命令）

```
./scripts/check.sh     # 静态检查（36 个脚本 / 322 项功能判据）：
                       #   check_imports / check_dead（含类成员、@State）
                       #   check_unused_exports / check_reachable / check_routes
                       #   check_storage_bindings / check_permissions
                       #   check_kit_imports（@kit.* 能力集入口）/ check_i18n / check_symbols
                       #   check_settings_copy / check_settings_reset
                       #   check_settings_ui / check_mini_player / check_responsive
                       #   check_keyboard / check_style_noise / check_duplicate_blocks
                       #   check_duplicate_impls / verify_features(322 项)
./scripts/release.sh   # 先自检，再出已签名的 Release HAP
```

**验收口径（本轮最终确定）**：以「静态判据全绿 + 编译通过 + 已签名 Release HAP 出包」
为完成标准，不把真机回归算作完成条件。真机脚本（`scripts/device_*.sh` + `scripts/ui.sh`）
保留在仓库里，需要时手动跑，不再是流程环节。

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

### 开发节奏（重要：别每轮都跑真机）

真机脚本是五个，逐个跑要十几分钟 —— 这是很容易失控的时间开销。约定：

- **每一轮改动**：`./hvigor.sh assembleApp && ./scripts/check.sh`（几秒），够抓编译错误、
  死代码、i18n、功能清单与结构回归；
- **里程碑 / 一轮里动了真机可见行为时**：跑 `./scripts/device_all.sh` 一次，
  它顺序跑完五个专项脚本并给出汇总（耗时打印在末尾）；
- 探索性点按（截图逐屏看）只在做 UI 走查时做，且一次看多屏、别反复冷启动。

## 本轮重构总览（结构 + 一致性）

**拆分原则**：只搬代码不改行为；页面只留编排，动作/映射/守卫下沉到模块；
同一件事只留一个实现出口。每一步都跑 `assembleApp` + `check.sh`（现在 322 项）。

当前最大文件与职责（拆分后）：

| 文件 | 行数 | 职责 |
| --- | --- | --- |
| `service/PlayerService.ets` | ~1366 | 播放编排（队列规则、系统播控、进度存储、歌词枢纽已外置；剩下的进度定时器与通知回调与模块级状态强耦合，暂不拆） |
| `pages/SonglistDetailPage.ets` | ~1226 | 歌单详情编排（选择/排序/滚动记忆；加载、动作、映射、行组件已外置） |
| `pages/Home/LeaderboardView.ets` | ~954 | 榜单编排（筛选/预览加载；卡片、骨架、搜索覆盖层已外置） |
| `pages/PlayDetailPage.ets` | ~1095 | 播放页编排（资源加载、控制条、顶栏、歌词面板、单曲动作已外置） |
| `pages/HomePage.ets` | ~908 | 首页 Tab 编排（搜索执行/源切换；搜索输入态已外置） |
| `pages/CommentPage.ets` | ~356 | 评论页编排（评论行已外置为组件） |
| `pages/Home/SongListView.ets` | ~625 | 歌单广场编排（SDK/标签/分页已外置） |
| `pages/Home/CustomSourceView.ets` | ~623 | 自定义源管理编排（源行已外置为组件） |
| `service/BackgroundRunningManager.ets` | ~748 | AVSession 与后台长时任务 |
| `service/ListService.ets` | ~705 | 自建歌单 CRUD 与持久化 |

已拆出的模块（按域）：

- `core/music/`：`download/*`（队列/文件/持久化/类型）、`PluginResolve`、`MusicSearch`、`OtherSourceMatch`、`MusicTitle`
- `service/player/`：`QueueRules`、`PlaybackEvents`、`PlaybackProgressStore`、`LyricHub`、`PlaybackSession`、`PlaybackTypes`
- `service/sync/`：`SyncTypes`、`SyncCrypto`、`SyncHistoryStore`、`SyncDataMapper`、`SyncTransport`
- `service/backup/`：`BackupTypes`、`BackupDataMapping`
- `service/crypto/`：`AesPayload`
- `service/settings/`：`SettingsTypes`、`SettingsStorage`、`SettingsWriters`
- `service/localization/`：`ZhCN`、`EnUS`
- `pages/PlayDetail/`：`PlayMediaAssets`、`PlayerControls`、`PlayDetailTopBar`、`LyricPane`、`PlaySongActions`、`QueueSheet`、`VolumeSheet`、`LyricOffsetSheet`、`SourceSwitchSheet`、`MoreActionsSheet`、`PlayDetailMenus`、`AlbumCover`
- `pages/SonglistDetail/`：`SonglistActions`、`SonglistCollectActions`、`SonglistMapper`、`SonglistBatchBar`、`SonglistMenus`、`SonglistSortSheet`、`SonglistPlayback`、`SonglistListOps`、`SonglistScrollMemory`、`SonglistDetailHeader`
- `pages/Home/SongList/`（SongListCard、SongListLoader）、`pages/Home/Leaderboard/`（ChartCard、SkeletonBoards、
  LeaderboardSearchOverlay）、`pages/Home/Home/SearchInputContent`、`pages/Home/CustomSource/CustomSourceRow`、
  `pages/BoardDetail/BoardSongRow`、`pages/Comment/CommentRow`、`pages/Download/*`：列表行、卡片与骨架组件
- `core/theme/`：`ThemeFactory`、`data/LightThemes`、`data/DarkThemes`
- `utils/FormatTools`：字节 / 时长 / 播放量格式化

统一出口（同一件事只有一份实现）：

| 能力 | 唯一出口 |
| --- | --- |
| 字节 / 时长 / 播放量格式化 | `utils/FormatTools` |
| 提示与确认框 | `service/DialogService`（appToast / appConfirm / appAlert / appActionMenu） |
| 加解密 | `service/crypto/AesPayload`（同步固定 IV / 备份随机 IV + SHA-256） |
| 下载队列与落盘 | `core/music/download/*` |
| 系统播控 | `service/player/PlaybackSession` |
| 主题数据 | `core/theme/{ThemeFactory,data/*}` |
| i18n 词条 | `service/localization/{ZhCN,EnUS}` |
| 歌曲标题/文件名 | `core/music/MusicTitle` |

**ArkTS 实测规则（写进开发约定）**

1. `@Builder` 的参数不会随状态刷新，但 Builder 内读 `this.*` 会刷新 →
   会变的内容（播放模式、点赞态、启用角标、选中态）一律用 `@Component + @Prop`，
   或在 Builder 内按 index 读组件状态；ForEach 的 key 要带上会变的字段。
2. 系统符号只能用 `SymbolGlyph`（`Image($r('sys.symbol.*'))` 不渲染）。
3. 禁 any/unknown、禁结构化类型（跨模块形参必须同一 interface）、禁对象字面量当类型。

### 自检脚本

每轮改完在 `harmony/` 下跑一遍（脚本在 `scripts/`，不依赖网络）：

```bash
./scripts/check.sh            # 依次跑下面五项
python3 scripts/check_imports.py       # 未使用的 import = 0
python3 scripts/check_dead.py          # 未被引用的私有方法 = 0
python3 scripts/check_i18n.py          # 中英词条一一对应、无重复、无闲置
python3 scripts/check_settings_copy.py # 设置快照字段完整（加设置项漏拷 copyOf 会被拦下）
python3 scripts/verify_features.py     # 与安卓版的功能对齐清单
```

静态检查证明不了运行时行为，所以另有真机冒烟回归（需要连着设备）：

```bash
./hvigor.sh assembleApp
./scripts/device_smoke.sh          # 主链路：换源 → 详情 → 播放/歌词 → 队列 → 设置
./scripts/device_settings_check.sh # 设置页专项：选完即时刷新 + 下载文件名落库
./scripts/device_download_check.sh # 下载页专项：筛选计数 → 多选 → 全选 → 批量删除确认
./scripts/device_player_check.sh   # 播放页专项：「更多」面板分组 + 12 项动作逐个点开
./scripts/device_queue_check.sh    # 队列手势专项：手柄拖拽排序、不误切歌、长按移除
./scripts/device_all.sh            # 上面五个一次跑完（里程碑用，末尾打印总耗时）
```

它会装包、冷启动，然后按顺序跑「换源重载 → 歌单详情出歌 → 播放页歌词链路 →
队列面板 → 设置项面板」并做日志/UI 树断言（`HDC=` / `TARGET=` 可指定设备）。

### 本轮真机走查修掉的问题

| 现象 | 根因 | 修复 |
| --- | --- | --- |
| 图标全隐形（45 处） | `Image($r('sys.symbol.*'))` 不渲染系统符号 | 统一 `SymbolGlyph` + `check_symbols.py` 防回归 |
| 设置项点了没反应 | 自绘浮层被 Scroll 裁剪 | `BottomSheet` 改 `bindSheet` + 全局面板宿主 |
| 主题名与实际不符 | 主题有两条写入路径 | 收敛到 `settingsService.update` |
| 换源后列表不刷新 / 详情「暂无歌曲」 | 只改高亮不重载；卡片音源取的是「页面当前源」 | 以 `sourceId` 变化触发重载；卡片以数据自身 source 为准 |
| QQ 歌单详情永远 0 首 | 老接口固定返回 check privacy error；新接口 cdlist 嵌在 data 里 | 换 `fcg_v8_playlist_cp` + 兼容两种结构 + 旧接口兜底 |
| 播放页封面/歌词请求风暴（~5 次/秒） | `onMusicInfoChange` 高频回调每次都直接发请求，失败后无「已尝试」记忆 | 加「进行中 / 本首已尝试」守卫，实测 10 秒内 50 次 → 0 |
| 每次下载都弹系统保存面板 | 配置目录写不进去就直接回退选择器 | 新增「每次下载询问保存位置」开关（默认关），失败时保留在应用目录不打断 |
| 下载任务路径指向错误文件 | 记录的是设置里的目录而不是实际落盘位置 | 用真实保存路径写回任务 |
| 「我的」页歌单卡片没有管理菜单 | 只有播放/同步，重命名与删除得绕到「全部歌单」页 | 卡片加 ⋮ 菜单（打开/更新内容/重命名/删除），与全部歌单页共用定义 |
| 面板确认后用户输入被吞 | 「关闭」事件先于回调触发，被当成取消 | InputSheet/SelectSheet 改为先回调再关闭 |
| 切语言后部分文案不变 | 筛选/排序文案缓存在 @State，只在加载数据时重建 | 两页对 langVersion 加 @Watch，语言变化即按现有数据重建 label |
| 榜单详情个别源白屏 | 只有榜单 Tab 自己实现了超时+空包重试 | 下沉到 `core/leaderboard.getLeaderboardDetailReliable`，两处共用 |
| 下载页多选栏写着「播放全部」、空选时写「暂无数据」 | 顶栏/批量栏文案混用了播放与列表的词条 | 顶栏改「多选 / 取消」，批量栏用「全选 / 已选 N 项 / 点击任务可多选」 |
| 暂停中的下载显示成「下载中」 | 状态文案 switch 里 PAUSED 与 DOWNLOADING 共用一条 | 新增 `download_paused`（已暂停），与下载中区分 |
| 底部「清空已完成」按钮只有「已完成」四个字 | 复用了 `download_completed` 词条当按钮文案 | 新增 `download_clear_completed` 并配垃圾桶图标，看得出是操作 |
| 下载页每秒整列表重绘 | 1s 轮询里无脑 `this.tasks = 新数组` | 用 `downloadTasksSignature` 指纹比对，进度没变不重建；进度按 5% 分桶做 ForEach key |
| 切换筛选后仍保留看不见的选中项 | 选中集合只在退出多选时清空 | 切筛选/任务被删后自动收敛选中集合（`pruneSelection`） |
| 播放页「更多」14 项平铺，找功能靠扫 | 缺少分组，长面板没有信息层级 | 按「歌曲 / 播放 / 歌词 / 保存」分组（`PlayActionSection`），与华为音乐「⋯」菜单一致 |
| 歌词偏移要点两次才能选到 ±0.5s | 7 档动作菜单被 `appActionMenu`「超 5 项折叠」吃掉常用档位 | 换成 `LyricOffsetSheet` 滑杆（±3s、0.1s 步进、拖动即时生效、一键重置），真机实测拖动后落库 `lyricOffset=1.5` |
| 队列拖动排序根本不生效，而且拖完会莫名切歌 | ① 用系统拖放 `onDragStart/onDrop`，真机上不触发；② 手势落在整行上被 `onClick` 当成点击 | 改为「行尾 ≡ 手柄 + 原始触摸事件」：按下即锁定列表滚动（`enableScrollInteraction(false)`），用 `screenY` 差值算跨行数，手柄 `onClick(() => {})` 吞掉点击，松手才重排 |
| 手柄拖一行却回到原位 | 触摸事件里的 `screenY` 单位是 vp，而代码按 px 乘了密度去算行高（跨行数被低估 3 倍） | 行高直接用 vp（真机实测 240px 注入 ≈ 71vp ≈ 1.1 行，比例正好是 1/密度） |
| 「应用启动」冒烟偶发假失败 | 断言只看初始化日志，紧跟清理日志之后可能已滚出缓冲 | 增加「进程真的在跑（`pidof`）」的等价判据 |
| 播放页进度条两端显示同一个时间 | 右侧标签误写成 `currentTime`（应为总时长） | 改为 `totalTime`，真机验证 01:18 / 03:25；并加静态判据防回归（截图走查才发现） |
| 点「播放模式」没反应（其实模式已切换并落库） | 动态文案/图标当 `@Builder` 参数传入，状态变化不会刷新 Builder 内容 | 按钮 Builder 只收静态参数（图标 + 动作标识），会变的内容在 Builder 内读 `this.*`；评论行点赞态同类问题一并修（`buildCommentItem` 改为只收 index） |
| 歌单卡片播放量出现 `8550.7` 这种带小数的值 | 4 处各自实现的格式化，一万以下直接 `toString()` | 统一到 `FormatTools.formatPlayCount` 并取整；真机复验 8551 / 4.1 万 / 5.5 万 |
| 排行榜里不同榜单卡片封面一模一样 | 没有榜单图时拿「第一首歌的封面」兜底，两个榜 #1 相同就完全一样 | 改为按榜单 id 生成的渐变占位块（每榜一色）+ 榜单图标；真机复验 流行指数榜=红、热歌榜=琥珀 |

> **两条实测结论（都做过对照实验）**
>
> 1. **`@Builder` 的参数不会随状态刷新，但 Builder 内部读 `this.*` 会刷新**。
>    实验：把播放模式文案当参数传 → 点击后状态已切到 `sequential`、界面仍停在上一档；
>    改成参数只留静态值、文案在 Builder 内读 → 界面与日志、落库三者一致。
>    这条是「底栏看起来点不动」的真因，全项目同写法（如评论点赞态）都要按此约束。
> 2. **验证要用直接证据**。我一度把「底栏点不动」归因于 `expandSafeArea`，
>    依据是「点播放/暂停没有播放器日志」；后来给控制条加了「收到点击」的直接日志再测，
>    10 次点击 10 次都被接收，恢复 `expandSafeArea` 后仍 8/8 —— 该属性无辜，
>    错在拿「播放器日志」当代理信号（它在某些播放状态下本来就不产生日志）。
>    结论：判据优先用组件自己的日志、落库值、界面树，不要用间接推断。
| 设置里选完选项，右侧「当前值」不变 | 设置分组 `ForEach` 的 key 只带 `title+index`，行被复用不重建 | key 加入 `type/value`，选完即刷新（真机复验：选「原名」立刻变） |
| 改「下载文件名」后下载仍按旧格式命名 | `settingsService.get()` 返回的是 `copyOf()` 手工逐字段快照，新字段漏拷 → 运行时拿到默认值 | 补 `copyOf` 字段，并加 `scripts/check_settings_copy.py` 把「加设置漏拷贝」变成可自动拦截的规则 |

### 与安卓版逐项核对（`app_setting` 全键比对）

拿安卓版 `src/types/app_setting.d.ts` 的 68 个设置键与鸿蒙 `AppSettings` 做了一次全量比对，
结论：68 个键里只有 6 个是 Android 布局/SAF 专有（`autoHidePlayBar`、`homePageScroll`、
`drawerLayoutPosition`、`showBackBtn`、`alwaysKeepStatusbarHeight`、`useSystemFileSelector`，
见上文差异说明），其余全部有对应实现；本轮补上最后一个真缺口：

| 安卓设置 | 鸿蒙实现 |
| --- | --- |
| `download.fileName`（下载文件名：歌名 - 歌手 / 歌手 - 歌名 / 歌名） | 设置 → 下载 →「下载文件名」，同时作用于下载文件命名、歌词/封面缓存命名与分享文案标题（`core/music/MusicTitle.ets` 单一入口，替换掉原来 4 处硬编码） |

### 本轮结构拆分

| 原 | 现 | 说明 |
| --- | --- | --- |
| `CommentService` 960 行 | 105 行 + `comment/{CommentTypes,CommentShared,CommentSourceAdapter,sources/*}` | 五平台评论各成适配器，主服务只做分发 |
| `SettingsService` 1521 行 | 864 行 + `settings/{SettingsTypes,SettingsStorage}` | 类型/默认值、存储加载与旧数据迁移各自成文件 |
| `SonglistDetailPage` 1689 行 | 1541 行 + `SonglistDetail/{SonglistPlayback,SonglistListOps,SonglistScrollMemory}` | 播放/队列、排序去重落库、滚动记忆 |
| `PlayerService` 1565 行 | 1453 行 + `player/{PlaybackEvents,PlaybackProgressStore,PlaybackTypes}` | 订阅中心、续播快照存储、公共类型 |
| `NavIndex` 13 段 NavDestination 样板 | `components/ui/AppDestination` | 新增页面只写一行 |
| 5 处手写 `showActionMenu` | `DialogService.appActionMenu` | 取消项交给系统菜单，危险项统一危险色 |
| `DownloadPage` 832 行（唯一没收口 UI Kit 的页面） | 433 行 + `Download/{DownloadView,DownloadTaskRow,DownloadSelectionBar}` | 纯逻辑（筛选/计数/状态文案与配色/行模型）与视图分离，顶栏/空态/分段/下拉刷新全走 UI Kit |
| 4 份字节格式化 + 2 份时长格式化 | `utils/FormatTools`（`formatBytes` / `formatBytesCompact` / `formatDuration`） | `LocalPlayback`、`CommonUtils`、`CacheService`、`ListTools` 全部改为委托，规则只有一处 |
| 下载状态色写死 `#FFA500/#4CAF50/…` | `DesignTokens.success() / warning() / info()` | 语义状态色进设计系统，页面不再出现魔法十六进制 |
| `RunMusicDownloads` 991 行（队列+文件+持久化混在一起） | 128 行门面 + `download/{DownloadTypes,DownloadContext,DownloadFiles,DownloadStorage,DownloadQueue}` | 类型 / 上下文 / 文件传输 / 历史持久化 / 任务状态机各自成文件，任务表只由队列持有 |
| `PlayDetailPage` 1589 行里 12 个「请求守卫」字段 + 200 行加载逻辑 | `PlayDetail/PlayMediaAssets` 类 | 封面与歌词共用同一套守卫（进行中跳过 / 同曲失败跳过 / 序号过期丢弃 / 退避重试），页面只负责把结果写进 @State |
| `PlayDetailPage` 底部控制条（~130 行 @Builder） | `PlayDetail/PlayerControls` 组件 | 组件只认「显示值 + 回调」，seek 判定留在页面；按钮 Builder 只收静态参数、动态内容在 Builder 内读状态（见下方实测结论） |
| 评论行 `@Builder buildCommentItem(comment, index)` | `buildCommentItem(index)` + `CommentBody(index)` | 评论对象不进参数（点赞态属于会变的状态），Builder 内从 `this.comments[index]` 读 |
| 播放量格式化在 4 处各写一遍（排行榜卡片/歌单卡片/歌单详情/搜索结果） | `utils/FormatTools.formatPlayCount(count, 万, 亿)` | 阈值、空格、小数位统一；单位文案由调用方注入，FormatTools 保持纯函数 |
| 榜单卡片封面取「第一首歌的封面」兜底 | `LeaderboardView.placeholderGradient` | 没有榜单图时用按榜单 id 生成的渐变块 + 榜单图标：各榜颜色不同、不再误导成同一张榜 |
| `LocalizationService` 1458 行（两张词条表占 1300 行） | 155 行服务 + `localization/{ZhCN,EnUS}.ets` | 中英各一份、各自演进；服务只留语言状态与查询 API，`check_i18n.py` 改读两张表 |
| `SyncService` 1151 行（协议/加解密/数据映射/历史揉在一起） | 690 行服务 + `sync/{SyncTypes,SyncCrypto,SyncHistoryStore,SyncDataMapper}` | 类型、加解密（改用系统 Base64Helper，删掉 80 行手写编解码）、服务器历史、数据合并各自成文件；传输与状态机留在服务里 |
| `PlayDetailPage` 里的分享/下载/收藏/加歌单/保存歌词封面/不喜欢/换源 | `PlayDetail/PlaySongActions` | 命令式动作只接收「当前歌曲 + toast 回调」，页面不再被 if-else 撑开（1589 → 1183 行） |
| `themes.ets` 2622 行纯数据 | 35 行门面 + `theme/{ThemeFactory,data/LightThemes,data/DarkThemes}` | 工厂函数与明暗数据分开；门面保留 `getDefaultThemes/getThemeById/DEFAULT_THEME_ID`，调用方 import 不变 |

## 设备验收清单（需要真机确认，代码侧已按此实现）

> 这些能力依赖真机系统服务或物理设备，构建通过 ≠ 设备可用，逐项勾选即可。

### 系统级歌词
- [ ] 播放页 / 设置页打开「桌面歌词」后，出现的是**系统原生歌词**（不是应用自绘的悬浮条）
- [ ] 若设备不支持系统桌面歌词，能自动**降级**为内置悬浮窗（透明浮字、可拖动、可锁定）
- [ ] 锁屏 / 控制中心出现歌词（来自 `AVMetadata.lyric` + `singleLyricText`）
- [ ] 内置悬浮窗设置项生效：颜色、字号、背景不透明度、显示下一句、锁定穿透

### 本地音乐
- [ ] 「我的 → 本地音乐」导入设备音频后列表出现曲目，标题/歌手/时长正确
      （**当前测试设备上无选择器可见的音频文件，且 shell 无权写入应用沙箱，
      这条链路尚未真机走查过**：需要在有本地音频的设备上点一次「导入」）
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

### Phase 5：逐字歌词 + 2in1 交互（本轮）

这一轮做的是「数据已经在手上、界面却没用」的那类补口，以及鸿蒙 2in1（PC / 平板接键鼠）
那条经常被忽略的输入通道。

| 能力 | 之前 | 现在 |
| --- | --- | --- |
| **逐字歌词（卡拉OK）** | `lxlyric` 一路带着走却从没渲染：酷我把逐字标记直接丢掉、网易云压根没请求 yrc | 新增 `core/lyric/WordLyric.ets` 统一解析 kg/kw/wy 三种格式；酷我保留 lrcxml 标记、网易云补 `yv=1`；播放页当前行按字高亮（已唱=主题色 / 未唱=暗色） |
| **播放页平滑进度** | 进度轮询 1s 一次，进度条与歌词每秒跳一下 | 新增 100ms 平滑表：以真实位置为基准、本地时钟插值（暂停/seek 立即对齐，页面销毁清表），逐字高亮与进度条都走它 |
| **下拉刷新** | 只有评论/下载/排行榜/我的歌单/歌单广场有 | 歌单详情、本地音乐（重扫）、播放历史、我喜欢补齐；统一 `RefreshContainer`，静默刷新保留列表（不闪骨架、失败只提示不清空） |
| **迷你播放条** | 只有首页/本地音乐/歌单详情/榜单详情有 | 历史、我喜欢、我的歌单、下载、评论补齐，并加脚本钉住 |
| **单条记录操作** | 长列表只能「全清」 | 历史侧滑删单条（按 id+source+playedAt 定位）、我喜欢侧滑取消收藏、歌词长按复制这一句、搜索历史长按删单条 |
| **2in1 键盘** | 自定义可点区域不可聚焦 | 列表行/卡片/歌词行 `.focusable(true)` + 回车激活（`utils/KeyboardTools.isConfirmKey`） |
| **2in1 鼠标** | 只有按压态 | 列表行与本地音乐行右键 = 长按（出同一套行菜单） |
| **播放页手势** | 只能点返回 | 封面区下滑关闭播放页（超阈值返回并轻震动，未到自动回弹；手势只挂封面，不吃歌词区滚动） |
| **一多** | 关于页 / 自定义源页在平板上整屏拉满 | 统一 1200vp 内容列居中，并由 `check_responsive.py` 守住 |

结构上这一轮也继续收口：`HomePage`（SearchOverlay / playSearchResult）、`UserListsPage`
（卡片四段）、`PlayDetailPage`（双形态 + 控制区）、`CommentPage`（加载态收口）、
`PlayerService.setSource`、`PluginManager.loadCustomSource`、网易云搜索、酷狗/酷我歌单、
两处热搜的长函数与重复兜底各收敛一处。

新增自检脚本（全部挂进 `check.sh`）：

| 脚本 | 拦什么 |
| --- | --- |
| `check_duplicate_blocks.py` | 同一文件里 15 行以上的重复片段（排行榜卡片列表曾复制两份，其中一份漏了宽屏留白） |
| `check_style_noise.py` | 连续重复且缩进错位的通用属性（漏改留下的尾巴） |
| `check_mini_player.py` | 内容页必须挂迷你播放条 |
| `check_responsive.py` | 内容页必须至少有一处断点处理 |
| `check_keyboard.py` | 共享行/卡片组件必须支持 2in1 键盘激活 |
| `check_settings_ui.py` | 每个设置项都必须「有入口写入 + 有人读取」 |

### Phase 6：启动顺序 / 状态持久化 / 国际化收口（本轮）

这一轮不做新功能，专挑「只有真机重启或切语言才暴露」的那类问题。每一条都先查代码取证、
再改、再补门禁，避免「以为修了」。

| 问题 | 根因 | 修法 |
| --- | --- | --- |
| 设成 FLAC 的用户重启后先播出来的是 128k；播放模式回到列表循环 | `playerService.setContext()` 在 `initAllServices()` 之前执行，那时设置还没加载，`syncFromSettings()` 同步下去的是默认值，且只有改任意设置才会纠正 | `PlayerService.init()` 里按「设置已就绪」再同步一次 |
| 关掉「播控封面 / 蓝牙歌词」的用户重启后播控中心仍有封面 | 同上：`setMetadataOptions` 也是启动早期用默认值下的 | `updateOptions()`（启动后阶段调用）里重放一次 |
| 自动同步 / 自动备份重启后开关看着开着却不跑 | 两个服务的 `initialize()` 全项目没有调用方；备份设置页还会显示服务里的默认开关 | `initAllServices` 里初始化同步；EntryAbility 延迟块 setContext + 初始化备份；设置页打开时先 `await initialize()` |
| 下载并发数设成 3、重启后仍按 1 跑 | 只有进过「设置 → 下载」才同步给下载引擎 | `initAllServices` 里按设置写入引擎 |
| 重启后播放队列被清成单曲（下一首没反应） | 只存了「最后一首 + 位置」 | 新增队列快照（去掉时效性 url、限 300 首），队列变更统一走 `persistQueue()` |
| 定时退出重启后按整段时长重新开始（等于白续 30 分钟） | 只存了分钟数，没存截止时间 | 落盘截止时间戳，按剩余时长恢复；已过期则清开关；到点统一清状态 |
| 「记住列表滚动位置」只在歌单详情生效 | 其余长列表没接 | 抽出 `ScrollMemoryHandle`，榜单详情/历史/我喜欢/本地音乐全部接上 |
| 「显示专辑 / 显示音源 / 显示时长」只在歌单详情生效 | 各页各自拼「歌手 · 专辑 · 音源」 | 行组件统一消费结构化字段，拼装只剩 `core/list/RowTexts` 一处 |
| 首页每次重启都回到默认音源 / 默认 Tab；歌单广场筛选每次重置 | 这些「上次看到哪儿」都没落盘 | 分别落盘（`home.lastSource` / `home.lastTab` / `songlist.lastFilter.<源>`） |
| 评论点赞退出去再进来就复原 | 标签只存在内存里（源接口没有登录态点赞能力） | 落盘本地点赞记录，计数按「服务端数 + 本地是否点过」 |
| 英文界面里播放量数字偏小一个数量级（12.3 万 → 12.3 K） | 只换单位文案、没换量级 | `playCountUnits()` 按语言同时决定量级与文案（中 万/亿，英 K/M） |
| 英文界面出现中文（下载失败原因、网络提示、榜单名兜底） | 逻辑层写死中文 | 全部走词条；新增 `check_error_i18n.py` 守住 |
| 整张列表取不到播放地址时无限重试 | 失败分支递归下一首，列表循环会从队尾绕回队首 | 连续失败 ≥ 队列长度即停下并置错误态（`handleUrlFetchFailure`） |
| 快速切「热门/最新」评论会跳回旧列表 | 多个请求在飞，先发的后返回 | 加 epoch，只认最后一次 |
| 歌词被自动跟随「拽走」，没法安静翻看 | 每换一句都强制滚到当前句 | 手动滚动即停止跟随，浮出「回到当前」；点某句恢复跟随 |

新增自检脚本（累计 34 个，全部挂进 `check.sh`）：

| 脚本 | 拦什么 |
| --- | --- |
| `check_service_init.py` | 单例服务定义了 `initialize()/init()` 却没有任何调用方（＝服务没初始化） |
| `check_error_i18n.py` | 逻辑层写死中文错误文案（下载失败原因这类会直接展示给用户） |
| `check_queue_persist.py` | 改动播放队列的函数必须调用 `persistQueue()` |
| `check_scroll_memory.py` | 长列表页面必须响应「记住滚动位置」并成对调用 restore/dispose |
| `check_row_texts.py` | 列表行文案必须走 `RowTexts`，行组件必须响应三个显示开关 |
| `check_error_states.py` | 联网页必须区分「失败」与「空」并给出重试 |

## Dependencies

### Core Dependencies
- HarmonyOS SDK
- ArkTS language

### Key Modules
- `@ohos.media` - Media playback
- `@ohos.storage` - Local storage
- `@ohos.http` - Network requests
