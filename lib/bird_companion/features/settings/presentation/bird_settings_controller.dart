import 'package:flutter/foundation.dart';

enum BirdPhotoSortOrder {
  newest('拍摄时间（最新）'),
  oldest('拍摄时间（最早）'),
  fileNameAscending('文件名（A-Z）'),
  fileNameDescending('文件名（Z-A）'),
  sizeDescending('文件大小（大到小）'),
  sizeAscending('文件大小（小到大）');

  const BirdPhotoSortOrder(this.label);
  final String label;
}

enum BirdCopyMode {
  keptOnly('只复制已保留'),
  all('复制全部'),
  dualTrack('双轨复制');

  const BirdCopyMode(this.label);
  final String label;
}

enum BirdThumbnailSize {
  small('小'),
  medium('中'),
  large('大');

  const BirdThumbnailSize(this.label);
  final String label;
}

class BirdSettingsController extends ChangeNotifier {
  int gridColumns = 4;
  bool showSubjectBox = true;
  bool autoAdvance = true;
  bool showRatingOverlay = true;
  BirdThumbnailSize thumbnailSize = BirdThumbnailSize.medium;
  BirdPhotoSortOrder sortOrder = BirdPhotoSortOrder.newest;
  bool birdPhotosOnly = true;
  BirdCopyMode copyMode = BirdCopyMode.keptOnly;
  String xmpStrategy = '生成同名 XMP（推荐）';
  bool verifyCopies = true;
  bool lowBatteryReminder = true;
  bool autoOpenReport = false;
  String selectedStorageId = 'removable-e';
  String selectedDeviceId = 'k7-current';
  bool technicalDetailsExpanded = false;
  bool searchingDevices = false;

  void setGridColumns(int value) => _set(() => gridColumns = value);
  void setShowSubjectBox(bool value) => _set(() => showSubjectBox = value);
  void setAutoAdvance(bool value) => _set(() => autoAdvance = value);
  void setShowRatingOverlay(bool value) => _set(() => showRatingOverlay = value);
  void setThumbnailSize(BirdThumbnailSize value) => _set(() => thumbnailSize = value);
  void setSortOrder(BirdPhotoSortOrder value) => _set(() => sortOrder = value);
  void setBirdPhotosOnly(bool value) => _set(() => birdPhotosOnly = value);
  void setCopyMode(BirdCopyMode value) => _set(() => copyMode = value);
  void setXmpStrategy(String value) => _set(() => xmpStrategy = value);
  void setVerifyCopies(bool value) => _set(() => verifyCopies = value);
  void setLowBatteryReminder(bool value) => _set(() => lowBatteryReminder = value);
  void setAutoOpenReport(bool value) => _set(() => autoOpenReport = value);
  void setStorageTarget(String value) => _set(() => selectedStorageId = value);
  void setDevice(String value) => _set(() => selectedDeviceId = value);
  void toggleTechnicalDetails() => _set(() => technicalDetailsExpanded = !technicalDetailsExpanded);
  void beginDeviceSearch() => _set(() => searchingDevices = true);

  void resetDisplaySettings() {
    gridColumns = 4;
    showSubjectBox = true;
    autoAdvance = true;
    showRatingOverlay = true;
    thumbnailSize = BirdThumbnailSize.medium;
    sortOrder = BirdPhotoSortOrder.newest;
    notifyListeners();
  }

  void _set(VoidCallback update) {
    update();
    notifyListeners();
  }
}
