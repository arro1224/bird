import 'package:flutter/material.dart';
import 'package:aves/bird_companion/app/app_router.dart';
import 'package:aves/bird_companion/core/widgets/page_back_button.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class QrConnectionScannerPage extends StatefulWidget {
  const QrConnectionScannerPage({super.key});

  @override
  State<QrConnectionScannerPage> createState() => _QrConnectionScannerPageState();
}

class _QrConnectionScannerPageState extends State<QrConnectionScannerPage> {
  bool _handled = false;

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    final raw = capture.barcodes.firstOrNull?.rawValue?.trim();
    final uri = _parseConnectionUri(raw);
    if (uri == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('二维码中未找到有效的盒子地址。')));
      return;
    }
    _handled = true;
    Navigator.of(context).pop(uri);
  }

  Uri? _parseConnectionUri(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final parsed = Uri.tryParse(raw);
    if (parsed == null) return null;
    if (parsed.scheme == 'birdbox') {
      final host = parsed.queryParameters['host'];
      final port = parsed.queryParameters['port'];
      return host == null ? null : Uri(scheme: parsed.queryParameters['https'] == 'true' ? 'https' : 'http', host: host, port: int.tryParse(port ?? '') ?? 8080);
    }
    return parsed.hasScheme && parsed.host.isNotEmpty ? parsed : null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const BirdPageBackButton(fallbackRoute: BirdRoutes.connection),
        title: const Text('扫码连接'),
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(onDetect: _onDetect),
          const Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              minimum: EdgeInsets.all(24),
              child: Text('扫描盒子显示的连接二维码。', style: TextStyle(color: Colors.white, fontSize: 16)),
            ),
          ),
        ],
      ),
    );
  }
}
