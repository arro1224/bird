import 'package:aves/bird_companion/app/app_dependencies.dart';
import 'package:aves/bird_companion/core/data/app_data_change_bus.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:package_info_plus/package_info_plus.dart';

class SettingsState {
  const SettingsState({
    this.loading = false,
    this.imageCacheBytes = 0,
    this.albumCacheBytes = 0,
    this.appVersion = '读取中',
    this.message = '',
  });

  final bool loading;
  final int imageCacheBytes;
  final int albumCacheBytes;
  final String appVersion;
  final String message;

  SettingsState copyWith({
    bool? loading,
    int? imageCacheBytes,
    int? albumCacheBytes,
    String? appVersion,
    String? message,
  }) => SettingsState(
    loading: loading ?? this.loading,
    imageCacheBytes: imageCacheBytes ?? this.imageCacheBytes,
    albumCacheBytes: albumCacheBytes ?? this.albumCacheBytes,
    appVersion: appVersion ?? this.appVersion,
    message: message ?? this.message,
  );
}

class SettingsCubit extends Cubit<SettingsState> {
  SettingsCubit(this._dependencies) : super(const SettingsState());
  final BirdCompanionDependencies _dependencies;

  Future<void> load() async {
    emit(state.copyWith(loading: true, message: ''));
    try {
      final package = await PackageInfo.fromPlatform();
      final imageBytes = await _dependencies.cacheMetricsService.imageCacheBytes();
      final albumBytes = _dependencies.cache.estimateBytesWithPrefix(
        'album:',
      );
      emit(
        state.copyWith(
          loading: false,
          imageCacheBytes: imageBytes,
          albumCacheBytes: albumBytes,
          appVersion: '${package.version}+${package.buildNumber}',
        ),
      );
    } catch (error) {
      emit(state.copyWith(loading: false, message: '读取本地设置信息失败：$error'));
    }
  }

  Future<void> clearImageCache() async {
    emit(state.copyWith(loading: true, message: ''));
    await _dependencies.cache.clearImageMetadata();
    await DefaultCacheManager().emptyCache();
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    _dependencies.dataChangeBus.publish(
      {AppDataResource.cache},
      reason: 'image_cache_cleared',
    );
    final bytes = await _dependencies.cacheMetricsService.imageCacheBytes();
    emit(
      state.copyWith(
        loading: false,
        imageCacheBytes: bytes,
        message: '已清理手机上保存的预览图；相册信息和待同步修改仍然保留。',
      ),
    );
  }

  Future<void> clearAlbumCache() async {
    emit(state.copyWith(loading: true, message: ''));
    await _dependencies.cache.clearAlbumSnapshots();
    _dependencies.dataChangeBus.publish(
      {AppDataResource.cache, AppDataResource.photos},
      reason: 'album_cache_cleared',
    );
    emit(
      state.copyWith(
        loading: false,
        albumCacheBytes: _dependencies.cache.estimateBytesWithPrefix(
          'album:',
        ),
        message: '已清理相册离线信息；预览图和待同步修改没有被删除。',
      ),
    );
  }

  Future<void> reconnect() async {
    final device = _dependencies.deviceSessionCubit.state.device;
    if (device == null) {
      emit(state.copyWith(message: '没有可重新连接的设备，请在连接页重新选择盒子。'));
      return;
    }
    emit(state.copyWith(loading: true, message: ''));
    try {
      final status = await _dependencies.connectionRepository.connect(device.baseUri, networkMode: device.networkMode);
      await _dependencies.deviceSessionCubit.setConnectedFromStatus(status);
      emit(state.copyWith(loading: false, message: '已重新连接拍鸟盒子。'));
    } catch (error) {
      emit(state.copyWith(loading: false, message: '重新连接失败：$error'));
    }
  }

  Future<void> forgetDevice() async {
    await _dependencies.connectionRepository.forgetDevice();
    _dependencies.deviceSessionCubit.disconnected(null, true);
    _dependencies.deviceSessionCubit.disconnected('已忘记当前设备');
    emit(state.copyWith(message: '已清除已保存的拍鸟盒子连接信息。'));
  }
}
