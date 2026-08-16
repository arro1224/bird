import 'dart:async';
import 'dart:io';

import 'mock_box_server.dart';

Future<void> main(List<String> arguments) async {
  final options = _Options.parse(arguments);
  final assets = Directory.fromUri(Platform.script.resolve('assets/'));
  final server = MockBoxServer(
    photoCount: options.photoCount,
    assetDirectory: assets,
    logRequests: !options.quiet,
    requireAuthentication: options.requireAuthentication,
    progressiveMedia: options.progressiveMedia,
    emitAssetReadyEvents: options.emitAssetReadyEvents,
    stateFile: options.stateFile,
  );
  final uri = await server.start(
    address: InternetAddress(options.host),
    port: options.port,
  );

  stdout.writeln('K7 mock box is running.');
  stdout.writeln('Host URL: $uri');
  stdout.writeln('Android emulator URL: http://10.0.2.2:${uri.port}');
  stdout.writeln('Photos: ${options.photoCount}');
  stdout.writeln('Authentication: ${options.requireAuthentication ? 'required' : 'disabled'}');
  stdout.writeln('Progressive media: ${options.progressiveMedia ? 'enabled' : 'disabled'}');
  stdout.writeln('Asset-ready events: ${options.emitAssetReadyEvents ? 'enabled' : 'disabled'}');
  stdout.writeln(
    'Persistent state: ${options.stateFile?.path ?? 'disabled'}',
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
    required this.progressiveMedia,
    required this.emitAssetReadyEvents,
    required this.stateFile,
  });

  final String host;
  final int port;
  final int photoCount;
  final bool quiet;
  final bool requireAuthentication;
  final bool progressiveMedia;
  final bool emitAssetReadyEvents;
  final File? stateFile;

  factory _Options.parse(List<String> arguments) {
    var host = '0.0.0.0';
    var port = 8787;
    var photoCount = 1200;
    var quiet = false;
    var requireAuthentication = false;
    var progressiveMedia = false;
    var emitAssetReadyEvents = true;
    File? stateFile;
    for (final argument in arguments) {
      if (argument == '--quick') {
        photoCount = 60;
      } else if (argument == '--quiet') {
        quiet = true;
      } else if (argument == '--auth') {
        requireAuthentication = true;
      } else if (argument == '--progressive-media') {
        progressiveMedia = true;
      } else if (argument == '--no-asset-events') {
        emitAssetReadyEvents = false;
      } else if (argument.startsWith('--host=')) {
        host = argument.substring('--host='.length);
      } else if (argument.startsWith('--port=')) {
        port = int.parse(argument.substring('--port='.length));
      } else if (argument.startsWith('--photos=')) {
        photoCount = int.parse(argument.substring('--photos='.length));
      } else if (argument.startsWith('--state-file=')) {
        final path = argument.substring('--state-file='.length).trim();
        if (path.isEmpty) {
          throw const FormatException('--state-file requires a path.');
        }
        stateFile = File(path);
      } else if (argument == '--help' || argument == '-h') {
        stdout.writeln(
          'Usage: dart run tool/mock_box_server/server.dart '
          '[--quick] [--auth] [--progressive-media] [--no-asset-events] '
          '[--photos=1200] [--host=0.0.0.0] '
          '[--port=8787] [--quiet] [--state-file=path]',
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
      progressiveMedia: progressiveMedia,
      emitAssetReadyEvents: emitAssetReadyEvents,
      stateFile: stateFile,
    );
  }
}
