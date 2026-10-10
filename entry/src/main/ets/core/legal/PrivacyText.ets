/**
 * 隐私政策正文（上架必备：应用内可随时查阅）
 *
 * 与许可协议同样按语言整篇维护：这是"内容"而不是界面文案，
 * 整篇放在一起便于和法律原文逐条比对，也不拆成大量 i18n 键。
 * 结构复用 PactText 的 PactSection（标题 + 段落），不另立一套类型。
 */
import type { PactSection } from './PactText';

const ZH_NOTICE = '我们不会收集你的个人信息。以下说明本应用会用到哪些能力、以及数据存在哪里。';

const ZH_SECTIONS: PactSection[] = [
  {
    title: '',
    paragraphs: [
      '本隐私政策适用于 LX Music（洛雪音乐）鸿蒙版。我们遵循"最小必要"原则：应用不要求注册、不要求登录、不申请通讯录/位置/相机等与音乐播放无关的权限，也不含任何广告或行为分析类第三方 SDK（仅集成系统自带的 HarmonyOS SDK 能力）。',
    ],
  },
  {
    title: '一、我们收集与不收集的信息',
    paragraphs: [
      '1.1 不收集：本应用不收集你的姓名、手机号、账号、通讯录、位置、相册、设备标识符等任何可识别个人身份的信息，也不会将其上传到我们控制的服务器。',
      '1.2 在你主动使用同步功能时，本应用会把"我的列表/歌单/播放历史"等音乐数据发送到你自己填写的同步服务器地址（由你自行提供与保管凭据）。这些数据不经过我们，我们也无法查看。这一项默认关闭。',
      '1.3 应用内置的音源搜索与播放，是向公开的第三方音乐平台接口发起请求以获取歌曲信息与音频地址；这类请求只包含歌曲关键词本身，不包含你的个人信息。',
    ],
  },
  {
    title: '二、数据如何存储',
    paragraphs: [
      '2.1 设置项、我的列表、播放历史、歌词缓存、下载记录等数据全部保存在本机应用沙箱内（Preferences 与应用私有目录），卸载应用即被系统清除。',
      '2.2 应用提供"设置 → 数据备份"导出为本地文件的能力；导出文件由你自行保存与分享，其内容安全由你掌握。',
      '2.3 应用提供"清理缓存"与"恢复默认设置"，你可以随时删除本机保存的全部应用数据。',
    ],
  },
  {
    title: '三、权限说明（与应用清单一一对应）',
    paragraphs: [
      '3.1 ohos.permission.INTERNET：访问音乐平台接口与自定义源，用于搜索、在线播放、下载歌词与封面。',
      '3.2 ohos.permission.GET_NETWORK_INFO：判断当前网络状态，网络不可用时避免无意义的请求与重试。',
      '3.3 ohos.permission.KEEP_BACKGROUND_RUNNING：在应用退到后台时继续播放音乐（后台类型：音频播放）。',
      '3.4 ohos.permission.VIBRATE：为切歌、播放暂停等操作提供轻微触感反馈（可在设置中关闭）。',
      '3.5 ohos.permission.MICROPHONE：仅在你主动使用「听歌识曲」时采集环境音频，并即时上传到酷狗指纹接口完成识别；音频本身不保存，识别出的歌曲文本信息只存本机历史记录（可随时清空）。',
    ],
  },
  {
    title: '四、第三方数据处理',
    paragraphs: [
      '4.1 本应用不内置任何统计、广告、崩溃上报 SDK，因此不会把数据交给第三方用于画像或广告。',
      '4.2 你自行添加的"自定义源"脚本属于第三方内容，其行为由脚本提供者负责；请只添加你信任的源。',
      '4.3 播放音乐时，音频数据、歌词、封面均从第三方音乐平台或你配置的源直接获取，请同时遵守相应平台的服务条款。',
      '4.4 「听歌识曲」会把你主动采集的音频片段即时上传到酷狗指纹接口完成识别；上传内容仅为音频指纹所需数据，不含账号等个人信息，请同时遵守酷狗的服务条款。',
    ],
  },
  {
    title: '五、未成年人保护',
    paragraphs: [
      '本应用不面向儿童设计，不收集任何年龄信息，也不含付费、抽奖、社交等交互，因此不存在针对未成年人的个性化推荐或商业化行为。',
    ],
  },
  {
    title: '六、你的权利',
    paragraphs: [
      '6.1 你可以在设置中随时关闭桌面歌词、蓝牙歌词、后台播放、触感反馈、自动同步等能力。',
      '6.2 你可以通过"恢复默认设置"或直接卸载应用，删除本机保存的全部数据；已导出到本机之外的文件请自行删除。',
      '6.3 你可以通过应用内"设置 → 关于"查看开源仓库地址，对本政策提出疑问。',
    ],
  },
  {
    title: '七、政策更新',
    paragraphs: [
      '如本政策发生变更，我们会在应用新版本中同步更新本页内容与版本号；变更后继续使用即视为你接受更新后的政策。',
    ],
  },
];

const EN_NOTICE =
  'We do not collect your personal information. This page explains which capabilities the app uses and where data is stored.';

const EN_SECTIONS: PactSection[] = [
  {
    title: '',
    paragraphs: [
      'This privacy policy applies to LX Music for HarmonyOS. We follow a data-minimisation principle: the app does not require registration or sign-in, does not request permissions unrelated to music playback (contacts, location, camera), and bundles no advertising or analytics third-party SDKs - only built-in HarmonyOS SDK capabilities.',
    ],
  },
  {
    title: '1. Information We Do and Do Not Collect',
    paragraphs: [
      '1.1 We do not collect your name, phone number, account, contacts, location, gallery or device identifiers, and never upload them to servers we control.',
      '1.2 Only when you enable sync yourself, the app sends music data (playlists, history) to the sync server address you provide and manage. Those credentials and data never pass through us, and are disabled by default.',
      '1.3 Online search and playback send requests to public third-party music platform endpoints to fetch song info and audio URLs; such requests contain only the search keywords, no personal information.',
    ],
  },
  {
    title: '2. How Data Is Stored',
    paragraphs: [
      '2.1 Settings, playlists, playback history, lyric cache and download records are stored inside the app sandbox on this device (Preferences and private app directory) and are removed by the system when the app is uninstalled.',
      '2.2 Backup export writes a local file that you keep and share yourself; you control its security.',
      '2.3 "Clear cache" and "Reset settings" let you delete all app data stored on this device at any time.',
    ],
  },
  {
    title: '3. Permissions (matching the app manifest)',
    paragraphs: [
      '3.1 ohos.permission.INTERNET: reach music platform endpoints and custom sources for search, streaming, lyrics and covers.',
      '3.2 ohos.permission.GET_NETWORK_INFO: detect network availability to avoid pointless requests and retries.',
      '3.3 ohos.permission.KEEP_BACKGROUND_RUNNING: keep audio playing while the app is in the background (background mode: audio playback).',
      '3.4 ohos.permission.VIBRATE: light haptic feedback for track changes and play/pause (can be disabled in settings).',
      '3.5 ohos.permission.MICROPHONE: only when you actively use song recognition, ambient audio is captured and immediately uploaded to the Kugou fingerprint endpoint for identification; the audio itself is never stored, and only the recognized song metadata is kept in the on-device history (which you can clear at any time).',
    ],
  },
  {
    title: '4. Third-Party Processing',
    paragraphs: [
      '4.1 No analytics, advertising or crash-reporting SDKs are bundled, so no data is handed to third parties for profiling or ads.',
      '4.2 Custom source scripts you add are third-party content and are the responsibility of their authors; only add sources you trust.',
      '4.3 Audio, lyrics and covers are fetched directly from third-party music platforms or your configured sources; please also follow the terms of those platforms.',
      '4.4 "Song recognition" uploads the audio snippet you capture to the Kugou fingerprint endpoint for identification; the upload contains only the data required for audio fingerprinting and no account or other personal information, and is subject to Kugou\'s terms of service.',
    ],
  },
  {
    title: '5. Protection of Minors',
    paragraphs: [
      'The app is not designed for children, collects no age information, and contains no payment, lottery or social features, so there is no profiling or commercialisation aimed at minors.',
    ],
  },
  {
    title: '6. Your Rights',
    paragraphs: [
      '6.1 You can switch off desktop lyrics, Bluetooth lyrics, background playback, haptics and auto sync at any time in settings.',
      '6.2 Use "Reset settings" or uninstall the app to delete all data stored on this device; delete exported files yourself.',
      '6.3 Check "Settings - About" for the open-source repository and raise any question about this policy.',
    ],
  },
  {
    title: '7. Policy Updates',
    paragraphs: [
      'If this policy changes, the updated page ships with the next app version; continued use after an update means you accept the revised policy.',
    ],
  },
];

/** 隐私政策页顶部提示 */
export function getPrivacyNotice(language: string): string {
  return language === 'en-US' ? EN_NOTICE : ZH_NOTICE;
}

/** 按语言取隐私政策正文 */
export function getPrivacySections(language: string): PactSection[] {
  return language === 'en-US' ? EN_SECTIONS : ZH_SECTIONS;
}
