# SmartFollow SF-B5：信息变化提示与统一预览确认（M1＋M2）

日期：2026-10-29（Asia/Shanghai）。分支 `thirdtime`，HEAD `c77fcd7bc866d02eed7d0ae3da7d67c5e7f9cfc8`；延续 SF-B0～SF-B4 的未提交工作区。

**SF-B5 App 侧已完成：运行页和完成页共用能力门控的信息更新入口，统一预览、部分更新确认和最终提交已接入正式路由。** 验证范围为本地自动化、生产路由测试和 HTTP mock；后端正式字段回执及真实目标盘验收仍待联调。

## 1. 信息变化提示（M1）

- 使用既有 `SmartFollowCapabilities.canUpdateMetadata`，同时要求增量识别、跟随复制和 metadata 能力有效。能力 false/缺失时不显示可执行更新入口，也不请求 availability、preview 或 create。
- 单独读取本轮 RecognitionJob，并验证 ID、类型和已有会话关联。不会用复制会话是否终态代替识别是否终态；提前结束跟随后识别仍可继续。
- 同时读取真实 metadata availability；不能仅凭会话摘要的旧 `metadata_update_available` 显示可执行更新。
- 识别尚未结束：显示仍可能产生新信息，提供次级“保存当前已有信息”。识别达到明确终态且有可更新信息时，改为主操作“更新识别信息”。
- 每 4 秒在前台且当前路由可见时补读；会话事件、连接恢复和全局刷新信号唤醒读取。后台/打开其他路由时不发起周期读取，返回前台补拉。定时器只读取事实，不生成写入任务或本地进度。
- session / availability 已提供 active update ID 时，只允许查看原任务；两个来源的 ID 矛盾时要求核对，不任意选一个创建新任务。

运行页和完成页都通过 `SmartFollowMetadataSection` 接入；完成页保留初次复制的信息保存结果，与后续统一更新操作分别展示。

## 2. 统一预览与明确确认（M2）

正式本地路由为 `/smart-follow-metadata-preview`，参数只带原会话及设备身份上下文。两处入口均先进入预览页，最终确认按钮才调用创建。

预览展示：目标盘名称、涉及复制批次、可更新照片/文件、信息不变/受阻/冲突项、预计写入字节、写入方式、有效期和受阻原因。照片使用“张”、文件使用“个”，尚未明确细分单位的分类使用“项”。目标盘显示名复用 RC3 的可读名称校验，不用 Linux 路径或内部介质 ID 代替名称。

以下情况可以呈现已取得的预览事实，但不能确认写入：

- 目标身份缺失、与原任务目标不一致，或没有可供用户核对的目标盘名称；
- 关键统计或确认要求未完整提供；
- 没有可更新照片/文件或涉及批次；
- 有效期缺失、已过期、预览尚未就绪/失败，或写入方式无法确认；
- 能力/availability 已失效、识别身份无法确认、已有父任务、设备上下文变化或存在未决提交。

预览 DTO 新增统计存在性标记，数字只接受有效的非负整数；页面使用强类型 `count()`，不把缺字段默认 0 当作真实零。沿用原 DTO 已有字段和别名，不在页面通过 raw 猜新字段。未确认的写入方式不会默认为 RC3 安全写入。

受阻/冲突数大于零或后端要求部分确认时，显示独立勾选项。用户明确同意“仅更新安全可更新的副本，跳过受阻和冲突项目”后，才能点击“确认部分更新”；仅勾选不会提交。普通范围由“确认更新识别信息”按钮明确授权。

最终点击后重新核对能力、会话、识别阶段、availability 和原预览详情。预览 token、目标、统计、方式、有效期、确认要求或原因变化时，停止提交并要求重新预览确认；不把新范围悄悄套入旧确认。识别阶段由进行中变为终态也要求重新获取。过期、后台切换和连接信号会撤销旧预览确认，取消/返回不创建任务。

## 3. 请求、防重与未知结果

- 复用已有 SmartFollowRepository / Gateway / API，无新增服务端路径、状态、动作、请求字段或能力开关。
- 当前预览没有用户可调的额外策略，沿用已有空预览请求；创建沿用原 `preview_token`、`target_media_id`、必要时的 `confirm_partial` 和 `md-create-{session}-{token}` 稳定幂等键。
- 控制器禁用重复操作；仓库按设备/会话合并并发创建，不允许用不同预览覆盖未决意图，也不允许 extra 覆盖已确认 token、目标和部分确认值。
- 发出创建前，生产依赖把已确认请求写入现有 LocalCache（Hive），按设备与会话隔离。超时、5xx、未知冲突或连接变化不解释为明确失败；重进页面/重建仓库仍先查询原会话和 availability，不生成新 token 换键重建。
- 找到原 active update ID 后转为查看原任务并解除未决标记。若两处都没有关联，仍保留“结果待确认”，不把暂时未查到当成未创建的证明。
- 明确拒绝的普通 4xx，以及 4xx 中已知的 `COPY_PREVIEW_EXPIRED`、`SMART_FOLLOW_METADATA_NOT_AVAILABLE`、`SMART_FOLLOW_METADATA_PARTIAL_CONFIRMATION_REQUIRED` 允许重新预览；不会自动重发写入。未知 409、408、429 仍保守保留未决意图。
- 所有新读请求和返回结果均检查设备代次；正式页面另校验设备 ID、地址与连接状态。旧盒子的晚到结果不能带到新盒子提交。

LocalCache 中保存的是已确认的提交意图，不是 App 复制队列，也不是后台自动重试任务。正式后端仍负责 token 校验、实际幂等、同盘串行写入和安全提交；没有新的按请求键查询接口时，App 无法自行证明未知请求未执行。

## 4. 原父任务查看与 SF-B6 边界

创建成功后只显示“任务已提交”，不显示“信息已全部保存”。新任务和已有 active ID 都可打开只读回执，使用既有 metadataUpdate API 读取对应父任务当前状态；未知状态显示待确认，设备切换隐藏旧状态，不会再次创建。

该回执是本批到 M3 的交接点。**独立父任务运行页、完整父子统计/报告、失败原因展开、结束后重新计算 availability 和更晚 revision 再提示，仍属于 SF-B6。** 本批不把收到 queued 父任务当作写盘成功，也不自动回滚、重复制或更新所有副本。

## 5. 主要文件

新增生产文件：

- `presentation/finish/smart_follow_metadata_controller.dart`：权威读取、门控、预览复核、部分确认和创建状态。
- `presentation/finish/smart_follow_metadata_section.dart`：运行/完成页共用 M1 组件，独立识别状态和前台刷新。
- `presentation/finish/smart_follow_metadata_preview_page.dart`：M2 页面及原父任务只读回执。

最小扩展：app_router、bird_route_args、app_dependencies、运行页/完成页的 metadata 插槽、预览 DTO 的字段存在性、仓库的设备保护/并发与未决记录。内存 FakeSmartFollowBackend 补齐显式预览统计并保存冻结预览，供本地演示/测试复用；不是修改真实后端。

新增测试文件 5 个：metadata fixture、控制器、页面、正式导航和 HTTP。

## 6. 验证与证据

证据目录：`build/smart-follow/sf-b5/`（构建目录，不提交）。

| 检查 | 最终结果 | 证据 |
| --- | --- | --- |
| 本批新增测试 | 56 项：控制器 41、页面 11、正式导航 3、HTTP 1 | `test/bird_companion/features/smart_follow/finish/smart_follow_metadata_*_test.dart` |
| 关联回归 | **660 通过 / 1 跳过 / 0 失败** | `related-tests-final.log`、`related-tests-final-result.json` |
| 全仓静态分析 | **No issues found** | `analyze-final.log`、`analyze-final-result.json` |
| 累计 Dart 格式 | 无格式改动 | `format-check.log`、`format-check-result.json` |
| Git 空白检查 | 通过 | `diff-check.log`、`diff-check-result.json` |
| 中文小屏大字 | 360dp、1.5 倍文字，预览统计及部分确认截图已查看 | `screenshots/metadata-preview-*-360dp-150pct.png` |
| 源码与证据索引 | SHA-256 和检查结果 | `evidence.json` |

关联范围包括 smart_follow、recognition、copy、features/tasks、tasks、jobs、统一导航及复制设置；没有宣称全仓测试验收。唯一跳过项为未配置 `BIRDBOX_CONTRACT_BASE` 的外部 Python HTTP 契约检查。

测试验证能力 false、availability false、普通/部分确认、零可更新、缺字段、未知方式、失败预览、无效目标名称、过期重取、内容/目标/识别阶段变化、重复点击、已有任务、未知结果跨仓库恢复及设备隔离。正式路由测试分别从运行页和完成页走到最终确认，并读取原父任务。HTTP mock 验证用户确认前没有 create，确认后只有一次创建且请求 token、目标、部分确认和幂等键保持一致，没有普通复制请求。

截图来自本地 fixture（2099 年有效期为测试值），使用微软雅黑与 Material 图标字体，不是真机或真实盘验收。没有部署固件、连接真实盒子、构建 APK 或提交 Git。先前 SF-B0～SF-B4 的变更均保留；回退应仅移除本批接线和新增文件，不能清空整个工作区。

下一批：**SF-B6：信息更新父任务与报告（M3）**。
