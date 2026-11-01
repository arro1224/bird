# SmartFollow SF-B2：完整设备与策略配置实施记录

日期：2026-10-29（Asia/Shanghai）。基线：`thirdtime / c77fcd7bc866d02eed7d0ae3da7d67c5e7f9cfc8`，延续 SF-B0、SF-B1 工作区。对应乙 E3。

**SF-B2 已完成配置面板、确认与失效处理：最终关联回归 520 通过 / 1 跳过 / 0 失败，全仓静态分析无问题。** 本批未提交 Git、构建 APK 或连接真实盒子。

## 1. 本批行为

三个 SF-B1 入口共用完整配置：复制范围页、任务页开始识别对话框、AI 分析详情。旧导入页的 `RecognitionOptions` 同样复用此配置，取消直接读取部分设备 Map 并默认发送三个字段的做法。

| 配置项 | 行为 |
| --- | --- |
| 目标设备 | 不自动选盘；复用 RC3 `CopyDevicePolicy` 和设备卡，排除源卡及 import_source；离线、只读、占用、文件系统等阻止原因沿用现有映射 |
| 目标身份与空间 | 使用盒子返回的 media_id、identity_confidence、容量和当前可用容量；身份/容量无法确认、空间为零时不能确认；degraded 沿用 RC3 规则并提示恢复时核验原盘 |
| 源卡 | 读取只读绑定、所属批次、token 和有效期；缺失/过期/不可读时阻止确认；不向相机卡写入 |
| 文件类型 | RAW 优先、JPEG/HEIF 优先、两份都复制；初始值取服务器 CopyPreferences，用户修改后不被刷新覆盖 |
| 同名处理 | 跳过、覆盖、两份保留三种既有策略；初始不选，必须由用户明确选择 |
| 信息保存 | 只有一个“随副本保存识别与审阅信息”开关，默认关闭；由 RC3 review_export_ready 门控，与后续 metadata_update 能力独立 |
| 确认 | 再次读取能力、识别任务、设备、源卡绑定及策略；参数变化则提示核对、要求再次确认；不会创建任务 |
| 失效 | 修改配置、重读失败、换盒子/连接上下文变化、刷新信号、设备/复制偏好变更通知、退后台、绑定过期、撤销确认会清空旧确认；不自动换到其他目标盘 |
| 识别轮次 | SF-B1 入口将预期识别阶段和 jobId 传入配置；若已进入另一轮或阶段变化，要求返回重新选择，不能把旧入口悄悄绑定到新任务 |

SmartFollow 不发起声称涵盖未来全部结果的静态 preview，也不估算尚未识别出的文件大小。界面只展示当前空间；后续每批复制前的空间检查和队列等待仍由后端承担。目标热插拔等物理状态以设备重读/已有通知为准，不声称离线页面能实时感知硬件。

## 2. 实现落点

新增：

- `presentation/entry/smart_follow_configuration_controller.dart`：只读配置快照、读取器、确认控制器及不可变 `SmartFollowConfiguredIntent`；保留本地盒子/批次/识别任务/源卡绑定/策略版本上下文，供 SF-B3 消费。
- `presentation/entry/smart_follow_configuration_form.dart`：设备卡、策略、单一信息开关、重新检测、确认与撤销；处理通知、生命周期、读取器替换和释放订阅。

修改：

- `smart_follow_entry_section.dart`：生产依赖读取接线，将设备连接、重连刷新与设备/复制偏好变更通知接到配置失效处理；挂完整面板并回传确认意图。
- `smart_follow_mode_panel.dart`：选中跟随后承载配置，切回快照移除面板。
- `recognition_widgets.dart`：替换旧部分配置；明确回传 ready 状态；任务识别对话框挂完整配置，独立兼容对话框也禁止未确认时提交跟随选项。
- `task_experience_root.dart`、`batch_setup_page.dart`：接线及导入按钮门控；开启跟随但未确认时不能提交；重新进入批次配置时清空上一次局部选择。

未修改甲侧 SmartFollow domain/data、既有设备策略、后端接口或 RC3 固定快照预检链路。

## 3. 确认输出与创建边界

最终请求使用既有 `SmartFollowStartRequest.toJson()`，没有增加 wire 字段：

```json
{
  "target_media_id": "<用户选择的目标盘>",
  "eligibility_mode": "recognized_only_v1",
  "pair_policy": "raw_only",
  "conflict_strategy": "skip",
  "review_export": {"enabled": false, "prefer_embedded": true}
}
```

源卡 token/有效期、策略 version、盒子连接和识别轮次只存入本地确认上下文，不擅自写入该请求。App 不计算 eligible、不产生真实复制队列。

**配置确认本身只有读请求，不创建分析任务、SmartFollowSession 或 CopyJob。SF-B1 新模式入口的正式提交仍待 SF-B3 接通。** 旧导入页保留既有“保存分析选项→导入→自动识别”链路，本批只将它消费的选项改成完整、显式确认的 DTO；这条旧链路的意图有效期、幂等和结果找回也须由 SF-B3 统一核对，不能据此宣称两条新创建路径已验收。

## 4. 实测与证据

| 检查 | 最终结果 | 证据 |
| --- | --- | --- |
| 本批新增测试 | 26 项，全部纳入最终回归通过 | 配置控制器 13 项、表单/入口集成 12 项、独立识别对话框 1 项；另更新旧 RecognitionOptions 用例 |
| 关联回归 | **520 通过 / 1 跳过 / 0 失败**，退出码 0 | `build/smart-follow/sf-b2/related-tests-final.log`、`related-tests-final-result.json` |
| 全仓静态分析 | **No issues found**，退出码 0 | `analyze-final.log`、`analyze-final-result.json` |
| 改动文件格式 | **16 个 Dart 文件，0 changed**，退出码 0（包含累计 SF-B1 改动） | `format-check.log`、`format-check-result.json` |
| Git 空白检查 | 通过，退出码 0 | `diff-check.log`、`diff-check-result.json` |
| 中文大字号布局 | 360dp、1.5 倍文本缩放，无布局异常，已查看渲染图 | `configuration-360dp-150pct.png`，本地 widget 渲染，非手机/真实盒子截图 |

关联回归范围：SmartFollow、recognition、copy、两组 tasks 目录，加 unified_shell_navigation 与 copy_settings_flow。唯一跳过项为未配置 `BIRDBOX_CONTRACT_BASE` 的外部 Python HTTP 契约测试，不以 Dart mock 代替真实后端验收。

覆盖包括：无目标/不可写/离线/占用/空间未知/身份未知；三种文件策略与三种冲突策略完整 DTO；初始信息保存和后续信息更新能力分离；源卡过期/错误批次；目标/偏好变化二次确认；原盘移除不换盘；不可变意图；请求期间换盒子；识别轮次或阶段改变；退后台、读取器替换、撤销、切回快照；任务对话框配置和旧导入选项的提交门控。

初轮测试发现的测试计数 fixture、回调返回类型和截图容器 Material 断言已修正；最后补充识别轮次锁定后重新执行了上述最终回归与分析。早期日志仅供诊断，最终结论以 final 日志为准。

机器可读证据：`build/smart-follow/sf-b2/evidence.json`，含累计改动 Dart 文件和最终日志/截图哈希。build 被 Git 忽略，移交时需另行携带证据目录。本轮未执行全量 Flutter 测试、Android 原生测试、APK 构建或物理设备验收。

## 5. 下一批接手

**SF-B3：两条创建路径、运行页接入与恢复（E4＋R3 接缝）。** 消费本批已确认的请求和本地上下文，提交前再次核验有效性：未开始识别走 analysis-jobs 原子携带 smart_follow，运行中走已有 RecognitionJob 的 startOnRecognitionJob；完善稳定幂等键、超时先查询、已有会话接管及运行页跳转。不得由配置确认按钮提前创建，不得用普通 CopyJob 模拟持续跟随。
