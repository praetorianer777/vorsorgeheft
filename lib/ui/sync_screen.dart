import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../app/providers.dart';
import '../l10n/app_localizations.dart';
import '../sync/bundle.dart';
import '../sync/replicated_store.dart';
import '../sync/sync_protocol.dart';
import '../sync/sync_transport.dart';
import '../sync/transfer_code.dart';

/// Pairing, the paired devices, and the file fallback.
class SyncScreen extends ConsumerWidget {
  const SyncScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final peers = ref.watch(peersProvider).value ?? const <Peer>[];

    return Scaffold(
      appBar: AppBar(title: Text(l10n.syncTitle)),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text('${l10n.syncIntro}\n\n${l10n.syncConflictRule}'),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton.tonalIcon(
                    key: const Key('show-my-code'),
                    onPressed: () => _showMyCode(context, ref),
                    icon: const Icon(Icons.qr_code_2),
                    label: Text(l10n.syncShowCode),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    key: const Key('scan-code'),
                    onPressed: () => _scanCode(context, ref),
                    icon: const Icon(Icons.qr_code_scanner),
                    label: Text(l10n.syncScanCode),
                  ),
                ),
              ],
            ),
          ),
          _Heading(l10n.syncDevices),
          if (peers.isEmpty)
            ListTile(
              key: const Key('no-peers'),
              leading: const Icon(Icons.devices_other_outlined),
              title: Text(l10n.syncNoDevices),
            ),
          for (final peer in peers) _PeerTile(peer: peer),
          const Divider(),
          _Heading(l10n.bundleSection),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text('${l10n.bundleHotspot}\n\n${l10n.bundleIntro}'),
          ),
          ListTile(
            key: const Key('send-to-phone'),
            leading: const Icon(Icons.send_to_mobile_outlined),
            title: Text(l10n.bundleSend),
            subtitle: Text(l10n.bundleSendSubtitle),
            onTap: () => _sendToPhone(context, ref),
          ),
          ListTile(
            key: const Key('receive-from-phone'),
            leading: const Icon(Icons.install_mobile_outlined),
            title: Text(l10n.bundleReceive),
            subtitle: Text(l10n.bundleReceiveSubtitle),
            onTap: () => _receiveFromPhone(context, ref),
          ),
          ListTile(
            key: const Key('export-bundle'),
            leading: const Icon(Icons.upload_file_outlined),
            title: Text(l10n.bundleExport),
            subtitle: Text(l10n.bundleExportSubtitle),
            onTap: () => _exportBundle(context, ref),
          ),
          ListTile(
            key: const Key('import-bundle'),
            leading: const Icon(Icons.file_open_outlined),
            title: Text(l10n.bundleImport),
            subtitle: Text(l10n.bundleImportSubtitle),
            onTap: () => _importBundle(context, ref),
          ),
        ],
      ),
    );
  }

  Future<void> _showMyCode(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final engine = ref.read(syncEngineProvider);
    final payload = await engine.pairingPayload(
      defaultName: l10n.syncDefaultDeviceName,
    );
    final address = await engine.transport.localAddress();
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => _MyCodeDialog(
        code: payload.encode(),
        deviceName: payload.deviceName,
        address: address,
        onRename: engine.rename,
      ),
    );
  }

  Future<void> _scanCode(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final code = await ref.read(qrScannerProvider).scan(context);
    if (code == null) return;
    try {
      final peer = await ref.read(syncEngineProvider).pairWith(code);
      _notify(messenger, l10n.syncPaired(peer.deviceName));
    } on FormatException {
      _notify(messenger, l10n.syncCodeInvalid);
    }
  }

  /// The code is on screen before the file is sealed: sealing takes a
  /// moment, and the share sheet that follows covers the app, so this is the
  /// only time the person sees what to type on the other phone.
  Future<void> _sendToPhone(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final code = TransferCode.generate();
    final sending = ref
        .read(bundleServiceProvider)
        .export(password: code, subject: l10n.bundleSubject);
    await showDialog<void>(
      context: context,
      builder: (_) => _TransferCodeDialog(code: code, sending: sending),
    );
  }

  Future<void> _receiveFromPhone(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final service = ref.read(bundleServiceProvider);
    final bytes = await service.pick();
    if (bytes == null || !context.mounted) return;
    final code = await showDialog<String>(
      context: context,
      builder: (_) => const _TransferCodeInputDialog(),
    );
    if (code == null) return;
    await _apply(messenger, l10n, service.importBytes(bytes, password: code));
  }

  Future<void> _exportBundle(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final password = await _askPassword(context, l10n.bundleExport);
    if (password == null) return;
    try {
      await ref
          .read(bundleServiceProvider)
          .export(password: password, subject: l10n.bundleSubject);
    } on Object {
      _notify(messenger, l10n.bundleFailed);
    }
  }

  Future<void> _importBundle(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final password = await _askPassword(context, l10n.bundleImport);
    if (password == null) return;
    await _apply(
      messenger,
      l10n,
      ref.read(bundleServiceProvider).import(password: password),
    );
  }

  Future<void> _apply(
    ScaffoldMessengerState messenger,
    AppLocalizations l10n,
    Future<MergeResult?> importing,
  ) async {
    try {
      final result = await importing;
      if (result == null) return;
      _notify(messenger, l10n.bundleImported(result.applied.length));
    } on WrongPasswordException {
      _notify(messenger, l10n.bundleWrongPassword);
    } on BundleFormatException {
      _notify(messenger, l10n.bundleInvalid);
    }
  }

  Future<String?> _askPassword(BuildContext context, String title) =>
      showDialog<String>(
        context: context,
        builder: (_) => _PasswordDialog(title: title),
      );
}

/// A status message replaces the one before it rather than queueing behind
/// it: what matters is how the latest attempt went, not the history.
void _notify(ScaffoldMessengerState messenger, String text) => messenger
  ..clearSnackBars()
  ..showSnackBar(SnackBar(content: Text(text)));

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 24, 16, 4),
    child: Text(text, style: Theme.of(context).textTheme.titleSmall),
  );
}

class _PeerTile extends ConsumerWidget {
  const _PeerTile({required this.peer});

  final Peer peer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final lastSync = peer.lastSyncAt?.toLocal();
    return ListTile(
      key: Key('peer-${peer.nodeId}'),
      leading: const Icon(Icons.phone_android_outlined),
      title: Text(peer.deviceName),
      subtitle: Text(
        lastSync == null
            ? l10n.syncNever
            : l10n.syncLastSync(lastSync, lastSync),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            key: Key('sync-now-${peer.nodeId}'),
            icon: const Icon(Icons.sync),
            tooltip: l10n.syncNow,
            onPressed: () => _syncNow(context, ref),
          ),
          IconButton(
            key: Key('remove-peer-${peer.nodeId}'),
            icon: const Icon(Icons.delete_outline),
            tooltip: l10n.delete,
            onPressed: () => _remove(context, ref),
          ),
        ],
      ),
    );
  }

  Future<void> _syncNow(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final engine = ref.read(syncEngineProvider);
    try {
      var result = await _attempt(engine, address: null);
      if (result == null) {
        if (!context.mounted) return;
        final address = await _askAddress(context, l10n);
        if (address == null) return;
        result = await _attempt(engine, address: address);
      }
      if (result == null) {
        _notify(messenger, l10n.syncUnreachable(peer.deviceName));
        return;
      }
      _notify(
        messenger,
        result.nothingNew
            ? l10n.syncNothingNew
            : l10n.syncDone(result.received, result.sent),
      );
    } on UnknownPeerException {
      _notify(messenger, l10n.syncNotAccepted);
    } on Object {
      _notify(messenger, l10n.syncFailed);
    }
  }

  /// Null when the peer could not be reached, which is the one failure that
  /// has a second try: the manual address.
  Future<SyncResult?> _attempt(
    SyncEngine engine, {
    required String? address,
  }) async {
    try {
      return await engine.syncWith(peer.nodeId, address: address);
    } on PeerUnreachableException {
      return null;
    }
  }

  Future<String?> _askAddress(BuildContext context, AppLocalizations l10n) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.syncUnreachable(peer.deviceName)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.syncEnterAddress),
            const SizedBox(height: 12),
            TextField(
              key: const Key('peer-address'),
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.url,
              decoration: InputDecoration(hintText: l10n.syncAddressHint),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            key: const Key('connect'),
            onPressed: () {
              final value = controller.text.trim();
              Navigator.of(context).pop(value.isEmpty ? null : value);
            },
            child: Text(l10n.syncConnect),
          ),
        ],
      ),
    );
  }

  Future<void> _remove(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.syncRemoveDevice(peer.deviceName)),
        content: Text(l10n.syncRemoveDeviceBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            key: const Key('confirm-remove-peer'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(databaseProvider).removePeer(peer.nodeId);
    }
  }
}

class _MyCodeDialog extends StatefulWidget {
  const _MyCodeDialog({
    required this.code,
    required this.deviceName,
    required this.address,
    required this.onRename,
  });

  final String code;
  final String deviceName;
  final String? address;
  final Future<void> Function(String name) onRename;

  @override
  State<_MyCodeDialog> createState() => _MyCodeDialogState();
}

class _MyCodeDialogState extends State<_MyCodeDialog> {
  late final _name = TextEditingController(text: widget.deviceName);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.syncShowCode),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // The name is part of the code, so a change only reaches the
            // other phone once the code is shown again.
            TextField(
              key: const Key('device-name'),
              controller: _name,
              decoration: InputDecoration(labelText: l10n.syncDeviceName),
              onChanged: (value) => widget.onRename(value.trim()),
            ),
            const SizedBox(height: 16),
            PairingCodeImage(key: const Key('pairing-code'), code: widget.code),
            const SizedBox(height: 12),
            Text(l10n.syncMyCodeHint, textAlign: TextAlign.center),
            if (widget.address != null) ...[
              const SizedBox(height: 8),
              SelectableText(
                l10n.syncAddressLabel(widget.address!),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const Key('close-my-code'),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.confirm),
        ),
      ],
    );
  }
}

class _PasswordDialog extends StatefulWidget {
  const _PasswordDialog({required this.title});

  final String title;

  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog> {
  final _password = TextEditingController();
  var _missing = false;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _password.text;
    if (value.isEmpty) {
      setState(() => _missing = true);
      return;
    }
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        key: const Key('bundle-password'),
        controller: _password,
        autofocus: true,
        obscureText: true,
        onSubmitted: (_) => _submit(),
        decoration: InputDecoration(
          labelText: l10n.bundlePassword,
          errorText: _missing ? l10n.bundlePasswordMissing : null,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          key: const Key('bundle-confirm'),
          onPressed: _submit,
          child: Text(l10n.confirm),
        ),
      ],
    );
  }
}

class _TransferCodeDialog extends StatelessWidget {
  const _TransferCodeDialog({required this.code, required this.sending});

  final String code;
  final Future<void> sending;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(l10n.transferCodeTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            code,
            key: const Key('transfer-code'),
            textAlign: TextAlign.center,
            style: theme.textTheme.displayMedium?.copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
              letterSpacing: 8,
            ),
          ),
          const SizedBox(height: 16),
          FutureBuilder<void>(
            future: sending,
            builder: (context, snapshot) => switch (snapshot.connectionState) {
              ConnectionState.done when snapshot.hasError => Text(
                l10n.bundleFailed,
                textAlign: TextAlign.center,
                style: TextStyle(color: theme.colorScheme.error),
              ),
              ConnectionState.done => Text(
                l10n.transferCodeHint,
                textAlign: TextAlign.center,
              ),
              _ => Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const LinearProgressIndicator(),
                  const SizedBox(height: 12),
                  Text(l10n.transferCodePreparing),
                ],
              ),
            },
          ),
        ],
      ),
      actions: [
        TextButton(
          key: const Key('close-transfer-code'),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.confirm),
        ),
      ],
    );
  }
}

class _TransferCodeInputDialog extends StatefulWidget {
  const _TransferCodeInputDialog();

  @override
  State<_TransferCodeInputDialog> createState() =>
      _TransferCodeInputDialogState();
}

class _TransferCodeInputDialogState extends State<_TransferCodeInputDialog> {
  final _code = TextEditingController();
  var _malformed = false;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _code.text.trim();
    if (!TransferCode.isWellFormed(value)) {
      setState(() => _malformed = true);
      return;
    }
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.bundleReceive),
      content: TextField(
        key: const Key('transfer-code-input'),
        controller: _code,
        autofocus: true,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        maxLength: TransferCode.length,
        onSubmitted: (_) => _submit(),
        decoration: InputDecoration(
          labelText: l10n.transferCodeEnter,
          errorText: _malformed ? l10n.transferCodeMissing : null,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          key: const Key('transfer-code-confirm'),
          onPressed: _submit,
          child: Text(l10n.confirm),
        ),
      ],
    );
  }
}

/// The code as a QR image, with the text it carries readable from the widget
/// so a spec can pick up what the other phone's camera would.
class PairingCodeImage extends StatelessWidget {
  const PairingCodeImage({required this.code, super.key});

  final String code;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    // The dialog measures its content's intrinsic width, and the QR image
    // lays itself out with a LayoutBuilder, which has none.
    dimension: 220,
    child: ColoredBox(
      color: Colors.white,
      child: QrImageView(data: code),
    ),
  );
}
