/// Produces a stable, device-scoped cache identity for short-lived media URLs.
///
/// Signed query parameters are deliberately excluded so refreshing a signed
/// URL reuses the same image, while the device namespace prevents two boxes
/// with identical project/file identifiers from sharing cached bytes.
String mediaCacheIdentity({
  required Uri uri,
  required String mediaId,
  required String variant,
  String? deviceNamespace,
}) {
  final explicitNamespace = deviceNamespace?.trim();
  final namespace = explicitNamespace == null || explicitNamespace.isEmpty ? uri.authority : explicitNamespace;
  final stableUri = uri.replace(
    queryParameters: const <String, String>{},
    fragment: '',
  );
  return 'bird-media:${Uri.encodeComponent(namespace)}:'
      '${Uri.encodeComponent(mediaId)}:'
      '${Uri.encodeComponent(variant)}:'
      '${Uri.encodeComponent(stableUri.toString())}';
}
