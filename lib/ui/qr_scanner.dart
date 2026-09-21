import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../l10n/app_localizations.dart';

/// Reads a pairing code off the other phone's screen.
///
/// Behind an interface because a camera cannot run under a test binding, and
/// what a spec needs to control is which code was read, not how.
abstract class QrScanner {
  /// The scanned text, or null when the person backed out.
  Future<String?> scan(BuildContext context);
}

class CameraQrScanner implements QrScanner {
  const CameraQrScanner();

  @override
  Future<String?> scan(BuildContext context) => Navigator.of(
    context,
  ).push(MaterialPageRoute<String>(builder: (_) => const ScanCodeScreen()));
}

class ScanCodeScreen extends StatefulWidget {
  const ScanCodeScreen({super.key});

  @override
  State<ScanCodeScreen> createState() => _ScanCodeScreenState();
}

class _ScanCodeScreenState extends State<ScanCodeScreen> {
  var _done = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.syncScanCode)),
      body: Column(
        children: [
          Expanded(
            child: MobileScanner(
              onDetect: (capture) {
                // The camera keeps reporting the same code every frame; only
                // the first one may pop the route.
                if (_done) return;
                final value = capture.barcodes.firstOrNull?.rawValue;
                if (value == null) return;
                _done = true;
                Navigator.of(context).pop(value);
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(l10n.syncScanHint, textAlign: TextAlign.center),
          ),
        ],
      ),
    );
  }
}
