# B12-B：真实硬件发布门禁

日期：2026-08-10  
前置批次：B12-A K7 模拟盒子发布前门禁  
实施结论：**门禁工具与正式发布链已实施；当前环境的发布状态为 blocked，未把模拟器结果伪装成真实硬件通过。**

## 1. 本批次交付

- 新增 B12-B 真实硬件证据模板，固定 33 个必须通过的真机用例；
- 新增可自动测试的失败关闭校验器；
- 将 B12-B 强制接入原有 B7 Release 门禁，正式 APK 验签后仍必须通过 B12-B；
- 明确拒绝 K7 mock、Android 模拟器、回环地址、Debug APK、未签名 APK、脏工作树、占位字段、缺失证据和含敏感字段的证据包；
- 保持 birdbox-v1 冻结：新增外部接口 0 个，修改外部接口 0 个。

## 2. 33 项真实硬件用例

门禁覆盖以下类别：

- 连接与身份：mDNS、二维码、手动地址、配对、会话恢复和吊销；
- SD 卡：detected、missing、unreadable、empty、重新插入和重扫；
- 任务：扫描、项目、导入、AI、App 被杀后恢复、断线重连、WS/REST 收敛和设备切换；
- 相册：审片、白鹭跨页搜索、其他鸟种、组合筛选、取消和部分缓存；
- 离线：待同步重放与冲突；
- 复制：目标在线、离线、空间不足、中断恢复、失败详情、报告和日志；
- 设备状态：低电量、外接电源和过温；
- 视觉：360dp/1.5 倍字体、426dp/1.3 倍字体；
- 发布：正式签名安装和回滚。

每项必须且只能出现一次，状态为 `passed`，并引用实际存在的脱敏截图、日志或报告文件。

## 3. 失败关闭规则

校验器要求：

- 冻结基线状态为 `ready`，盒子仓库、分支、固件 SHA、部署命令、数据库版本、迁移/回滚和四方联系人完整；
- Git 工作树干净，证据 App SHA 与当前检出 SHA 一致；
- APK 必须为 `app-bird-release.apk`，实际 SHA-256 与证据一致；
- `build_mode=release`、`signed=true`、`signature_verified=true`，证书 SHA-256 完整；
- Android 设备必须是真机，拒绝 `emulator-*`；
- 盒子设备 ID、型号和地址不得来自 mock、模拟器、localhost、127.0.0.1、`::1` 或 `10.0.2.2`；
- 固件 SHA 和数据库版本必须与冻结基线一致；
- 性能记录至少包含 3,672 张照片、白鹭与其他鸟种非空结果、首反馈、完整搜索、内存峰值和取消验证；
- App、固件回滚产物、回滚说明及协议/Flutter/盒子/QA 四方批准证据均存在；
- 证据 JSON 不得保存 Token、密码、Secret 或配对码。

## 4. 正式发布链集成

`tool/release/run_b7_gate.ps1 -Mode Release` 新增强制参数：

```powershell
-B12BEvidencePath C:\secure\b12b-real-hardware-evidence.json
```

正式顺序为：严格冻结基线 → 原有真实盒子 E2E → 正式 APK 构建 → 证书验签 → B12-B 33 项专项证据。缺少 B12-B 文件或任一条件不满足时发布脚本失败。

## 5. 当前环境判定

当前 B12-B 判定结果：`blocked`。

- 真实硬件用例：0/33；
- 当前 K7 为 `mock-k7-001 / K7 模拟盒子`；
- 未发现 `adb`，没有 Android 真机序列号；
- `android/key.properties` 不存在；
- 四项 Release 签名环境变量均未配置；
- 没有正式证书 SHA-256；
- 当前只有 B12-A Debug APK，B12-B 明确拒绝；
- 工作树包含用户已授权的未提交/未追踪相关改动，不满足正式发布的干净工作树要求。

严格冻结基线当前返回 13 个外部阻断：

- `status=blocked_external_inputs`；
- 缺少盒子仓库、分支、固件 SHA、部署命令、数据库版本、迁移、回滚和真实集成地址；
- 缺少协议、Flutter 核心、盒子 API、QA/发布四方联系人。

使用未填写模板和 B12-A Debug APK执行门禁时返回预期退出码 2，状态为 `blocked`。模板产生 138 条具体失败原因，覆盖上述基线、签名、真机、33 项用例、性能、回滚和批准材料，而不是笼统显示“未通过”。

## 6. 自动化结果

- B12-B 专项测试：4/4 通过；
- 全量 Flutter 测试：339/339 通过；
- 全项目 Dart 静态分析：`No issues found`；
- PowerShell 发布脚本语法检查：通过；
- birdbox-v1 非严格契约校验：通过；
- birdbox-v1 严格基线校验：按预期 blocked；
- OpenAPI SHA-256：`44f8a04a6daf94e2b41533ec0303fcc2249c749e1f1eecae69123e33c725d76f`，未变化。

## 7. 修改文件

- `tool/acceptance/b12b_release_gate.dart`
- `docs/acceptance/b12b-real-hardware-evidence.template.json`
- `test/bird_companion/acceptance/production_b12b_release_gate_test.dart`
- `tool/release/run_b7_gate.ps1`
- `tool/release/README.md`

## 8. 真机到位后的执行方法

1. 由盒子、协议、Flutter 和 QA owner 补全冻结基线并确认状态为 `ready`；
2. 配置正式签名和批准证书指纹；
3. 复制模板到安全证据目录，逐项执行 33 个真机用例并附脱敏证据；
4. 执行 B12-B 校验器；
5. 执行 B7 Release 门禁并提供原有盒子 E2E 与 B12-B 两份证据；
6. 仅当两级门禁均通过时批准发布。

当前可以继续使用 B12-A 进行开发和模拟联调，但 B12-B 发布状态保持 blocked，直到真实硬件和外部发布资料齐备。
