# 拍鸟伴侣 App：复制功能现状迁移对照

**版本：** v1.0-rc1  
**日期：** 2026-08-24  
**主协议：** [拍鸟盒子_复制全量备份与多存储设备三端协议_v1.0-rc1_开发冻结版_2026-08-24.md](拍鸟盒子_复制全量备份与多存储设备三端协议_v1.0-rc1_开发冻结版_2026-08-24.md)

本文只回答“现有 App 复制页面和代码应保留什么、修改什么、删除什么”。所有字段、状态、错误码和接口以主协议为准；本文不得形成第二套接口定义。

---

## 1. 迁移结论

现有“入口 → 配置 → 确认 → 任务详情 → 结果/报告”的页面骨架可以保留，不需要推倒重做。主要问题集中在旧业务枚举、自动目标盘、mock 设备和 `xmp_enabled` 单布尔值，必须替换。

### 必须保留

- 任务首页和相册两个复制入口；
- 配置页、最后确认页、任务进度页和结果报告页；
- 提交前重新预检、防重复提交；
- 目标容量与在线状态展示；
- 源卡不会被修改的安全提示；
- 断线后重连并刷新盒子权威状态；
- 失败明细分页和日志入口；
- 低电量提醒与完成后自动打开报告的本地偏好。

### 必须替换

- `keep/all/dual` → 主协议四种 `scope`；
- `xmp_enabled` → `review_export` 对象；
- 自动选择任意可用目标 → 同批次上次成功目标仅预选；
- 固定/模拟目标列表 → 后端实时稳定设备列表；
- Linux/盘符式目标概念 → 稳定 `media_id`；
- 估算版本 → `preview_token`；
- 直接提交大量照片 ID → 不可变 `selection_id`；
- “跳过失败项”前端动作 → 由盒子任务状态和协议允许操作决定。

### 必须删除

- “双轨复制”；
- 跨批次永久默认物理目标盘；
- 默认目标离线后自动改选另一块盘；
- 把本机/系统存储作为普通复制目标的预置卡片；
- App 自己计算可复制数量或目标空间是否足够；
- 未经用户选择的同名冲突默认策略。

---

## 2. 旧字段迁移表

| 现有字段/行为 | 处理 | 新语义 |
|---|---|---|
| `mode=keep` | 替换 | `scope=kept_assets` |
| `mode=all` | 替换 | `scope=batch_all_assets` |
| `mode=dual` | 删除 | 不存在；全量备份是独立 `media_full_backup` 入口 |
| 相册多选暂不支持复制 | 实现 | 创建 `selection_id`，使用 `scope=selected_assets` |
| `target_id` | 改类型/语义 | `target_media_id`，值为稳定 `media_id` |
| `xmp_enabled` | 删除 | `review_export.enabled/write_xmp/write_csv/embed_into_supported_copy` |
| `verify_after_copy` | 不再让 App 决定 | v1 正式复制固定强校验，结果页展示即可 |
| `version` | 替换 | 预检使用 `preview_token`，动作使用 `expected_state_version` |
| 保存默认复制范围 | 可保留 | 仅保存范围和 RAW/JPEG 等偏好，最终确认不可跳过 |
| 保存默认目标位置 | 删除全局行为 | 改为同一 `batch_id` 的上次成功目标预选 |
| 自动选其他在线目标 | 删除 | 原目标不在线时要求用户重选 |
| XMP/写入照片/不导出三选一 | 重组 | 一个总开关 + 是否嵌入支持格式；开启时 XMP+CSV 固定同时输出 |
| 暂停/继续 | 保留 | 文件边界暂停，不承诺字节级暂停 |
| 重试失败项 | 保留 | 只重试失败项，不重复制成功项 |
| 跳过失败项 | 暂不作为通用动作 | 若后端未返回该能力，App 不显示；不得前端伪造完成 |

---

## 3. 页面级修改

### 3.1 任务首页

保留当前复制入口，但修改能力判断：

- 当前存在分析任务时，不应仅因此禁止复制；
- 当前存在另一个目标写任务时禁止创建，并显示“已有复制/备份任务正在使用目标设备”；
- 无当前批次时，仍可在存储工具入口发起“摄影资料全量备份”，但不能发起批次复制；
- 入口文案分为“复制照片”和“摄影资料全量备份”。

涉及：

```text
lib/bird_companion/features/tasks/domain/task_home_capability_resolver.dart
```

### 3.2 相册页与多选操作栏

保留“复制当前拍摄”，并在多选操作栏增加“复制所选”。

“复制所选”规则：

- 0 张时隐藏或禁用；
- 只能来自同一批次；
- 点击后先创建不可变 `selection_id`；
- 进入配置页后范围固定显示“已选择 N 张”，不得再显示 keep/all/dual；
- 复制不得改变保留、弃选、精选、评分或标签；
- 是否复制弃选照片不做协议限制；既然用户明确选中就允许，确认页显示其中弃选数量作为提醒即可。

涉及：

```text
lib/bird_companion/features/gallery/presentation/gallery_page.dart
lib/bird_companion/features/gallery/presentation/widgets/selection_action_bar.dart
```

### 3.3 内容配置页

页面改为以下顺序：

1. 复制范围；
2. RAW+JPEG 策略（全量备份时隐藏）；
3. 目标设备；
4. 同名文件处理（必选）；
5. 随副本保存审阅信息；
6. 获取预检。

目标设备卡片必须显示：

- 图标和用户可读名称，如“相机卡（读卡器）”“U 盘 Ee”；
- 厂商/型号、容量、可用空间和文件系统；
- 类型可信提示；
- 当前角色和不可选原因；
- “上次用于这个批次”标记，但不得用“系统默认盘”文案。

禁止展示 `/dev/sda1`、Linux 挂载点和内部序列号。

范围列表：

- `selected_assets`：仅从相册多选入口出现；
- `kept_assets`：复制已保留；
- `batch_all_assets`：复制本批次全部照片；
- `media_full_backup`：独立入口进入，不与前三者混排成旧“模式”。

### 3.4 最后确认页

保留现有页面和二次预检，新增必显项：

- 源设备名称；
- 目标设备名称；
- 复制范围；
- 逻辑照片数与实际文件数；
- RAW/JPEG 策略；
- 视频/伴随文件数（全量备份）；
- 同名冲突策略；
- 审阅信息：XMP+CSV、嵌入支持格式，或“不导出”；
- 预计写入量、剩余空间和安全余量；
- 源卡只读提示与目标盘勿拔出提示。

若用户没有选择同名策略，“开始复制”必须禁用；不得在 Cubit 中补默认值。

涉及：

```text
lib/bird_companion/features/copy/presentation/copy_confirmation_page.dart
lib/bird_companion/features/copy/presentation/copy_confirmation_cubit.dart
```

### 3.5 任务详情

保留阶段时间线，建议阶段改为：

```text
等待设备 → 获取目标盘 → 复制文件 → 校验文件 → 写入审阅信息 → 安全同步 → 完成
```

只显示后端 `allowed_actions` 返回的按钮：

- `pause`
- `resume`
- `cancel`
- `retry_failed`
- `safe_remove_source`
- `safe_remove_target`

暂停按钮说明“当前文件完成后暂停”。取消确认继续说明“已完成的副本不会删除”。

设备拔出时区分：

- 等待相机卡；
- 等待原目标 U 盘；
- 检测到另一块盘但不能自动继续。

涉及：

```text
lib/bird_companion/features/jobs/presentation/job_detail_page.dart
```

### 3.6 结果与报告

保留当前结构，统计字段改为：

- 逻辑照片数；
- 实际文件数；
- 成功、失败、同名跳过、不适用；
- RAW/JPEG/视频/伴随文件分类；
- 总字节数、耗时、有效吞吐；
- XMP 数、CSV 状态、嵌入成功/降级数量；
- 源/目标设备展示快照；
- `copy_job_id`、`selection_id`、`review_snapshot_id`。

“部分成功”不得显示成成功。失败项分页使用后端 cursor，不要在前端按文件名去重。

涉及：

```text
lib/bird_companion/features/tasks/presentation/pages/production_task_result_page.dart
```

### 3.7 设置：复制与备份

建议保留：

- 默认复制范围（仅作为页面初始偏好）；
- 默认 RAW/JPEG 策略；
- 随副本保存审阅信息；
- 支持格式中嵌入副本元数据；
- 低电量提醒；
- 完成后自动打开报告。

必须移除或改名：

- 删除“双轨复制”；
- 删除“完整性校验开关”，正式模式固定开启；
- 删除全局默认物理目标；
- “生成同名 XMP”改成“随副本保存审阅信息（XMP + CSV）”；
- “写入照片元数据”改成从属开关“支持时写入副本”，并明确永不修改相机卡。

涉及：

```text
lib/bird_companion/features/settings/presentation/pages/copy_backup_settings_page.dart
```

### 3.8 设置：目标位置

现有预置设备卡片不能继续作为真实数据源。建议改为“存储设备”页：

- 实时列出盒子当前设备；
- 显示类型、卷标、容量、空间和角色；
- 允许设置用户别名；
- 提供安全移除；
- 不提供跨批次“设为默认目标”；
- 可展示最近使用记录，但离线设备不可作为当前选择。

涉及：

```text
lib/bird_companion/features/settings/presentation/pages/storage_target_page.dart
```

---

## 4. 数据层迁移

涉及：

```text
lib/bird_companion/features/copy/data/copy_api.dart
lib/bird_companion/features/copy/domain/copy_repository.dart
```

### 4.1 删除旧接口依赖

```text
GET  /api/v1/projects/{batchId}/copy/estimate?mode=keep|all|dual
POST /api/v1/projects/{batchId}/copy
```

App 迁移到主协议第 13 节接口。旧接口可以由后端在过渡期返回明确弃用错误，但新 App 不应再调用。

### 4.2 建议 App 模型

App 领域模型至少拆分：

```text
StorageDeviceSummary
CopySelectionSnapshot
CopyPreview
CopyRequestDraft
CopyJobSummary
CopyJobDetail
CopyJobItem
CopyReport
CopyAllowedAction
```

禁止继续用一个 `CopyMode` 同时表达照片范围、RAW/JPEG 和全量备份。

### 4.3 状态同步

- 列表/详情以盒子状态为权威；
- 每次动作携带 `expected_state_version`；
- 重连后以 `event_seq` 增量获取，序列缺口时重新拉完整详情；
- App 本地只能保存草稿和展示缓存，不能把本地状态写回成任务成功；
- `Idempotency-Key` 在网络重试时复用，用户重新发起新意图时生成新值。

---

## 5. 分阶段实施建议

### 阶段 A：模型和接口壳

- 新增稳定设备、预检、选择快照和任务模型；
- 保留旧页面但接假实现/feature flag；
- 删除业务代码对 `/dev/sdX` 或固定目标的任何假设。

### 阶段 B：设备选择和确认页

- 接真实 `/storage/devices`；
- 实现同批次预选；
- 加入同名策略、RAW/JPEG 和审阅导出；
- 接 `preview_token`。

### 阶段 C：相册多选

- 批量操作增加“复制所选”；
- 创建不可变 `selection_id`；
- 验证选中数量、失效项和确认页统计。

### 阶段 D：任务与报告

- 接状态机、`allowed_actions`、`event_seq`；
- 实现文件边界暂停语义；
- 报告增加分类、哈希与元数据统计。

### 阶段 E：删除旧逻辑

- 删除 `dual`、旧 estimate/create DTO、mock 目标盘和全局默认物理目标；
- 清理旧本地偏好迁移：`dual` 迁移为 `batch_all_assets`，但首次使用必须提示用户确认；旧 target 默认直接丢弃，不映射到新盘。

---

## 6. App 验收清单

- [ ] 能同时显示“相机卡（读卡器）”和“U 盘 Ee”，且不显示 Linux 路径。
- [ ] 设备类型不确定时显示普通说明，不伪装成确定类型。
- [ ] 源盘与目标盘由用户分别确认，同一设备不能同时选择。
- [ ] 同批次第二次复制只预选上次目标，仍可改选。
- [ ] 上次目标离线时不自动选择另一块盘。
- [ ] 未选同名策略不能进入创建。
- [ ] 多选 4 张时，配置和确认均显示 4 个逻辑照片及实际文件数。
- [ ] 复制弃选照片不会改变其审阅状态。
- [ ] 全量备份是独立入口，不出现“双轨”。
- [ ] RAW/JPEG 策略和全量备份范围不会混淆。
- [ ] 关闭审阅导出时，确认页明确显示“不向目标盘导出审阅信息”。
- [ ] 暂停文案说明文件边界生效。
- [ ] App 断线后任务继续，重连恢复真实状态。
- [ ] 目标拔出后不会自动切到另一块盘。
- [ ] 安全移除成功后明确显示“现在可以拔出”。
- [ ] 部分成功、失败、取消分别展示，不伪装成全部成功。

---

## 7. 给 App 开发者的最短结论

可以保留现有页面流程和大部分视觉结构；不要继续扩展旧 `keep/all/dual + xmp_enabled + 默认目标盘` 模型。先按主协议重建领域模型和接口，再逐页替换数据源。若后端接口尚未交付，页面可以继续开发，但所有 mock 必须使用主协议字段，禁止再创造临时枚举。
