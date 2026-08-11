# B13-C：照片详情视觉与回归门禁

日期：2026-08-11  
前置批次：B13-A 识别度百分比统一、B13-B 左右快捷翻页

## 1. 交付结论

- 照片详情左右箭头通过 360/390/426dp 与 1.0/1.3/1.5 倍字体的 9 组自动化视觉结构门禁。
- 两个箭头在全部组合下均保持 52×52dp 点击区域，中心位于照片预览范围内并贴近左右边缘。
- 以中央识别框为基准的布局检查通过，左右箭头与识别框没有重叠。
- 右上角扩展菜单继续保留上一张、下一张和修改记录入口，菜单翻页回归通过。
- “选择后自动下一张”开启时，保留操作保存当前照片后仍能进入下一张。
- 已加载序列末尾点击下一张仍会调用既有分页加载器。
- 全项目测试、静态分析和 Android `bird` Debug 构建通过。
- 按用户明确要求，本批次不分析、不测试也不修复详情标题中的总数异常问题。

## 2. 门禁实现

- `test/bird_companion/features/review/photo_detail_navigation_test.dart`
  - 增加扩展菜单共存与菜单翻页回归；
  - 增加自动下一张回归；
  - 增加 3 种屏宽 × 3 种字体比例的视觉结构矩阵；
  - 检查箭头点击区域、图片边界和中央识别框避让。
- `lib/bird_companion/features/review/presentation/widgets/subject_overlay_view.dart`
  - 为识别框增加稳定测试键，不改变识别框尺寸、位置或生产交互。

## 3. 验证结果

- B13-C 详情专项门禁：13/13 通过；
- review 模块回归：53/53 通过；
- 全项目 Flutter 测试：364/364 通过；
- 全项目 Dart 静态分析：`No issues found`；
- `git diff --check`：通过；
- Android `bird` Debug APK：构建通过。

APK 产物：

- 路径：`build/app/outputs/flutter-apk/app-bird-debug.apk`
- 大小：212,002,627 字节
- SHA-256：`59742A3EE060BBB72DFD969BAE77AD91545AAAD97CFDA451085E03DDC373ED82`

## 4. 已知非阻塞项

- `mobile_scanner` 仍会产生 Kotlin Gradle Plugin 未来兼容性警告，本次 Debug 构建成功；该警告与 B13 照片详情改动无关。
- 本批次为自动化布局与构建门禁，不替代 B12-B 的真实 Android 设备、真实盒子与物理网络验收。
- 详情标题总数异常由用户明确排除，不列入 B13-C 遗留问题。
