# M8 plan — Purchases (SPEC §13, §16 M8)

Written and implemented 2026-09-18 while Jeremy was away.

- **`LivePurchaseService`** (StoreKit 2): `Product.products(for:)`, `product.purchase()` with verification and `finish()`, `Transaction.currentEntitlements` for the unlock (revoked transactions ignored, so refunds lock again), `Transaction.updates` listened once and broadcast to `AppState` (purchase, restore, Family Sharing, refund), `AppStore.sync()` for Restore.
- **Free-summary counter** (`FreeSummaryCounter`): Keychain (`AfterFirstUnlockThisDeviceOnly`, not synced) mirrored in UserDefaults; the larger value wins, so it survives a reinstall and can't be reset by clearing one store.
- **Gating**: the pipeline's summarizing stage stops the 4th summary with `SummarizationError.freeLimitReached` (recording still `.ready`, transcript untouched) and counts each generated summary while locked, any template. The Summary tab shows "n of 3 free summaries used" and, at the limit, an **Unlock** button. Exports: free tier keeps the two plain-text copies; files, email, and Reminders open the paywall (`ExportGate`).
- **Paywall** (`PaywallView` + `PaywallModel`): price from the store, benefits, Unlock, Restore Purchases, Family Sharing note, terms/privacy links (hidden until `AppLinks` has real URLs). Never on launch. On iPhones without Apple Intelligence it says so plainly and sells the exports (SPEC §13.3 open decision, recorded in DECISIONS).
- **Local testing**: `VeraFlow.storekit` (non-consumable, family shareable, $24.99 placeholder) attached to the scheme's run and test actions.

Device checks: buy in the StoreKit test environment (Xcode → Debug → StoreKit → Manage Transactions), refund it and watch the app lock again, restore on a second device with the same sandbox account, Family Sharing in TestFlight, and delete + reinstall to confirm the free count holds.
