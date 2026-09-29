/// The Hub Market App (`MagentoEgypt_HubApp*`) foundation, in one import:
///
/// * availability — [hubAppStatusProvider] (`available` / `unavailable` /
///   `unknown`), [hubAppProvider] (the probe itself), [hubAppFlagProvider];
/// * settings — [hmAppConfigProvider] ([HmAppConfig]);
/// * public reads — [runHubAppQuery] over `publicGraphqlClientProvider`
///   (`core/graphql/graphql_client.dart`: GET, token-less, `Store` header),
///   which throws [HubAppMissing] when the server lacks the hm* schema;
/// * shared contract types — [HmLink], [HmSellerSummary], [HmStoreCard], …
///   and their GraphQL fragments ([HmFragments]).
///
/// The contract: `lib/core/graphql/hubapp.graphql`.
library;

export 'hm_app_config.dart';
export 'hubapp_config_repository.dart';
export 'hubapp_models.dart';
export 'hubapp_providers.dart';
export 'hubapp_query.dart';
