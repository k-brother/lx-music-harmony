// Index 页面 - 应用入口页面，使用 Navigation 组件
import hilog from '@ohos.hilog';
import { NavIndex } from './NavIndex';

const TAG = 'Index';
const DOMAIN = 0x0001;

@Entry
@Component
struct Index {
  aboutToAppear() {
    hilog.info(DOMAIN, TAG, 'Index page appearing - loading NavIndex with Navigation component');
  }

  build() {
    Column() {
      NavIndex()
    }
  }
}
