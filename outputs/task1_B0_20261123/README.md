# 任务一 T1 B0 基线证据

核查日期：2026-11-23，北京时间。B0本地核查已完成；板端答复、手机拓扑和真实硬件验收继续待确认，不代表A15/A17/A18已修复或通过。

基线：`28aeae2a0ba5edf4c19dca584117345d26762e05`，由 `thirdtime` 创建实施分支 `codex/task1-network-20261123`。未改业务源码、权限、构建配置或任务二测试，未构建APK，未切换设备网络或清除配对。

| 内容 | 文件 |
| --- | --- |
| 基线、分支、Git树、工作区和源文件清单指纹 | [baseline.json](baseline.json) |
| 894个已跟踪输入文件的SHA256 | [source_manifest.json](source_manifest.json) |
| 材料ZIP、回交清单及包内两份网络要求指纹 | [materials_manifest.json](materials_manifest.json) |
| 实际工具版本及ADB观察 | [toolchain.json](toolchain.json) |
| 检查结果及3项跳过原因 | [checks.json](checks.json) |
| 资源释放、所有权与后续处理 | [资源释放与所有权清单](资源释放与所有权清单.md) |
| 382条词法命中记录 | [resource_sites.tsv](resource_sites.tsv)、[resource_sites.json](resource_sites.json) |
| A15/A17/A18与函数、已有测试及缺口对应 | [需求与测试映射](需求与测试映射.md) |
| 任务二必须保留的行为 | [任务二保护与回归清单](任务二保护与回归清单.md) |
| 板端与团队待答事项及答复模板 | [接口待确认清单](接口待确认清单.md) |
| 两款手机、盒子、网络拓扑与准备条件 | [测试环境与拓扑](测试环境与拓扑.md) |
| 原始测试事件 | [flutter_test_events.jsonl](flutter_test_events.jsonl)、[flutter_test_stderr.txt](flutter_test_stderr.txt) |
| 静态分析与门禁原始结果 | [dart_analyze.txt](dart_analyze.txt)、[production_integrity.txt](production_integrity.txt)、[contracts.txt](contracts.txt) |
| 只读采集脚本 | [capture_baseline.py](capture_baseline.py) |

本轮Flutter测试结果为518项通过、3项跳过、0失败，运行约37.6秒。跳过项依赖另行启动的本机Python服务；没有启动该服务，不算通过。静态分析无问题，生产完整性检查及非严格契约检查通过；未执行正式发布门禁、完整Android原生测试或手机集成测试。

使用本机已有 `dart.exe + flutter_tools.snapshot` 运行Flutter，避免启动器在受限SDK锁处无输出；实际运行仍需SDK锁写权限，本次获准后完成。未修改SDK脚本或锁文件内容，未安装/升级依赖。

`source_manifest.json` 是工作区文件字节SHA256，受换行格式影响；Git树记录的是提交内容，两者用途不同。文件范围为已跟踪的lib、android、test、integration_test、tool、docs/contracts及主要根配置，不包含用户凭据、生成APK或整个outputs。采集脚本拒绝覆盖已有baseline，后续批次应使用新目录和新时间点。

资源命中清单包含方法定义、调用、通道命令及注释，也包含流/图片控制器销毁和模拟代码；382不是运行次数或382个断网点。语义分类以资源清单为准。文件路径与行号冻结在B0提交基线，后续改动后按函数重新定位。
