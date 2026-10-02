# City Manager integration

The account address form and guest checkout share the Hub Market directory at `/citymanager/directory/index`. Egypt uses Governorate/City, Saudi Arabia Region/City, USA State/City, and UAE City/Locality without an Emirate selector. UAE locality is required only when active localities are configured for the selected city, as approved by the project owner.

Standard Magento country, region ID and city fields remain the API contract. UAE city is saved as `City — Locality`, or `City` when no localities exist. Magento resolves the names to directory IDs and preserves address snapshots on existing orders. Dependent selections clear on country/region changes; loading failures block submission and offer Retry.

Verification on 2 October 2026: 2,039 Flutter tests passed, including the EN/AR host device-layout audit; the additional locality-rule tests passed (10 City Manager tests total). All 125 GraphQL operations and 26 fragments validated offline with zero problems; 17 Python tool tests passed. These checks use fake repositories and do not prove native device, live order, or carrier behavior. Review builds are separate from the existing main-branch store deployment workflow.

The directory is admin-managed. Imported geographic coverage is not a promise of seller delivery coverage. UAE locality coverage is currently limited; cities without localities accept city-only addresses.
