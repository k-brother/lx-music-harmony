/**
 * 搜索栏组件 - 支持搜索历史和热搜
 */

import type { HotSearchItem } from '../../core/search/search';

@Component
export struct HomeSearchBar {
  @StorageProp('theme') theme: string = 'light';
  @Prop searchText: string = '';
  @Prop isExpanded: boolean = false;

  // 搜索历史
  @State searchHistory: string[] = [];
  private maxHistory: number = 10;

  // 热搜数据
  @Prop hotSearchList: HotSearchItem[] = [];

  // 回调
  private onSearch: (keyword: string) => void = () => {};
  private onTextChange: (text: string) => void = () => {};
  private onClose: () => void = () => {};
  private onHotSearchClick: (keyword: string) => void = () => {};

  // 设置回调
  setCallbacks(
    onSearch: (keyword: string) => void,
    onTextChange: (text: string) => void,
    onClose: () => void,
    onHotSearchClick: (keyword: string) => void
  ): void {
    this.onSearch = onSearch;
    this.onTextChange = onTextChange;
    this.onClose = onClose;
    this.onHotSearchClick = onHotSearchClick;
  }

  // 加载搜索历史
  loadHistory(history: string[]): void {
    this.searchHistory = history.slice(0, this.maxHistory);
  }

  // 添加到搜索历史
  addToHistory(keyword: string): void {
    if (!keyword.trim()) return;
    const filtered = this.searchHistory.filter(h => h !== keyword);
    this.searchHistory = [keyword, ...filtered].slice(0, this.maxHistory);
  }

  // 清空搜索历史
  clearHistory(): void {
    this.searchHistory = [];
  }

  // 删除单条历史
  removeHistory(index: number): void {
    if (index >= 0 && index < this.searchHistory.length) {
      this.searchHistory.splice(index, 1);
      this.searchHistory = this.searchHistory;
    }
  }

  aboutToAppear() {
    // 读取搜索历史
  }

  build() {
    Column() {
      // 搜索输入栏
      Row() {
        TextInput({ placeholder: '搜索歌曲、歌手、专辑', text: this.searchText })
          .layoutWeight(1)
          .height(40)
          .backgroundColor(this.theme === 'dark' ? '#2C2C2C' : '#F0F0F0')
          .borderRadius(20)
          .padding({ left: 16, right: 16 })
          .fontSize(14)
          .fontColor(this.theme === 'dark' ? '#FFFFFF' : '#333333')
          .placeholderColor('#999999')
          .caretColor('#E63946')
          .onChange((text: string) => {
            this.onTextChange(text);
          })
          .onSubmit(() => {
            if (this.searchText.trim()) {
              this.addToHistory(this.searchText.trim());
              this.onSearch(this.searchText.trim());
            }
          })

        Text('取消')
          .fontSize(14)
          .fontColor('#E63946')
          .padding({ left: 12 })
          .onClick(() => {
            this.onClose();
          })
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 8, bottom: 8 })
      .backgroundColor(this.theme === 'dark' ? '#1C1C1C' : '#FFFFFF')

      // 搜索内容区域
      if (this.isExpanded) {
        this.SearchContent()
      }
    }
    .width('100%')
    .backgroundColor(this.theme === 'dark' ? '#121212' : '#F5F5F5')
  }

  @Builder
  SearchContent() {
    Column() {
      // 搜索历史（如果有）
      if (this.searchHistory.length > 0 && !this.searchText) {
        Column() {
          Row() {
            Text('搜索历史')
              .fontSize(14)
              .fontColor(this.theme === 'dark' ? '#FFFFFF' : '#333333')
              .fontWeight(FontWeight.Medium)

            Blank()

            Text('清空')
              .fontSize(12)
              .fontColor('#999999')
              .onClick(() => {
                this.clearHistory();
              })
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 12, bottom: 8 })

          // 历史标签
          Flex({ wrap: FlexWrap.Wrap }) {
            ForEach(this.searchHistory, (item: string, index: number) => {
              Text(item)
                .fontSize(12)
                .fontColor(this.theme === 'dark' ? '#CCCCCC' : '#666666')
                .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                .backgroundColor(this.theme === 'dark' ? '#2C2C2C' : '#F0F0F0')
                .borderRadius(16)
                .margin({ right: 8, bottom: 8 })
                .onClick(() => {
                  this.searchText = item;
                  this.onTextChange(item);
                  this.onSearch(item);
                })
            })
          }
          .padding({ left: 16, right: 16, bottom: 8 })
        }
        .width('100%')
      }

      // 热搜标题
      Row() {
        Text('热门搜索')
          .fontSize(14)
          .fontColor(this.theme === 'dark' ? '#FFFFFF' : '#333333')
          .fontWeight(FontWeight.Medium)
      }
      .width('100%')
      .padding({ left: 16, top: 12, bottom: 8 })

      // 热搜列表
      List() {
        ForEach(this.hotSearchList, (item: HotSearchItem) => {
          ListItem() {
            Row() {
              Text((item.index).toString())
                .fontSize(14)
                .fontColor(item.index <= 3 ? '#E63946' : '#999999')
                .fontWeight(item.index <= 3 ? FontWeight.Bold : FontWeight.Normal)
                .width(32)

              Text(item.title)
                .fontSize(14)
                .fontColor(this.theme === 'dark' ? '#CCCCCC' : '#666666')
                .layoutWeight(1)

              Image($r('sys.symbol.play_fill'))
                .width(16)
                .height(16)
                .fillColor('#E63946')
                .margin({ right: 8 })
            }
            .width('100%')
            .padding({ left: 12, right: 12, top: 12, bottom: 12 })
          }
          .onClick(() => {
            this.searchText = item.title;
            this.addToHistory(item.title);
            this.onHotSearchClick(item.title);
          })
        })
      }
      .width('100%')
      .layoutWeight(1)
      .backgroundColor(this.theme === 'dark' ? '#1C1C1C' : '#FFFFFF')
    }
    .width('100%')
    .layoutWeight(1)
  }
}
