# B13-A：照片详情识别度百分比统一

日期：2026-08-11  
前置批次：B12-A K7 模拟盒子发布前门禁  
后续批次：B13-B 照片详情左右快捷翻页

## 1. 交付结论

- 照片详情主卡片、修改识别结果页和详细鸟种指标统一使用整数百分比展示识别度。
- 有识别结果时展示 `识别度：86%` 或候选项中的 `86%`，不再追加“很有把握”“比较有把握”等定性文字。
- 识别度继续沿用既有四舍五入规则；例如 `0.855` 显示为 `86%`。
- 没有识别度数值时继续显示“等待确认”或“人工确认”，不伪造百分比。
- 低识别度的独立风险提示继续保留，因为它不是识别度数值的一部分。
- 外部接口新增 0 个、修改 0 个；本批次不改变照片模型、分页、保存或同步行为。

## 2. 实现范围

- `lib/bird_companion/core/presentation/user_facing_text.dart`
  - 新增统一的 `recognitionPercent` 格式化方法。
- `lib/bird_companion/features/review/presentation/photo_detail_page.dart`
  - 主识别结果卡片改为百分比显示。
- `lib/bird_companion/features/review/presentation/review_edit_page.dart`
  - 当前结果和候选鸟种统一为 `识别度：xx%`，移除重复的尾部百分比。
- `lib/bird_companion/features/review/presentation/widgets/recognition_panel.dart`
  - 当前识别度和其他候选结果统一显示百分比。

## 3. 自动化验证

- B13-A 专项测试：8/8 通过。
- review 模块回归测试：34/34 通过。
- B13-A 相关 7 个 Dart 文件静态分析：`No issues found`。
- `git diff --check` 通过。

## 4. 范围外事项

- 本批次不增加照片左右翻页箭头；该功能留给 B13-B。
- 本批次不处理详情页标题中异常的总数数据，例如 `2 / 0`。
- 本批次不移除右上角扩展菜单中的上一张、下一张入口。
