/**
 * 菜单行图标
 *
 * 商业级 App 的动作菜单每行都是「左图标 + 右文案」，只有文字会显得廉价、也不好扫读。
 * 菜单项的文案在各调用点已经本地化过（中/英），所以这里按关键字决定图标：
 * 先匹配到谁就用谁，都不匹配用一条中性横线占位，保证行高与缩进一致。
 *
 * 图标名必须是 SDK 符号表里真实存在的（scripts/check_symbols.py 会核对）。
 */

/** 关键字 -> 图标（顺序即优先级：更具体的词写在前面） */
interface IconRule {
  keywords: string[];
  icon: Resource;
}

const ICON_RULES: IconRule[] = [
  // 「取消」要先匹配：否则落到「删除」规则上会显示垃圾桶
  {
    keywords: ['取消', 'cancel', 'dismiss'],
    icon: $r('sys.symbol.xmark'),
  },
  {
    keywords: ['取消收藏', '不喜欢', '不再喜欢', '取消喜欢', 'unlike', 'dislike', 'remove from favorites'],
    icon: $r('sys.symbol.heart_slash'),
  },
  {
    keywords: ['收藏', '喜欢', 'favorite', 'save to', 'like'],
    icon: $r('sys.symbol.heart'),
  },
  {
    keywords: ['下一首', '稍后播放', '插队', 'play next', 'play later'],
    icon: $r('sys.symbol.arrow_down_circle'),
  },
  {
    keywords: ['播放', '试听', 'play', 'preview'],
    icon: $r('sys.symbol.play_fill'),
  },
  {
    keywords: ['分享', 'share'],
    icon: $r('sys.symbol.arrow_up_right'),
  },
  {
    keywords: ['下载', 'download'],
    icon: $r('sys.symbol.arrow_down_to_line'),
  },
  {
    keywords: ['删除', '移除', '清空', '清除', 'delete', 'remove', 'clear'],
    icon: $r('sys.symbol.trash'),
  },
  {
    keywords: ['排序', '去重', '重复', 'sort', 'duplicate'],
    icon: $r('sys.symbol.sort'),
  },
  {
    keywords: ['多选', '全选', '选择', 'select', 'checkbox'],
    icon: $r('sys.symbol.checkmark_circle'),
  },
  {
    keywords: ['重命名', '编辑', '修改', '改名', 'rename', 'edit'],
    icon: $r('sys.symbol.pencil_line'),
  },
  {
    keywords: ['移动', '移动到', 'move'],
    icon: $r('sys.symbol.folder'),
  },
  {
    keywords: ['来源', '详情', '信息', 'source', 'detail', 'info'],
    icon: $r('sys.symbol.info_circle'),
  },
  {
    keywords: ['复制', 'copy'],
    icon: $r('sys.symbol.doc_text'),
  },
  {
    keywords: ['搜索', 'search', 'find'],
    icon: $r('sys.symbol.magnifyingglass'),
  },
  {
    keywords: ['音质', '音效', '音源', '倍速', '速度', 'quality', 'speed', 'source'],
    icon: $r('sys.symbol.wand_and_stars'),
  },
  {
    keywords: ['循环', '播放模式', 'loop', 'repeat', 'mode'],
    icon: $r('sys.symbol.repeat'),
  },
  {
    keywords: ['随机', 'shuffle', 'random'],
    icon: $r('sys.symbol.shuffle'),
  },
  {
    keywords: ['定时', '睡眠', 'timer', 'sleep'],
    icon: $r('sys.symbol.timer'),
  },
  {
    keywords: ['历史', 'history'],
    icon: $r('sys.symbol.clock'),
  },
  {
    keywords: ['刷新', '重新', '重置', 'refresh', 'rescan', 'reset'],
    icon: $r('sys.symbol.arrow_clockwise'),
  },
  {
    keywords: ['添加', '新建', '导入', 'add', 'create', 'new', 'import'],
    icon: $r('sys.symbol.plus'),
  },
  {
    keywords: ['导出', '备份', 'export', 'backup'],
    icon: $r('sys.symbol.arrow_up_to_line'),
  },
  {
    keywords: ['恢复', 'restore', 'recover'],
    icon: $r('sys.symbol.arrow_counterclockwise'),
  },
  {
    keywords: ['歌词', 'lyric'],
    icon: $r('sys.symbol.music_note_list'),
  },
  {
    keywords: ['歌手', '艺术家', 'artist', 'singer'],
    icon: $r('sys.symbol.person'),
  },
  {
    keywords: ['专辑', 'album'],
    icon: $r('sys.symbol.rectangle_3_group'),
  },
  {
    keywords: ['查看', '预览', 'view'],
    icon: $r('sys.symbol.eye'),
  },
  {
    keywords: ['列表', '队列', 'list', 'queue'],
    icon: $r('sys.symbol.list_bullet'),
  },
  {
    keywords: ['确认', '确定', 'ok', 'confirm', 'got it', '知道了'],
    icon: $r('sys.symbol.checkmark'),
  },
];

export function menuIconFor(label: string): Resource {
  const text: string = label ?? '';
  for (let i = 0; i < ICON_RULES.length; i++) {
    const rule = ICON_RULES[i];
    for (let k = 0; k < rule.keywords.length; k++) {
      if (text.indexOf(rule.keywords[k]) >= 0) {
        return rule.icon;
      }
    }
  }
  return $r('sys.symbol.line_3_horizontal');
}
