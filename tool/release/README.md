# B7 Android 发布门禁

`run_b7_gate.ps1` 把实施说明书 B7 的格式、契约、静态检查、测试、Android
构建和证据采集收口到一个可重复执行的入口。

## 本地预检

预检允许脏工作树，执行非严格契约检查、生产入口完整性检查、全部测试和 bird debug APK 构建：

```powershell
powershell -ExecutionPolicy Bypass -File tool/release/run_b7_gate.ps1 `
  -Mode Preflight
```

证据默认写入 `build/b7/b7-gate-evidence.json`，包括工具版本、App SHA、工作树
状态、契约版本、各步骤耗时以及 APK 路径、大小和 SHA-256。

## 正式发布

正式模式额外要求：

1. Git 工作树干净；
2. `birdbox-v1-baseline.json` 的真实盒子与四方联系人字段完整，状态为
   `ready`；
3. 正式签名四项凭据完整注入；
4. 提供与冻结盒子 SHA 一致的真实盒子 E2E 证据；
5. release APK 通过 `apksigner verify --print-certs`。

签名凭据只能通过未入库的 `android/key.properties`，或以下环境变量注入：

- `AVES_RELEASE_STORE_FILE`
- `AVES_RELEASE_STORE_PASSWORD`
- `AVES_RELEASE_KEY_ALIAS`
- `AVES_RELEASE_KEY_PASSWORD`

发布负责人还必须提供可公开核对的批准证书指纹
`AVES_RELEASE_CERT_SHA256`。验签脚本不仅检查 APK 签名结构有效，还会拒绝签名证书
与该指纹不一致的包。

真实盒子证据是一个 JSON 文件，最低结构如下：

```json
{
  "box_sha": "完整固件提交 SHA",
  "device_model": "真实设备型号",
  "api_version": "v1",
  "schema_version": "真实数据库 schema 版本",
  "e2e_passed": true,
  "cases": [
    {
      "id": "connect_mdns",
      "status": "passed",
      "evidence": "脱敏日志、截图或测试报告路径"
    }
  ]
}
```

`cases` 必须完整包含并通过：`connect_mdns`、`connect_qr`、`connect_manual`、
`pair_session_restore_revocation`、`device_status`、
`scan_project_import_analysis`、`job_resume_after_app_kill`、
`gallery_review`、`offline_replay_conflict`、`copy_failures_report_logs` 和
`signed_install_rollback`；每项都必须提供非空的脱敏证据引用。

执行命令：

```powershell
powershell -ExecutionPolicy Bypass -File tool/release/run_b7_gate.ps1 `
  -Mode Release `
  -RealBoxEvidencePath C:\secure\bird-real-box-e2e.json `
  -B12BEvidencePath C:\secure\b12b-real-hardware-evidence.json
```

正式门禁不会把缺失盒子材料、调试签名或手工声明当作通过。发布包生成后还可单独
复核：

```powershell
powershell -ExecutionPolicy Bypass -File tool/release/verify_android_release.ps1
```

## B12-B 真实硬件专项证据

B7 正式门禁之外，任务设计与相册搜索筛选的最终硬件放行还必须填写
`docs/acceptance/b12b-real-hardware-evidence.template.json`，并运行：

```powershell
dart run tool/acceptance/b12b_release_gate.dart `
  --evidence=C:\secure\b12b-real-hardware-evidence.json `
  --apk=build\app\outputs\flutter-apk\app-bird-release.apk
```

B12-B 校验器要求 33 个真机用例、3,672 张以上真实照片性能指标、正式签名
Release APK、真实固件与数据库版本、回滚材料和四方批准证据。它会拒绝
`mock-k7-*`、模拟器序列号、回环地址、Debug APK、脏工作树、占位字段和包含
Token/密码/配对码的证据文件。

`run_b7_gate.ps1 -Mode Release` 已强制要求 `-B12BEvidencePath`，并在正式 APK
验签完成后调用同一校验器；不能通过跳过独立命令绕过 B12-B。
