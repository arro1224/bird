# T1-B5 / T1-B6 本地实施与候选证据

日期 2026-11-23；`thirdtime / 28aeae2a0ba5edf4c19dca584117345d26762e05`。全部改动保留工作区，不暂存、不提交。说明见 [B5](../../doc/任务/任务一_T1-B5_重新发现与有效设备实施记录_2026-11-23.md)、[B6](../../doc/任务/任务一_T1-B6_回归与候选构建记录_2026-11-23.md)。最终机器可读结果在 `checks.json`。

最终全仓 **2012 通过/9 跳过**，原生 **248 通过**，分析、门禁、契约与设备测试编译通过。[bird Debug候选](../../build/delivery/task1_B6_20261123_01/BirdBox-1.14.11-176-debug.apk) 及 [构建清单](../../build/delivery/task1_B6_20261123_01/build-manifest.json) 已生成，未安装、未发布。APK中构建身份与权限标志、签名、SHA256和535个编译输入核对通过。

- `start_manifest.json`：开始时 1371 个已有文件指纹，用于核对 B0～B4 成果保留及本批预期改动。
- `targeted_initial.txt`、`targeted_2.txt`、`full_suite.txt`、`connection_final.txt`：过程记录，包含当时未修复的失败；文件名中的 final 不代表通过，只以最终摘要及实际终态为准。
- `targeted_final.txt`：中途 71 项定向通过；之后增加的窄屏/权限/迟到取消及释放边界由后续最终回归覆盖。
- `release_gate_retest.txt`、`preflight_retest.txt`：释放状态/owner 边界 26 项、首次配对/扫描 12 项复核通过；不与全仓结果相加。
- `full_suite_final.txt`：修复后、最终源码的完整 Flutter 回归。
- `analyze_final.txt`、`production_integrity.txt`、`contracts.txt`：静态分析、生产完整性及非严格契约检查。
- `android_checks.txt`、`android_unit_summary.json`：Android 原生检查；单测数取 XML，设备测试只编译。
- `adb_devices.txt`：设备清单，无连接设备。
- `build_01.txt`、`apk_metadata.txt`：统一 bird Debug 候选构建及 APK 实际元数据检查；具体候选路径及 SHA256 见 `checks.json`。
- `apk_inspection.json`：实际 DEX 中检出 Git SHA/构建ID/源码指纹，及实际Manifest的never-for-location/Debug属性。
- `preservation.json`、`source_manifest.json`：原有成果保留、任务二保护项与本次源码指纹索引。APK 的确切构建输入另见候选目录 `source-files.sha256`。

共享 Android 入口的主机用例通过仅证明生产页面在模拟 transport 下的行为；不表示 Android 权限、真实广播、系统批准复用、切 AP/旧网或盒子已验收。候选为未提交源码构建的 Debug，不发布、不安装手机。
