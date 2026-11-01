# SmartFollow SF-B1：四态入口与双模式实施记录

日期：2026-10-29（Asia/Shanghai）。基线：`thirdtime / c77fcd7bc866d02eed7d0ae3da7d67c5e7f9cfc8`，延续 SF-B0 的工作区。对应 E1＋E2。

**SF-B1 已完成：统一入口判断、双模式呈现及任务/复制页接线已落地；关联回归 494 通过 / 1 跳过 / 0 失败，全仓静态分析无问题。** 尚未提交 Git、构建 APK 或连接真实盒子。

## 1. 用户可见行为

| 识别状态 | 本批行为 |
| --- | --- |
| 未开始 | 提供“识别并复制已识别照片”和普通识别/快照选择；必须主动选跟随，不静默转换 |
| 进行中 | 显示推荐“边识别边复制”，同时保留“仅复制当前已识别结果”；明确标注“识别中·仅复制当前结果”及后续结果不加入普通任务 |
| 已完成 | 提供普通“复制已识别照片”，不新开跟随；若该轮已有会话仍可查看（包括识别结束但复制排空中的会话） |
| 失败/中断 | 提供“复制当前已完成结果”和原识别任务入口，不自动重启识别或扩大范围 |
| 排队/暂停 | 保留本轮任务关联并说明等待/恢复，不猜测后端允许开启跟随 |
| 能力缺失/false/404 | 无可执行跟随入口，普通识别和静态复制继续按原规则工作 |
| 归属/轮次不明确 | 提示无法确认并允许重读，不把不完整列表推断为“未开始” |

已有会话进入原 sessionId，不提供第二个创建入口。模式选择只有 UI 状态变化和只读请求，不创建 RecognitionJob、SmartFollowSession 或普通 CopyJob。

本批是入口阶段：**跟随配置尚不完整，因此跟随开始按钮禁用**。SF-B2 补完整设备/策略确认，SF-B3 接两条创建路径及结果找回；不把这些后续批次提前记为完成。普通快照继续使用既有 RC3 配置、预检和提交链路。

## 2. 实现落点

新增：

- `presentation/entry/smart_follow_entry_decision.dart`：四态决策及只读读取器，按批次匹配 analysis job，读完现有 jobs cursor 分页后再判定是否未开始；多活动任务、缺批次归属、缺可靠先后关系时保守处理；校验设备上下文与会话归属。
- `presentation/entry/smart_follow_mode_panel.dart`：独立模式选择，跟随不进入 CopyScope 枚举；推荐与实际选中分开，初始保留快照意图。
- `presentation/entry/smart_follow_entry_section.dart`：生产依赖接线、已有会话入口、手动刷新、会话变化重读及请求轮次隔离。连续刷新只重置模式，不自动导航到快照。

修改：

- `app/bird_route_args.dart`：CopyConfirmationArgs 新增默认关闭的 `enableSmartFollow`，只由任务页批次复制入口显式开启。
- `copy/presentation/copy_confirmation_page.dart`：仅在已识别 scope、入口允许且没有选中/筛选参数时挂模式选择；选跟随后暂停原 CopyConfigCubit 页面活动并隐藏普通预检按钮，返回快照后恢复既有流程。
- `recognition/recognition_widgets.dart`：任务识别对话框消费统一决策，已有会话/任务返回原 ID；弹窗打开期间换设备后丢弃旧选择。保留旧选项兼容接口，并将其能力判断收紧为 incremental＋copy 两项同时可用。
- `tasks/presentation/task_experience_root.dart`：接入任务开始识别和 AI 分析详情；原 SmartFollowTaskTile 保留；详情中可进入普通 recognized_assets 复制页，或查看已有跟随会话。

没有修改甲侧的 domain/data、SmartFollow API、后端路径或算法；没有新增 TaskType、OLED、相册或设备页独立入口。

## 3. 保持的边界

- `recognized_assets` 仍由原 CopyConfigCubit → preview → 完整计划核对 → 再预检 → createJob 执行，后续识别结果不会自动加入。
- selected_assets、filtered_assets、batch_all_assets、media_full_backup 不挂整轮跟随入口；相册原参数默认不启用 SmartFollow。
- 页面不累计 eligible、不维护真实复制队列、不创建微批、不修改子 CopyJob 清单。
- 全部创建参数、稳定幂等键、创建超时查询、运行页前台/退避和全局旧设备响应隔离仍按 SF-B2/SF-B3 的原边界实施；本批的入口读取隔离不等于仓库全局恢复已经结案。
- 后端字段问询仍是对方交付输入，没有由 App 自行新增协议字段或更改五动作。

## 4. 实测结果

| 检查 | 结果 | 证据 |
| --- | --- | --- |
| 新增入口测试 | 24 项，均包含在最终关联回归中通过 | `entry/smart_follow_entry_decision_test.dart` 11 项；`entry/smart_follow_modes_test.dart` 13 项 |
| 最终关联回归 | **494 通过 / 1 跳过 / 0 失败**，退出码 0 | `build/smart-follow/sf-b1/related-tests-final.log`、`related-tests-final-result.json` |
| 全仓静态分析 | **No issues found**，退出码 0 | `analyze-final.log`、`analyze-final-result.json` |
| 改动文件格式检查 | **9 个 Dart 文件，0 changed**，退出码 0 | `format-check.log`、`format-check-result.json` |
| Git 空白检查 | 通过，退出码 0 | `diff-check.log`、`diff-check-result.json` |
| 中文大字号布局 | 已检查 360dp、1.5 倍文本缩放，无布局异常；为本地 widget 渲染，非手机截图 | `modes-running.png` |

最终关联回归范围：SmartFollow、recognition、copy、两组 tasks 测试目录，加 unified_shell_navigation 和 copy_settings_flow。唯一跳过项仍是缺外部 Python HTTP 服务的 `python_backend_contract_test.dart`，不以 Dart mock 代替。

关键新增覆盖：四态、能力 false/缺失/404、已有会话及识别先结束、完整分页、分页不前进、错误批次、归属不明、多轮次、旧设备迟到响应、弹窗期间换设备、连续刷新不导航、未配置跟随零创建、切回快照保留 scope，以及四类静态 scope 不扩大范围。

初轮新增测试暴露的 fixture 标识重复、控件布局/点击定位及截图异步等待已处理；初轮分析的两处风格提示已消除。最终结果以上述 final 日志为准，早期日志仅保留诊断过程。

本轮未执行全量 Flutter 测试、Android 原生单测、APK 构建、真实后端或物理盘验收；不将本批结果写成完整 SmartFollow 交付或正式发布通过。

机器可读证据：`build/smart-follow/sf-b1/evidence.json`；包含本轮 9 个改动/新增 Dart 文件哈希、检查退出码及 final 日志/预览哈希。build 目录被忽略，移交证据时需另行携带该目录。

## 5. 下一批接手点

下一批为 **SF-B2（E3）：完整创建配置**：以本批 entry decision/panel/section 为入口，复用已有 SmartFollowStartRequest、设备仓库及 CopyDevicePolicy，补目标身份/可写性/空间、RAW/JPEG/HEIF、明确同名策略和单一信息保存开关。配置尚未确认前继续禁止创建。

不在 SF-B2 绕过仓库拼接新接口，不通过普通 CopyJob 模拟 SmartFollow；两条实际创建、稳定键及超时恢复留给 SF-B3。
