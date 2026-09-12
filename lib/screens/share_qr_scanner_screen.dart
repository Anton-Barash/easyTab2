import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../l10n/app_localizations.dart';
import '../services/api_service.dart';
import '../services/share_token_storage.dart';
import '../services/anonymous_id_service.dart';

/// Экран сканирования QR-кода расшаренного отчёта.
///
/// Закрывается через `Navigator.pop(context, true)`, если QR относится к
/// редактируемому отчёту (share.permissions == 'edit') и токен добавлен в
/// список; иначе — через `pop(context, false)` без добавления.
class ShareQrScannerScreen extends StatefulWidget {
  const ShareQrScannerScreen({super.key});

  @override
  State<ShareQrScannerScreen> createState() => _ShareQrScannerScreenState();
}

class _ShareQrScannerScreenState extends State<ShareQrScannerScreen> {
  final MobileScannerController _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
    facing: CameraFacing.back,
  );

  bool _processing = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_processing) return;
    final barcode = capture.barcodes.isNotEmpty ? capture.barcodes.first : null;
    final raw = barcode?.rawValue;
    if (raw == null || raw.isEmpty) return;

    final token = _extractToken(raw);
    if (token == null || token.isEmpty) {
      _showMessage(
        AppLocalizations.of(context)!.qrCantAdd,
      );
      return;
    }

    _processing = true;
    _handleToken(token);
  }

  Future<void> _handleToken(String token) async {
    final loc = AppLocalizations.of(context)!;
    try {
      final anonymousId = await AnonymousIdService.getId();
      final result = await ApiService.getShareInfo(
        token: token,
        anonymousId: anonymousId,
      );

      if (!mounted) return;

      if (result.success && result.data != null) {
        final share = result.data!['share'] ?? {};
        final permissions = share['permissions']?.toString() ?? 'edit';
        if (permissions == 'edit') {
          await ShareTokenStorage.addToken(token);
          if (mounted) Navigator.of(context).pop(true);
          return;
        }
        // Отчёт только для просмотра — не добавляем в список.
        _showMessage(loc.qrNotEditable);
      } else {
        _showMessage(loc.qrCantAdd);
      }
    } catch (e) {
      if (!mounted) return;
      _showMessage(AppLocalizations.of(context)!.qrCantAdd);
    } finally {
      _processing = false;
    }
  }

  /// Извлекает share-токен из отсканированной строки. QR кодирует полную
  /// ссылку вида `https://easytab.cloud/#/welcome?token=XXX`.
  String? _extractToken(String raw) {
    final uri = Uri.tryParse(raw);
    if (uri == null) return null;
    final fragment = uri.fragment;
    if (fragment.isNotEmpty) {
      final fragmentUri = Uri.tryParse(fragment);
      final token = fragmentUri?.queryParameters['token'];
      if (token != null && token.isNotEmpty) return token;
    }
    final token = uri.queryParameters['token'];
    return (token != null && token.isNotEmpty) ? token : null;
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 4)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(loc.scanQr),
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
          ),
        ],
      ),
    );
  }
}