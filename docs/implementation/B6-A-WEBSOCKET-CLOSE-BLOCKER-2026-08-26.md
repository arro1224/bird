# B6 A 侧缺陷复盘：动态地址切换后旧 WebSocket 未关闭（已解决）

## 1. 结论

B6 动态地址会话契约曾被 A 侧 WebSocket 生命周期缺陷阻塞。该缺陷已由 A 侧提交 `5c952c8e8` 修复，并通过 `thirdtime@6b6a81ee0` 合入公共基线。

设备地址从旧地址迁移到新地址时，新 WebSocket 能够建立，旧客户端 channel 的写端也会结束，但盒子服务端观察到的旧 WebSocket 连接不会真正关闭。测试等待 2 秒和 6 秒均未收到旧连接关闭事件。

根因位于 `EventClient` 的清理顺序：代码先取消旧 WebSocket 的 stream subscription，再调用 `sink.close()`。取消订阅会使 Dart WebSocket 无法继续读取服务端返回的 close frame，因此关闭握手不能完成。

这是一次已解决的 A5/A6 公共层阻塞。B 侧始终遵守所有权边界，没有修改 A 侧生产代码；修复合入后，B6 动态地址契约已通过。

## 2. 当前基线与状态

- 修复提交：`5c952c8e8 fix(connection): close replaced event sockets gracefully`
- 公共基线：`thirdtime@6b6a81ee0261d55ce86aa51fd5cfe3e62ccb08e0`
- 本地同步提交：`d6f66046a merge(hotfix-A6): sync WebSocket close fix into part2`
- B6 契约提交：`a5d9c7a75`、`12cb2567a`
- B6 契约测试：[`b5_b6_session_recovery_test.dart`](../../test/bird_companion/features/connection/b5_b6_session_recovery_test.dart)
- A 侧生产文件改动：0。

## 3. 已验证的 B6 结果

同一契约文件包含三项测试：

1. 离线启动保留已保存设备且不重连：通过。
2. 在线启动只恢复一次并执行 retained-write recovery：通过。
3. 动态地址迁移并关闭旧 WebSocket：修复前失败，修复后通过。

修复后的稳定结果：

```text
offline startup retains the saved device without reconnecting       PASS
online startup restores once and runs retained-write recovery       PASS
dynamic address updates the active device and refreshes B views     PASS

B6 contract                                                     3/3 PASS
A close + B6 contract                                           6/6 PASS
dynamic_base_uri_test                                           1/1 PASS
```

复现命令：

```powershell
$env:CI='true'
$env:GIT_CONFIG_COUNT='1'
$env:GIT_CONFIG_KEY_0='safe.directory'
$env:GIT_CONFIG_VALUE_0='D:/birdphoto/.tooling/flutter-3.44.5'
& 'D:\birdphoto\.tooling\flutter-3.44.5\bin\flutter.bat' test --no-pub test\bird_companion\features\connection\b5_b6_session_recovery_test.dart --reporter expanded
```

## 4. 触发链路

动态地址迁移调用 [`SessionCoordinator.activate()`](../../lib/bird_companion/core/session/session_coordinator.dart)。当前顺序如下：

1. 持久化新的 `SessionCredential`。
2. 调用 `_eventClient.disconnect()` 清理旧事件连接。
3. 将相同 Bearer token 和 API 版本配置给 REST 客户端。
4. 将 REST base URI 更新为新地址。
5. 在新地址建立 WebSocket。
6. 发布 `SessionAddressChange`。

相关代码：

```dart
await _eventClient.disconnect();
_apiClient.setSession(
  accessToken: credential.accessToken,
  apiVersion: credential.apiVersion,
);
_apiClient.configure(credential.baseUri);
_activeCredential = credential;
await _eventClient.connect(
  eventUri,
  accessToken: credential.accessToken,
  apiVersion: credential.apiVersion,
);
```

`SessionCoordinator` 的总体迁移顺序没有直接表现出错误。缺陷发生在 `EventClient.disconnect()` 内部。

## 5. 根因分析

### 5.1 当前错误顺序

[`EventClient.disconnect()`](../../lib/bird_companion/core/network/event_client.dart) 当前执行：

```dart
await _subscription?.cancel();
_subscription = null;
await _closeChannel(_channel);
```

`_closeChannel()` 最终只执行：

```dart
await channel?.sink.close();
```

实际顺序为：

```text
取消旧 WebSocket 的读取订阅
        ↓
底层无法继续读取服务端 close frame
        ↓
客户端再发送 close frame
        ↓
客户端 sink.done 完成
        ↓
服务端旧 WebSocket 仍保持打开
```

### 5.2 为什么 `sink.done` 会造成误判

契约测试分别观察了两端：

```dart
await clientChannels.first.sink.done.timeout(...); // 通过
await oldSocket.done.timeout(...);                  // 超时
```

这说明：

- 客户端 WebSocket sink 已完成写端关闭。
- 但服务端没有完成 WebSocket 关闭握手。
- “客户端 sink 完成”不能证明底层连接已真正释放。

### 5.3 Dart WebSocket 内部行为

Dart SDK 的 WebSocket stream 被取消时，会取消内部 socket subscription 并将其设为 `null`。

之后调用 `WebSocket.close()` 时，SDK 原本需要保持读取状态，才能接收服务端返回的 close frame。如果内部 subscription 已为 `null`，就无法通过 drain/read 完成关闭握手。

诊断中已确认：

- 测试服务器真实接受了旧连接，并为该连接注册了 stream listener。
- 客户端旧 sink 在 2 秒内完成。
- 服务端旧 socket 在 2 秒内未关闭。
- 将观察窗口增加到 6 秒，服务端旧 socket 仍未关闭。

因此问题不是测试服务器未监听、连接建立竞态或单纯的网络延迟。

### 5.4 相同问题还存在于 `_open()`

[`EventClient._open()`](../../lib/bird_companion/core/network/event_client.dart) 清理 previous channel 时也采用：

```dart
await _subscription?.cancel();
_subscription = null;
final previousChannel = _channel;
_channel = null;
await _closeChannel(previousChannel);
```

因此风险不只存在于动态地址切换。普通重新连接或直接重新打开事件连接时，也可能留下旧服务端 WebSocket。

## 6. 影响

### 6.1 功能影响

- 新 WebSocket 建立后，盒子端仍保留旧连接。
- 客户端只消费新连接事件，旧连接上的事件无人处理。
- 盒子端不知道旧连接已经失效，仍可能继续发送事件。

### 6.2 资源影响

- 多次 DHCP 地址变化、切网、重连或会话激活后，旧连接可能累积。
- 盒子端持续占用 TCP socket、WebSocket 会话、内存和事件发送资源。
- 手机和盒子之间可能存在不必要的连接与网络开销。

### 6.3 安全影响

- 旧 WebSocket 是使用有效 Bearer token 建立的已认证连接。
- 地址迁移后，旧授权连接的服务端生命周期被非预期延长。
- 虽然客户端 generation guard 会忽略旧回调，但它只能阻止业务层处理旧事件，不能撤销或关闭服务端授权连接。

## 7. A 侧建议修复方向

不要通过增加测试超时或仅依赖 generation guard 绕过问题。修复目标必须是完成旧 WebSocket 的真实关闭握手。

建议统一调整 `disconnect()` 和 `_open()` 的旧连接清理流程：

1. 先冻结当前 generation，阻止旧 channel 的业务回调影响新会话。
2. 保存旧 channel、subscription 和对应的关闭完成信号。
3. 保持旧 stream subscription 存活。
4. 先向旧 channel 发送 WebSocket close。
5. 等待旧 channel 的 `onDone`/关闭确认。
6. 关闭确认完成后，再 cancel subscription 并清空引用。
7. 对无法完成握手的对端提供明确的超时和强制底层关闭策略。

概念顺序：

```text
generation 失效旧回调
        ↓
发送 WebSocket close
        ↓
保持读取订阅，接收对端 close frame
        ↓
确认 channel onDone
        ↓
取消 subscription / 清空引用
        ↓
连接新地址
```

仅简单交换 `cancel()` 与 `sink.close()` 两行仍可能存在竞态，因为 `sink.close()` 完成通常只代表关闭帧已写出，不一定代表已经收到服务端关闭响应。建议增加每个活动 channel 对应的 close-completion 信号。

## 8. A 侧建议测试

至少补充以下回归测试：

1. `disconnect closes the server-side WebSocket`
   - 建立真实 loopback WebSocket。
   - 调用 `EventClient.disconnect()`。
   - 断言服务端 socket 在 2 秒内 `done`。

2. `connect replacement closes the previous WebSocket`
   - 连续连接两个地址或端点。
   - 断言旧服务端 socket 关闭。
   - 断言只有新 socket 保持活动。

3. `dynamic address migration keeps one active event socket`
   - 通过 `SessionCoordinator.activate()` 切换 base URI。
   - 断言旧连接关闭、新连接建立。
   - 断言 Authorization header 继续使用相同 Bearer token。

4. `repeated address changes do not accumulate sockets`
   - 连续迁移多次地址。
   - 每次迁移后服务端只保留一个活动 WebSocket。

5. `disconnect remains safe after stream error`
   - 模拟旧 stream 已异常结束。
   - 断言清理不会阻止新连接建立，也不会残留旧 transport。

## 9. B6 验收标准

A 侧修复合入 `thirdtime` 后，B 侧将重新运行完整契约。通过标准：

- 离线启动保留已保存设备，不调用 reconnect。
- 在线启动只 reconnect 一次。
- retained-write recovery 只执行一次。
- 恢复成功触发两次 B 视图刷新 generation。
- 动态地址切换后旧服务端 WebSocket 在 2 秒内关闭。
- 当前设备 `baseUri` 更新为新地址。
- REST API base URI 更新为新地址。
- 相对媒体地址解析到新地址。
- 新 WebSocket endpoint 使用新 host。
- 新 WebSocket 继续使用原 Bearer token。
- 外部设备地址事件不改变当前设备或刷新 generation。
- 连续迁移不会累积旧连接。

## 10. B 侧完成情况

1. 已备份同步前的本地契约测试。
2. 已拉取并合入 `thirdtime@6b6a81ee0`，未直接合并 `origin/part1`。
3. 已恢复并运行本报告中的 B6 契约测试。
4. 三项 B6 测试全部通过并提交 Task 4。
5. 生产 Fake 隔离门禁及 wiring 契约已完成，后续只剩最终全量验证和推送。
