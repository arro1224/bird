import 'dart:async';
import 'dart:io';

import 'mock_box_server.dart';

Future<void> main(List<String> arguments) async {
  _Options options;
  try {
    options = _Options.parse(arguments);
  } on FormatException catch (error) {
    stderr.writeln('mock box 启动参数错误：${error.message}');
    stderr.writeln('用 --help 查看全部参数。');
    exit(2);
  }
  final assets = Directory.fromUri(Platform.script.resolve('assets/'));
  final server = MockBoxServer(
    photoCount: options.photoCount,
    assetDirectory: assets,
    logRequests: !options.quiet,
    requireAuthentication: options.requireAuthentication,
    deviceId: options.deviceId,
    progressiveMedia: options.progressiveMedia,
    emitAssetReadyEvents: options.emitAssetReadyEvents,
    // 演示默认开启 workflow 任务推进器（import/analysis/sync 自动走完
    // 生命周期并广播 job_updated）；测试/特殊排查用 --no-workflow-advance 关。
    workflowAutoAdvance: options.workflowAutoAdvance,
    autoSmartFollow: options.autoSmartFollow,
    stateFile: options.stateFile,
    embeddedDemo: options.embeddedDemo,
  );
  final uri = await server.start(
    address: InternetAddress(options.host),
    port: options.port,
  );

  stdout.writeln('K7 mock box is running.');
  stdout.writeln('Host URL: $uri');
  stdout.writeln('Android emulator URL: http://10.0.2.2:${uri.port}');
  stdout.writeln('Photos: ${options.photoCount}');
  stdout.writeln('Device ID: ${options.deviceId} (${options.deviceId.length} chars)');
  stdout.writeln('Authentication: ${options.requireAuthentication ? 'required' : 'disabled'}');
  stdout.writeln('Progressive media: ${options.progressiveMedia ? 'enabled' : 'disabled'}');
  stdout.writeln('Asset-ready events: ${options.emitAssetReadyEvents ? 'enabled' : 'disabled'}');
  stdout.writeln(
    'Persistent state: ${options.stateFile?.path ?? 'disabled'}',
  );
  stdout.writeln(
    'Workflow auto-advance: ${options.workflowAutoAdvance ? 'enabled' : 'disabled'}',
  );
  stdout.writeln(
    'SmartFollow auto-drive: ${options.autoSmartFollow ? 'enabled' : 'disabled'}',
  );
  stdout.writeln('Press Ctrl+C to stop.');

  final stop = Completer<void>();
  ProcessSignal.sigint.watch().listen((_) async {
    await server.close();
    if (!stop.isCompleted) stop.complete();
  });
  await stop.future;
}

class _Options {
  const _Options({
    required this.host,
    required this.port,
    required this.photoCount,
    required this.quiet,
    required this.requireAuthentication,
    required this.deviceId,
    required this.progressiveMedia,
    required this.emitAssetReadyEvents,
    required this.workflowAutoAdvance,
    required this.autoSmartFollow,
    required this.stateFile,
    required this.embeddedDemo,
  });

  final String host;
  final int port;
  final int photoCount;
  final bool quiet;
  final bool requireAuthentication;
  final String deviceId;
  final bool progressiveMedia;
  final bool emitAssetReadyEvents;
  final bool workflowAutoAdvance;
  final bool autoSmartFollow;
  final File? stateFile;
  final bool embeddedDemo;

  factory _Options.parse(List<String> arguments) {
    var host = '0.0.0.0';
    var port = 8787;
    var photoCount = 1200;
    var quiet = false;
    var requireAuthentication = false;
    var deviceId = 'mock-k7-001';
    var progressiveMedia = false;
    var emitAssetReadyEvents = true;
    var workflowAutoAdvance = true;
    var embeddedDemo = false;
    var autoSmartFollow = false;
    File? stateFile;
    for (final argument in arguments) {
      if (argument == '--embedded-demo') {
        embeddedDemo = true;
      } else if (argument == '--quick') {
        photoCount = 60;
      } else if (argument == '--quiet') {
        quiet = true;
      } else if (argument == '--auth') {
        requireAuthentication = true;
      } else if (argument == '--progressive-media') {
        progressiveMedia = true;
      } else if (argument == '--no-asset-events') {
        emitAssetReadyEvents = false;
      } else if (argument == '--no-workflow-advance') {
        workflowAutoAdvance = false;
      } else if (argument == '--auto-smart-follow') {
        // 「边识别边复制」的分析任务会被推进器跳过（防会话快照撕裂），进度只能
        // 由 POST /mock/control/smart-follow 驱动。演示现场没人去 curl 那个测试
        // 端点，所以用这个开关把驱动内置化，否则「AI 分析」会永远停在 0%。
        autoSmartFollow = true;
      } else if (argument.startsWith('--host=')) {
        host = argument.substring('--host='.length);
      } else if (argument.startsWith('--port=')) {
        port = int.parse(argument.substring('--port='.length));
      } else if (argument.startsWith('--photos=')) {
        photoCount = int.parse(argument.substring('--photos='.length));
      } else if (argument.startsWith('--device-id=')) {
        deviceId = argument.substring('--device-id='.length).trim();
        if (deviceId.isEmpty) {
          throw const FormatException('--device-id requires a value.');
        }
        // App 的直连热点交接会把「模拟入口广播的 deviceId」与盒子 /health 自报的
        // deviceId 做严格字符串比对，差一个字符就报「设备身份不一致」。
        // 手敲 --device-id 曾两次打错（多一对 b7），启动时直接拦下来。
        if (deviceId.startsWith('bbx-') && !RegExp(r'^bbx-[0-9a-f]{32}$').hasMatch(deviceId)) {
          throw FormatException(
            '--device-id 不符合 rc4 身份约束：应为 "bbx-" + 32 位小写十六进制（共 36 字符），'
            '当前值是 "$deviceId"（${deviceId.length} 字符，bbx- 后 ${deviceId.length - 4} 位）。\n'
            'App 侧期望值见 lib/bird_companion/features/connection/presentation/'
            'b7_simulated_provisioning_repository.dart 的 simulatedBirdBoxDeviceId，'
            '用 birdSim flavor 时两者必须完全一致。',
          );
        }
        if (!deviceId.startsWith('bbx-')) {
          stderr.writeln(
            '[warn] --device-id="$deviceId" 不是 bbx- 开头的盒子身份，'
            'birdSim App 直连热点交接时会报「设备身份不一致」。',
          );
        }
      } else if (argument.startsWith('--state-file=')) {
        final path = argument.substring('--state-file='.length).trim();
        if (path.isEmpty) {
          throw const FormatException('--state-file requires a path.');
        }
        stateFile = File(path);
      } else if (argument == '--help' || argument == '-h') {
        stdout.writeln(
          'Usage: dart run tool/mock_box_server/server.dart '
          '[--embedded-demo] [--quick] [--auth] [--progressive-media] [--no-asset-events] '
          '[--no-workflow-advance] [--auto-smart-follow] [--photos=1200] [--host=0.0.0.0] '
          '[--port=8787] [--device-id=id] [--quiet] [--state-file=path]',
        );
        exit(0);
      } else {
        throw FormatException('Unknown option: $argument');
      }
    }
    return _Options(
      host: host,
      port: port,
      photoCount: photoCount,
      quiet: quiet,
      requireAuthentication: requireAuthentication,
      deviceId: deviceId,
      progressiveMedia: progressiveMedia,
      emitAssetReadyEvents: emitAssetReadyEvents,
      workflowAutoAdvance: workflowAutoAdvance,
      autoSmartFollow: autoSmartFollow,
      stateFile: stateFile,
      embeddedDemo: embeddedDemo,
    );
  }
}
