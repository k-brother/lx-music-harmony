/**
 * 实况窗服务（LiveView，UIAbility 进程侧）
 *
 * 负责系统实况窗（胶囊 / 通知中心卡片 / 锁屏沉浸页）的生命周期：
 * 切歌创建、歌词句变化更新、停止播放销毁。锁屏扩展跑在独立进程，
 * 歌词负载经 common event 广播（事件名与负载形状见 utils/LiveViewKeys）。
 *
 * 与对方项目的差异（规范化适配）：
 * - 歌词只订阅 LyricHub（playerService.onLyricLineChange），不自己解析 LRC、
 *   不靠播放进度 tick 二分查找 —— 全应用歌词只有 PlayerService 一个中枢；
 * - 界面文案（播放中/已暂停/暂无歌词）由本进程 t() 翻译后随负载下发，
 *   锁屏进程不引资源、不做本地化；
 * - 双开关：应用设置 enableLiveView + 系统实况窗总开关（isLiveViewEnabled），
 *   缺任何一个都不创建；设置页开关变化经 syncEnabled() 即时生效。
 *
 * 限制：本地实况窗只能在应用前台时创建，所有调用都是 best-effort，
 * 失败只记日志，绝不影响播放。
 */
import { hilog } from '@kit.PerformanceAnalysisKit';
import { commonEventManager } from '@kit.BasicServicesKit';
import type { BusinessError } from '@kit.BasicServicesKit';
import { wantAgent } from '@kit.AbilityKit';
import type { common, WantAgent } from '@kit.AbilityKit';
import { liveViewManager } from '@kit.LiveViewKit';
import { playerService } from './PlayerService';
import type { LyricLineState } from './PlayerService';
import type { PlayStatus } from './player/PlaybackTypes';
import type { MusicInfo } from '../types/MusicTypes';
import { settingsService } from './SettingsService';
import { t } from './LocalizationService';
import {
  LIVE_VIEW_ID,
  LIVE_VIEW_EVENT,
  LIVE_VIEW_LOCK_ABILITY,
  LIVE_VIEW_PARAM_KEY,
  LIVE_VIEW_LYRIC_EVENT,
  type LiveViewLyricPayload,
} from '../utils/LiveViewKeys';
import { Throttle } from '../utils/Throttle';

const TAG = 'LiveViewService';
const DOMAIN = 0x0003;

/** 胶囊 / 富文本 / 标题长度上限（实况窗模板限制） */
const CAPSULE_TEXT_MAX: number = 120;
const RICH_TEXT_MAX: number = 120;
const PRIMARY_TITLE_MAX: number = 200;
/** 两次 push 的最小间隔（歌词逐字动画不会触发系统级更新风暴） */
const MIN_PUSH_INTERVAL_MS: number = 500;
/** PICKUP 布局强制要求一张 rawfile 图标（系统 API 限制，见 module 头注释） */
const LIVE_VIEW_ICON: string = 'liveview_icon.png';

class LiveViewService {
  private context: common.UIAbilityContext | null = null;
  private unsubscribers: (() => void)[] = [];
  private started: boolean = false;
  /** startLiveView 成功后为 true，门控 update/stop */
  private active: boolean = false;
  /** 创建中（防重复创建） */
  private starting: boolean = false;
  private wantAgentInstance: WantAgent | null = null;
  private title: string = '';
  private artist: string = '';
  private curLine: string = '';
  private nextLine: string = '';
  private isPlaying: boolean = false;
  /** 更新节流：距上次更新不足 MIN_PUSH_INTERVAL_MS 的直接丢弃（见 utils/Throttle） */
  private readonly updater: Throttle = new Throttle(MIN_PUSH_INTERVAL_MS, (): void => {
    this.pushNow();
  });

  setContext(context: common.UIAbilityContext): void {
    this.context = context;
  }

  /** 订阅播放器事件；总开关开着且正在播放时补一次创建 */
  start(): void {
    if (this.started) {
      return;
    }
    this.started = true;
    this.unsubscribers.push(playerService.onMusicInfoChange((info: MusicInfo): void => {
      this.onTrackChanged(info);
    }));
    this.unsubscribers.push(playerService.onPlayStateChange((isPlay: boolean): void => {
      this.isPlaying = isPlay;
      if (isPlay) {
        this.ensureActive();
      }
      this.pushUpdate();
    }));
    this.unsubscribers.push(playerService.onLyricLineChange((state: LyricLineState): void => {
      const cur: string = state.hasLyric ? state.current : '';
      const next: string = state.hasLyric ? state.next : '';
      if (cur !== this.curLine || next !== this.nextLine) {
        this.curLine = cur;
        this.nextLine = next;
        this.pushUpdate();
      }
    }));
    this.unsubscribers.push(playerService.onStatusChange((status: PlayStatus): void => {
      if (status === 'stopped' || status === 'idle') {
        this.stopLiveView();
      }
    }));
    if (settingsService.get().enableLiveView && playerService.isPlaying()) {
      this.ensureActive();
    }
  }

  stop(): void {
    for (const unsubscribe of this.unsubscribers) {
      unsubscribe();
    }
    this.unsubscribers = [];
    this.started = false;
    this.updater.dispose();
    this.stopLiveView();
  }

  /**
   * 设置页开关变化时调用：开 → 立即补创建（若在播放）；关 → 立即销毁。
   */
  syncEnabled(): void {
    if (!settingsService.get().enableLiveView) {
      this.stopLiveView();
      return;
    }
    if (playerService.isPlaying()) {
      this.ensureActive();
    }
  }

  /** 切歌：更新曲目信息并重置歌词句，未创建则尝试创建 */
  private onTrackChanged(info: MusicInfo): void {
    this.title = info.name.length > 0 ? info.name : t('live_view_fallback_title');
    this.artist = info.singer;
    this.curLine = '';
    this.nextLine = '';
    this.ensureActive();
    this.pushUpdate();
  }

  /** 未创建时尝试创建（受双开关门控）；已创建则只走 pushUpdate */
  private ensureActive(): void {
    if (this.active || this.starting) {
      return;
    }
    if (!settingsService.get().enableLiveView) {
      return;
    }
    this.starting = true;
    void this.doStart();
  }

  private async doStart(): Promise<void> {
    try {
      if (!await liveViewManager.isLiveViewEnabled()) {
        hilog.info(DOMAIN, TAG, 'system live view switch off, skip');
        return;
      }
      const agent: WantAgent | null = await this.getWantAgent();
      const liveView: liveViewManager.LiveView = this.buildLiveView(agent);
      const result: liveViewManager.LiveViewResult = await liveViewManager.startLiveView(liveView);
      if (result.resultCode === 0) {
        this.active = true;
        hilog.info(DOMAIN, TAG, 'live view started');
      } else {
        hilog.warn(DOMAIN, TAG, 'startLiveView resultCode=%{public}d msg=%{public}s',
          result.resultCode, result.message);
      }
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'startLiveView failed: %{public}s', JSON.stringify(err));
    } finally {
      this.starting = false;
    }
  }

  /** 停止并复位；未激活时是纯 no-op */
  private stopLiveView(): void {
    if (!this.active) {
      return;
    }
    this.active = false;
    const liveView: liveViewManager.LiveView = this.buildLiveView(this.wantAgentInstance);
    liveViewManager.stopLiveView(liveView).then((result: liveViewManager.LiveViewResult): void => {
      if (result.resultCode !== 0) {
        hilog.warn(DOMAIN, TAG, 'stopLiveView resultCode=%{public}d', result.resultCode);
      }
    }).catch((err: BusinessError): void => {
      hilog.warn(DOMAIN, TAG, 'stopLiveView failed: %{public}s', JSON.stringify(err));
    });
    this.curLine = '';
    this.nextLine = '';
  }

  /** 构建当前状态的 LiveView 请求体 */
  private buildLiveView(agent: WantAgent | null): liveViewManager.LiveView {
    const lockScreenParams: Record<string, string> = {};
    lockScreenParams[LIVE_VIEW_PARAM_KEY] = JSON.stringify(this.buildPayload());
    const liveView: liveViewManager.LiveView = {
      id: LIVE_VIEW_ID,
      event: LIVE_VIEW_EVENT,
      isMute: true,
      liveViewData: {
        primary: {
          title: this.fitText(this.title, PRIMARY_TITLE_MAX),
          content: this.primaryContent(),
          keepTime: 0,
          layoutData: this.pickupLayoutData(),
          liveViewLockScreenAbilityName: LIVE_VIEW_LOCK_ABILITY,
          liveViewLockScreenAbilityParameters: lockScreenParams,
        },
        capsule: {
          type: liveViewManager.CapsuleType.CAPSULE_TYPE_TEXT,
          status: 1,
          title: this.capsuleText(),
          content: this.fitText(this.artist, CAPSULE_TEXT_MAX),
        },
      },
    };
    if (agent !== null) {
      liveView.liveViewData.primary.clickAction = agent;
    }
    return liveView;
  }

  /** TIMER 场景要求扩展区布局；PICKUP（强调文本）展示当前歌词句 */
  private pickupLayoutData(): liveViewManager.PickupLayout {
    const line: string = this.curLine.trim().length > 0 ? this.curLine : t('live_view_fallback_title');
    const layout: liveViewManager.PickupLayout = {
      layoutType: liveViewManager.LayoutType.LAYOUT_TYPE_PICKUP,
      title: this.fitText(this.title, RICH_TEXT_MAX),
      content: this.fitText(line, RICH_TEXT_MAX),
      descPic: LIVE_VIEW_ICON,
    };
    return layout;
  }

  /** 卡片内容：当前句（空则回退文案）+ 可选下一句 */
  private primaryContent(): liveViewManager.RichText[] {
    const content: liveViewManager.RichText[] = [];
    const current: string = this.curLine.trim().length > 0 ?
      this.fitText(this.curLine, RICH_TEXT_MAX) : t('live_view_no_lyric');
    content.push({ text: current });
    if (this.nextLine.trim().length > 0) {
      content.push({ text: this.fitText(this.nextLine, RICH_TEXT_MAX) });
    }
    return content;
  }

  /** 胶囊：优先当前歌词句，其次歌曲名 */
  private capsuleText(): string {
    if (this.curLine.trim().length === 0) {
      return this.fitText(this.title, CAPSULE_TEXT_MAX);
    }
    return this.fitText(this.curLine, CAPSULE_TEXT_MAX);
  }

  /** 节流更新实况窗，并把负载广播给锁屏进程 */
  private pushUpdate(): void {
    if (!this.active) {
      return;
    }
    this.updater.tryRun();
  }

  /** 真正的下发（由 updater 决定时机） */
  private pushNow(): void {
    const liveView: liveViewManager.LiveView = this.buildLiveView(this.wantAgentInstance);
    liveViewManager.updateLiveView(liveView).then((result: liveViewManager.LiveViewResult): void => {
      if (result.resultCode !== 0) {
        hilog.warn(DOMAIN, TAG, 'updateLiveView resultCode=%{public}d', result.resultCode);
      }
    }).catch((err: BusinessError): void => {
      hilog.warn(DOMAIN, TAG, 'updateLiveView failed: %{public}s', JSON.stringify(err));
    });
    this.publishLyricEvent(JSON.stringify(this.buildPayload()));
  }

  private buildPayload(): LiveViewLyricPayload {
    return {
      title: this.title,
      artist: this.artist,
      curLine: this.curLine,
      nextLine: this.nextLine,
      isPlaying: this.isPlaying,
      playingLabel: t('live_view_playing'),
      pausedLabel: t('live_view_paused'),
      noLyricLabel: t('live_view_no_lyric'),
    };
  }

  /** 锁屏进程无 LocalizationService，文案随负载一起广播 */
  private publishLyricEvent(payloadJson: string): void {
    try {
      const options: commonEventManager.CommonEventPublishData = { data: payloadJson };
      commonEventManager.publish(LIVE_VIEW_LYRIC_EVENT, options, (err: BusinessError): void => {
        if (err) {
          hilog.warn(DOMAIN, TAG, 'publish lyric event failed: %{public}s', JSON.stringify(err));
        }
      });
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'publish lyric event error: %{public}s', JSON.stringify(err));
    }
  }

  /** 延迟构建并缓存点击实况窗回到应用的 wantAgent */
  private async getWantAgent(): Promise<WantAgent | null> {
    if (this.wantAgentInstance !== null) {
      return this.wantAgentInstance;
    }
    if (this.context === null) {
      return null;
    }
    const wantAgentInfo: wantAgent.WantAgentInfo = {
      wants: [
        {
          bundleName: this.context.abilityInfo.bundleName,
          abilityName: 'EntryAbility',
        },
      ],
      actionType: wantAgent.OperationType.START_ABILITIES,
      requestCode: 0,
      actionFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG],
    };
    try {
      this.wantAgentInstance = await wantAgent.getWantAgent(wantAgentInfo);
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'getWantAgent failed: %{public}s', JSON.stringify(err));
    }
    return this.wantAgentInstance;
  }

  private fitText(text: string, max: number): string {
    return text.length > max ? text.substring(0, max) : text;
  }
}

export const liveViewService = new LiveViewService();
