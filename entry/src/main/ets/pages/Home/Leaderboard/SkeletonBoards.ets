/**
 * 榜单首屏骨架占位
 *
 * 从 LeaderboardView 抽出：首屏加载时用三张骨架卡片占位（与歌单页同一套骨架），
 * 组件只负责摆放，数量固定三张。
 */
import { DesignTokens } from '../../../theme/DesignTokens';
import { SkeletonGridItem } from '../../../components/common/SkeletonView';

@Component
export struct SkeletonBoards {
  build() {
    Column() {
      ForEach([0, 1, 2], (index: number) => {
        SkeletonGridItem()
      }, (index: number) => `board_skeleton_${index}`)
    }
    .width('100%')
    .layoutWeight(1)
    .padding({ left: DesignTokens.spaceGutter(), right: DesignTokens.spaceGutter(), top: 12 })
  }
}
