/**
 * 许可协议文本（对应安卓版 navigation/components/PactModal.tsx）
 *
 * 协议是"内容"而不是界面文案，所以放在这里按语言整篇维护，
 * 不拆成大量 i18n 键（便于和法律原文逐条比对）。
 * 首次启动必须同意后才能使用；「设置 → 关于 → 许可协议」可随时回看。
 */

/** 协议的一个小节：标题 + 若干段落 */
export interface PactSection {
  title: string;
  paragraphs: string[];
}

const ZH_NOTICE = '在使用本软件前，你（使用者）需签署本协议才可继续使用！';

const ZH_SECTIONS: PactSection[] = [
  {
    title: '',
    paragraphs: [
      '本项目基于 Apache License 2.0 许可证发行，以下协议是对于 Apache License 2.0 的补充，如有冲突，以以下协议为准。',
      '词语约定：本协议中的“本项目”指 LX Music（洛雪音乐）移动版项目；“使用者”指签署本协议的使用者；“官方音乐平台”指对本项目内置的包括酷我、酷狗、咪咕等音乐源的官方平台统称；“版权数据”指包括但不限于图像、音频、名字等在内的他人拥有所属版权的数据。',
    ],
  },
  {
    title: '一、数据来源',
    paragraphs: [
      '1.1 本项目的数据来源原理是从各官方音乐平台的公开服务器中拉取数据（与未登录状态在官方平台 APP 获取的数据相同），经过对数据简单地筛选与合并后进行展示，因此本项目不对数据的准确性负责。',
      '1.2 本项目本身没有获取某个音频数据的能力，本项目使用的在线音频数据来源来自软件设置内“自定义源”设置所选择的“源”返回的在线链接。例如播放某首歌，本项目所做的只是将希望播放的歌曲名、艺术家等信息传递给“源”，若“源”返回了一个链接，则本项目将认为这就是该歌曲的音频数据而进行使用，至于这是不是正确的音频数据本项目无法校验其准确性，所以使用本项目的过程中可能会出现希望播放的音频与实际播放的音频不对应或者无法播放的问题。',
      '1.3 本项目的非官方平台数据（例如“我的列表”内列表）来自使用者本地系统或者使用者连接的同步服务，本项目不对这些数据的合法性、准确性负责。',
    ],
  },
  {
    title: '二、版权数据',
    paragraphs: [
      '2.1 使用本项目的过程中可能会产生版权数据。对于这些版权数据，本项目不拥有它们的所有权。为了避免侵权，使用者务必在 24 小时内清除使用本项目的过程中所产生的版权数据。',
    ],
  },
  {
    title: '三、音乐平台别名',
    paragraphs: [
      '3.1 本项目内的官方音乐平台别名为本项目内对官方音乐平台的一个称呼，不包含恶意。如果官方音乐平台觉得不妥，可联系本项目更改或移除。',
    ],
  },
  {
    title: '四、资源使用',
    paragraphs: [
      '4.1 本项目内使用的部分包括但不限于字体、图片等资源来源于互联网。如果出现侵权可联系本项目移除。',
    ],
  },
  {
    title: '五、免责声明',
    paragraphs: [
      '5.1 由于使用本项目产生的包括由于本协议或由于使用或无法使用本项目而引起的任何性质的任何直接、间接、特殊、偶然或结果性损害（包括但不限于因商誉损失、停工、计算机故障或故障引起的损害赔偿，或任何及所有其他商业损害或损失）由使用者负责。',
    ],
  },
  {
    title: '六、使用限制',
    paragraphs: [
      '6.1 本项目完全免费，且开源发布于 GitHub 面向全世界人用作对技术的学习交流，本项目不对项目内的技术可能存在违反当地法律法规的行为作保证。',
      '6.2 禁止在违反当地法律法规的情况下使用本项目，对于使用者在明知或不知当地法律法规不允许的情况下使用本项目所造成的任何违法违规行为由使用者承担，本项目不承担由此造成的任何直接、间接、特殊、偶然或结果性责任。',
    ],
  },
  {
    title: '七、版权保护',
    paragraphs: [
      '7.1 音乐平台不易，请尊重版权，支持正版。',
    ],
  },
  {
    title: '八、非商业性质',
    paragraphs: [
      '8.1 本项目仅用于对技术可行性的探索及研究，不接受任何商业（包括但不限于广告等）合作及捐赠。',
    ],
  },
  {
    title: '九、接受协议',
    paragraphs: [
      '9.1 若你使用了本项目，将代表你接受本协议。',
      '* 若协议更新，恕不另行通知，可到开源地址查看。',
    ],
  },
];

const EN_NOTICE = 'You (the user) must accept this agreement before using this software.';

const EN_SECTIONS: PactSection[] = [
  {
    title: '',
    paragraphs: [
      'This project is released under the Apache License 2.0. The following terms supplement that license; in case of conflict, the terms below prevail.',
      'Terminology: "this project" refers to LX Music Mobile; "user" refers to anyone who accepts this agreement; "official music platforms" refers to the built-in sources such as Kuwo, Kugou and Migu; "copyrighted data" refers to data owned by others, including but not limited to images, audio and names.',
    ],
  },
  {
    title: '1. Data Sources',
    paragraphs: [
      '1.1 This project retrieves data from the public servers of the official music platforms (the same data an unauthenticated user gets in the official apps), then filters and merges it for display. This project is not responsible for the accuracy of that data.',
      '1.2 This project cannot obtain audio data by itself. Online audio comes from the link returned by the "source" selected in Settings → Custom Source. When playing a song, this project only passes the song name and artist to the source; if the source returns a link, this project treats it as the audio of that song. Its accuracy cannot be verified, so a mismatch or playback failure may occur.',
      '1.3 Non-official data (such as your lists) comes from your local device or a sync service you connect to. This project is not responsible for its legality or accuracy.',
    ],
  },
  {
    title: '2. Copyrighted Data',
    paragraphs: [
      '2.1 Using this project may generate copyrighted data. This project does not own it. To avoid infringement, please delete such data within 24 hours.',
    ],
  },
  {
    title: '3. Platform Aliases',
    paragraphs: [
      '3.1 The aliases of official music platforms inside this project are merely nicknames with no malicious intent. If a platform objects, the alias can be changed or removed on request.',
    ],
  },
  {
    title: '4. Resource Usage',
    paragraphs: [
      '4.1 Some resources used by this project (including but not limited to fonts and images) come from the internet and can be removed on request if infringement occurs.',
    ],
  },
  {
    title: '5. Disclaimer',
    paragraphs: [
      '5.1 The user bears responsibility for any direct, indirect, special, incidental or consequential damages arising from the use of this project (including but not limited to loss of goodwill, work stoppage, or computer failure).',
    ],
  },
  {
    title: '6. Usage Restrictions',
    paragraphs: [
      '6.1 This project is free and open source on GitHub for learning and technical exchange. It makes no guarantee that its technology complies with local laws and regulations.',
      '6.2 Do not use this project in violation of local laws. The user is solely responsible for any unlawful act committed with this project.',
    ],
  },
  {
    title: '7. Copyright Protection',
    paragraphs: [
      '7.1 Please respect copyright and support official releases.',
    ],
  },
  {
    title: '8. Non-commercial',
    paragraphs: [
      '8.1 This project exists for technical exploration and research only. Commercial cooperation (including advertising) and donations are not accepted.',
    ],
  },
  {
    title: '9. Acceptance',
    paragraphs: [
      '9.1 Using this project means you accept this agreement.',
      '* The agreement may be updated without notice; check the open-source repository for the latest version.',
    ],
  },
];

/** 未同意时的提示语（首启弹窗顶部加粗显示） */
export function getPactNotice(language: string): string {
  return language === 'en-US' ? EN_NOTICE : ZH_NOTICE;
}

/** 按语言取协议正文 */
export function getPactSections(language: string): PactSection[] {
  return language === 'en-US' ? EN_SECTIONS : ZH_SECTIONS;
}
