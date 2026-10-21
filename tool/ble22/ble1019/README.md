# BLE1019乙6验收与证据工具

本目录用于2026-10-19返修要求：主文档§6十二项、增量文档§8六行，覆盖MIS-AL00、PKC110、PMA110。手机型号只用于验收矩阵，不进入App核心协议逻辑。

**当前基线为thirdtime的d0eb144e67e634bfd6d43830f3f9e6d4ab028c82叠加乙第一至三批及原生补充工作区改动。** 本轮已补普通disconnect终态实例和trace、快速路径、lastRelease查询及超时非成功语义，pre_connect_reset超时停止本次拨号；仍需甲复核及独立外设预联调。参见[当前接口契约](../../../docs/contracts/ble-pairing-preflight-1019-dart-native-contract.md)。本工具不会连接手机、安装/构建APK、调用createBond、忘记设备或修改板端。旧的`../run_phone_round.ps1`是FIN-AL60/vivo虚拟外设基线，不能直接当作本轮真实盒子验收。

## 1. 创建本轮与离线回归

项目根目录，PowerShell 7.4+，Python仅用标准库：

```powershell
$python = "$env:USERPROFILE/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe"
& $python tool/ble22/ble1019/acceptance.py init --round-id ble1019-20261021-b3-r1
$round = 'outputs/ble22/ble1019-20261021-b3-r1'
./tool/ble22/ble1019/run_offline.ps1 -RoundDirectory $round -Python $python -PlanOnly
./tool/ble22/ble1019/run_offline.ps1 -RoundDirectory $round -Python $python
```

有其他Python/Flutter路径时显式传`-Python`、`-FlutterSdk`。`-SkipFlutter`只运行工具检查，报告会标记Flutter未执行。每次检查生成独立`checks/offline-时间-随机后缀/`，记录完整命令、工作目录、原始退出码、超时、日志及SHA-256。默认运行本目录Python测试、原BLE22 Python/PowerShell测试、BLE19接收器测试、Flutter连接/错误映射/契约回归、设置页与App启动/恢复集成回归、静态分析、契约校验与验收汇总。连接目录同时覆盖STA、直连HTTP接管和全局会话恢复。不会自动执行Gradle或手机测试。

每次实际检查保存`source-before.json`和`source-after.json`，仅当commit及审查范围指纹在运行前后相同且各检查成功，才将`offline_checks_passed`设为true。快照包括App共享代码、Java源码及单测、Dart核心/设置页/App测试和本轮工具，包含未跟踪的新文件。它是审查范围指纹，仍不是完整发布构建指纹；运行期间改源码要重新检查。

两项真实Python HTTP集成用例分别需要`BIRDBOX_DIRECT_AP_BASE`和`BIRDBOX_STA_BASE`，还需独立后端源码和运行环境。未配置时必须记录跳过原因。Dart Fake或本地fixture不替代板端和手机验收。

`init`生成`round.json`、`matrix.json`、`matrix.md`、`source-snapshot.json`、`build.template.json`及空的runs/artifacts/checks目录。源码快照是审查范围内的当前文件哈希，**不是正式构建使用的完整源码指纹**。目录存在时拒绝覆盖；旧回归/旧诊断不会被复制为新结果。

主十二项与增量六行独立登记，Wi-Fi三态展开，共51个手机/场景单元、264轮，未去重。main-6.n表示§6第n项，不是§6.n子章节。如双方决定同一轮覆盖多个要求，应先修改有审查记录的矩阵和工具规则，不可复制诊断凑数。

## 2. 合流前后检查顺序

1. 乙第一至三批：完成当前工作区的离线检查，所有正式验收单元保留not_run/pending。旧事务、同代际换实例、retiring、断开完成前门禁、首错及显式恢复须有行为断言。
2. 原生补充已由乙代补：普通disconnect终态冻结退役generation/instance/trace，补已知断链快速路径及lastRelease查询，超时不幂等成功，pre_connect_reset超时或close异常停止本次dial。代码与Dart接入已回归，仍需甲复核及独立外设验证；旧缺口的安全失败测试不能代替新成功路径或手机证据。
3. 独立运行原生回归，保留本次XML报告和完整日志。需要实际重执行、避免UP-TO-DATE时使用`--rerun-tasks`；命令不加`--offline`：

   ```powershell
   Push-Location android
   ./gradlew.bat :app:testBirdDebugUnitTest --console=plain --rerun-tasks
   Pop-Location
   ```

4. 契约缺口闭合并通过外设预联调后，由甲乙共同冻结通用实现；乙汇总源码diff、新增文件、完整构建指纹和APK，再登记候选。甲修订后须基于最终源码重跑受影响回归。
5. 先按主文档§6.1做已绑定连接、冷启动、蓝牙开关、盒子重启及交替连接的最小基线。正式矩阵中同类轮次仍须逐项有证据。
6. 真盒子×三机型执行matrix.md。每轮单独导出诊断、记录人工观察和板端证据。任意失败先导出完整诊断再动“忘记设备”，保留不对称现场；失败记录不能覆盖。

文档声称板端预检已部署不等于本轮已重新核验；板端版本、响应封装、两阶段同peer约束和广告恢复应与当前实机一起确认。没有支持新预检的模拟盒子时，Dart Fake只算离线验证，不能标为虚拟外设联调或真机通过。

### 已有手机模拟盒子的能力检查

`integration_test/ble1019_existing_peripheral_test.dart`可作为独立调试入口构建，使用生产BLE通道读取现有外设的设备信息、真实native bond及公开预检能力；默认目标为BirdBox-B1E11001及其完整测试device_id，可通过BLE1019_PEER_NAME/BLE1019_PEER_ID构建参数指定。

该入口不发起系统配对、不清理绑定、不修改外设。仅当能力声明为true且手机native bond为NONE时执行生产prepareConnection；旧外设或已绑定条件单独记录，`e09_preflight_completed=false`，不能把检查执行完成当作0007验证成功。收尾只释放本入口拥有或精确检查过的实例。

结果保存到App私有目录`files/ble1019-existing-peripheral-result.json`，含实际App构建身份与APK哈希、外设固件/能力、初始bond、诊断、createBond调用数及收尾状态。createBond计数不替代独立观察系统弹框次数。每次启动前只清除这一检查入口自己的旧结果，并绑定本次安装APK哈希；保留失败记录。运行后换回正常`lib/main.dart`入口，保留应用数据。该调试构建不登记为正式候选。

2026-10-21使用FIN-AL60读取vivo现有模拟盒子的本地记录位于`outputs/ble22/ble1019-20261021-e09-existing/`：实际固件phone-simulator-1.0.0，pairing_preflight_v1=false，手机已绑定。已完成扫描、连接和公开信息读取；新预检链路尚未执行。模拟盒子独立项目的源码及应用不在本次项目4修改范围内。

## 3. 登记正式候选APK（未来合流后执行）

```powershell
./tool/ble22/ble1019/register_build.ps1 -RoundDirectory $round `
  -Apk 'D:/候选路径/formal.apk' -ApkSha256 '<独立确认的64位SHA256>' `
  -GitCommit '<构建commit>' -SourceFingerprint '<完整构建源码指纹>' -BuildId '<唯一构建ID>'
```

这条命令只读取APK、用aapt检查正式包名和version name/code、复制到本轮artifacts、绑定最终APK哈希、保存原round.json并登记build。不会安装、启动或构建。若已登记则拒绝覆盖，应开新轮次。GitCommit/SourceFingerprint/BuildId取自该APK的真实冻结构建记录，不能拿今天的审查快照替代。

## 4. 每轮证据记录

```powershell
& $python tool/ble22/ble1019/acceptance.py new-run $round --case P03 --phone huawei_mis_al00 --iteration 1 --kind real_phone_real_board
```

目录固定为`runs/P03-huawei_mis_al00-01/`，带`evidence.json`及人工/板端模板。kind必须显式选择`real_phone_real_board`、`virtual_peripheral`或`offline_fixture`；后两者不计正式通过。

操作员实际执行后：

- 将App原样导出的JSON/ZIP放入该目录，保留App界面独立显示的最终文件SHA-256，不修改原文件；缺失关键记录的导出不算完整证据。
- 填写`operator.template.json`后另存`operator.json`：观察人别名、带时区时间、真实机型/SDK/稳定物理手机别名、真实原生bond基线、板端起始记录、最终UI/error code、是否首次用户动作成功、是否要求双端忘记才能恢复、逐动作实际系统框次数、各项人工确认。不要写完整设备地址或私密身份。
- `user_actions`例子：`[{"id":"connect-1","pairing_dialogs":1}]`。快速点击M10还需`input_taps>=2`；M11需两条动作，首次`outcome=failed`，第二条`kind=manual_retry,outcome=succeeded`，每次动作弹框最多一次。两次输入不等于允许自动重复配对。
- M12-same/different/none填写对应`wifi_state`，只记录环境，不由工具切换网络。
- 独立记录`preflight_dialogs=0`；不得从createBond调用次数推断系统实际弹框次数。P06在fresh预检就绪处截断弹框计数，期望0；整条非对称业务流程另按M03/M04/P03核对一次弹框。
- 板端在不暴露MAC/token/密码的前提下保留当前peer及其他peer、prepare/confirm、ACK先于移除、广告恢复等事实；填写`board.template.json`另存`board.json`。phone_alias与operator一致，paired_before/bonded_before与独立板端观察一致，source_log_sha256绑定本轮脱敏board.log。
- 为evidence.artifacts填诊断、operator.json、board.json、board.log的**相对于本轮根目录**的path与sha256，确认实际执行后将status从not_run改为observed。缺字段不能填true凑数。

生成并核对已有文件引用（仅计算/比对哈希，不复制文件或填写通过状态）：

```powershell
& $python tool/ble22/ble1019/acceptance.py reference $round --file 'runs/P03-huawei_mis_al00-01/diagnostic.zip' --sha256 '<App显示的最终文件SHA256>'
& $python tool/ble22/ble1019/acceptance.py check-run $round "$round/runs/P03-huawei_mis_al00-01/evidence.json"
```

接收检查复用BLE19的JSON/ZIP完整性、分包SHA和关键保留统计，额外检查原生证据、prepare/confirm/fresh request匹配、同逻辑attempt、新generation、预期断链及人工弹框事实。同步ACK后的断链可能先于“Future恢复后写入的result诊断”出现在日志中，校验不会据此错误判定ACK迟到。

对包含`gatt_release_requested`的新版诊断，每个请求还必须有后到的同flow/trace、generation、instance的Dart确认或显式恢复结果。单独的原生`teardown_completed`、幂等事件、其他实例或其他flow的成功都不能使未完成释放通过校验；未完成返回`release_completion_unconfirmed`。这项文件检查仍需与人工和板端证据联合复核。

工具拒绝reset_token及其hash、密码/授权字段和常见完整地址；输出错误只给固定原因。扫描器不能识别任意无标签不透明秘密，因此仍须执行App白名单脱敏、人工复核；不要把原始BlueZ/MAC日志放入交付目录。接收文件完整不代表真实行为通过，板端及手机观察需要联合复核。

## 5. 汇总和交付清单

```powershell
& $python tool/ble22/ble1019/acceptance.py summarize $round
& $python tool/ble22/ble1019/acceptance.py summarize $round --require-ready
```

普通汇总允许展示待验状态，退出0不代表验收通过。`--require-ready`缺项返回2，结构/文件错误返回1。check-run不通过返回1。新建记录是not_run，不能计通过。重复trace/诊断不能充当另一轮；同一手机别名应稳定，不允许同一物理别名覆盖不同型号。

round.json的deliverables填非空文件引用：源码diff及新增文件清单、原生单测、Dart报告、逐项验收报告、成功非对称诊断、取消诊断、前后台GATT诊断、App/板端改动与未改项说明。signoffs由双方实际审查后填写`{confirmed:true,reviewer_alias:"…",evidence:{path:"…",sha256:"…"}}`，包括ABI、原生single-flight/幂等清理、首错、原生GATT释放/前台同步、无品牌分支、无自动重复配对、Dart首错保真。

所有矩阵单元满足轮次且没有失败/缺项、交付物和签字齐备，才标记ready_for_joint_review。工具始终保持releasable=false，最终发布仍需双方审核真实证据。既有历史回归结果不能抵消本候选的失败。

当前Dart/原生源码及新文件的审查包可先生成，不依赖APK或手机：

```powershell
& $python tool/ble22/ble1019/acceptance.py export-review $round --label dart-b0-b6
```

输出changes.patch、source-snapshot.json、manifest.json，包含范围内未跟踪的新文件；同名审查包拒绝覆盖，导出前后核对源文件未变化。它仅是当前工作区审查材料，不代替合流后的正式构建源码指纹，也不自动填写交付验收通过。
