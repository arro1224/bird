# T1-B7 当前拓扑证据与回交索引

vivo X20 / Android 8.1.0 / API27 为客户端；华为前台运行独立拍鸟模拟盒子。**当前拓扑的可执行部分已实测；指定双机与真盒子验收仍待完成，任务一不关闭。**

[实施记录](../../doc/任务/任务一_T1-B7_vivo与模拟盒子联调记录_2026-11-23.md) · [检查摘要](checks.json) · [18例明细](case_results.json)

## 本轮实测

- 正常候选完成真实 BLE 与 HTTP/WS 验证；三轮查找/重扫/重进，共六次扫描，当前业务卡片唯一、蓝牙状态保留。
- 短暂退后台返回仍为同一进程，原 GATT1/1 复用；相册、任务、设备切页及大图显示已取证。
- 蓝牙关闭操作后仍为 ON，未取得有效断链，原页恢复不计通过。AP入退及两端旧网恢复因模拟外设/API限制未测。
- 设备集成的结果与模拟边界见 [integration_results.json](integration_results.json)。中断/失败尝试保留，不并入最终通过数。

Flutter测试运行器自动卸载了同包名测试应用，导致原App本地状态被清除，已向用户说明。正常候选已重新安装并核对哈希；重新连接结果见最终环境。未保存完整App数据备份，不能宣称全部偏好或凭据已恢复。

## 候选与源码

[正常 bird Debug APK](../../build/delivery/task1_B6_20261123_01/BirdBox-1.14.11-176-debug.apk) · [原构建清单](build-manifest.json) · [构建时确切文件哈希](source-files.sha256) · [535个编译输入核对](compiled_inputs.json)

`build_id=ble-20261123T095328618Z-56fb4f811179`。APK SHA256：`684e38a5aaa8e66276492e5b9cb839581ba4a7a47c21cb175da40122d5b81a2e`。Debug、build_dirty=true、releasable=false。B0～B7保持工作区，由用户统一提交 thirdtime。B7增加测试脚本/证据和测试等待修正；没有修改此候选的535个应用编译输入。

## 证据

- [最终App去敏ZIP](final_phone.zip)、[App界面独立哈希接收记录](final_phone.receipt.json)、[完整性及受控窗口检查](final_inspection.json)。原生文件选择器取消，无外部分享。
- [三轮操作](a15_r2_rounds.json)、[六次扫描窗口](discovery_diagnostics.json)、[前后台进程](foreground.json)、[去敏操作记录](ui_actions.jsonl)。
- [第三轮完成](screenshots/a15_r2_3_after.png)、[返回前台](screenshots/lifecycle_after.png)、[真实网络状态读取](screenshots/network_settings_ready.png)、[大图显示](screenshots/media_photo_initial.png)、[App文件哈希](screenshots/final_receipt_hash_ui.png)。
- [恢复后业务与蓝牙验证](screenshots/restoration_verified.png)、[最终在线相册](screenshots/final_restored_album.png)。
- [初始环境](environment.json)、[WLAN故障](vivo_wifi_before.json)、[一次开关尝试](wifi_toggle_attempt.json)、[用户重启后](vivo_wifi_after_reboot.json)、[结束环境与候选恢复](final_environment.json)。
- [初次脚本停止](discovery_rounds.json)、[旧接收校验器失败](baseline_verify.json)、[基线独立检查](baseline_inspection.json)。详细原因见实施记录 TOOL-01/02/03。

ZIP是本机有界保留记录，含历史且有裁剪；成功媒体请求细节未完整保留。不把事件未出现当无限历史的零次证明，也不把旧错误计作当前轮次。原始系统设置、桌面及XML留在被忽略的 build/task1_B7_20261123_01/private，未整包回交。

## 18例当前状态

| 用例 | 当前拓扑结果 | 范围与缺口 |
| --- | --- | --- |
| T1-01 首次自动直连 | 条件不足 | 当前模拟盒子不提供 AP，vivo API27 不支持现实现的系统请求；已保存认证的 STA 连接不算首次 AP |
| T1-02 同盒退出再进至少三次 | 条件不足 | 执行的是三轮查找/重扫/返回；没有执行三轮 AP 退出和重新接入 |
| T1-03 重开 App 与重启盒子 | 待补测 | 本轮未安排受控盒子重启或 App 冷启动验收；WLAN 故障后的手机重启不代替该例 |
| T1-04 相册→任务→设备 | 当前拓扑子集通过 | 真实候选切页和大图显示正常，HTTP/WS 验证成功；没有 AP 请求可验证其释放计数，成功媒体请求未完整保留 |
| T1-05 拒绝/取消/撤权限/忘记网络 | 条件不足 | 没有 AP 系统请求，不删除现有网络、配对或权限来制造首次条件 |
| T1-06 无互联网 AP 与默认路由/VPN | 条件不足 | 本轮为同 LAN，未建立无互联网盒子 AP、蜂窝或 VPN 对照 |
| T1-07 OPPO 自开热点冲突 | 未执行指定机型 | 无 OPPO 客户端，vivo 不替代 OPPO 专项 |
| T1-08 连点/迟到回调/离页/切设备 | 待补测 | 真实候选仅做正常导航；模拟 UI 用例不能代替系统请求并发与迟到回调 |
| T1-09 AP关闭/DHCP/错误设备 | 条件不足 | 外设不提供 AP，未注入真实 DHCP 或身份不符环境 |
| T1-10 后台/锁屏/进程回收 | 当前拓扑部分通过 | 仅 HOME 约3秒后回前台，PID一致、GATT1/1复用；锁屏及系统进程回收未执行 |
| T1-11 Wi-Fi在线时原页恢复断开的BLE | 未形成有效断链 | 关闭命令和系统开关尝试后系统仍 ON；未确认断链，不计原页恢复通过；也没有 AP 状态 |
| T1-12 HTTP不通而BLE可用 | 待补测 | 没有独立阻断 HTTP 的可控外设；早期波动不代替定向场景 |
| T1-13 恢复控制连点/取消/离页/重试 | 待补测 | 没有形成可确认的断链前置，不计恢复交互通过 |
| T1-14 停止AP与两端恢复旧网 | 条件不足 | 模拟盒子不支持切模式或旧网恢复，不能发送不存在的 AP 停止主线 |
| T1-15 查找/重扫/重进/前后台 | 当前拓扑通过 | 3轮、6次实际扫描；每轮当前卡片唯一且业务/BLE在线；前台同步复用GATT1/1，窗口关键事件无丢失且未记录拆链；首次配网不在本轮 |
| T1-16 停广告及历史断链区分 | 待真外设对照 | 未独立停止广播同时保留 HTTP/GATT；集成模拟场景仅证明 widget 行为 |
| T1-17 任务二入口与恢复三态 | 设备集成范围见结果 | 设备测试使用真实SSID通道/二维码解码与模拟repository；不包含真盒子入路由器、另一手机热点与真实恢复三态 |
| T1-18 已有持续复制详情 | 前置条件未满足 | 任务页显示无运行中的盒子任务；未执行持续复制对照 |

OPPO PMA110、华为 MIS-AL00 客户端各例均未执行；本轮华为是模拟外设。后续需支持当前AP请求API的客户端与真盒子，补齐A17/A18及规定矩阵后再关闭正式验收。
