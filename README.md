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

# Debug build
./hvigor.sh assembleDebug

# Release build
./hvigor.sh assembleRelease
```

The build output is located in `harmony/.hvigor/outputs/`.

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

HarmonyOS uses `@State` and `@Consume` decorators with event-based communication via `EventBus`.

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
