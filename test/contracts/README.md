# BirdBox v1 固定契约样例

契约版本：`birdbox-v1@1.0.0`

`fixture-manifest.json` 是样例入口。每个 fixture 都声明对应 JSON Schema 和预期
校验结果。相同的有效样例后续必须同时喂给：

1. `tool/mock_box_server` 的响应/请求测试；
2. 真实盒子的契约测试；
3. Flutter DTO 的 `fromJson/toJson` 往返测试。

不得在 mock、App 和真实盒子目录各复制并修改一份样例。需要变更字段时，先修改
OpenAPI/Schema 和 ADR，再更新这里的唯一 fixture。

执行：

```powershell
dart run tool/contracts/verify_contracts.dart
flutter test test/contracts/contract_validation_test.dart
```
