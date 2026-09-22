/**
 * 「我的」页的歌曲行列表（我喜欢 / 播放历史共用）
 *
 * 用统一 `ListRow` 渲染，卡片内分隔线；点击播放。
 * 之前两处各自拼「序号 + 标题 + 副标题 + 播放按钮」，样式与行高不一致。
 */
import { DesignTokens } from '../../../theme/DesignTokens';
import { ListRow } from '../../../components/ui/ListRow';
import type { MylistSongRow } from './MylistTypes';

@Component
export struct SongRowList {
  @StorageProp('theme') theme: string = 'light';
  @Prop @Require songs: MylistSongRow[] = [];
  onPlay?: (song: MylistSongRow) => void;

  build() {
    Column() {
      ForEach(this.songs, (song: MylistSongRow, index: number) => {
        ListRow({
          index: index + 1,
          title: song.name,
          subtitle: (song.album ?? '').length > 0 ? `${song.singer} · ${song.album}` : song.singer,
          divider: index < this.songs.length - 1,
          onTap: (): void => {
            if (this.onPlay) {
              this.onPlay(song);
            }
          },
        })
      }, (song: MylistSongRow, index: number) => `${song.id}_${index}`)
    }
    .width('100%')
    .padding({ left: 12, right: 12 })
    .backgroundColor(DesignTokens.card(this.theme))
    .borderRadius(DesignTokens.radiusCard())
    .shadow(DesignTokens.cardShadow(this.theme))
  }
}
