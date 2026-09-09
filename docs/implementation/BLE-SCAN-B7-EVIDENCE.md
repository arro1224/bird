# B7 BLE 扫描真机证据

B7 在 App 内为每次扫描生成 `scanSessionId`，并输出以
`BLE_SCAN_DIAGNOSTIC` 开头的单行 JSON。记录不包含设备地址、广播名称、
厂商数据、配对码、密码或令牌。

## 采集矩阵

每个场景至少执行 10 次：

1. `cold_start_permission_granted`：冷启动且权限已授予。
2. `bluetooth_enabled_after_launch`：启动后再打开蓝牙。
3. `denied_then_granted`：拒绝权限后再授权。
4. `foreground_resume`：应用从后台恢复。
5. `timeout_manual_retry`：首次超时后手动重试。
6. `multiple_boxes`：多个盒子同时广播。

采集 Android 日志时筛选 `BLE_SCAN_DIAGNOSTIC`。把每条 JSON 与人工确认的
场景名组合为：

```json
{
  "runs": [
    {
      "scenario": "cold_start_permission_granted",
      "session": { "scan_session_id": "..." }
    }
  ]
}
```

完成 60 次真机运行后执行：

```text
dart run tool/acceptance/ble_scan_b7_evidence_validator.dart <evidence.json>
```

校验器只检查样本数量、字段完整性、计数一致性、会话 ID 唯一性和敏感字段。
它会报告每个场景发现候选盒子的比例，但不会把低成功率隐藏为通过，也不会把
模拟测试当作真机证据。

## 自动重启决策

本批次不默认增加自动重启。只有真机记录显示首轮失败集中在生命周期竞争或
Scanner 尚未稳定，同时权限拒绝、蓝牙关闭与不支持场景已排除时，才允许增加
一次带抖动的自动重启；该决策必须引用对应的 `scanSessionId` 样本。
