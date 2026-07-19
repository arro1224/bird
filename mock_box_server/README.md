# 拍鸟伴侣模拟盒子端

## USB 真机（推荐）

在项目根目录执行：

```powershell
powershell -ExecutionPolicy Bypass -File mock_box_server\run_usb_mock_box.ps1
```

脚本会检查或启动模拟盒子、确认 USB 真机已授权、自动执行 `adb reverse tcp:8080 tcp:8080`，并验证状态接口。随后在 App 中连接 `http://127.0.0.1:8080`。

手机重新插线、ADB 服务重启或电脑重启后，需要重新运行脚本。手机处于密码锁屏时，ADB 无法代替用户完成解锁和 App 页面点击。

## 局域网连接

运行：`python server.py --host 0.0.0.0 --port 8080`。真机连接时填写电脑局域网 IP，例如 `http://192.168.x.x:8080`；请确认电脑防火墙允许 8080 端口。

已内置的演示场景：

- 10,000 张可分页、筛选的图库记录（默认每页只返回 60 张，用于真机滚动和筛选压测）；
- 4 个拍摄场景、场景照片筛选和鸟种词典搜索；
- 清晰度、AI 推荐、鸟眼/构图评分等照片 UI 契约字段；
- 审阅保存与版本历史；
- 选择 `photo-demo-005` 的批量操作时返回部分失败；
- 复制预估、任务暂停/继续/取消，以及日志导出地址。
- 可通过 `--scenario slow`、`--scenario conflict`、`--scenario storage-full` 分别模拟慢接口、审阅冲突和存储不足；默认使用 `normal`。

这个文件夹只用于前端联调；真实盒子接口就绪后可整体删除，不影响 Flutter App。
