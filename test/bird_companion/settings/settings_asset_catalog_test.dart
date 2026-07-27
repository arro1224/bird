import 'dart:io';

import 'package:aves/bird_companion/features/settings/presentation/bird_settings_asset_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('settings icon catalog contains the 13 approved local assets', () {
    expect(BirdSettingsAssetCatalog.all, hasLength(13));
    for (final asset in BirdSettingsAssetCatalog.all) {
      expect(asset, startsWith('assets/bird_companion/settings/icons/'));
      expect(File(asset).existsSync(), isTrue, reason: asset);
    }
  });
}
