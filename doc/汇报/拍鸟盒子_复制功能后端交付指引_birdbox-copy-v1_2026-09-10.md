# 拍鸟盒子后端：birdbox-copy-v1 复制功能交付指引

**日期：** 2026-09-10
**写给：** 盒子业务后端
**App 分支：** `thirdtime`
**状态：** App 侧复制功能迁移（阶段 A+B+C）已完成，mock 先行；**本指引对应后端待交付的 HTTP 接口**

---

## 0. 背景

拍鸟伴侣 App 已按冻结协议完成复制功能迁移，当前通过 App 内 mock 数据运行（`useMockCopyRepository = true`）。后端交付下述接口后，App 侧**只改一个开关**即可切到真实 HTTP，无需改页面代码。

App 侧目前不会等待后端即可自测，但**任务进度/报告联动（阶段 D）必须等后端接口真实交付后才能联调**（当前提交后只弹成功对话框）。

---

## 1. 契约基线（按优先级阅读）

1. **主协议（开发冻结版，唯一权威）：**
   `doc/拍鸟盒子_复制全量备份与多存储设备三端协议_v1.0-rc1_开发冻结版_2026-08-24.md`
   - 设备模型 §4、复制范围 §5、pair_policy §6.2、冲突策略 §8、审阅导出 §9、预检 §10、任务状态机 §12、HTTP API §13、错误码 §15、持久化最低要求 §18
2. **参考实现（可直接当联调目标运行）：** `tool/mock_box_server/mock_box_server.dart` 的 copy-v1 路由
   - 启动：`dart run tool/mock_box_server/server.dart --quick --auth --progressive-media --host=0.0.0.0 --port=8787 --device-id=bbx-82f41c9e7a3d4b68a1501e21e536c649`
3. **App 侧契约实现（解析规则以这里为准）：** `lib/bird_companion/features/copy/data/copy_api.dart` + `features/copy/domain/copy_models.dart`

---

## 2. 通用要求（§13.1）

| 项目 | 要求 |
|---|---|
| Base path | `/api/v1` |
| 请求头 | 所有请求携带 `X-BirdBox-Protocol: birdbox-copy-v1` |
| 幂等 | 所有创建/动作请求携带 `X-Idempotency-Key`（mock 校验至少 8 字符；同键并发只执行一次，重放首次响应） |
| 时间 | ISO 8601 含时区 |
| 成功包络 | `{"request_id":"...","data":{...}}`（App 端自动解包 `data`，也可返回裸 JSON） |
| 错误包络 | `{"request_id":"...","error":{"code":"...","message":"...","details":{}}}` |
| 错误语义 | 面向用户的 `message` 必须是普通语言（如"目标 U 盘空间不足，还需要 12.4 GB"），不得只显示错误码 |
| 鉴权 | 沿用现有 Bearer 体系 |

---

## 3. 本次必须交付的端点（App 现在就在调用）

### 3.1 `GET /api/v1/storage/devices`（§13.2 / §4.1）

响应 `data.devices` 为设备列表，每项字段（App 全部按必填解析，缺失即报协议不兼容）：

```json
{
  "media_id": "media_2d6dee77bb5ecc73e3d34787",
  "display_name": "相机卡（读卡器）",
  "kind": "card_reader",
  "kind_confidence": "high",
  "detail": "双逻辑槽位读卡器 · 119.2 GB · EXFAT",
  "capacity_bytes": 128000000000,
  "free_bytes": 96400000000,
  "filesystem": "exfat",
  "label": "",
  "role_state": "available",
  "can_be_source": true,
  "can_be_target": false,
  "target_block_reasons": ["当前任务源设备"],
  "identity_confidence": "stable_uuid",
  "last_seen_at": null,
  "user_alias": null
}
```

关键语义：
- `media_id` 是**唯一稳定身份**（§3.1）。**禁止把 Linux 设备路径传给 App**，App 不展示 `/dev/sdX`
- `kind` 枚举：`memory_card / card_reader / usb_flash / usb_storage / external_hdd / external_ssd / removable_storage / unknown`
- `role_state`：`available / removed / unavailable`；App 判定在线 = 非 removed 且非 unavailable
- `identity_confidence`：`stable_uuid / degraded`（无 UUID 时降级指纹）
- `target_block_reasons`：设备不可作目标时的原因列表，App 卡片必须展示原因，不得只灰掉（§4.3）
- 同一设备不能同时被选为源与目标（§1.3）

### 3.2 `POST /api/v1/storage/devices/{media_id}/alias`（§13.2 / §4.2）

```json
{ "alias": "Ee" }
```

- 别名必须**服务端持久化**（§18 `storage_devices.user_alias`），设备重插后保持；空字符串清除别名
- 展示优先级：用户别名 > 服务端 `display_name`（§4.2）

### 3.3 `POST /api/v1/batches/{batch_id}/copy-selections`（§13.3）

相册多选"复制所选"时调用。请求：

```json
{ "asset_ids": ["asset_...", "asset_..."], "client_revision": 7 }
```

响应（不可变快照，§3）：

```json
{ "selection_id": "sel_...", "asset_count": 4, "created_at": "2026-09-10T08:00:00+08:00" }
```

关键语义：快照**不可变**；创建后资产状态变化不影响复制内容。`GET /api/v1/copy-selections/{selection_id}` 为查询端点（§13.3）。

### 3.4 `POST /api/v1/copy-jobs/preview`（§13.4 / §10.1）

请求体（App `CopyRequestDraft.toJson`，全量备份时 `batch_id` 可省略）：

```json
{
  "batch_id": "batch_...",
  "source_media_id": "media_...",
  "target_media_id": "media_...",
  "scope": "kept_assets",
  "selection_id": "sel_...",
  "pair_policy": "raw_only",
  "conflict_strategy": "keep_both",
  "review_export": {
    "enabled": true,
    "write_xmp": true,
    "write_csv": true,
    "embed_into_supported_copy": true
  }
}
```

`scope` 枚举：`selected_assets / kept_assets / batch_all_assets / media_full_backup`
`pair_policy` 枚举：`raw_only / jpeg_only / both`
`conflict_strategy` 枚举：`skip / overwrite / keep_both`

响应（App 全字段必填解析）：

```json
{
  "preview_token": "preview_...",
  "expires_at": "2026-09-10T08:15:00+08:00",
  "source": { "...设备对象（§4.1）..." },
  "target": { "...设备对象（§4.1）..." },
  "logical_photo_count": 34,
  "actual_file_count": 67,
  "total_bytes": 1174405120,
  "raw_count": 34,
  "jpeg_count": 33,
  "video_count": 0,
  "companion_count": 2,
  "estimated_date_directories": 2,
  "conflict_count": 3,
  "target_free_bytes": 30500000000,
  "safety_reserve_bytes": 1073741824,
  "unsupported_count": 0,
  "missing_count": 1,
  "permission_error_count": 0
}
```

关键语义：
- 逻辑照片数：RAW+JPEG 视为一个（§6.1）；`actual_file_count` 是实际文件数
- `safety_reserve_bytes` ≥ 5% 容量或配置下限（§10.1）；App 判定空间：`target_free_bytes - safety_reserve >= total_bytes`
- `preview_token` 有有效期（§10.2）：App 在确认页展示过期提示并允许重新获取；提交前会二次预检
- 统计口径（§10.1）：按固定目录规则预估日期目录数、同名冲突数

### 3.5 `POST /api/v1/copy-jobs`（§13.5 / §10.2 / §8）

请求 = §3.4 预检请求体 + `preview_token`。**必须校验：**

1. `conflict_strategy` 缺失 → `422 COPY_CONFLICT_STRATEGY_REQUIRED`（§8 禁止默认值，App 与 mock 均已实现该校验）
2. `preview_token` 缺失或过期 → 错误码见 §15 错误码表

响应（§13.5 创建响应，App `CopyJobSummary.fromJson`）：

```json
{ "copy_job_id": "copy_...", "state": "queued", "event_seq": 0, "created_at": "2026-09-10T08:00:00+08:00" }
```

关键语义：
- 创建即落库（§18 `copy_jobs` / `copy_items`），任务状态机见 §12；`event_seq` 单调递增供增量同步
- 全盒子同时最多一个目标写租约、一个复制 worker（§16）
- 幂等键重放返回首次响应

---

## 4. 建议一并交付（阶段 D/E 联调依赖，App 已定义好接法）

| 端点 | 协议节 | 说明 |
|---|---|---|
| `GET /api/v1/copy-jobs/{copy_job_id}` | §13.5 | 任务详情；App 阶段 D 将在此接入"查看任务进度"跳转 |
| `GET /api/v1/copy-jobs/{copy_job_id}/events?after_seq=...` | §13.5 | 事件增量同步 |
| `GET /api/v1/copy-jobs/{copy_job_id}/report` | §13.5 | 结果报告：RAW/JPEG/视频/伴随分类、XMP/CSV/嵌入、哈希 |
| `GET /api/v1/copy-jobs/{copy_job_id}/items?cursor=...&state=failed` | §13.5 | 失败项 cursor 分页 |
| `POST /api/v1/copy-jobs/{id}/actions/pause\|resume\|cancel\|retry-failed` | §13.6 | 动作；携带 `expected_state_version`，版本冲突 `409 COPY_STATE_VERSION_CONFLICT` |
| `POST /api/v1/storage/devices/{media_id}/safe-remove` | §13.2 | 安全移除（阶段 E）；保持期默认 60 秒不得自动重挂载 |
| 任务统一入口 | — | 复制任务需接入现有 `/api/v1/jobs` 体系，App 任务首页/任务列表从 `/api/v1/jobs` 读取 |
| WebSocket 事件 | — | 复制任务状态变化推事件（现有事件通道），App 据此刷新任务列表 |
| 同批次上次成功目标读取 | §4.4 | App 接口已预留 `lastSuccessfulTarget`（当前返回 null，本地先记 `batchTargetPreferences`）；后端交付后 App 可改读服务端 |

---

## 5. 错误码（§15，以协议为准）

| 错误码 | HTTP | 可重试 | 含义 |
|---|---:|---|---|
| `COPY_CONFLICT_STRATEGY_REQUIRED` | 422 | 否 | 未选择同名策略 |
| `COPY_SOURCE_TARGET_SAME` | 422 | 否 | 源和目标相同 |
| `COPY_SOURCE_NOT_PRESENT` | 409 | 是 | 源盘不在线 |
| `COPY_TARGET_NOT_PRESENT` | 409 | 是 | 目标盘不在线 |
| `COPY_MEDIA_ID_CHANGED` | 409 | 否 | 介质身份与快照不一致 |
| `COPY_TARGET_BUSY` | 409 | 是 | 已有写租约或任务 |
| `COPY_TARGET_READ_ONLY` | 409 | 否 | 目标硬件/文件系统只读 |
| `COPY_UNSUPPORTED_FILESYSTEM` | 422 | 否 | 不支持的文件系统 |
| `COPY_INSUFFICIENT_SPACE` | 409 | 是 | 空间不足 |
| `COPY_SOURCE_CHANGED` | 409 | 是 | 源文件在任务后变化 |
| `COPY_SOURCE_PATH_UNSAFE` | 422 | 否 | 越界、符号链接或非普通文件 |
| `COPY_HASH_MISMATCH` | 500 | 是 | 目标校验失败 |
| `COPY_DEVICE_REMOVED` | 409 | 是 | 复制中拔盘 |
| `COPY_LEASE_EXPIRED` | 409 | 是 | 目标写租约过期 |
| `COPY_METADATA_WRITE_FAILED` | 500 | 是 | XMP/CSV/嵌入失败 |
| `COPY_STATE_VERSION_CONFLICT` | 409 | 是 | App 操作基于旧状态 |
| `COPY_PREVIEW_EXPIRED` | 409 | 是 | 预检已过期 |
| `COPY_SELECTION_IMMUTABLE` | 409 | 否 | 尝试修改快照 |
| `COPY_SAFE_REMOVE_BUSY` | 409 | 是 | 设备仍有活动任务 |

> ⚠️ 已知偏差：mock 参考实现对缺失 `preview_token`/`scope` 返回 `422 COPY_PREVIEW_EXPIRED`，**与协议 §15 的 409 不一致，实现以协议为准**。

---

## 6. 后端自测验收清单

以下对 mock 盒子的 curl 可照搬测你本地实现（`--auth` 启动时需带 Bearer；去掉 `--auth` 可免鉴权）：

1. **设备列表**：`GET /api/v1/storage/devices` → 至少一台 `can_be_source`、一台 `can_be_target`，字段齐全
2. **预检**：`POST /api/v1/copy-jobs/preview`（§3.4 请求体）→ 200，返回 token/统计/空间
3. **创建 422 语义**：`POST /api/v1/copy-jobs` 不带 `conflict_strategy` → `422 COPY_CONFLICT_STRATEGY_REQUIRED`
4. **创建任务**：带完整参数 + `preview_token` → 202/200 返回 `copy_job_id`/`state`/`event_seq`
5. **任务可见**：创建后 `GET /api/v1/jobs` 能查到该任务（类型 copy）
6. **幂等**：同一 `X-Idempotency-Key` 重复 POST → 返回首次响应，不重复创建
7. **状态流转**（如交付 §4）：任务由 `queued → copying → completed`，`event_seq` 递增；报告接口返回分类统计
8. **别名**：`POST /api/v1/storage/devices/{media_id}/alias` 后重启进程别名仍在（持久化）

---

## 7. 交付判定与 App 侧切换

后端交付后，App 侧只需：

```dart
// lib/bird_companion/features/copy/data/mock_copy_repository.dart 第 11 行
const useMockCopyRepository = false;
```

即全部复制功能走真实 HTTP（`CopyApi` 已实现 §13 全部调用与解析），页面无需改动。

联调方式：App 以 `--dart-define=BIRD_TEST_BASE_URL=http://<后端地址>:<端口>` 指向你的服务。

---

## 8. 后端尚未交付前，App 侧现状

- 复制配置 → 预检 → 提交 → 成功对话框全流程可用（数据为协议字段 mock）
- 任务列表**看不到复制任务**属正常：提交只落在 App 内存 mock，未进盒子 `/api/v1/jobs`；阶段 D（提交后跳任务详情、任务列表进度、结果报告）等后端交付后联调
- 安全移除（safe-remove）、失败项重试等阶段 E 功能未实现，见迁移实施记录
