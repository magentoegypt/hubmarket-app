import 'bootstrap.dart';

/// Default entrypoint (dev). Prefer the flavor entrypoints with
/// `--dart-define-from-file`, e.g.:
///   flutter run -t lib/main_dev.dart --dart-define-from-file=config/dev.json --flavor dev
void main() => bootstrap();
