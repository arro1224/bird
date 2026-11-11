import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Opt-in baseline measurements. Records counts and timings without device,
/// project, photo, URL or search data.
class GalleryTiming {
  GalleryTiming._(this._id);

  static const _enabled = bool.fromEnvironment('BIRD_GALLERY_TIMING');
  static final _zoneKey = Object();
  static final _session = DateTime.now().millisecondsSinceEpoch;
  static final _output = getTemporaryDirectory().then((directory) => File('${directory.path}/bird-gallery-timing.jsonl'));
  static Future<void> _pendingWrite = Future.value();
  static int _nextId = 0;

  static GalleryTiming? start() => _enabled ? GalleryTiming._(++_nextId) : null;

  static GalleryTiming? get current => _enabled ? Zone.current[_zoneKey] as GalleryTiming? : null;

  final int _id;
  final Stopwatch _clock = Stopwatch()..start();
  int requests = 0;
  bool _thumbnailShown = false;

  int get elapsedUs => _clock.elapsedMicroseconds;

  T run<T>(T Function() action) => runZoned(action, zoneValues: {_zoneKey: this});

  void firstThumbnail() {
    if (_thumbnailShown) return;
    _thumbnailShown = true;
    event('first_thumbnail');
  }

  void event(String name, [Map<String, Object> fields = const {}]) {
    final line = jsonEncode({
      'session': _session,
      'run': _id,
      'event': name,
      'elapsed_us': elapsedUs,
      ...fields,
    });
    debugPrint('BIRD_GALLERY_TIMING $line');
    if (!Platform.isAndroid) return;
    // Some devices filter Flutter info logs. Keep a second copy in the app
    // cache and never make the query wait for it.
    _pendingWrite = _pendingWrite.then((_) async {
      try {
        await (await _output).writeAsString('$line\n', mode: FileMode.append);
      } catch (_) {
        // A log export failure should never interrupt the gallery.
      }
    });
  }
}
