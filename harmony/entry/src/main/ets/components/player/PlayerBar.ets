// 迷你播放器栏组件 - 对应 src/components/player/PlayerBar/index.tsx
// 显示在首页底部的迷你播放控制栏

import hilog from '@ohos.hilog';
import { navigationService, RouteName } from '../../service';

// 导入播放器服务
import { playerService } from '../../service/PlayerService';

// 使用与PlayerService一致的MusicInfo接口
import type { MusicInfo } from '../../service/PlayerService';

@Component
export struct PlayerBar {
  @StorageProp('theme') theme: string = 'light';
  @StorageProp('primaryColor') primaryColor: string = '#E63946';
  @State isPlay: boolean = false;
  @State musicName: string = '';
  @State singer: string = '';
  @State pic: string = '';
  @State progress: number = 0;
  @State nowPlayTimeStr: string = '00:00';
  @State maxPlayTimeStr: string = '00:00';

  // 每个实例独立订阅，避免 this 指向问题
  private unsubscribePlayState: (() => void) | null = null;
  private unsubscribeMusicInfo: (() => void) | null = null;
  private unsubscribeProgress: (() => void) | null = null;

  aboutToAppear() {
    hilog.info(0x0001, 'PlayerBar', 'aboutToAppear, registering listeners');

    // 订阅播放状态变化
    this.unsubscribePlayState = playerService.onPlayStateChange((isPlay: boolean) => {
      hilog.info(0x0001, 'PlayerBar', 'isPlay changed to %{public}s', isPlay.toString());
      this.isPlay = isPlay;
    });

    // 订阅音乐信息变化
    this.unsubscribeMusicInfo = playerService.onMusicInfoChange((info: MusicInfo) => {
      hilog.info(0x0001, 'PlayerBar', 'musicInfo updated - name: %{public}s, pic: %{public}s', info.name, info.pic || 'null');
      this.musicName = info.name;
      this.singer = info.singer;
      this.pic = info.pic || info.img || '';
    });

    // 订阅进度变化
    this.unsubscribeProgress = playerService.onProgressInfoChange((prog) => {
      this.progress = prog.progress;
      this.nowPlayTimeStr = prog.nowPlayTimeStr;
      this.maxPlayTimeStr = prog.maxPlayTimeStr;
    });

    // 初始化时获取当前播放状态和音乐信息
    this.isPlay = playerService.isPlaying();

    // 获取当前音乐信息
    const currentMusicInfo = playerService.getCurrentMusicInfo();
    if (currentMusicInfo && currentMusicInfo.name) {
      this.musicName = currentMusicInfo.name;
      this.singer = currentMusicInfo.singer;
      this.pic = currentMusicInfo.pic || currentMusicInfo.img || '';
    }
  }

  aboutToDisappear() {
    hilog.info(0x0001, 'PlayerBar', 'aboutToDisappear, unregistering listeners');

    if (this.unsubscribePlayState) {
      this.unsubscribePlayState();
      this.unsubscribePlayState = null;
    }
    if (this.unsubscribeMusicInfo) {
      this.unsubscribeMusicInfo();
      this.unsubscribeMusicInfo = null;
    }
    if (this.unsubscribeProgress) {
      this.unsubscribeProgress();
      this.unsubscribeProgress = null;
    }
  }

  // 播放/暂停 - 先获取实际状态再执行
  async togglePlay(): Promise<void> {
    // 每次点击前先获取实际播放状态
    const actualIsPlaying = playerService.isPlaying();
    hilog.info(0x0001, 'PlayerBar', 'togglePlay: actual state is %{public}s', actualIsPlaying.toString());

    if (actualIsPlaying) {
      hilog.info(0x0001, 'PlayerBar', 'Calling pause...');
      await playerService.pause();
    } else {
      hilog.info(0x0001, 'PlayerBar', 'Calling play...');
      await playerService.play();
    }
    // 状态会通过 onPlayStateChange 回调自动更新
  }

  // 上一曲
  async playPrev(): Promise<void> {
    await playerService.playPrev();
  }

  // 下一曲
  async playNext(): Promise<void> {
    await playerService.playNext();
  }

  build() {
    Row() {
      // 封面图片
      if (this.pic) {
        Image(this.pic)
          .width(46)
          .height(46)
          .borderRadius(4)
          .objectFit(ImageFit.Cover)
          .onClick(() => {
            try {
              navigationService.navigateTo(RouteName.PLAY_DETAIL);
            } catch (e) {
              console.error('PlayerBar: Navigation failed:', JSON.stringify(e));
            }
          })
      } else {
        // 默认封面图标
        Stack() {
          Column()
            .width(46)
            .height(46)
            .backgroundColor('#E0E0E0')
            .borderRadius(4)

          Text('♪')
            .fontSize(24)
            .fontColor('#999999')
        }
        .width(46)
        .height(46)
        .onClick(() => {
          try {
            navigationService.navigateTo(RouteName.PLAY_DETAIL);
          } catch (e) {
            console.error('PlayerBar: Navigation failed:', JSON.stringify(e));
          }
        })
      }

      // 歌曲信息
      Column() {
        Text(this.musicName || '未播放')
          .fontSize(14)
          .fontColor('#333333')
          .maxLines(1)
        Text(this.singer || '-')
          .fontSize(12)
          .fontColor('#999999')
          .maxLines(1)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .margin({ left: 12 })

      // 控制按钮
      Row() {
        // 上一曲
        Text('⏮')
          .fontSize(20)
          .fontColor(this.theme === 'dark' ? '#FFFFFF' : '#333333')
          .margin({ right: 20 })
          .onClick(() => { this.playPrev(); })

        // 播放/暂停
        Stack() {
          Circle({ width: 44, height: 44 })
            .fill(this.theme === 'dark' ? '#333333' : '#E8E8E8')

          if (this.isPlay) {
             Row() {
               Column().width(4).height(16).backgroundColor('#E63946').borderRadius(2).margin({ right: 6 })
               Column().width(4).height(16).backgroundColor('#E63946').borderRadius(2)
             }.justifyContent(FlexAlign.Center).alignItems(VerticalAlign.Center)
          } else {
             Text('▶').fontSize(16).fontColor('#E63946').margin({ left: 2 })
          }
        }
        .margin({ right: 20 })
        .onClick(() => { this.togglePlay(); })

        // 下一曲
        Text('⏭')
          .fontSize(20)
          .fontColor(this.theme === 'dark' ? '#FFFFFF' : '#333333')
          .onClick(() => { this.playNext(); })
      }
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .height(56)
    .padding({ left: 12, right: 12 })
    .backgroundColor('#FFFFFF')
    .alignItems(VerticalAlign.Center)
    .border({ width: { top: 0.5 }, color: '#E0E0E0' })
  }
}
