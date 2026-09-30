import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:graphql_flutter/graphql_flutter.dart';

import '../error/failure.dart';
import '../graphql/graphql_client.dart';
import 'hm_app_config.dart';
import 'hubapp_models.dart';
import 'hubapp_query.dart';

/// Reads `hmAppConfig` over the public GET client. The same request is the
/// HubApp availability probe: [HubAppMissing] means the module isn't deployed.
class HubAppConfigRepository {
  HubAppConfigRepository(this._client, {this.timeout = defaultTimeout});

  final GraphQLClient _client;

  /// Bounds the probe, retries included, so a dead network can't hold the
  /// launch — the app then carries on as Build 1 and probes again later.
  final Duration timeout;

  static const Duration defaultTimeout = Duration(seconds: 12);

  /// The document for Android. The platform goes inline, never as a
  /// `$platform: HmPlatform` variable: while the module is missing, a
  /// variable of an unknown type makes Magento answer HTTP 500 instead of
  /// "Cannot query field" (see [runHubAppQuery]).
  ///
  /// Carries the P3.1 fields too — the satellite list, the free-shipping
  /// threshold and the storefront's search layout — so they cost no request
  /// of their own; a backend without them is read with [p2Document] (see
  /// [fetch]).
  static const String document = r'''
query HmAppConfig {
  hmAppConfig(platform: ANDROID) {
    store_code
    locale
    search { hint trending_terms }
    algolia {
      application_id search_api_key valid_until index_prefix
      product_index category_index page_index
      facets { attribute type label }
      sorts { index attribute direction label }
      suggestion_index suggestion_count currency_code price_group
      max_values_per_facet product_suggestions category_suggestions
      page_suggestions category_separator categories_outside_menu
    }
    contact { whatsapp_number whatsapp_url phone email hours }
    version { platform min_version latest_version store_url message }
    maintenance { enabled message retry_after_minutes }
    features { code enabled }
    capabilities
    shipping { free_over { value currency } }
  }
}
''';

  /// [document] as the first HubApp release (PR #22) answers it, without the
  /// P3.1 fields: read when the module is there but older than this build.
  static const String p2Document = r'''
query HmAppConfigP2 {
  hmAppConfig(platform: ANDROID) {
    store_code
    locale
    search { hint trending_terms }
    algolia {
      application_id search_api_key valid_until index_prefix
      product_index category_index page_index
    }
    contact { whatsapp_number whatsapp_url phone email hours }
    version { platform min_version latest_version store_url message }
    maintenance { enabled message retry_after_minutes }
    features { code enabled }
  }
}
''';

  /// [base] for [platform]; without one the server returns every platform's
  /// version policy and only the all-platform flags.
  static String documentFor(HmPlatform? platform, {String base = document}) =>
      switch (platform) {
        HmPlatform.android => base,
        null => base.replaceFirst('(platform: ANDROID)', ''),
        final other => base.replaceFirst(
          '(platform: ANDROID)',
          '(platform: ${other.wire})',
        ),
      };

  /// This store view's settings (the `Store` header). Throws [HubAppMissing]
  /// when the server has no `hmAppConfig`, a `Failure` for anything else.
  ///
  /// A server whose `hmAppConfig` lacks a field this build asks for — HubApp
  /// deployed before the P3.1 additions (`capabilities`, `shipping`, the
  /// Algolia layout) — is asked again with [p2Document]: the module is there,
  /// so the answer is Build 2 without those extras, not "not deployed". Its
  /// config then lists no capabilities, and every satellite field a shared
  /// document would need stays off.
  Future<HmAppConfig> fetch({HmPlatform? platform}) async {
    Map<String, dynamic> data;
    try {
      data = await runHubAppQuery(
        _client,
        documentFor(platform),
        timeout: timeout,
      );
    } on HubAppMissing catch (missing) {
      if (isMissingRootField(missing, 'hmAppConfig')) rethrow;
      data = await runHubAppQuery(
        _client,
        documentFor(platform, base: p2Document),
        timeout: timeout,
      );
    }
    final json = data['hmAppConfig'];
    try {
      if (json is Map<String, dynamic>) return HmAppConfig.fromJson(json);
    } on FormatException catch (error) {
      throw Failure(FailureKind.server, detail: error.message);
    }
    // Non-null in the schema: an answer without it is a broken response, not
    // a missing module.
    throw const Failure(FailureKind.server, detail: 'hmAppConfig is empty');
  }
}

final hubAppConfigRepositoryProvider = Provider<HubAppConfigRepository>(
  (ref) => HubAppConfigRepository(ref.watch(publicGraphqlClientProvider)),
);
