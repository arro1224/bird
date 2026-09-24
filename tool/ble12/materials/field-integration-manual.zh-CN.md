# RC4-HF-BLE-12 外场联调手册

本目录是模拟候选交接包，不是正式发布包。收到后先运行根目录
`verify_package.ps1`；只有输出 `candidate_package_ready` 才表示文件未损坏。

## 使用顺序

1. 核对 `candidate-manifest.json` 中的 `candidate_id`、App APK SHA-256 和源码
   指纹，测试全程不得换包或重新编译。
2. 模拟环境具备 Android Emulator 36.5+ 时，依次执行 `success`、
   `auto_bond`、`fallback_once`、`disconnect_once`，每个场景使用独立清理后的
   AVD 数据。
3. 模拟结果只填写为 `evidence_kind=simulated`、`hardware_status=pending`。
4. OPPO、Huawei 和真实 BirdBox/K7 到位后，使用随包的 BLE-03 模板执行真实
   扫描、首次 Bond、加密写、通知恢复、同请求单次重试和同进程再次连接。
5. 真实证据通过 BLE-03 后，仍须执行 BLE-04 正式签名、审批和回滚门禁。

## 绝对禁止

- 不得把 AVD 截图、AVD 序列号或 PCAP 当作真实硬件通过证据；
- 不得把 debug APK 改名为 release APK；
- 不得编辑 JSON 状态来绕过校验；
- 不得在聊天、工单或仓库中粘贴配对码、Wi-Fi 凭据、Token、完整 MAC 或原始
  PCAP；
- 不得在没有新证据的情况下修改冻结的 BLE 生产文件。

原始 PCAP 可能包含链路层标识，只能在受控环境中本地保存。对外回传其相对路径
和 SHA-256，不回传 PCAP 本体，除非接收方提供了明确的受限传输渠道。
