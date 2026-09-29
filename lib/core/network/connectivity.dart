import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../error/failure.dart';

/// The device's network state as the OS reports it — `true` while a Wi-Fi,
/// mobile, ethernet or VPN link is up. That is what Figma S3 is about ("Check
/// your Wi-Fi or mobile data"); whether the store itself answers is the
/// requests' business.
///
/// A provider of the source (not the state) so tests can drive it.
final networkStatusSourceProvider = Provider<Stream<bool> Function()>(
  (ref) => _watchPlatform,
);

/// Emits the current network state, then every change. Invalidate it to
/// re-check (the offline banner's Retry).
final connectivityProvider = StreamProvider<bool>(
  (ref) => ref.watch(networkStatusSourceProvider)(),
);

/// True only once the OS has said there is no network — unknown counts as
/// online, so nothing flashes "offline" while the first check runs.
final isOfflineProvider = Provider<bool>(
  (ref) => ref.watch(connectivityProvider).valueOrNull == false,
);

/// Whether [error] means the request never reached the store.
bool isNetworkFailure(Object? error) =>
    error is Failure && error.kind == FailureKind.network;

Stream<bool> _watchPlatform() async* {
  final connectivity = Connectivity();
  final List<ConnectivityResult> first;
  try {
    first = await connectivity.checkConnectivity();
  } on Object {
    // No plugin behind the channel (widget tests, an unsupported platform):
    // assume online and don't open the platform's event stream at all.
    yield true;
    return;
  }
  yield _online(first);
  yield* connectivity.onConnectivityChanged.map(_online);
}

bool _online(List<ConnectivityResult> results) =>
    results.any((r) => r != ConnectivityResult.none);
