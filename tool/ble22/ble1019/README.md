# BLE1019乙6验收与证据工具

本目录用于2026-10-19返修要求：主文档§6十二项、增量文档§8六行，覆盖MIS-AL00、PKC110、PMA110。手机型号只用于验收矩阵，不进入App核心协议逻辑。

**当前已适配e160043ef的四个Java接口并完成离线验证，原生物理释放语义和真机联合验收仍待确认，不能据此发布APK。** 参见[当前接口契约](../../../docs/contracts/ble-pairing-preflight-1019-dart-native-contract.md)。本工具不会连接手机、安装/构建APK、调用createBond、忘记设备或修改板端。旧的`../run_phone_round.ps1`是FIN-AL60/vivo虚拟外设基线，不能直接当作本轮真实盒子验收。

## 1. 创建本轮与离线回归

项目根目录，PowerShell 7.4+，Python仅用标准库：

```powershell
$python = "$env:USERPROFILE/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe"
& $python tool/ble22/ble1019/acceptance.py init --round-id ble1019-20261020-r1
$round = 'outputs/ble22/ble1019-20261020-r1'
./tool/ble22/ble1019/run_offline.ps1 -RoundDirectory $round -Python $python -PlanOnly
./tool/ble22/ble1019/run_offline.ps1 -RoundDirectory $round -Python $python
```

有其他Python/Flutter路径时显式传`-Python`、`-FlutterSdk`。`-SkipFlutter`只运行工具检查，报告会标记Flutter未执行。每次检查生成独立`checks/offline-时间-随机后缀/`，记录原始退出码、超时、日志及SHA-256。默认运行本目录Python测试、原BLE22 Python/PowerShell测试、BLE19接收器测试、Flutter连接/错误映射/契约回归、静态分析、契约校验与验收汇总。不会自动执行Gradle或手机测试。

`init`生成`round.json`、`matrix.json`、`matrix.md`、`source-snapshot.json`、`build.template.json`及空的runs/artifacts/checks目录。源码快照是审查范围内的当前文件哈希，**不是正式构建使用的完整源码指纹**。目录存在时拒绝覆盖；旧回归/旧诊断不会被复制为新结果。

主十二项与增量六行独立登记，Wi-Fi三态展开，共51个手机/场景单元、264轮，未去重。main-6.n表示§6第n项，不是§6.n子章节。如双方决定同一轮覆盖多个要求，应先修改有审查记录的矩阵和工具规则，不可复制诊断凑数。

## 2. 合流前后检查顺序

1. 当前：完成离线检查，所有正式验收单元保留not_run/pending。
2. 甲方合流：共同确认四个Java ABI及通知generation；验证A2/A3/A4/A6/A7/A8，补齐乙5原生快照、有效GATT复用、关闭完成语义。
3. 运行原生回归，保留完整结果，命令不加`--offline`：

   ```powershell
   Push-Location android
   ./gradlew.bat :app:testBirdDebugUnitTest --console=plain
   Pop-Location
   ```

4. 甲方冻结通用协议实现，保存源码diff、新增文件、完整构建指纹和APK，再登记候选。
5. 先按主文档§6.1做已绑定连接、冷启动、蓝牙开关、盒子重启及交替连接的最小基线。正式矩阵中同类轮次仍须逐项有证据。
6. 真盒子×三机型执行matrix.md。每轮单独导出诊断、记录人工观察和板端证据。任意失败先导出完整诊断再动“忘记设备”，保留不对称现场；失败记录不能覆盖。

文档声称板端预检已部署不等于本轮已重新核验；板端版本、响应封装、两阶段同peer约束和广告恢复应与当前实机一起确认。没有支持新预检的模拟盒子时，Dart Fake只算离线验证，不能标为虚拟外设联调或真机通过。

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
