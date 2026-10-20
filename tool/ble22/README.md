# BLE-22 双手机工具

2026-10-19非对称预检返修使用独立的[BLE1019工具入口](ble1019/README.md)：MIS-AL00/PKC110/PMA110真盒子矩阵、离线回归、诊断接收与交付登记。下述旧双手机虚拟外设轮次不能替代1019真实盒子验收。

这些工具用于华为 FIN-AL60 与 vivo X20 的 App 预验收。手机虚拟外设与实际 BirdBox 的验收结果分别记录。BLE-22C-1 仅实施本地修正、工具和候选准备；离线检查与 APK 构建不会自动接机或执行 BLE。首绑新 GATT status 133 保持待关闭。

## 离线检查与构建

在项目根目录使用 PowerShell 7.4+：

```powershell
./tool/ble22/test_tools.ps1
python tool/ble22/test_tools.py
./tool/ble22/prepare_round.ps1 -RoundId ble22-20261012-round11
```

构建脚本顺序生成 transport、正式 bird、birdSim、虚拟外设四个 Debug APK，检查包名、版本、源码指纹并记录最终 SHA-256；目录已存在时拒绝覆盖。构建期间不要修改源码或同时启动其他 Flutter/Gradle 构建、驱动。`builds.json` 的 `built_not_phone_accepted` 只证明构建完成。

可通过参数指定 Flutter/Android/JDK 路径。birdSim 使用 `birdSim` flavor 和 `BIRD_SIMULATED_DEVICE_ID`；它与正式 bird 的包名不同。所有测试产物位于已忽略的 `outputs/ble22/<round>/`，工具自身保存在 `tool/ble22/`。

## 接机前与角色切换

BLE-22C 开始时核对序列号、型号、SDK、实际安装包 hash。恢复上一轮 vivo 临时日志标签为空；只处理能确认归属的旧 USB 转发。分别记录两端实际系统 bond，清 App 数据不能证明未绑定。

P1：华为运行 App，vivo 运行虚拟外设。P2：vivo 运行 App，华为运行虚拟外设。角色切换前停止上轮测试进程并核对服务、广播和绑定基线。只清理明确的 BirdBox 测试绑定；旧临时助手的泛化“忘记设备”操作没有移入自动运行器。需要首次绑定基线时在系统设备详情核对目标后取消配对，记录操作并由原生实际事件再次核验。

手机外设如使用公开系统请求设置 120 秒可发现窗口，单独记录为外设测试条件；不作为正式产品手工预配对要求。两机同时通过 USB 连接电脑是测试环境，P1/P2 是交替角色的无线测试。

## 运行 transport 场景

读取当前轮 `builds.json` 后传入明确的 APK 和 hash：

```powershell
$round = 'ble22-20261012-round11'
$directory = Join-Path 'outputs/ble22' $round
$builds = Get-Content (Join-Path $directory 'builds.json') -Raw | ConvertFrom-Json
./tool/ble22/run_phone_round.ps1 -RoundId $round -Role P2 -Scenario already_bonded `
  -AppSerial b502aabb -BoxSerial 2TX9K24619004426 `
  -AppApk (Join-Path $directory $builds.artifacts.transport.path) `
  -BoxApk (Join-Path $directory $builds.artifacts.virtual.path) `
  -AppSha256 $builds.app_sha256 -BoxSha256 $builds.box_sha256
```

`-AutoConfirm` 可处理已识别的测试 APK 安装和 App 侧目标配对确认。外设手机侧地址型弹窗只匹配本场 `connection_state_changed` 的对端地址哈希，要求 run_id、scenario、成功连接及唯一对端一致。哈希输入为 `run_id:大写蓝牙地址`，自有外设事件不记录地址明文。华为 `message_subhead` 已纳入识别；仅有地址文本而没有本场身份依据时保留人工操作。`-BoxPeerName` 可提供实际 App 手机蓝牙名称；不得把外设别名假定为 App 手机名称。系统 PIN 输入、无法识别的对端或歧义控件停止自动确认并留存失败。实际手机弹窗行为仍需 BLE-22C-2 验收。

运行器校验两端本地及已安装 APK hash，并按 transport 模式授予声明的蓝牙/位置权限。启动失败也生成 `evidence.json`；未执行测试时 `test_invoked=false`、`test_exit_code=null`。真实集成入口在扫描、初始连接/订阅及安全准备失败时收集实际事件。没有执行命令的失败不填充请求/命令完成事实。

受保护写入故障由明确场景注入。完成测试后读取该 `run_id` 的结果与当前外设事件；保存 App 实际生成的 JSON/ZIP 字节并核对文件 SHA-256。失败文件也尽量回收。转发、App 进程和临时文件仅清理本轮拥有的资源；失败清理会写入证据且不能登记 passed。VM 端点仅用于 Debug 和本机 ADB 转发的回环地址，两端实际 USB/TCP/IP 运输方式另记。

## BLE-22C-1 固化的续测准备

`device_alias` / `physical_device_alias` 基于手机 Android 序列属性；`adb_selector`、`adb_selector_alias` 和 `adb_transport` 分别记录调试选择器及 USB/TCP/IP 方式。同一 vivo 的 USB 与网络选择器不能充当两个端点。无法取得物理身份、离线或未授权均失败；P1/P2 按 FIN-AL60 SDK31 与 vivo X20 SDK27 校验。

安装后可用 `prepare_phone_pair.ps1 -AppSerial ... -BoxSerial ... -Role P2 -AppSha256 ... -BoxSha256 ... -RecordPath ...` 核对两端身份和已安装候选。显式加 `-StopOwnedApps` 时仅停止两端自有 App/外设进程，便于角色切换。此结果不证明未绑定或已广播；运行器再检查本场广播，初始绑定由实际原生事件确认。

`reset_test_bond.ps1` 只操作**当前已打开的测试对端详情页**：要求名称、当前运行地址哈希和唯一“取消配对”控件同时匹配。先人工核对并进入准确详情，再提供 `-Serial -RunId -PeerAddressHash -ActionLog`；页面缺少地址、未知确认弹窗或匹配失败时交由操作员处理。记录仅为点击动作，下一场仍须由原生起点确认未绑定，不宣称绑定已清理。

BLE-22C-2 已观察到两机详情页不展示地址。显式 `-UseObservedSettingsDetail` 可补充只读 `dumpsys activity top` 的精确详情 Fragment 参数：华为 DeviceProfilesSettingsActivity 的 `DEVICE_ID`，vivo SubSettings / DeviceProfilesSettings 的 `device`。只接受一个已知详情 Activity 中唯一完整地址，匹配本场已验证对端哈希及当前详情名称/唯一解绑控件；不依赖同名条目推断身份。优先取标签最近的可点击祖先；已实测的 vivo Preference 标签及祖先均报告不可点击时，只在精确 Native 身份匹配下点击唯一 `android:id/title` / TextView “取消配对”的观察范围，并记录该控件方式。没有可核对参数、地址不符或歧义仍拒绝操作，不调用隐藏解绑接口。

同名测试条目可能对应不同地址。`open_test_bond_detail.ps1 -Serial ... -RunId ... -PeerAddressHash ... -ActionLog ...` 只遍历已观察的同名测试条目及其唯一详情按钮，按有限页数滚动，在精确地址匹配并核对解绑控件后停在详情；此脚本本身不解绑。同名但地址不符只记录并返回，未找到则失败。随后再单独调用严格的 reset 工具。

`release_received_cache.ps1 -Serial ... -RoundDirectory outputs/ble22/<round> -AuditPath ...` 只释放已实际接收、接收报告与本地/手机 SHA-256 一致的 transport 缓存副本，保留电脑文件。要求 transport 进程已停止，在线检查必须成功；缺文件单独列入 missing，未校验/不同手机列入 skipped，不能由 Optional ADB 空值推导清理完成。旧证据没有物理身份时仅接受同一个已记录选择器，不推断 USB/网络映射。该工具不清空诊断目录、不修改生产配额。

正常首绑沿用 `-PairMode Confirm`。专项取消/超时使用 `-Scenario bond_first -PairMode Cancel` 或 `Timeout`：App 侧只取消目标弹窗或观察目标超时，外设侧仍按当前对端正常确认。`verify_pairing_stop.py` 要求实际动作日志、原生未绑定起点、一次 createBond、有界终止、零受保护写入与完整释放。专项结果写入 `pairing-stop-verification.json`，保留原始 `test_failed` / 退出码 1，正常成功次数为零。手工操作需通过观察到的 `operator_ui.ps1 -Mode Pair -PairMode ... -RunId ... -ActionLog ...` 留存；未知界面或缺少动作证据保持未完成。

运行器的 `-Python` 可指定可执行文件绝对路径；本地 Python 命令解析到 WindowsApps 别名时应使用实际 Python 路径。批次包内 `first-bond-run.template.json` 将两端基线、系统确认、新客户端、连接/MTU/服务/CCCD、终态、接收和清理分阶段记录；null 表示未观察，不能预填通过。

BLE-22C-2：自动配对回调由模块创建，脱离调用脚本作用域后仍可读取当前外设事件。普通“已配对的设备”列表不作为未知配对弹窗阻断测试。`-AutoConfirm -ForegroundPairingSettings` 是显式手机外设测试条件：观测到本场唯一对端连接后，两端各打开系统蓝牙设置一次，让厂商系统请求实际呈现，仍只确认身份匹配的系统弹窗，不提前手工绑定。环境操作与两端配对动作分别记录，不能变成正式产品预配对步骤。结束前采集自有 App/外设进程原生 BLE 日志；空日志、无进程或采集失败均如实标注。

手机 transport 入口在 testWidgets 记录基线前固定测试平台 semantics 为开启，套件结束恢复真实值，避免 UIAutomator 在测试中途开启 platform-owned SemanticsHandle 被误计为泄漏。保留测试自有句柄计数/释放断言；这不用于正式 App，也不作为生产辅助功能验收。`test_harness` 单独记录该条件。以前原生成功但框架退出码 1 的场次仍保留失败，不回写通过。

transport 收集到实际连接证据后，先同步写入自有测试结果临时文件并在 Android 文件系统上 rename 替换检查点，避免操作器读取半写 JSON。再执行事件存储、快照、导出构建身份与 Native 文件准备，每阶段分别记录 `export_stage`。导出异常保留 `export_failure_stage`；pending 检查点不是 prepared 文件，不登记接收或场景通过。驱动超时仍保留原始退出码，检查点仅用于定位，不替代真实 JSON/ZIP。

P1 曾在系统设置前台时停于 `export_build_identity`，将现有测试任务带回前台后才完成真实导出。显式设置前台条件下，操作器只有读取到同 run_id / scenario、自有包、已收集的实际 transport 结果及已知 pending 导出阶段后，才将仍在运行的测试 App 返回前台一次；校验前后 PID 一致，记录独立环境动作。缺检查点、未知阶段、旧请求或 prepared 结果均不触发，不提前越过正在配对的流程，也不改写失败结果。

## 正式 UI 安装和操作

正式权限验收使用 `install_phone_apk.ps1 -PermissionMode Ui`（默认），不带 `-g`、不执行 `pm grant`。在两机分别用真实系统界面拒绝/永久拒绝、进入设置授权并返回 App；之前 transport 已授权的手机需针对测试 App 在系统设置恢复所需权限基线，并记录实际状态。

`operator_ui.ps1` 支持 Install、Pair、Discover 和 AppButton 单步操作。AppButton 必须明确 `ExpectedPackage`、`ExpectedPageText` 和 `ButtonText`；只点击当前已观察到、唯一且可点击的对应控件。未知页面、系统覆盖窗口和输入不会被猜测。每个设备的界面操作用互斥锁串行执行，避免多个 uiautomator 会话冲突。阻塞决策记录于传入的 `ActionLog`，不保存无关通知文本。

正式入口步骤：扫描→选择虚拟外设→系统绑定→应用验证码→页面取消/返回；随后检查位置/蓝牙设置返回、前后台/锁屏和断链。系统 PIN 与应用验证码分开。正式成功/失败的扫描与连接完整历史需要通过 App「导出完整诊断」的保存、分享流程回收；集成入口连接事件导出不能替代此项。

P3 两机分别安装 birdSim，使用独立新 HTTP Mock 会话。设备 ID 与构建参数一致；分别测试错误/正确验证码、模拟 AP/STA 终态、HTTP `/health`、会话兑换和首页三 Tab。P4 使用正式 App，无外设，覆盖权限/位置、扫描取消/超时和诊断清理。这些网络模拟不证明真实盒子 AP/STA/DPP 或手机路由。

## 文件校验与汇总

```powershell
python tool/ble22/verify_received.py outputs/ble22/ble22-20261012-round11
python tool/ble22/summarize.py --input-root outputs/ble22 --output build/ble22-summary-review.json
```

接收端独立校验文件、payload SHA-256、字节数、JSON/ZIP 结构及关键记录完整性；无文件时报告 skipped，不能记成已验证接收。文件完整性通过与 BLE 场景通过分别记录。

汇总工具要求显式输出位置。更新已有汇总时保留暂停状态、当前轮与交接状态；不根据某个场景通过推导整个 BLE-22 通过，真实硬件始终 pending、不可发布。启动/导出/清理失败不能借旧 validation.log 登记通过。正式接收报告还应核对扫描历史范围和构建身份。
