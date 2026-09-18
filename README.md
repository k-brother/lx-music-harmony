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
