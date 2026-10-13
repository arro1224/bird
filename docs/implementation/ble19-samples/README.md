# BLE19本地合成样例

这些文件用于验证诊断保留及文件管道，未经过华为、vivo、真实 BirdBox 或外部分享目标。source 为 synthetic_local_test，构建身份和计数为测试占位值。

JSON 保留 17 条关键记录；ZIP 来自超过 500 条输入的压力快照，保留 500 条记录及全部 17 类关键事件。ZIP 包含 summary.json、full_trace.json、README.txt。verification.json 为独立 Python 接收端实际重读后的结果，phone_acceptance 为 false。

最终 JSON SHA-256：`14cbc233211938b33762124d6c58dcafc1d47672fdcd7e5384eb40e978365374`。

最终 ZIP SHA-256：`7f8d58f39f77854cc1dbf35f1ac3123383195a8b4cfc34439433477189276509`；完整 JSON payload SHA-256：`0bce6bd4300ad8658f7531ff56bf9443c4af7ed364cd8ebde925b062cfc029b7`。

在项目根使用 tool/ble19/verify_diagnostic_file.py，传入实际文件路径和上述最终文件 hash，即可独立复核。完整说明见上级目录 BLE-19 实施记录。
