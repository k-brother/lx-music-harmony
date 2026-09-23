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
 # 本地音乐离线歌词：同名 .lrc 优先，读不到再回退在线匹配
 ('本地同名歌词文件读取', 'core/music/local/LocalLyricFile.ets', r'readSidecarLyric'),
 ('本地歌词优先走同名文件', 'core/music/ResolvePlayback.ets', r'readSidecarLyric'),
 ('运行日志页', 'pages/LogPage.ets', r'logService'),
 ('日志落盘/回读', 'service/LogService.ets', r'restoreFromFile|exportToFile'),
 ('日志门面接入', 'core/log/AppLogger.ets', r'appLog'),
 ('缓存分项统计', 'service/CacheService.ets', r'getMetadataCacheInfo|getResourceCacheInfo'),
 # 主题数据拆到 core/theme/{ThemeFactory,data/LightThemes,data/DarkThemes}，门面只留查询 API
 ('主题 16 套（浅色）', 'core/theme/data/LightThemes.ets', r'LIGHT_THEMES: ThemeItem\[\]'),
 ('主题 16 套（深色）', 'core/theme/data/DarkThemes.ets', r'DARK_THEMES: ThemeItem\[\]'),
 ('主题工厂统一出口', 'core/theme/ThemeFactory.ets', r'export function createTheme\('),
 ('主题门面保留查询 API', 'core/theme/themes.ets', r'export function getThemeById'),
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
 # 搜索结果整列入队的逻辑收敛到 syncSearchQueueAsPlaylist（判据跟着指向该辅助方法，
 # 且必须真的把整列交给播放器，避免只留一句守卫、实际不入队）
 ('搜索结果整列表入队', 'pages/HomePage.ets',
  r'syncSearchQueueAsPlaylist\(item: SearchResultItem\): void[\s\S]*?setPlayList\(queue, startIndex\)'),
 ('榜单整列表入队', 'pages/BoardDetailPage.ets', r'buildQueue\(\)'),
 ('播放页音量/静音', 'pages/PlayDetailPage.ets', r'applyVolume|toggleMute|VolumeSheet'),
 ('播放队列面板', 'pages/PlayDetailPage.ets', r'QueueSheet|playFromQueue'),
 ('队列读取接口', 'service/PlayerService.ets', r'getPlayList\(\): SongInfo\[\]|getCurrentIndex'),
 ('搜索联想词 UI', 'pages/HomePage.ets', r'getTipListInfo|scheduleSearchTips'),
 ('歌单内调整位置', 'service/ListService.ets', r'moveMusicInList'),
 ('歌单行菜单:调整位置/移动到列表', 'pages/SonglistDetail/SonglistMenus.ets', r'list_change_position|list_move_to'),
 ('歌单排序面板已挂载', 'pages/SonglistDetailPage.ets', r'this\.SortSheet\(\)'),
 ('本地列表排序落库', 'pages/SonglistDetail/SonglistLocalLibrary.ets', r'replaceUserListMusic'),
 ('歌单详情排序走列表操作模块', 'pages/SonglistDetailPage.ets', r'sortRows\('),
 ('歌单详情去重走列表操作模块', 'pages/SonglistDetailPage.ets', r'dedupeRows\('),
 ('歌单详情队列走播放模块', 'pages/SonglistDetail/SonglistPlayActions.ets', r'buildQueue\('),
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
 ('播放页用统一分段控件', 'pages/PlayDetail/PlayDetailTopBar.ets', r'SegmentedBar\('),
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
 ('榜单展开/进入热区', 'pages/Home/Leaderboard/ChartCard.ets', r'touchRegion\('),
 ('歌单批量栏触控高度', 'pages/SonglistDetail/SonglistBatchBar.ets', r'touchTarget\(\)'),
 ('系统符号用 SymbolGlyph 渲染', 'components/ui/StateView.ets', r'SymbolGlyph\('),
 ('底部 Tab 图标用 SymbolGlyph', 'pages/Home/Home/HomeBottomTabBar.ets', r'SymbolGlyph\(tab\.icon\)'),
 # EmptyView/ErrorView 已并入 StateView：空态图标仍必须是 SymbolGlyph
 ('空态图标用 SymbolGlyph', 'components/ui/StateView.ets', r'SymbolGlyph\(this\.state === .error.'),
 ('底部面板用系统 bindSheet', 'components/ui/BottomSheet.ets', r'bindSheet\(\$\$this\.visible'),
 ('全局面板宿主', 'components/ui/SheetHost.ets', r'export struct SheetHost'),
 ('全局面板服务', 'service/SheetService.ets', r'export const sheetService'),
 ('面板宿主挂在根节点', 'pages/NavIndex.ets', r'SheetHost\(\)'),
 ('设置项走全局面板', 'components/ui/SettingsSection.ets', r'sheetService\.(select|input)'),
 ('主题写入走设置服务(单一入口)', 'service/ThemeService.ets', r'settingsService\.update\(\{ themeId \}\)'),
 ('切源自动重载歌单列表', 'pages/Home/SongListView.ets', r'@Watch\(.onSourceIdChange.\)'),
 ('歌单卡片音源以数据来源为准', 'pages/Home/SongList/SongListLoader.ets', r'source: sl\.source \|\| sourceId'),
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
 # 真机踩坑（对照实验结论）：@Builder 的参数不会随状态刷新，但 Builder 内部读 this.* 会刷新。
 # 实验：参数版点「播放模式」后状态已切到 sequential，界面仍停在上一档；
 #      改成 Builder 内读状态后，界面与日志一致。
 # 底线：动态内容（播放模式文案、播放/暂停图标、点赞态…）一律不进 @Builder 参数。
 ('底栏动态文案在 Builder 内读状态', 'pages/PlayDetail/PlayerControls.ets', r'Text\(this\.labelFor\(kind\)\)'),
 ('底栏 Builder 不接收动态文案参数', 'pages/PlayDetail/PlayerControls.ets', r'private labelFor\(',
  r'label: string'),
 # 评论行已抽成组件（@Prop 会随父组件重渲染更新），比“Builder 内按 index 读”更彻底
 ('评论行抽成组件', 'pages/CommentPage.ets', r'CommentRow\(\{'),
 ('评论行用 @Prop 接收数据', 'pages/Comment/CommentRow.ets', r'@Prop comment: Comment'),
 ('评论点赞态读自身数据', 'pages/Comment/CommentRow.ets', r'this\.comment\.isLiked',
  r'buildCommentItem\('),
 # 播放量格式化曾经在 4 处各写一遍（阈值/空格/小数不同，真机出现过 8550.7）
 ('播放量格式化单一出口', 'utils/FormatTools.ets', r'export function formatPlayCount'),
 ('排行榜播放量走统一实现', 'pages/Home/Leaderboard/ChartCard.ets', r'formatPlayCount\(count, t\(',
  r"toFixed\(1\) \+ ' ' \+ t\('ten_thousand_unit'\)"),
 ('歌单卡片播放量走统一实现', 'pages/Home/SongList/SongListCard.ets', r'formatPlayCount\(num, t\(',
  r"toFixed\(1\) \+ ' ' \+ t\('ten_thousand_unit'\)"),
 # 提示/确认框统一出口：页面不再自己 getPromptAction().showDialog 拼按钮与颜色
 ('确认与提示统一走 DialogService', 'service/DialogService.ets', r'export async function appAlert'),
 ('日志页清空走统一确认', 'pages/LogPage.ets', r'appConfirm\(',
  r'getPromptAction\(\)\.showDialog'),
 ('自定义源删除走统一确认', 'pages/Home/CustomSourceView.ets', r'appConfirm\(',
  r'getPromptAction\(\)\.showDialog'),
 ('退出确认走统一确认', 'pages/Index.ets', r'appConfirm\(',
  r"color: '#8E8E93'"),
 ('歌单详情确认走统一确认', 'pages/SonglistDetailPage.ets', r'appConfirm\(title, message\)',
  r'getPromptAction\(\)\.showDialog'),
 # 榜单封面不允许再拿「第一首歌的封面」冒充（不同榜单会长得一模一样）
 ('榜单封面只用榜单自己的图', 'pages/Home/Leaderboard/ChartCard.ets', r'placeholderGradientOptions',
  r'card\.topSongs\[i\]\.pic'),
 # 备份曾经的「XOR + Base64」等于没加密（原注释自称仅供演示），现统一到 AES
 ('备份加密用 AES 而非 XOR', 'service/crypto/AesPayload.ets', r'export async function encryptWithPassword',
  r'XOR 加密（仅用于演示'),
 ('备份兼容旧 XOR 格式解密', 'service/crypto/AesPayload.ets', r'legacyXorDecrypt'),
 ('备份服务走统一加解密', 'service/BackupService.ets', r'decryptWithPassword\('),
 ('同步加解密走同一实现', 'service/sync/SyncCrypto.ets', r"from '../crypto/AesPayload'"),
 # 备份域拆分：类型/数据映射与服务分开
 ('备份类型独立成文件', 'service/backup/BackupTypes.ets', r'export enum BackupDataType'),
 ('备份数据映射独立成文件', 'service/backup/BackupDataMapping.ets', r'export async function collectBackupData'),
 ('备份服务只留文件与调度', 'service/BackupService.ets', r'from \'./backup/BackupDataMapping\''),
 # 自定义源行已抽成组件（@Prop 随父组件重渲染更新，避免「启用角标不刷新」）
 ('自定义源行抽成组件', 'pages/Home/CustomSourceView.ets', r'CustomSourceRow\(\{'),
 ('自定义源行接收启用态', 'pages/Home/CustomSource/CustomSourceRow.ets', r'@Prop isEnabled: boolean'),
 # 颜色 token 化：面板遮罩/日志状态色不再写死
 ('面板遮罩走设计 token', 'components/ui/BottomSheet.ets', r'DesignTokens\.maskColor\(\)'),
 ('日志状态色走设计 token', 'pages/LogPage.ets', r'DesignTokens\.(warning|success|info)\(\)'),
 # 空/加载/错误态统一出口：旧 EmptyView/ErrorView 已删除，页面一律用 StateView
 ('空态加载态统一走 StateView', 'components/ui/StateView.ets', r"export type ViewState"),
 ('列表页用 StateView 展示空态', 'pages/Home/SongListView.ets', r"StateView\(\{ state: 'empty'"),
 ('榜单详情用 StateView 展示状态', 'pages/BoardDetailPage.ets', r"StateView\(\{ state: 'loading'"),
 ('日志页用 StateView 展示空态', 'pages/LogPage.ets', r"StateView\(\{ state: 'empty'"),
 ('排行榜空态用 StateView', 'pages/Home/LeaderboardView.ets', r"StateView\(\{"),
 # 歌单存储层独立：业务层不再直接读写 Preferences
 ('歌单存储层独立成文件', 'service/list/ListStorage.ets', r'export async function loadListsFromStorage'),
 ('歌单服务不再直写存储', 'service/ListService.ets', r"from '\./list/ListStorage'",
  r'StorageService\.setString'),
 ('歌单 ID 常量独立成文件', 'service/list/ListIds.ets', r'export const LIST_IDS'),
 # 系统播控命令注册器独立，且注册/回调错误处理只有一处
 ('播控命令注册器独立成文件', 'service/player/MediaControlCommands.ets', r'export function registerMediaControlCommands'),
 ('播控命令错误处理统一', 'service/player/MediaControlCommands.ets', r'function safeInvoke'),
 ('播控类型独立成文件', 'service/player/AvSessionTypes.ets', r'export interface AvSessionCallbacks'),
 # 播放量格式化只允许一份实现：CommonUtils 的同名函数必须委托给 FormatTools
 ('音源侧的播放量格式化也走统一实现', 'utils/CommonUtils.ets', r'formatPlayCountCore\(',
  r"toFixed\(1\) \+ '万'"),
 # 时间解析/格式化只允许一份实现（FormatTools），其它入口必须是薄委托
 ('时间解析统一实现', 'utils/FormatTools.ets', r'export function parsePlayTimeText'),
 ('时钟格式化统一实现', 'utils/FormatTools.ets', r'export function formatClock\('),
 ('CommonUtils 时长格式化委托统一实现', 'utils/CommonUtils.ets', r'formatClockWithHours\(time\)',
  r"padStart\(2, '0'\)"),
 # 秒↔文本 只允许 FormatTools 一份实现：映射层必须委托，且不得自己拼字符串
 ('歌单映射的时长格式化委托统一实现', 'core/list/SongMappers.ets', r'formatClock\(', r'padStart|Math\.floor\(.*60'),
 ('音源解析的时长函数委托统一实现', 'core/music/MusicParsingUtils.ets', r'parsePlayTimeText\(interval\)'),
 # 通用小工具只留一份实现（delayMs / generateId / bytesToString / 歌名过滤 / 内建源判断）
 ('等待工具统一实现', 'utils/Utils.ets', r'export function delayMs'),
 ('ID 生成统一实现', 'utils/CommonUtils.ets', r"export \{ generateId \} from './Utils'"),
 ('字节转字符串统一实现', 'core/music/sources/kg/util.ets', r'cryptoBytesToString\(bytes\)'),
 ('歌名过滤统一实现', 'core/music/MusicParsingUtils.ets', r'trimSpecialChars\(name\)'),
 ('内建音源判断统一实现', 'core/music/MusicFeatureEntry.ets', r'return isBuiltinSourceId\(id\)'),
 # 进度轮询独立成类：节奏与失败容错只有一处
 ('进度轮询器独立成文件', 'service/player/ProgressPoller.ets', r'export class ProgressPoller'),
 ('进度轮询失败自动停表', 'service/player/ProgressPoller.ets', r'MAX_FAILURES'),
 ('播放服务用进度轮询器', 'service/PlayerService.ets', r'this\.poller\.start\(\)'),
 # 下拉刷新：容器统一成一个组件，各列表页都要真的接上（入口方法名各页统一）
 ('下拉刷新容器统一实现', 'components/ui/RefreshContainer.ets', r'export struct RefreshContainer'),
 ('歌单详情下拉刷新', 'pages/SonglistDetailPage.ets', r'RefreshContainer[\s\S]*?onPullRefresh\(\): void'),
 ('本地音乐下拉刷新重新扫描', 'pages/LocalMusicPage.ets', r'refreshLibrary\(\): Promise<void>[\s\S]*?localMusicService\.rescan\(\)'),
 ('播放历史下拉刷新', 'pages/HistoryListPage.ets', r'RefreshContainer[\s\S]*?loadHistory\(true\)'),
 ('我喜欢下拉刷新', 'pages/LoveListPage.ets', r'RefreshContainer[\s\S]*?loadSongs\(true\)'),
 # 下拉刷新必须保留列表：静默刷新不能把 isLoading 置回 true 导致闪骨架
 ('下拉刷新保留列表不闪骨架', 'pages/SonglistDetailPage.ets', r'if \(!silent\) \{\s*\n\s*this\.isLoading = true;'),
 # 播放页手势：封面区下滑关闭（位移过阈值直接返回上一页）
 ('播放页下滑关闭手势', 'pages/PlayDetailPage.ets',
  r'DISMISS_DRAG_THRESHOLD_VP[\s\S]*?navigationService\.back\(\)'),
 # 播放页两种形态各自独立成 Builder（原先塞在同一个 80 行函数里）
 ('播放页宽屏双栏/窄屏翻页拆分', 'pages/PlayDetailPage.ets', r'WideStage\(\)[\s\S]*?NarrowStage\(\)'),
 # 逐字歌词（卡拉OK）：解析 / 取数 / 对齐 / 渲染 / 开关 五段都要在
 ('逐字歌词解析器', 'core/lyric/WordLyric.ets', r'export function parseWordLyric'),
 ('逐字歌词高亮渲染', 'components/common/LyricView.ets', r'KaraokeLine'),
 ('逐字歌词开关接入播放页菜单', 'pages/PlayDetail/PlaySettingsActions.ets', r'wordLyric'),
 ('逐字歌词与主歌词时间对齐', 'pages/PlayDetail/PlayMediaAssets.ets', r'parseWordLyric'),
 ('酷我逐字歌词保留逐字标记', 'core/music/sources/kw/lyric.ets', r'wordLines\.push'),
 ('网易云逐字歌词请求 yrc', 'core/music/sources/wy/lyric.ets', r'yv=1'),
 # 平滑进度：逐字高亮与进度条都靠它才有连续推进的观感
 ('播放页平滑进度表', 'pages/PlayDetailPage.ets', r'SMOOTH_TICK_MS'),
 # 单条记录的快捷操作（长列表里一次全清太粗）
 ('播放历史侧滑删除单条', 'pages/HistoryListPage.ets', r'removePlayHistoryItem'),
 ('我喜欢侧滑取消收藏', 'pages/LoveListPage.ets', r'SwipeUnloveAction'),
 ('歌词行长按复制', 'components/common/LyricView.ets', r'onLineLongPress'),
 ('搜索历史可删单条', 'pages/Home/Home/SearchInputContent.ets', r'onRemoveHistory'),
 # 2in1：接键盘后列表行/卡片要能用回车激活
 ('键盘激活判定统一实现', 'utils/KeyboardTools.ets', r'export function isConfirmKey'),
 ('统一列表行支持键盘激活', 'components/ui/ListRow.ets', r'isConfirmKey'),
 ('歌单卡片支持键盘激活', 'pages/Home/SongList/SongListCard.ets', r'isConfirmKey'),
 # 2in1：接鼠标时右键等同长按（PC 上没人愿意按住不动）
 ('列表行右键出菜单', 'components/ui/ListRow.ets', r'MouseButton\.Right'),
 # 重启续播：此前只恢复「最后一首 + 位置」，队列被清成单曲，下一首直接没反应
 ('播放队列快照存储', 'service/player/QueueSnapshot.ets', r'export async function loadQueueSnapshot'),
 ('队列变更统一落盘出口', 'service/PlayerService.ets', r'private persistQueue\(\): void'),
 ('重启恢复整队列', 'service/PlayerService.ets', r'restoreQueue\(song, savedQueue\)'),
 # 「记住列表滚动位置」从只有歌单详情覆盖到全部长列表
 ('滚动位置记忆统一实现', 'service/ScrollMemoryService.ets', r'export class ScrollMemoryHandle'),
 ('榜单详情记住滚动位置', 'pages/BoardDetailPage.ets', r'scrollMemory\.save'),
 ('本地音乐记住滚动位置', 'pages/LocalMusicPage.ets', r'scrollMemory\.restore'),
 ('历史记住滚动位置', 'pages/HistoryListPage.ets', r'scrollMemory\.restore'),
 ('我喜欢记住滚动位置', 'pages/LoveListPage.ets', r'scrollMemory\.restore'),
 # 「设置 → 列表」的三个显示开关此前只在歌单详情生效，现在由行组件统一执行
 ('列表行副标题统一拼装', 'core/list/RowTexts.ets', r'export function composeRowSubtitle'),
 ('列表行时长统一拼装', 'core/list/RowTexts.ets', r'export function composeRowDurationText'),
 ('统一列表行响应显示设置', 'components/ui/ListRow.ets', r"@StorageProp\('showListAlbum'\)"),
 ('本地音乐行响应显示设置', 'pages/LocalMusic/TrackRow.ets', r"@StorageProp\('showListDuration'\)"),
 ('榜单歌曲行响应显示设置', 'pages/BoardDetail/BoardSongRow.ets', r"@StorageProp\('showListSource'\)"),
 # 播放页封面手势：左右滑动切歌（华为音乐/Spotify 的习惯），翻页改由显式入口驱动
 ('播放页封面左右滑切歌', 'pages/PlayDetailPage.ets', r'SWIPE_TRACK_THRESHOLD_VP[\s\S]{0,500}?playNext\(\)'),
 ('播放页歌词页右滑回封面', 'pages/PlayDetailPage.ets',
  r'PanDirection\.Horizontal, distance: 30[\s\S]{0,200}?switchToCoverTab'),
 ('播放页翻页由显式入口驱动', 'pages/PlayDetailPage.ets', r'disableSwipe\(true\)'),
 # 下载并发数此前只有进过设置页才生效，现在随启动写入下载引擎
 ('下载并发数启动即生效', 'service/index.ets',
  r'setMaxConcurrentDownloads\(settingsService\.get\(\)\.maxConcurrentDownloads\)'),
 # 失败 ≠ 空：联网页拉取失败要有明确失败态与一键重试
 ('榜单详情失败态可重试', 'pages/BoardDetailPage.ets', r"state: 'error'[\s\S]{0,220}?loadBoardDetail\(\)"),
 ('排行榜失败态可重试', 'pages/Home/LeaderboardView.ets', r"state: 'error'[\s\S]{0,220}?loadBoardList\(\)"),
 ('歌单广场失败态可重试', 'pages/Home/SongListView.ets', r"state: 'error'[\s\S]{0,220}?loadSongList\(true\)"),
 ('评论失败态可重试', 'pages/CommentPage.ets', r"state: 'error'[\s\S]{0,220}?loadComments\(true\)"),
 # 启动不再用默认值覆盖用户偏好（曾经 setPlaybackRate(1.0) 会把倍速写回成 1.0）
 ('启动应用上次倍速', 'app/entryability/EntryAbility.ets', r'applySavedPlaybackRate\(\)'),
 ('倍速启动同步不写回设置', 'service/PlayerService.ets', r'async applySavedPlaybackRate\(\)'),
 # 队列面板：打开即定位到正在播放 + 一键回到当前（队列上百首时的必备入口）
 ('队列面板打开定位当前播放', 'pages/PlayDetail/QueueSheet.ets', r'onVisibleChanged\(\): void[\s\S]{0,260}?scrollToCurrent\(\)'),
 ('队列面板一键定位按钮', 'pages/PlayDetail/QueueSheet.ets', r"a11y_scroll_to_current"),
 ('底部面板支持标题栏动作', 'components/ui/BottomSheet.ets', r'@BuilderParam trailing'),
 # 定时退出：跨重启按剩余时长恢复，到点后清掉开关与落盘截止时间
 ('定时退出按剩余时长恢复', 'service/SleepTimerService.ets', r'resumeByDeadline'),
 ('定时退出到点清理状态', 'service/SleepTimerService.ets', r'void this\.clearDeadline\(\)'),
 # 播放页不得用页面里的旧状态覆盖定时开关（定时器的唯一所有者是 SleepTimerService）
 ('播放页不越权写定时开关', 'pages/PlayDetailPage.ets', r'private async savePlaySettings',
  r'sleepTimerEnabled: this\.timeoutExitEnabled'),
 # 搜索结果也能长按出单曲菜单（此前只能点一下播放）
 ('搜索结果长按出单曲菜单', 'pages/HomePage.ets', r'openSearchResultMenu'),
 ('搜索结果复用歌单详情单曲菜单', 'pages/HomePage.ets', r'showSongItemMenu\(row'),
 ('单曲菜单多选项可选', 'pages/SonglistDetail/SonglistMenus.ets', r'onSelectMode\?:'),
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
