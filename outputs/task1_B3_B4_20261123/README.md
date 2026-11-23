# T1-B3 / T1-B4 本地验证

日期 2026-11-23。基线 HEAD `28aeae2a0ba5edf4c19dca584117345d26762e05`，分支 `thirdtime`。B0～B2 原提交已按用户要求退回工作区；本次继续叠加 B3/B4，未暂存、未提交。历史 B0～B2 证据不作改写。

实现记录：[B3](../../doc/任务/任务一_T1-B3_重开与短断恢复实施记录_2026-11-23.md)、[B4](../../doc/任务/任务一_T1-B4_原页控制恢复与退出实施记录_2026-11-23.md)。最终检查摘要见 `checks.json`。

- `analyze_initial.txt`、`analyze_1.txt`、`analyze_2.txt`、`regression_1.txt`、`targeted_1.txt`：过程记录，含编译/格式检查或旧 UI 断言失败，保留而不记通过。
- `targeted_2.txt`：中途定向验证 81 项通过；后续新增身份/取消与停止恢复边界由最终检查覆盖。
- `analyze_final.txt`：最终静态分析。
- `full_suite.txt`：全仓 `test --no-pub --timeout 90s --concurrency 2` 回归；全仓运行启动后继续补齐的最后停止边界另由 `connection_final.txt` 覆盖，不将两轮计数相加。
- `connection_final.txt`：最终连接、任务二、网络设置与 reconnect 路由回归。
- `owner_final.txt`：最后同设备 Future 合并和异常事件防护后的 repository/session 复核，41 项通过；不与前述结果累加。
- `production_integrity.txt`、`contracts.txt`：既有生产完整性和非严格契约检查。
- `adb_devices.txt`：ADB 设备清单，无连接设备。
- `source_manifest.json`：本批结束时工作区源码/测试及任务一文档的 SHA256，便于未提交源码追踪；不含实际 AP 或手机凭据。
- `preservation.json`：B0～B2 保留核对与任务二保护项检查。预期改动的共享源码和当前进度文档不要求等于旧指纹；原始证据保留原样。

本次没有 APK、设备安装、instrumentation、真实盒子或两机验收。命名空间测试验证 Flutter 到既有加密通道的接线和相互隔离；不将 MethodChannel mock 当作 Android Keystore 真机证明。全部恢复时间预算需在 B7 对齐板端并实际验证。
