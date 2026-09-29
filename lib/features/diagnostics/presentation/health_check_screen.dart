import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/error/failure.dart';
import '../../../core/graphql/graphql_client.dart';
import '../../../core/notifications/notification_service.dart';
import '../../../core/storage/secure_token_store.dart';
import '../../../core/store/store_controller.dart';
import '../../../core/widgets/failure_message.dart';
import '../../../l10n/l10n.dart';
import '../data/store_config_repository.dart';

/// Phase 0 diagnostics: shows live `storeConfig` for the active store view and a
/// language toggle that proves the atomic store switch (header flip + cache
/// reset + RTL rebuild + font swap).
class HealthCheckScreen extends ConsumerWidget {
  const HealthCheckScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final store = ref.watch(storeControllerProvider);
    final config = ref.watch(storeConfigProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.healthCheckTitle),
        actions: [
          _LanguageToggle(
            activeLocale: store.activeLocale,
            onChanged: (locale) =>
                ref.read(storeControllerProvider.notifier).switchLocale(locale),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(storeConfigProvider),
        child: ListView(
          padding: const EdgeInsetsDirectional.all(16),
          children: [
            Text(
              l10n.healthCheckSubtitle,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            config.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 48),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (error, _) => _ErrorBlock(
                message: error is Failure
                    ? failureMessage(context, error)
                    : l10n.errorGeneric,
                // Raw cause so iOS/transport failures are diagnosable on-device
                // (FailureKind: network=DNS/TLS, service=WAF/HTML, server=GraphQL).
                detail: error.toString(),
                onRetry: () => ref.invalidate(storeConfigProvider),
                retryLabel: l10n.actionRetry,
              ),
              data: (data) => _StoreConfigCard(
                rows: <({String label, String value})>[
                  (label: l10n.fieldStoreCode, value: data.storeCode),
                  (label: l10n.fieldLocale, value: data.locale),
                  (label: l10n.fieldCurrency, value: data.currency),
                  (label: l10n.fieldBaseUrl, value: data.baseUrl),
                  (label: l10n.fieldMediaUrl, value: data.baseMediaUrl),
                ],
              ),
            ),
            const SizedBox(height: 24),
            const _PushDiagnostics(),
            const SizedBox(height: 24),
            const _TokenDiagnostics(),
            const SizedBox(height: 24),
            const _TransportProbe(),
            const SizedBox(height: 24),
            if (store.stores.isNotEmpty) ...[
              Text(
                l10n.availableStoresTitle,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              for (final view in store.stores)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('${view.storeName} · ${view.storeCode}'),
                  subtitle: Text('${view.locale} · ${view.currency}'),
                  trailing: view.isDefault
                      ? Chip(label: Text(l10n.fieldDefaultView))
                      : null,
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StoreConfigCard extends StatelessWidget {
  const _StoreConfigCard({required this.rows});

  final List<({String label, String value})> rows;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsetsDirectional.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final row in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 110,
                      child: Text(
                        row.label,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    Expanded(child: Text(row.value.isEmpty ? '—' : row.value)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Push / FCM diagnostics — surfaces the FCM availability + registration token
/// so it can be copied and pasted into Firebase Console → "Send test message"
/// to confirm APNs/FCM delivery on a real device.
class _PushDiagnostics extends StatefulWidget {
  const _PushDiagnostics();

  @override
  State<_PushDiagnostics> createState() => _PushDiagnosticsState();
}

class _PushDiagnosticsState extends State<_PushDiagnostics> {
  late Future<
    ({String permission, String? regStatus, String? apns, String? fcm})
  >
  _diag;

  @override
  void initState() {
    super.initState();
    _diag = _gather();
  }

  Future<({String permission, String? regStatus, String? apns, String? fcm})>
  _gather() async {
    final svc = NotificationService.instance;
    return (
      permission: await svc.permissionStatus(),
      regStatus: await svc.apnsRegistrationStatus(),
      apns: await svc.apnsToken(),
      fcm: await svc.token(),
    );
  }

  void _refresh() => setState(() => _diag = _gather());

  Future<void> _copy(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).actionLinkCopied)),
      );
    }
  }

  Widget _line(String label, String value) => Padding(
    padding: const EdgeInsets.only(top: 4),
    child: SelectableText(
      '$label: $value',
      style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final svc = NotificationService.instance;
    return Card(
      child: Padding(
        padding: const EdgeInsetsDirectional.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Push notifications (FCM)',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  tooltip: 'Refresh',
                  icon: const Icon(Icons.refresh),
                  onPressed: _refresh,
                ),
              ],
            ),
            _line('FCM available', svc.fcmAvailable ? 'yes' : 'no'),
            if (svc.initError != null) _line('Init error', svc.initError!),
            FutureBuilder<
              ({String permission, String? regStatus, String? apns, String? fcm})
            >(
              future: _diag,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return _line('Status', 'checking…');
                }
                final data = snapshot.data;
                if (data == null) return _line('Status', 'error');
                final apns = data.apns;
                final apnsText = apns == null
                    ? 'null — not ready / no Push capability / permission'
                    : (apns.startsWith('error') || apns.startsWith('n/a')
                          ? apns
                          : 'present (${apns.length} chars)');
                final fcm = data.fcm;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _line('Permission', data.permission),
                    _line('APNs registration', data.regStatus ?? 'not reported'),
                    _line('APNs token', apnsText),
                    const SizedBox(height: 8),
                    if (fcm == null || fcm.isEmpty)
                      const Text(
                        'FCM token: unavailable. Read the lines above — '
                        'an Init error means Firebase failed; APNs null while '
                        'available=yes means Push capability/provisioning/'
                        'permission; permission=denied means grant it.',
                        style: TextStyle(fontSize: 12),
                      )
                    else ...[
                      const Text(
                        'FCM token (tap to copy):',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 6),
                      InkWell(
                        onTap: () => _copy(fcm),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Theme.of(
                              context,
                            ).colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: SelectableText(
                            fcm,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: OutlinedButton.icon(
                          onPressed: () => _copy(fcm),
                          icon: const Icon(Icons.copy, size: 18),
                          label: Text(l10n.actionCopy),
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Customer-token diagnostics. The app attaches any stored token as
/// `Authorization: Bearer` on every request; a stale/expired one makes Magento
/// reject everything ("Consumer key has expired") even though guest GraphQL
/// (the raw transport test, no token) returns 200. This card shows whether a
/// token is stored, wipes it, **re-reads to confirm the iOS Keychain delete
/// took**, and re-runs the store-view test as guest.
class _TokenDiagnostics extends ConsumerStatefulWidget {
  const _TokenDiagnostics();

  @override
  ConsumerState<_TokenDiagnostics> createState() => _TokenDiagnosticsState();
}

class _TokenDiagnosticsState extends ConsumerState<_TokenDiagnostics> {
  String _status = '…';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final token = await ref.read(secureTokenStoreProvider).read();
    if (!mounted) return;
    setState(() {
      _status = (token == null || token.isEmpty)
          ? 'none — requests go out as guest'
          : 'PRESENT (${token.length} chars, '
                '${token.substring(0, token.length < 6 ? token.length : 6)}…) '
                '— sent on every request';
    });
  }

  Future<void> _clear() async {
    setState(() => _busy = true);
    final store = ref.read(secureTokenStoreProvider);
    await store.clear();
    // Re-read to confirm the iOS Keychain delete actually removed the item.
    final after = await store.read();
    ref.invalidate(graphqlClientProvider);
    ref.invalidate(storeConfigProvider);
    await _refresh();
    if (!mounted) return;
    setState(() => _busy = false);
    final wiped = after == null || after.isEmpty;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          wiped
              ? 'Token cleared — re-running the store view test as guest.'
              : 'WARNING: token still present after delete (iOS Keychain).',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsetsDirectional.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Customer token',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            const Text(
              'Browsing needs NO token (guest GraphQL returns 200). A stale '
              'token makes every request fail. Clear it to recover.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 10),
            SelectableText(
              'Stored token: $_status',
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: FilledButton.icon(
                onPressed: _busy ? null : _clear,
                icon: const Icon(Icons.logout, size: 18),
                label: const Text('Clear token & retry as guest'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Raw transport probe — POSTs `storeConfig` through the **platform** HTTP
/// client (NSURLSession on iOS) with the app's real headers and shows the raw
/// status + body. Lets us see exactly what the edge (CloudFront/WAF) returns on
/// the actual iOS transport: a JSON `200` (good) vs an HTML block page (the
/// `service` error). Bypasses graphql_flutter and the link chain entirely.
class _TransportProbe extends ConsumerStatefulWidget {
  const _TransportProbe();

  @override
  ConsumerState<_TransportProbe> createState() => _TransportProbeState();
}

class _TransportProbeState extends ConsumerState<_TransportProbe> {
  Future<
    ({
      int status,
      String contentType,
      String contentEncoding,
      int bytes,
      String body,
    })
  >?
  _result;

  void _run() {
    final config = ref.read(appConfigProvider);
    final storeCode = ref.read(storeControllerProvider).activeStoreCode;
    setState(() => _result = rawTransportProbe(config, storeCode));
  }

  Future<void> _copy(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).actionLinkCopied)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsetsDirectional.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Raw transport test',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            const Text(
              'POSTs storeConfig through the platform HTTP client '
              '(NSURLSession on iOS) and shows the raw edge response.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: FilledButton(onPressed: _run, child: const Text('Run')),
            ),
            if (_result != null) ...[
              const SizedBox(height: 12),
              FutureBuilder<
                ({
                  int status,
                  String contentType,
                  String contentEncoding,
                  int bytes,
                  String body,
                })
              >(
                future: _result,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Text('Running…');
                  }
                  if (snapshot.hasError) {
                    final text = 'Transport error: ${snapshot.error}';
                    return InkWell(
                      onTap: () => _copy(text),
                      child: SelectableText(
                        text,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                          color: Colors.red,
                        ),
                      ),
                    );
                  }
                  final data = snapshot.data!;
                  final text =
                      'HTTP ${data.status}\n'
                      'content-type: ${data.contentType}\n'
                      'content-encoding: ${data.contentEncoding}\n'
                      'bytes: ${data.bytes}\n\n'
                      '${data.body}';
                  return InkWell(
                    onTap: () => _copy(text),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: SelectableText(
                        text,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ErrorBlock extends StatelessWidget {
  const _ErrorBlock({
    required this.message,
    required this.onRetry,
    required this.retryLabel,
    this.detail,
  });

  final String message;
  final String? detail;
  final VoidCallback onRetry;
  final String retryLabel;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(message, textAlign: TextAlign.center),
        if (detail != null) ...[
          const SizedBox(height: 8),
          SelectableText(
            detail!,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 12,
              fontFamily: 'monospace',
              color: Colors.grey,
            ),
          ),
        ],
        const SizedBox(height: 16),
        FilledButton(onPressed: onRetry, child: Text(retryLabel)),
      ],
    );
  }
}

class _LanguageToggle extends StatelessWidget {
  const _LanguageToggle({required this.activeLocale, required this.onChanged});

  final String activeLocale;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 8),
      child: SegmentedButton<String>(
        showSelectedIcon: false,
        segments: const [
          ButtonSegment<String>(value: 'en', label: Text('EN')),
          ButtonSegment<String>(value: 'ar', label: Text('AR')),
        ],
        selected: {activeLocale == 'ar' ? 'ar' : 'en'},
        onSelectionChanged: (selection) => onChanged(selection.first),
      ),
    );
  }
}
