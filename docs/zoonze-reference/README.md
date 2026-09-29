# Zoonze reference — not Hub Market facts

The Hub Market app started from the Zoonze storefront app
(`magentoegypt/zoonze-app` @ 8034e97). These documents came with that code and
are kept only for the reasoning they record — how the deep links, the codegen
pipeline, CI, guest order tracking, checkout addresses, performance work, push
contract, customer-session lifetime and App Store submission were worked out.

**Nothing here describes Hub Market.** Store codes, hosts (`zoonze.com`), bundle
and application ids, backend modules, payment gateways, listing copy and
App Store answers are Zoonze's. Before relying on anything in these files,
check it against [`CLAUDE.md`](../../CLAUDE.md), the live schema
(`lib/core/graphql/schema.graphql`) and the code.

Removed rather than kept: the Zoonze Figma handoff and phase plan, the N-Genius
/ Tabby payment and saved-card contracts, the Zoonze home-sections and OTP
module contracts, the Zoonze backend blocker and QA-flag lists, the Huawei
AppGallery submission notes and the export script for the Zoonze Figma file.
