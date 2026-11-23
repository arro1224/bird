# T1 B2 自动直连验证证据

源码起点：T1-B1提交 `e79f8552e`。实现说明见 [B2实施记录](../../doc/任务/任务一_T1-B2_自动直连实施记录_2026-11-23.md)。

最终统计见 `checks.json`。证据范围与限制：

- `targeted_tests.txt`：系统join、handoff、协议/授权、恢复及协调器定向回归。
- `full_test_events.jsonl`：首轮全仓回归。该轮与原生构建同时运行，3项用例发生30秒超时并伴随失败；保留原始结果，不算通过。
- `mock_timeout_retest.txt`：其中复制模拟服务用例隔离复测通过；后续以完整重跑结果为准，不据一次隔离通过关闭全部回归。
- `full_test_final_events.jsonl`及stderr/exit：减少并发、原生构建结束后对B2代码再次执行的全仓回归。
- 第二轮仍有两项超时；查明其自身等待约35至40秒超过默认30秒窗口。
- `verified_test_events.jsonl`及stderr/exit：使用90秒测试窗口、2并发全仓执行，1978通过、9跳过，无失败。仅改变测试运行器窗口，不改变业务超时或断言。
- `final_connection_events.jsonl`及stderr/exit：最后取消/意图归属补强后的连接、任务二、网络设置/路由复核，535通过、3跳过，无失败。
- `android_checks.txt`及exit：`:app:testBirdDebugUnitTest :app:compileBirdDebugAndroidTestJavaWithJavac -Ptarget=lib/main.dart -x :app:compileFlutterBuildBirdDebug --offline`；使用Android Studio的JBR21和现有缓存，不安装设备应用。
- `android_final_checks.txt`：最终native源文件调整后的增量复查。
- `analyze_final.txt`、`production_integrity.txt`、`contracts.txt`：最终静态分析、生产完整性与非严格契约结果。
- `checks.json`：机器可读统计与覆盖边界。

新增Wi-Fi设备测试仅编译，本轮无手机连接，未运行instrumentation、未验收系统弹窗/批准复用、实际Wi-Fi路由或退出旧网，也未生成可交付APK。Android原生单测的通过数不包含设备测试。

248项原生单测、最终静态分析、生产完整性和非严格契约检查均通过。任务二Manifest、配网卡片/相册页面、SSID读取、QR解析、夹具及生产门禁与 `28aeae2a0` 相比未改；共享repository、平台通道与会话装配的变化由最终回归覆盖。

两份Gradle输出日志仅清理了行尾空格以通过仓库空白检查，保留警告、任务结果和退出状态。
