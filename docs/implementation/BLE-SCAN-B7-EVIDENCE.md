# B7 BLE 扫描真机证据

B7 在 App 内为每次扫描生成 `scanSessionId`，并输出以
`BLE_SCAN_DIAGNOSTIC` 开头的单行 JSON。RC4-HF-BLE-06 起使用 schema v3：
设备地址只保存按扫描会话加盐的 SHA-256；广播记录除长度和 SHA-256 外，还保存
最多 512 字节的脱敏十六进制。名称、Service UUID 等识别字段保留，Manufacturer
Data 和 Service Data 只保留标识前缀，其余载荷清零；不保存配对码、密码或令牌。

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
      "session": {
        "schema_version": 3,
        "trace_id": "...",
        "scan_session_id": "...",
        "observations": []
      }
    }
  ]
}
```

完成 60 次真机运行后执行：

```text
dart run tool/acceptance/ble_scan_b7_evidence_validator.dart <evidence.json>
```

校验器检查样本数量、schema v3 字段完整性、计数一致性、会话 ID 唯一性、
地址哈希格式、明文 MAC 和敏感字段。
它会报告每个场景发现候选盒子的比例，但不会把低成功率隐藏为通过，也不会把
模拟测试当作真机证据。

## 自动重启决策

本批次不默认增加自动重启。只有真机记录显示首轮失败集中在生命周期竞争或
Scanner 尚未稳定，同时权限拒绝、蓝牙关闭与不支持场景已排除时，才允许增加
一次带抖动的自动重启；该决策必须引用对应的 `scanSessionId` 样本。
