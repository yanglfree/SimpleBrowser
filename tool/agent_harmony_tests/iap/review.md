# IAP recovery review

Scope: task-owned changes only. Existing onboarding, paywall selection and agreement/UI edits remain user-owned and are not staged.

## Findings and resolution

- Server JWT creation lacked a trusted ZhuoBrowser Huawei application ID. The server catalog now supplies it; client values and another app's global configuration cannot override it.
- Pending payment recovery discarded its result. The shared kit now awaits bounded recovery and invokes the success callback, updates membership state and prevents overlapping purchase/restore actions.
- Page disappearance cancels delayed recovery and suppresses late success callbacks.
- Restore no longer treats server outages as an empty purchase result. Each unfinished purchase is acknowledged only after that purchase is verified and delivered.
- ZhuoBrowser subscriptions use the provider's active status and `expiresTime`, not a locally calculated month/year duration. Revoked and identity-mismatched purchase data is rejected.

## Harmony review

| Dimension | Result |
| --- | --- |
| Style | Task-owned changes match the existing file style. |
| Types/modeling | Typed recovery result and cancellation controller; no `any` or `ESObject`. |
| ArkUI state | Success updates the existing local state and parent callback; cancellation owns its timer. |
| Rendering | No network calls added to build functions; existing shared page retained. |
| Routing | No route, storage schema or navigation contract changes. |
| Errors/logging | Retry errors remain visible to the flow; logs omit purchase tokens and JWS. |

P0: 0 open. P1: 0 open in the changed recovery path. P2: full store lifecycle coverage remains unexecuted and is recorded as not-run.

## Official references

- [Server JWT](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/iap-jwt-description), updated 2026-08-31: `aid` is the Huawei application ID.
- [IAP data model](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/iap-data-model), fetched 2026-09-03: `SubscriptionStatus.status`, `expiresTime`, and purchase `revocationTime`.
- [Subscription flow](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/iap-integrate-subscription), fetched 2026-09-03: deliver verified services before acknowledging purchase delivery.

## Acceptance boundary

The existing lifetime sandbox purchase and member UI are recovered. This is not evidence for a new charge, monthly/yearly real-device purchase, renewal, refund, account switching or AppGallery review. No secrets, purchase tokens, raw JWS or account identifiers are included in the report. Device screenshots are from the first recovery build; the final build also includes tested page-disappearance guards.
