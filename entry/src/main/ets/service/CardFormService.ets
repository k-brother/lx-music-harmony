/**
 * 桌面卡片桥接（UIAbility 进程侧，service 层单一入口）
 *
 * 进程模型：服务卡片由 CardFormAbility（FormExtensionAbility）承载，运行在独立进程，
 * 拿不到本进程的 PlayerService。两边经 preferences 共享状态（键见 StorageKeys.CARD_*）：
 * - 本服务是唯一快照写入方：切歌 / 播放态 / 当前歌词句变化时落盘 CARD_SNAPSHOT 并推送；
 * - formIds 列表由卡片进程维护（添加/移除卡片时），本服务只读缓存；
 * - 卡片按钮经 postCardAction(call) → EntryAbility callee 通道回到本服务 handleCardAction。
 *
 * 对方项目的教训在这里的对应做法：
 * - 冷启动时 call 事件可能先于播放器就绪到达 → 动作先入队，就绪后一次冲刷（3s 兜底）；
 * - 推送合并 400ms，歌词逐句变化不会每句都 updateForm。
 */
import { formBindingData, formProvider } from '@kit.FormKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import type { common } from '@kit.AbilityKit';
import { playerService } from './PlayerService';
import type { LyricLineState } from './PlayerService';
import type { PlayStatus } from './player/PlaybackTypes';
import type { MusicInfo } from '../types/MusicTypes';
import storageService, { StorageKeys } from './StorageService';
import { CardFormCover, type CardCoverFd } from '../utils/CardFormCover';
import { CardPushPayload } from '../utils/CardFormPayload';
import type { RegisteredCard } from '../utils/CardFormKeys';
import { decodeRegisteredCards } from '../utils/CardFormCodec';
import { Throttle } from '../utils/Throttle';
import { CARD_REFRESH_EVENT } from '../utils/CardFormKeys';
import { commonEventManager } from '@kit.BasicServicesKit';
import type { BusinessError } from '@kit.BasicServicesKit';

const TAG = 'CardFormService';
const DOMAIN = 0x0003;

export type CardActionType = 'playPause' | 'next' | 'previous';

interface CardSnapshot {
  title: string;
  singer: string;
  cover: string;
  playing: boolean;
  lyric: string;
}

/** 空快照工厂（ArkTS 禁止对象展开，不能写 { ...EMPTY_SNAPSHOT }） */
function emptySnapshot(): CardSnapshot {
  return { title: '', singer: '', cover: '', playing: false, lyric: '' };
}
const PUSH_THROTTLE_MS: number = 400;
const READY_FALLBACK_MS: number = 3000;
const FORM_IDS_CACHE_MS: number = 5000;

class CardFormService {
  private context: common.UIAbilityContext | null = null;
  private unsubscribers: (() => void)[] = [];
  private snapshot: CardSnapshot = emptySnapshot();
  /** 卡片推送节流：合并窗口内的快照变化，窗口结束推一次（见 utils/Throttle） */
  private readonly pusher: Throttle = new Throttle(PUSH_THROTTLE_MS, (): void => {
    this.pushToForms().catch((err: Error): void => {
      hilog.warn(DOMAIN, TAG, '卡片推送失败: %{public}s', err.message ?? '');
    });
  });
  private registeredCards: RegisteredCard[] = [];
  private formIdsLoadedAt: number = 0;
  private started: boolean = false;
  private playerReady: boolean = false;
  private pendingActions: CardActionType[] = [];
  private readyTimer: number = -1;
  /** 卡片进程发来的刷新请求订阅（stop() 时退订） */
  private refreshSubscriber: commonEventManager.CommonEventSubscriber | null = null;

  setContext(context: common.UIAbilityContext): void {
    this.context = context;
  }

  start(): void {
    if (this.started) {
      return;
    }
    this.started = true;
    this.unsubscribers.push(playerService.onMusicInfoChange((info: MusicInfo): void => {
      this.onTrackChanged(info);
    }));
    this.unsubscribers.push(playerService.onPlayStateChange((isPlay: boolean): void => {
      this.markPlayerReady();
      if (this.snapshot.playing !== isPlay) {
        this.snapshot.playing = isPlay;
        this.onSnapshotDirty();
      }
    }));
    this.unsubscribers.push(playerService.onLyricLineChange((state: LyricLineState): void => {
      const line: string = state.hasLyric ? state.current : '';
      if (this.snapshot.lyric !== line) {
        this.snapshot.lyric = line;
        this.onSnapshotDirty();
      }
    }));
    this.unsubscribers.push(playerService.onStatusChange((status: PlayStatus): void => {
      if (status === 'stopped' || status === 'idle') {
        this.snapshot = emptySnapshot();
        this.onSnapshotDirty();
      }
    }));
    this.watchRefreshRequests();
  }

  /**
   * 卡片进程（FormExtensionAbility）在添加/系统刷新时会发一次刷新请求：
   * 扩展进程按官方要求不做网络 IO，封面与最新一句由这里整帧补推。
   * 这是 provider 主动推模型里唯一的"扩展 → 主进程"信号，写法与锁屏实况窗同一套。
   */
  private watchRefreshRequests(): void {
    const info: commonEventManager.CommonEventSubscribeInfo = { events: [CARD_REFRESH_EVENT] };
    commonEventManager.createSubscriber(info).then((sub: commonEventManager.CommonEventSubscriber): void => {
      if (!this.started) {
        // 订阅过程中服务已停：立刻退订，避免悬挂订阅
        commonEventManager.unsubscribe(sub);
        return;
      }
      this.refreshSubscriber = sub;
      commonEventManager.subscribe(sub,
        (err: BusinessError, _data: commonEventManager.CommonEventData): void => {
          if (err) {
            hilog.warn(DOMAIN, TAG, 'refresh event error: %{public}s', JSON.stringify(err));
            return;
          }
          // 请求即推：绕过节流，保证卡片立刻拿到带图的一帧
          this.pushToForms().catch((pushErr: Error): void => {
            hilog.warn(DOMAIN, TAG, '刷新请求推送失败: %{public}s', pushErr.message ?? '');
          });
        });
      this.unsubscribers.push((): void => {
        const current: commonEventManager.CommonEventSubscriber | null = this.refreshSubscriber;
        this.refreshSubscriber = null;
        if (current !== null) {
          commonEventManager.unsubscribe(current);
        }
      });
    }).catch((err: BusinessError): void => {
      hilog.warn(DOMAIN, TAG, 'createSubscriber for refresh requests failed: %{public}s',
        JSON.stringify(err));
    });
  }

  stop(): void {
    if (!this.started) {
      return;
    }
    this.started = false;
    for (const unsub of this.unsubscribers) {
      unsub();
    }
    this.unsubscribers = [];
    this.pusher.dispose();
    this.clearReadyTimer();
    this.playerReady = false;
    this.pendingActions = [];
  }

  /** 来自卡片 postCardAction(call) 的用户动作（playPause / next / previous） */
  handleCardAction(action: string): void {
    const typed: CardActionType | null = CardFormService.normalizeAction(action);
    if (typed === null) {
      hilog.warn(DOMAIN, TAG, '未知卡片动作: %{public}s', action);
      return;
    }
    if (!this.playerReady) {
      this.pendingActions.push(typed);
      this.armReadyFallback();
      return;
    }
    this.dispatch(typed);
  }

  private static normalizeAction(action: string): CardActionType | null {
    if (action === 'playPause' || action === 'next' || action === 'previous') {
      return action;
    }
    return null;
  }

  private markPlayerReady(): void {
    if (this.playerReady) {
      return;
    }
    this.playerReady = true;
    this.clearReadyTimer();
    const queue: CardActionType[] = this.pendingActions;
    this.pendingActions = [];
    for (const action of queue) {
      this.dispatch(action);
    }
  }

  private armReadyFallback(): void {
    if (this.readyTimer !== -1) {
      return;
    }
    this.readyTimer = setTimeout((): void => {
      this.readyTimer = -1;
      this.markPlayerReady();
    }, READY_FALLBACK_MS);
  }

  private clearReadyTimer(): void {
    if (this.readyTimer !== -1) {
      clearTimeout(this.readyTimer);
      this.readyTimer = -1;
    }
  }

  private dispatch(action: CardActionType): void {
    if (action === 'playPause') {
      const target = playerService.isPlaying() ? playerService.pause() : playerService.play();
      target.catch((err: Error): void => {
        hilog.warn(DOMAIN, TAG, 'playPause 失败: %{public}s', err.message ?? '');
      });
    } else if (action === 'next') {
      playerService.playNext().catch((err: Error): void => {
        hilog.warn(DOMAIN, TAG, 'next 失败: %{public}s', err.message ?? '');
      });
    } else {
      playerService.playPrev().catch((err: Error): void => {
        hilog.warn(DOMAIN, TAG, 'previous 失败: %{public}s', err.message ?? '');
      });
    }
    this.onSnapshotDirty();
  }

  private onTrackChanged(info: MusicInfo): void {
    this.markPlayerReady();
    const title: string = (info.name ?? '').trim();
    const cover: string = (info.pic ?? info.img ?? '').trim();
    if (this.snapshot.title === title &&
        this.snapshot.singer === info.singer &&
        this.snapshot.cover === cover) {
      return;
    }
    this.snapshot.title = title;
    this.snapshot.singer = info.singer;
    this.snapshot.cover = cover;
    this.snapshot.lyric = '';
    this.onSnapshotDirty();
  }

  private onSnapshotDirty(): void {
    storageService.setString(StorageKeys.CARD_SNAPSHOT, JSON.stringify(this.snapshot))
      .catch((err: Error): void => {
        hilog.warn(DOMAIN, TAG, '快照落盘失败: %{public}s', err.message ?? '');
      });
    this.pusher.schedule();
  }

  private async readRegisteredCards(): Promise<RegisteredCard[]> {
    const now: number = Date.now();
    if (now - this.formIdsLoadedAt < FORM_IDS_CACHE_MS) {
      return this.registeredCards;
    }
    this.formIdsLoadedAt = now;
    try {
      const raw: string = await storageService.getString(StorageKeys.CARD_FORM_IDS);
      // 契约解析与卡片进程共用一份实现（utils/CardFormCodec）
      this.registeredCards = decodeRegisteredCards(raw);
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'formIds 读取失败: %{public}s',
        err instanceof Error ? err.message : JSON.stringify(err));
    }
    return this.registeredCards;
  }

  private async pushToForms(): Promise<void> {
    const cards: RegisteredCard[] = await this.readRegisteredCards();
    if (cards.length === 0 || this.context === null) {
      return;
    }
    let cover: CardCoverFd | null = null;
    if (this.snapshot.cover.length > 0 && this.context !== null) {
      cover = await CardFormCover.prepare(this.context.tempDir, this.snapshot.cover);
    }
    for (const card of cards) {
      const payload: CardPushPayload = new CardPushPayload();
      payload.title = this.snapshot.title;
      payload.singer = this.snapshot.singer;
      payload.playing = this.snapshot.playing;
      payload.lyric = this.snapshot.lyric;
      payload.formId = card.id;
      payload.dimension = card.dimension;
      if (cover !== null && cover.fd >= 0) {
        payload.imgName = cover.name;
        payload.formImages[cover.name] = cover.fd;
      }
      try {
        const data: formBindingData.FormBindingData = formBindingData.createFormBindingData(payload);
        await formProvider.updateForm(card.id, data);
      } catch (err) {
        hilog.warn(DOMAIN, TAG, 'updateForm %{public}s 失败: %{public}s', card.id,
          err instanceof Error ? err.message : JSON.stringify(err));
      }
    }
  }
}

export const cardFormService: CardFormService = new CardFormService();
