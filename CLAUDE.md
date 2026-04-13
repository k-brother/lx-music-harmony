# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

LX Music Mobile is a React Native music player app with support for multiple music source platforms. The project has two parallel implementations:

- **React Native (Android)** in `src/` - Primary implementation
- **HarmonyOS NEXT** in `harmony/` - Separate implementation using ArkTS

The README states no current plan to support iOS.

## Common Commands

### React Native (Android)
```bash
npm run dev          # Run Android (react-native run-android)
npm run start        # Start Metro bundler
npm run sc           # Start Metro with cache reset
npm run lint         # Lint with ESLint
npm run lint:fix     # Lint and auto-fix
npm run bundle-android   # Bundle JS for Android
npm run pack:android:debug  # Build debug APK (./gradlew assembleDebug)
npm run clear        # Clean Android build (./gradlew clean)
```

### HarmonyOS
```bash
cd harmony
./hvigor.sh assembleDebug    # Build HarmonyOS debug
./hvigor.sh assembleRelease  # Build HarmonyOS release
```

## Architecture

### React Native Structure (`src/`)
- `store/` - State management modules (player, list, songlist, setting, theme, search, etc.)
- `core/` - Business logic (player, list, leaderboard, music sources, search, sync)
- `screens/` - Screen components (Home, PlayDetail, SonglistDetail, Comment)
- `components/` - Reusable UI components (common, player, OnlineList, modals)
- `navigation/` - Navigation setup and screen registration
- `utils/` - Utilities (data, tools, native modules, musicSdk wrappers)
- `theme/` - Theme definitions
- `types/` - TypeScript type definitions

### Music Sources Architecture
Music sources are abstracted via interfaces in `src/core/music/sources/`:
- **kg** (Kugou)
- **kw** (Kuwo)
- **mg** (Migu)
- **tx** (QQ Music)
- **wy** (Netease)

Each source implements: music search, play URL retrieval, lyrics, song lists, leaderboards, hot search.

### HarmonyOS Structure (`harmony/entry/src/main/ets/`)
Mirrors the React Native structure with ArkTS:
- `pages/` - UI pages (HomePage, PlayDetailPage, SonglistDetailPage, etc.)
- `core/` - Core business logic and music sources
- `store/` - State management using HarmonyOS state patterns
- `service/` - Services (ListService, StorageService, HttpService, EventBus)
- `components/` - Reusable components

### State Management
React Native uses a Redux-like store pattern in `src/store/`. HarmonyOS uses `@State` and `@Consume` decorators with event-based communication via `EventBus.ets`.

## Key Dependencies
- React Native 0.73.11
- React Native Navigation 7.39.2 (navigation)
- React Native Track Player (audio playback)
- Redux for state management
- TypeScript throughout

## Path Aliases
`@/*` maps to `src/*` (configured in tsconfig.json)
