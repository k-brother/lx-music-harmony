import pathlib, re, sys

# 允许从任意目录执行：以脚本位置定位工程根目录
import os
root = pathlib.Path(__file__).resolve().parent.parent / 'entry/src/main/ets'
def read(rel):
    p = root / rel
    return p.read_text() if p.exists() else ''

# 每个检查项： (名称, 相对 ets 根目录的路径, 必须匹配的正则 [, 禁止出现的正则])
# 负向断言用于记录「真机上踩过坑、不允许再出现的写法」。
CHECKS = [
 ('不喜欢列表（屏蔽+跳过）', 'core/dislike/DislikeList.ets', r'dislikeList'),
 ('保存播放进度/续播', 'service/PlayerService.ets', r'restoreLastPlayback|saveProgress'),
 ('歌词简繁转换', 'core/lyric/ChineseConvert.ets', r'convertChinese'),
 ('歌词翻译/罗马音开关', 'pages/PlayDetailPage.ets', r'showLyricTranslation|showLyricRoma|toRoma'),
 # 评论按源拆分后，楼层/图片/归属地字段定义在 CommentTypes，映射在各源适配器
 ('评论楼层+图片', 'service/comment/CommentTypes.ets', r'images: string\[\]|replies: Comment\[\]|location: string'),
 ('评论按源适配器拆分', 'service/comment/CommentSourceAdapter.ets', r'CommentSourceAdapter'),
 ('评论分发薄层', 'service/CommentService.ets', r'resolveAdapter'),
 ('评论图片预览', 'pages/CommentPage.ets', r'buildImagePreview'),
 ('列表排序/去重工具', 'utils/ListTools.ets', r'sortSongs|dedupeSongs'),
 ('歌单多选批量', 'pages/SonglistDetailPage.ets', r'BatchBar|batchDownload|batchRemove'),
 ('列表级同步到本地', 'service/ListService.ets', r'replaceUserListMusic|removeMusicsFromList'),
 ('手动换源弹窗', 'pages/PlayDetailPage.ets', r'sourceCandidates|showSourceCandidates|switchSource'),
 ('本地音乐元数据编辑', 'service/LocalMusicService.ets', r'updateMetadata'),
 ('运行日志页', 'pages/LogPage.ets', r'logService'),
 ('日志落盘/回读', 'service/LogService.ets', r'restoreFromFile|exportToFile'),
 ('日志门面接入', 'core/log/AppLogger.ets', r'appLog'),
 ('缓存分项统计', 'service/CacheService.ets', r'getMetadataCacheInfo|getResourceCacheInfo'),
 ('主题 16 套', 'core/theme/themes.ets', r'themes'),
 ('桌面歌词宽度/行数/动画/阴影', 'pages/DesktopLyricPage.ets', r'desktopLyricWidth|maxLines|lyricFontSize|shadowColor'),
 ('桌面歌词单行/文字位置/当前句色', 'pages/DesktopLyricPage.ets', r'singleLine|textPosX|playedColor'),
 ('音质四档', 'service/SettingsService.ets', r'playQuality'),
 ('分享服务（系统分享+回退）', 'service/ShareService.ets', r'ACTION_SEND_TO_DATA'),
 ('歌曲详情页链接', 'core/music/MusicDetailUrl.ets', r'getMusicDetailPageUrl'),
 ('源名别名/原名', 'service/LocalizationService.ets', r'source_alias_kw|sourceName\('),
 ('自动跟随系统主题', 'service/ThemeService.ets', r'applyAutoTheme|setSystemDarkMode'),
 ('主题动态背景/字体阴影/隐藏背景', 'pages/PlayDetailPage.ets', r'dynamicBg|fontShadow|hideBgDark'),
 ('定时退出播完再退', 'service/SleepTimerService.ets', r'sleepTimerWaitTrackEnd|onTrackCompleted|cancelPendingExit'),
 ('允许拖动进度条开关', 'pages/PlayDetailPage.ets', r'allowProgressBarSeek'),
 ('搜索历史显示开关', 'pages/HomePage.ets', r'showSearchHistorySetting'),
 ('点击列表项播放整个列表', 'pages/SonglistDetailPage.ets', r'listClickPlay'),
 ('许可协议弹层', 'components/common/PactDialog.ets', r'PactDialog|agreedPact'),
 ('许可协议正文', 'core/legal/PactText.ets', r'PactSection'),
 ('自定义源多源管理', 'core/plugin/PluginStore.ets', r'StoredCustomSource'),
 ('自定义源启用/更新/删除', 'core/plugin/PluginManager.ets', r'setSourceEnabled|updateSource|removeSource|restoreEnabledSource'),
 ('自定义源管理 UI', 'pages/Home/CustomSourceView.ets', r'buildCustomSourceRow|toggleSourceEnabled|removeSource'),
('播控封面开关', 'service/BackgroundRunningManager.ets', r'showNotificationImage'),
 ('下载文件名格式(歌名/歌手顺序)', 'core/music/MusicTitle.ets', r'DownloadFileNameFormat|buildMusicFileStem'),
 ('下载文件名格式接入设置', 'service/settings/SettingsTypes.ets', r'downloadFileName'),
 ('文件命名与分享标题同源', 'core/music/MusicDetailUrl.ets', r'formatMusicTitle'),
 ('蓝牙歌词开关', 'service/BackgroundRunningManager.ets', r'showBluetoothLyric'),
 ('整首播完事件', 'service/PlayerService.ets', r'onTrackCompleted'),
 ('收藏歌单=绑定列表', 'service/UserListSyncService.ets', r'collectOnlineSonglist|findUserListByBinding'),
 ('列表级同步(拉取覆盖)', 'service/UserListSyncService.ets', r'syncUserListFromOnline|fetchAllOnlineSongs'),
 ('旧收藏标记迁移', 'service/UserListSyncService.ets', r'migrateLegacyCollections'),
 ('我的歌单同步入口', 'pages/UserListsPage.ets', r'syncList'),
 ('我的tab绑定角标+同步', 'pages/Home/MylistView.ets', r'bindingListId'),
 ('歌单详情收藏/更新菜单', 'pages/SonglistDetailPage.ets', r'openCollectedMenu|syncBoundList'),
 ('桌面歌词文字不透明度', 'pages/DesktopLyricPage.ets', r'textOpacity'),
 ('同步历史(可选中/清空)', 'service/SyncService.ets', r'getServerHistory|rememberServer|removeServerHistory'),
 ('同步历史 UI', 'pages/Home/Setting/SyncSection.ets', r'openHistory|refreshHistory'),
 ('版本检查服务可调用', 'service/VersionCheckService.ets', r'checkVersionNow|compareVersion'),
 ('版本检查 UI', 'pages/Home/AboutView.ets', r'runVersionCheck|versionStatus'),
 ('打开链接(仓库/发布页)', 'pages/Home/AboutView.ets', r'openUrl'),
 ('自定义源本地文件导入', 'pages/Home/CustomSourceView.ets', r'importFromLocalFile'),
 ('下一首播放(插队)', 'service/PlayerService.ets', r'insertNext'),
 ('队列后台补全全量', 'service/PlayerService.ets', r'refineQueueWithFullList'),
 ('歌单行菜单:下一首/来源详情/不喜欢', 'pages/SonglistDetailPage.ets', r'playLater|openSourceDetail|showDislikeMenu'),
 ('搜索结果整列表入队', 'pages/HomePage.ets', r'this.searchResults.length > 1'),
 ('榜单整列表入队', 'pages/BoardDetailPage.ets', r'buildQueue\(\)'),
 ('播放页音量/静音', 'pages/PlayDetailPage.ets', r'applyVolume|toggleMute|VolumeSheet'),
 ('播放队列面板', 'pages/PlayDetailPage.ets', r'QueueSheet|playFromQueue'),
 ('队列读取接口', 'service/PlayerService.ets', r'getPlayList\(\): SongInfo\[\]|getCurrentIndex'),
 ('搜索联想词 UI', 'pages/HomePage.ets', r'getTipListInfo|scheduleSearchTips'),
 ('歌单内调整位置', 'service/ListService.ets', r'moveMusicInList'),
 ('歌单行菜单:调整位置/移动到列表', 'pages/SonglistDetail/SonglistMenus.ets', r'list_change_position|list_move_to'),
 ('歌单排序面板已挂载', 'pages/SonglistDetailPage.ets', r'this\.SortSheet\(\)'),
 ('本地列表排序落库', 'pages/SonglistDetail/SonglistListOps.ets', r'replaceUserListMusic'),
 ('歌单详情排序走列表操作模块', 'pages/SonglistDetailPage.ets', r'sortRows\('),
 ('歌单详情去重走列表操作模块', 'pages/SonglistDetailPage.ets', r'dedupeRows\('),
 ('歌单详情队列走播放模块', 'pages/SonglistDetailPage.ets', r'buildQueue\('),
 ('歌单详情滚动记忆模块', 'pages/SonglistDetail/SonglistScrollMemory.ets', r'saveScrollOffset'),
 # 守卫逻辑搬到 PlayMediaAssets 后，判据指向加载器（页面只负责应用结果）
 ('封面请求防风暴守卫', 'pages/PlayDetail/PlayMediaAssets.ets', r'coverAttemptKey'),
 ('歌词请求防风暴守卫', 'pages/PlayDetail/PlayMediaAssets.ets', r'lyricFailedKey'),
 ('封面歌词共用同一套守卫', 'pages/PlayDetail/PlayMediaAssets.ets', r'MAX_RETRY'),
 ('封面 URL 规则单一出口', 'pages/PlayDetailPage.ets', r'PlayMediaAssets\.normalizeCoverUrl'),
 # 进度条两端必须分别是「当前时间 / 总时长」：曾经误写成两端都显示 currentTime
 # 控制条抽成组件后，判据指到组件（右侧必须是总时长，不能用 currentTime）
 ('播放页进度两侧为当前/总时长', 'pages/PlayDetail/PlayerControls.ets', r'\? this\.previewTime : this\.totalTime'),
 ('播放页控制条抽成组件', 'pages/PlayDetailPage.ets', r'PlayerControls\(\{'),
 # 下载域拆成 download/{Types,Context,Files,Storage,Queue} 后，判据指向对应分层文件
 ('下载不打断用户（默认不进选择器）', 'core/music/download/DownloadFiles.ets', r'downloadUseFilePicker'),
 ('下载任务用真实落盘路径', 'core/music/download/DownloadQueue.ets', r'task\.filePath = savedPath'),
 ('下载历史只存完成/失败', 'core/music/download/DownloadStorage.ets', r'pickHistoricTasks'),
 ('下载队列唯一持有任务表', 'core/music/download/DownloadQueue.ets', r'const downloadTasks: Map<string, DownloadTask> = new Map\(\)'),
 ('下载文件名规则单一出口', 'core/music/download/DownloadFiles.ets', r'buildMusicFileStem'),
 ('下载文件选择器开关设置项', 'pages/Home/Setting/DownloadSection.ets', r'downloadUseFilePicker'),
 # 设置服务拆分：类型/默认值、存储加载与旧数据迁移各自成文件，主文件只负责写与广播
 ('设置类型与默认值模块', 'service/settings/SettingsTypes.ets', r'export function createDefaultSettings'),
 ('设置存储加载模块', 'service/settings/SettingsStorage.ets', r'export async function loadSettingsFromStorage'),
 ('设置旧数据迁移模块', 'service/settings/SettingsStorage.ets', r'export async function migrateLegacySettings'),
 ('设置服务保留对外类型', 'service/SettingsService.ets', r"export type \{[\s\S]{0,200}AppSettings"),
 # 动作菜单统一走 DialogService：取消项由系统菜单提供，避免两个「取消」
 ('播放页菜单走统一入口', 'pages/PlayDetailPage.ets', r'await appActionMenu\('),
 ('本地音乐菜单走统一入口', 'pages/LocalMusicPage.ets', r'await appActionMenu\('),
 ('收藏歌单菜单走统一入口', 'pages/SonglistDetailPage.ets', r'await appActionMenu\('),
 # 播放服务拆分：订阅中心 / 进度快照存储 / 公共类型
 ('播放事件订阅中心', 'service/player/PlaybackEvents.ets', r'export const playbackEvents'),
 ('播放进度快照存储', 'service/player/PlaybackProgressStore.ets', r'export async function savePlaybackSnapshot'),
 ('播放公共类型模块', 'service/player/PlaybackTypes.ets', r'export type PlayStatus'),
 ('歌词页可拖拽进度线', 'pages/PlayDetailPage.ets', r'handleSeekChange'),
 ('两处进度控件共用 seek 逻辑', 'pages/PlayDetailPage.ets', r'this\.handleSeekChange\(value, mode\)'),
 # 我的页歌单卡片菜单（重命名/删除/更新内容），与全部歌单页共用一份定义
 ('我的卡片歌单菜单', 'pages/Home/MylistView.ets', r'openListMenu'),
 ('歌单菜单共享定义', 'pages/Home/Mylist/ListMenuActions.ets', r'showPlaylistActionMenu'),
 ('全部歌单页共用菜单', 'pages/UserListsPage.ets', r'showPlaylistActionMenu'),
 ('面板先回调再关闭', 'components/ui/InputSheet.ets', r'先回调再关闭'),
 ('榜单详情统一超时重试', 'core/leaderboard.ets', r'getLeaderboardDetailReliable'),
 ('榜单 Tab 用统一重试', 'pages/Home/LeaderboardView.ets', r'getLeaderboardDetailReliable'),
 ('榜单详情页用统一重试', 'pages/BoardDetailPage.ets', r'getLeaderboardDetailReliable'),
 # 语言切换后缓存文案要重建（筛选/排序标签缓存在 @State 里）
 ('榜单筛选文案跟随语言', 'pages/Home/LeaderboardView.ets', r"@Watch\('onLanguageChanged'\)"),
 ('歌单排序文案跟随语言', 'pages/Home/SongListView.ets', r"@Watch\('onLanguageChanged'\)"),
 ('酷我歌词双通道+重试', 'core/music/sources/kw/lyric.ets', r'requestNewlyric|requestMobileLyric'),
 ('酷我歌词 zlib 解压(原生)', 'core/napi/napi_inflate.ets', r'zlibInflate'),
 ('二进制 HTTP 请求入口', 'core/network/http/HttpClient.ets', r'httpRequestBinary'),
 # 批量栏拆成独立组件后，判据变成「页面在 build 里挂载了批量栏」+「批量栏组件存在」
 ('下载页多选批量栏已挂载', 'pages/DownloadPage.ets', r'DownloadSelectionBar\(\{'),
 ('下载页批量操作组件可用', 'pages/Download/DownloadSelectionBar.ets', r'onToggleSelectAll|onDeleteAll'),
 ('系统歌词:会话就绪后接管', 'service/BackgroundRunningManager.ets',
  r'pendingSystemDesktopLyric|notifySessionReady'),
 ('系统歌词:显式置为可见', 'service/BackgroundRunningManager.ets', r'setDesktopLyricVisible\(enable\)'),
 ('系统歌词:元数据带整段 LRC', 'service/BackgroundRunningManager.ets',
  r'showBluetoothLyric \|\| this\.systemDesktopLyricActive'),
 ('系统歌词:由浮窗自动升级', 'components/common/DesktopLyric.ets', r'upgradeToSystemLyric'),
 ('桌面歌词模式提示', 'pages/Home/Setting/DesktopLyricSection.ets', r'desktop_lyric_system_mode'),
 ('触感反馈服务(鸿蒙振动)', 'service/HapticService.ets', r'vibrator\.startVibration|HapticService'),
 ('触感反馈接入交互点', 'components/player/PlayerBar.ets', r'hapticService\.'),
 ('触感反馈设置项', 'pages/Home/Setting/BasicSection.ets', r'hapticFeedback'),
 ('触感反馈权限声明', '../module.json5', r'ohos\.permission\.VIBRATE'),
 ('统一分段控件组件', 'components/ui/SegmentedBar.ets', r'export struct SegmentedBar'),
 ('下载页用统一分段控件', 'pages/DownloadPage.ets', r'SegmentedBar\('),
 ('运行日志用统一分段控件', 'pages/LogPage.ets', r'SegmentedBar\('),
 ('播放页用统一分段控件', 'pages/PlayDetailPage.ets', r'SegmentedBar\('),
 ('歌单排序用统一分段控件', 'pages/Home/SongListView.ets', r'SegmentedBar\('),
 ('下拉刷新容器', 'components/ui/RefreshContainer.ets', r'export struct RefreshContainer'),
 ('歌单页下拉刷新', 'pages/Home/SongListView.ets', r'RefreshContainer\('),
 ('榜单页下拉刷新', 'pages/Home/LeaderboardView.ets', r'RefreshContainer\('),
 ('下载页下拉刷新', 'pages/DownloadPage.ets', r'RefreshContainer\('),
 ('我的页下拉刷新', 'pages/Home/MylistView.ets', r'RefreshContainer\('),
 ('触控热区工具函数', 'theme/DesignTokens.ets', r'touchRegion\('),
 ('下载页操作图标热区', 'pages/Download/DownloadTaskRow.ets', r'touchRegion\(22\)'),
 ('下载页状态色走设计 token', 'pages/Download/DownloadView.ets', r'DesignTokens\.(success|warning|info|danger)\(\)'),
 ('下载页暂停态独立文案', 'pages/Download/DownloadView.ets', r"download_paused"),
 ('下载页进度未变不重绘', 'pages/Download/DownloadView.ets', r'downloadTasksSignature'),
 ('返回按钮热区', 'components/common/NavBackButton.ets', r'touchRegion\(34\)'),
 ('榜单展开/进入热区', 'pages/Home/LeaderboardView.ets', r'touchRegion\('),
 ('歌单批量栏触控高度', 'pages/SonglistDetail/SonglistBatchBar.ets', r'touchTarget\(\)'),
 ('系统符号用 SymbolGlyph 渲染', 'components/ui/StateView.ets', r'SymbolGlyph\('),
 ('底部 Tab 图标用 SymbolGlyph', 'pages/Home/Home/HomeBottomTabBar.ets', r'SymbolGlyph\(tab\.icon\)'),
 ('空态图标用 SymbolGlyph', 'components/common/EmptyView.ets', r'SymbolGlyph\(this\.iconRes\)'),
 ('底部面板用系统 bindSheet', 'components/ui/BottomSheet.ets', r'bindSheet\(\$\$this\.visible'),
 ('全局面板宿主', 'components/ui/SheetHost.ets', r'export struct SheetHost'),
 ('全局面板服务', 'service/SheetService.ets', r'export const sheetService'),
 ('面板宿主挂在根节点', 'pages/NavIndex.ets', r'SheetHost\(\)'),
 ('设置项走全局面板', 'components/ui/SettingsSection.ets', r'sheetService\.(select|input)'),
 ('主题写入走设置服务(单一入口)', 'service/ThemeService.ets', r'settingsService\.update\(\{ themeId \}\)'),
 ('切源自动重载歌单列表', 'pages/Home/SongListView.ets', r'@Watch\(.onSourceIdChange.\)'),
 ('歌单卡片音源以数据来源为准', 'pages/Home/SongListView.ets', r'source: sl\.source \|\| this\.sourceId'),
 ('QQ歌单详情用可用接口', 'core/music/sources/tx/songList.ets', r'fcg_v8_playlist_cp\.fcg'),
 ('QQ歌单详情兼容两种外层结构', 'core/music/sources/tx/songList.ets', r'body\.data\?\.cdlist \?\? body\.cdlist'),
 # 拖拽排序从「系统拖放 onDragStart/onDrop」改为「手柄 + 原始触摸」：
 # 真机上系统拖放不生效还会误触发切歌，判据同步改成新的实现要点。
 ('队列拖拽手柄', 'pages/PlayDetail/QueueSheet.ets', r'sys\.symbol\.line_3_horizontal'),
 ('队列拖拽用原始触摸事件', 'pages/PlayDetail/QueueSheet.ets', r'TouchType\.Move'),
 ('拖拽期间锁定列表滚动', 'pages/PlayDetail/QueueSheet.ets', r'enableScrollInteraction\(!this\.dragging\)'),
 ('拖拽手柄吞掉点击', 'pages/PlayDetail/QueueSheet.ets', r'\.onClick\(\(\) => \{\}\)'),
 ('队列拖拽结果落到播放队列', 'pages/PlayDetailPage.ets', r'this\.reorderQueue\(from, to\)'),
 ('队列移除', 'service/PlayerService.ets', r'removeFromQueue'),
 ('动作菜单不再重复“取消”', 'service/DialogService.ets', r'不再自己追加'),
 ('更多操作面板标题用歌曲', 'pages/PlayDetailPage.ets', r'title: this\.singer\.length > 0'),
 # 真机踩坑 1：底栏挂了 expandSafeArea 后整条控制栏点不动（触控区不生效）
 ('播放页底栏可点(不吞触控)', 'pages/PlayDetail/PlayerControls.ets', r'dispatch\(',
  r'expandSafeArea'),
 # 真机踩坑 2：把动态文案/图标当 @Builder 参数传，状态变了界面不变（看起来像点了没反应）
 ('底栏动态文案不走 @Builder 参数', 'pages/PlayDetail/PlayerControls.ets', r'Text\(this\.playModeText\)',
  r'@Builder\s+(MenuButton|TransportButton)'),
]

fails = []
for check in CHECKS:
    name, rel, pattern = check[0], check[1], check[2]
    forbidden = check[3] if len(check) > 3 else None
    text = read(rel)
    ok = bool(text) and re.search(pattern, text) is not None
    if ok and forbidden is not None and re.search(forbidden, text) is not None:
        print(f'（{name}：出现了禁止写法 /{forbidden}/）')
        ok = False
    print(('PASS ' if ok else 'FAIL ') + name)
    if not ok:
        fails.append(name)
print()
print('总计', len(CHECKS), '未通过', len(fails))
sys.exit(1 if fails else 0)
