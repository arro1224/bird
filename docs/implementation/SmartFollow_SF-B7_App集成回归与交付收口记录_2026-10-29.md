# SmartFollow SF-B7：App 集成回归与交付收口记录

日期：2026-10-29（Asia/Shanghai）。分支 `thirdtime`；HEAD `c77fcd7bc866d02eed7d0ae3da7d67c5e7f9cfc8`；延续 SF-B0～SF-B6 未提交工作区。

**本地集成回归和联调包交付准备已完成，正式联合验收保留未通过项。** 全量测试 1606 通过 / 3 跳过 / 0 失败，静态分析无问题；Normal Debug APK 已安装到隔离 Android 14 模拟器并完成冷启动。第 13 条普通全量复制的信息更新接线仍需关联协议，不能认定所有 App 验收已完成。

## 1. 本批实际工作

- 对累计 SF-B0～SF-B6 代码运行全仓默认 test、静态分析、格式检查、冻结契约和生产完整性检查，没有为交付修改生产业务行为。
- 对照 App §11 十五条及字段问询十项逐条登记证据与缺口，形成 [验收矩阵与遗留清单](SmartFollow_SF-B7_验收矩阵与遗留清单_2026-10-29.md)。后端问询单没有正式回执，本轮不代填。
- 通过项目已有 Normal Debug 构建脚本生成 APK，独立核验 APK hash、签名、包名与版本，登记源码指纹和构建输入。
- 隔离模拟器安装成功，首次权限页面正常，授予蓝牙权限后再次冷启动进入“查找盒子”；保存截图和日志，随后关闭本次模拟器。没有连接真实盒子或目标盘。
- 生成有明确 fixture 水印的 13 帧组件演示与图片索引，覆盖双模式、配置、运行、排空、完成/部分完成、预览确认、父任务报告及再次信息变化。

本批新增可追踪内容是实施/验收文档与计划更新；回归、渲染和打包辅助脚本、日志、APK 均在忽略的 `build/smart-follow/sf-b7/`，没有改 SDK、升级依赖或更改发布签名。

## 2. 最终检查

| 检查 | 结果 | 相对 `build/smart-follow/sf-b7/` 的证据 |
| --- | --- | --- |
| 默认 test/ 全量 | **1606 通过 / 3 跳过 / 0 失败**，exit 0 | full-tests-final.log、full-tests-final-result.json |
| 全仓静态分析 | **No issues found**，exit 0 | analyze-final.log、analyze-final-result.json |
| 累计 Dart 格式 | **59 文件、0 改动**，exit 0 | format-check.log、format-check-result.json |
| Git 空白检查 | 通过，exit 0 | diff-check-result.json |
| 冻结契约 | **PASS birdbox-v1@1.0.0**，exit 0 | contracts.log、contracts-result.json |
| strict baseline | **FAIL，13 项缺失/未就绪**，exit 1；正式门禁未通过 | contracts-strict.log、contracts-strict-result.json |
| 生产完整性 | **PASS**，exit 0 | production-integrity.log、production-integrity-result.json |
| Normal Debug 构建 | 成功，exit 0 | apk-build.log、apk-build-result.json |
| APK 独立校验 | hash 与 manifest 一致、v2 签名验证通过、包版本正确 | apk-verification.json、apk-signature.log、apk-badging.log |
| API 34 x86_64 模拟器 | 安装 Success、两次 COLD 启动 Status ok、进程存活、版本 1.14.11 / 176；所采 AndroidRuntime:E / flutter:E 无内容 | emulator-smoke.json、emulator-install.log、emulator-launch.log、emulator-relaunch.log、emulator-package.log、emulator-ready.png |
| 组件演示渲染 | 单独 1 项通过；不计入上方 1606 | showcase-render.log、showcase_test.dart、showcase/frames.json |
| 构建输入及证据索引 | 构建输入逐文件 hash 与当前源码核对，附累计变更清单 | source-reconciliation.json、changed-files.json、evidence.json |

实际调用与环境：Flutter 3.44.5、Dart 3.12.2；使用 `D:/flutter344/flutter/bin/cache/dart-sdk/bin/dart.exe` 调用同 SDK 的 `flutter_tools.snapshot`，测试参数 `test --no-pub --reporter expanded`，分析 `analyze --no-pub`。保持既有 package_config，未做 pub get 或升级。全量命令用时约 125 秒。

构建沿用 `tool/release/build_android_apks.ps1 -Mode Normal -BuildType Debug -NoPub`。本次忽略目录中的 launcher 仅把 flutter 命令转交同一已缓存 snapshot；JAVA_HOME 在构建子进程使用现有 Android Studio JBR，SDK 为 `D:/Androidstudio2`，没有修改系统环境或项目构建规则。

全量范围包括既有 SmartFollow、recognition、copy、tasks、导航、设置及其他 test/ 测试。没有执行真实设备 integration_test、独立 Android 原生单测、Release 构建或真实盒子验收。三项跳过与 strict baseline 的详细原因见验收矩阵。

## 3. 安装包与来源

独立交付目录：`build/smart-follow/sf-b7/delivery/`。

| 字段 | 本次值 |
| --- | --- |
| APK | BirdBox-1.14.11-176-debug.apk |
| 版本 / 包名 | 1.14.11+176 / deckers.thibault.aves.bird |
| 构建完成 | 2026-10-29 22:09:21 +08:00 |
| APK 字节数 | 254832140 |
| APK SHA-256 | 9c9d471aaaae6f577298b9caaf2c26f34f08ccc1c678be0ddf16fd0d5f58510e |
| 签名证书 SHA-256 | 542da17c96faff1e6c346e9eca9546b09331633b9bfb9ae60c36675e320081b8 |
| 源码指纹 | ce3cbe7cfd4d745a27ec31a73b049066fc776d208c569c2e30da877c94143b16 |
| 构建输入数 | 988；详见 source-files.sha256 |
| Build ID | ble-20261029T140617247Z-ce3cbe7cfd4d（沿原脚本命名，不代表 BLE 联合验收） |
| 构建类型 | Normal / bird / Debug；Android Debug 证书；releasable=false |
| SDK / ABI | min 24 / target 36；arm64-v8a、armeabi-v7a、x86_64 |

本次没有升版本；同版本历史包应按 hash / Build ID / 源码指纹区分。HEAD 本身不包含未提交的 SF-B0～SF-B6，因此不能只凭 Git SHA 复现本包。保留全部工作区并使用 source-files.sha256 核对。源码指纹按原脚本规则排除 docs/doc/.run 和 README；最终文档更新不改变该构建输入。

原脚本输出位置 `build/delivery/1.14.11-176/normal/debug/` 中原有旧版 phone-acceptance.json、delivery-verification.json，**不是本次证据**。已保留旧文件；本次独立交付目录只复制新 APK、build-manifest.json、source-files.sha256 并附本批文档，没有混入旧手机验收记录。

## 4. 变更清单与兼容行为

累计修改/新增 Dart 文件 **59 个**，逐文件状态及 SHA-256 在 `changed-files.json`，Dart 路径另见 `changed-dart-files.txt`；可审阅模块清单附于本文末尾。它们是 SF-B0～SF-B6 累计内容，不是本批重新实施 59 个文件。

| 模块 | 累计变化 |
| --- | --- |
| app / jobs / job models | 入口依赖、带设备身份的路由参数、原子 analysis+smart_follow 请求及幂等键传递 |
| recognition / copy / tasks | 四态入口、双模式、配置确认、已有任务接管、识别结束与排空导航衔接；普通复制范围继续保留 |
| smart_follow/entry | 决策、配置、创建服务、未知结果恢复；异步设备/任务变化重新确认 |
| smart_follow/run | 最新识别事实、前台/路由恢复、完成页与信息操作接线 |
| smart_follow/finish | C1 完成统计、M1 提示、M2 预览授权、M3 父任务/报告/历史和再次变化 |
| repository / domain / fake | 报告字段存在性、权威版本保护、设备隔离历史及本地 fixture 支持 |
| test | 入口/配置/创建/HTTP/恢复/设备隔离/完成/metadata/正式导航回归 |

旧盒子、缺失/false capability、404 或读取失败不开放 SmartFollow 执行入口。metadata 还需真实 availability；正式包没有强制开启开关。普通 recognized_assets 继续冻结；selected_assets、filtered_assets、batch_all_assets、media_full_backup 不转成持续跟随。第 13 条普通 batch_all_assets 后续信息更新是已登记缺口。

创建使用两条既有路径；App 不循环创建普通复制任务模拟跟随。原子请求和运行中开启均保留同次意图的幂等键与请求体；结果未知时查询原结果，不换键盲建。事件只唤醒读权威快照，前后台/重连补拉，错误退避，不用本地计时器增加进度。

## 5. 演示资料

- `showcase/index.html`：13 帧中文图集；`showcase/smart-follow-components.gif`：52 秒组件动画。
- 每页挂载真实页面组件并注入 fixture，都标注“本地组件演示 · Fixture · 非真机/真实盒子”。不是连续 E2E 操作，也不是盒子录屏；真实连续录屏仍待补。
- `emulator-start.png`：安装后的首次附近设备权限提示；`emulator-ready.png`：授权后冷启动的“查找盒子”。这是实际 APK 模拟器截图，但没有 SmartFollow 正式服务连接。
- 前序批次保留 360dp / 中文 1.5 倍文字的边界布局证据；本批图集不替代这些测试。

## 6. 未通过项与后续顺序

1. 先取得第 13 条普通 CopyJob 到信息更新上下文的正式关联，补 App 普通全量复制完成后的提示和 M2/M3 接线，以及“只更新信息、零重复制”回归。这是剩余 App 工作。
2. 接收 SmartFollow 正式 OpenAPI、事件 schema、错误表及问询十项回执，核对字段和关联保证；未确认统计保持未提供。既有 birdbox-v1 冻结校验通过不等于新增扩展协议就绪。
3. 取得正式环境后执行矩阵 R 项并补连续录像，包含手机杀进程、双端接管、超时、热拔插、真实 committed 和物理更新；按失败结果补 App 适配。
4. 严格基线 13 项仍失败，真实 capability 未验收前由后端保持 false；正式 Release 继续走原有门禁。本轮没有后端代码、迁移、固件或部署工作。

## 7. 回滚与交接

联调阶段可由后端关闭 smart_follow_copy / metadata capability，App 会关闭对应执行入口；关闭能力不等于取消盒子上已存在的会话，已有任务由其权威动作和状态处理。不得通过清空 App 数据或重新建任务“回滚”已经复制/更新的文件。

客户端需要回退时使用事先核对 hash 的上一个受信任包，并确认签名兼容；同版本用 APK hash 区分。不要直接卸载来解决签名冲突，以免丢失本地设置和找回引用。没有验证任意历史 APK 的数据兼容性，不承诺无条件降级。

源码回退按 SF-B0～SF-B6 文件和对应记录逐项处理，本批只新增文档和忽略目录证据；不要对整个工作区执行 reset/clean。保留先前改动，未提交 Git、未创建 PR、未发布正式 Release。

## 8. 累计 Dart 文件明细

以下清单由当前 Git tracked diff 与 non-ignored untracked 文件合并生成，状态/哈希以证据 JSON 为准。

- `lib/bird_companion/app/app_dependencies.dart`
- `lib/bird_companion/app/app_router.dart`
- `lib/bird_companion/app/bird_route_args.dart`
- `lib/bird_companion/core/models/job_models.dart`
- `lib/bird_companion/features/copy/presentation/copy_confirmation_page.dart`
- `lib/bird_companion/features/jobs/data/job_api.dart`
- `lib/bird_companion/features/jobs/domain/job_create_requests.dart`
- `lib/bird_companion/features/recognition/recognition_widgets.dart`
- `lib/bird_companion/features/smart_follow/data/fake_smart_follow_backend.dart`
- `lib/bird_companion/features/smart_follow/data/smart_follow_repository.dart`
- `lib/bird_companion/features/smart_follow/domain/smart_follow_metadata.dart`
- `lib/bird_companion/features/smart_follow/domain/smart_follow_models.dart`
- `lib/bird_companion/features/smart_follow/presentation/entry/smart_follow_configuration_controller.dart`
- `lib/bird_companion/features/smart_follow/presentation/entry/smart_follow_configuration_form.dart`
- `lib/bird_companion/features/smart_follow/presentation/entry/smart_follow_creation_service.dart`
- `lib/bird_companion/features/smart_follow/presentation/entry/smart_follow_entry_decision.dart`
- `lib/bird_companion/features/smart_follow/presentation/entry/smart_follow_entry_section.dart`
- `lib/bird_companion/features/smart_follow/presentation/entry/smart_follow_mode_panel.dart`
- `lib/bird_companion/features/smart_follow/presentation/entry/smart_follow_start_panel.dart`
- `lib/bird_companion/features/smart_follow/presentation/finish/smart_follow_completion_controller.dart`
- `lib/bird_companion/features/smart_follow/presentation/finish/smart_follow_completion_page.dart`
- `lib/bird_companion/features/smart_follow/presentation/finish/smart_follow_metadata_controller.dart`
- `lib/bird_companion/features/smart_follow/presentation/finish/smart_follow_metadata_preview_page.dart`
- `lib/bird_companion/features/smart_follow/presentation/finish/smart_follow_metadata_section.dart`
- `lib/bird_companion/features/smart_follow/presentation/finish/smart_follow_metadata_update_controller.dart`
- `lib/bird_companion/features/smart_follow/presentation/finish/smart_follow_metadata_update_page.dart`
- `lib/bird_companion/features/smart_follow/presentation/run/smart_follow_run_page.dart`
- `lib/bird_companion/features/tasks/presentation/pages/batch_setup_page.dart`
- `lib/bird_companion/features/tasks/presentation/repository_task_experience_controller.dart`
- `lib/bird_companion/features/tasks/presentation/task_experience_root.dart`
- `test/bird_companion/features/recognition/recognition_test.dart`
- `test/bird_companion/features/smart_follow/entry/configuration_fixtures.dart`
- `test/bird_companion/features/smart_follow/entry/creation_fixtures.dart`
- `test/bird_companion/features/smart_follow/entry/smart_follow_configuration_controller_test.dart`
- `test/bird_companion/features/smart_follow/entry/smart_follow_configuration_form_test.dart`
- `test/bird_companion/features/smart_follow/entry/smart_follow_creation_service_test.dart`
- `test/bird_companion/features/smart_follow/entry/smart_follow_entry_decision_test.dart`
- `test/bird_companion/features/smart_follow/entry/smart_follow_modes_test.dart`
- `test/bird_companion/features/smart_follow/entry/smart_follow_start_panel_test.dart`
- `test/bird_companion/features/smart_follow/finish/completion_fixtures.dart`
- `test/bird_companion/features/smart_follow/finish/metadata_fixtures.dart`
- `test/bird_companion/features/smart_follow/finish/metadata_update_fixtures.dart`
- `test/bird_companion/features/smart_follow/finish/smart_follow_completion_controller_test.dart`
- `test/bird_companion/features/smart_follow/finish/smart_follow_completion_http_test.dart`
- `test/bird_companion/features/smart_follow/finish/smart_follow_completion_navigation_test.dart`
- `test/bird_companion/features/smart_follow/finish/smart_follow_completion_page_test.dart`
- `test/bird_companion/features/smart_follow/finish/smart_follow_metadata_controller_test.dart`
- `test/bird_companion/features/smart_follow/finish/smart_follow_metadata_http_test.dart`
- `test/bird_companion/features/smart_follow/finish/smart_follow_metadata_navigation_test.dart`
- `test/bird_companion/features/smart_follow/finish/smart_follow_metadata_page_test.dart`
- `test/bird_companion/features/smart_follow/finish/smart_follow_metadata_update_controller_test.dart`
- `test/bird_companion/features/smart_follow/finish/smart_follow_metadata_update_http_test.dart`
- `test/bird_companion/features/smart_follow/finish/smart_follow_metadata_update_navigation_test.dart`
- `test/bird_companion/features/smart_follow/finish/smart_follow_metadata_update_page_test.dart`
- `test/bird_companion/features/smart_follow/smart_follow_atomic_http_test.dart`
- `test/bird_companion/features/smart_follow/smart_follow_device_isolation_test.dart`
- `test/bird_companion/features/smart_follow/smart_follow_run_recovery_test.dart`
- `test/bird_companion/features/tasks/production_task_r0_baseline_test.dart`
- `test/bird_companion/tasks/repository_task_experience_controller_test.dart`
