# vivo X20 真机视觉基线

- 设备：vivo X20
- 系统：Android 8.1.0
- 物理分辨率：1080 × 2160
- 屏幕密度：480 dpi
- Flutter 逻辑尺寸：约 360 × 720 dp
- 字体缩放：1.0
- 应用包名：`deckers.thibault.aves.bird`
- 构建入口：`lib/main_bird.dart`
- 构建变体：`birdDebug`
- 设计目标：430 × 932；真机验收同时检查 360 dp 窄屏适配和安全区域。

## 截图说明

- `batch0_current.png`：整改前相册首页真机基线。
- `batch1_selection.png`：第一版多选态，保留用于记录底部导航未隐藏的问题。
- `batch1_selection_after.png`：整改后的多选态，底部导航已隐藏，操作面板已压缩适配窄屏。
- `batch1_feedback_visible*.png`、`batch1_feedback_expired*.png`：反馈生命周期调试过程截图。
- `bird_window.xml`：批次 1 调试时的 Android 无障碍控件层级，用于确认真实点击区域。
- `batch2_scenes.png`：场景页真机空状态；当前模拟批次未返回场景数据，因此该 fixture 不能继续进入连拍组。
- `batch2_detail.png`、`batch2_detail_next.png`：照片详情页内从第 1 张切换到第 2 张的过程证据。
- `batch2_tab_restore.png`、`batch2_tab_reset.png`：切换 Tab 保留深层栈、再次点击当前 Tab 回根页的证据。
- `batch2_album_root_final.png`：统一审片面包屑初版真机状态。
- `batch2_album_final3.png`：最终包中批次总数透传修复，标题由错误的 `2 / 60` 修正为 `2 / 10000`。
- `batch2_breadcrumb_final.png`：最终包的统一审片路径，当前位置“批次”保持深绿，后续层级为暖灰。

后续页面按照实施批次补充“进入页面、关键状态、异常/空状态、操作反馈消失后”四类截图；设计稿尚未覆盖或项目尚未进入的状态会在对应批次建立基线，不以占位截图冒充完成验收。
