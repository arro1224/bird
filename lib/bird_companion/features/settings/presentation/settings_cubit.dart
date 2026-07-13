import 'package:aves/bird_companion/app/app_dependencies.dart';
import 'package:aves/bird_companion/core/data/app_data_change_bus.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

class SettingsCubit extends Cubit<String> {
  SettingsCubit(this._dependencies) : super('');
  final BirdCompanionDependencies _dependencies;
  Future<void> clearCache() async {
    await _dependencies.cache.clearImageMetadata();
    await DefaultCacheManager().emptyCache();
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    _dependencies.dataChangeBus.publish({AppDataResource.cache, AppDataResource.photos}, reason: 'cache_cleared');
    emit('已清理缩略图缓存并刷新图库；待同步操作未受影响。');
  }

  Future<void> reconnect() async {
    final device = _dependencies.deviceSessionCubit.state.device;
    if (device == null) {
      emit('没有可重新连接的设备，请在连接页重新选择盒子。');
      return;
    }
    try {
      final status = await _dependencies.connectionRepository.connect(device.baseUri, networkMode: device.networkMode);
      await _dependencies.deviceSessionCubit.setConnectedFromStatus(status);
      emit('已重新连接拍鸟盒子。');
    } catch (error) {
      emit('重新连接失败：$error');
    }
  }

  Future<void> forgetDevice() async {
    await _dependencies.connectionRepository.forgetDevice();
    _dependencies.deviceSessionCubit.disconnected('已忘记当前设备');
    emit('已清除已保存的拍鸟盒子连接信息。');
  }
}
