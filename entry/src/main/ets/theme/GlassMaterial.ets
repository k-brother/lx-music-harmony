/**
 * 玻璃材质：优先用系统的沉浸材质（API 26 的 `@ohos.arkui.uiMaterial`，即鸿蒙版"液态玻璃"）
 *
 * 为什么不自己画毛玻璃：
 * - 系统材质会跟着系统的**沉浸光感**配置与设备性能档位自适应 —— 高档机有滤镜与高光，
 *   低档机退化成底色 + 描边 + 阴影，仍然可读；自己写 `backgroundBlurStyle` 只有固定一档模糊；
 * - `interactive`（交互形变）与 `lightEffect`（光感反馈）只能由系统材质提供：
 *   手指在玻璃上按下/划过时材质会跟着动，这就是"灵动"的来源，自己算不出来。
 *
 * 回退：设备/ROM 不支持时（`isImmersiveMaterialSupported()` 为 false）返回 undefined，
 * 组件里保留的自绘玻璃（`DesignTokens.glassFill` + `backgroundBlurStyle` + 描边）照常生效，
 * 不会出现"没有材质又没底色"的透明条。
 *
 * 使用范围（**结合实际，不做无差别玻璃化**）：只给浮在内容之上的"系统 chrome"用 ——
 * 底部底舱、面板；内容卡片与列表保持不透明，否则文字可读性会掉。
 */
import { uiMaterial } from '@kit.ArkUI';

/** 底部底舱（迷你播放条 + Tab 栏）：厚一档，保证图标与文字清楚 */
export function createDockGlassMaterial(): uiMaterial.Material | undefined {
  return createMaterial(uiMaterial.ImmersiveStyle.THICK);
}

function createMaterial(style: uiMaterial.ImmersiveStyle): uiMaterial.Material | undefined {
  if (!uiMaterial.isImmersiveMaterialSupported()) {
    return undefined;
  }
  const options: uiMaterial.ImmersiveOptions = {
    style: style,
    // 材质自带投影，比组件上再挂一层 shadow 更贴合系统观感
    applyShadow: true,
    // 交互形变：按下/滑动时玻璃跟着"压一下"
    interactive: true,
    // 光感反馈：手指附近有跟随的高光（默认白色，浅色玻璃上不刺眼）
    lightEffect: {},
  };
  return new uiMaterial.ImmersiveMaterial(options);
}
