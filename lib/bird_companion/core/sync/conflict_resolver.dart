class VersionConflict {
  const VersionConflict({required this.localVersion, required this.remoteVersion, required this.message});

  final int? localVersion;
  final int? remoteVersion;
  final String message;
}

class ConflictResolver {
  const ConflictResolver();

  VersionConflict? detect({required int? localVersion, required int? remoteVersion}) {
    if (localVersion != null && remoteVersion != null && remoteVersion > localVersion) {
      return VersionConflict(
        localVersion: localVersion,
        remoteVersion: remoteVersion,
        message: '盒子端已有更新结果，请确认后再决定是否覆盖。',
      );
    }
    return null;
  }
}
