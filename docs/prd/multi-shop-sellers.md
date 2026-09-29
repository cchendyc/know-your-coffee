# PRD: Multi-shop sellers

Status: backend shipped, design ready, web/iOS UI pending.
Design: [Figma — Seller Hub](https://www.figma.com/design/3lR5C4ZhUKXctW3tnmDAts) frames
`Web / Multi-shop — Switcher open`, `Web / Multi-shop — All shops overview`,
`Web / Multi-shop — Copy listings`, `iOS / Multi-shop — Shop switcher`.

## Problem

Roasters and small chains run 2–5 locations. Today each shop is a silo: the
hub shows one shop, orders and shipments need a `shopId`, and listings are
re-typed per location. Owners of a second shop get the same "Become a seller"
pitch as a stranger.

## Goals

1. One account owns any number of shops; each shop keeps one owner.
2. See work across all shops at a glance, then drill into one.
3. Reuse listings between shops in one action.
4. Claiming a second shop reads as "add a location", not "become a seller".

Non-goals: several owners per shop, staff roles, shared inventory, chain-wide
pricing, auto-approving claims.

## Model

`shops.owner_user_id` already allows many shops per user. No migration.
Ownership still comes only from an approved `ShopClaim`.

## API (shipped)

| Surface | Change |
| --- | --- |
| `Query.mySeller: Seller` | `shops` plus summed `workload`. Null when the viewer owns nothing. |
| `SellerWorkload` | `toFulfill` (PLACED, READY_FOR_PICKUP), `toShip` (LABEL_READY, READY_FOR_DROPOFF), `lowStock`. |
| `CoffeeShop.workload` | Per-shop counts; null for non-owners. Drives switcher badges. |
| `myOrders`, `myShipments` | `shopId` now optional; omitted = every owned shop. |
| `copyProducts(fromShopId, toShopId, productIds?)` | Copies name, variant, price, threshold, photos. Stock 0, hidden. Both shops must be owned. |
| `ShopClaim.applicantOwnedShops` | Support sees existing shops when reviewing a new claim. |

## UX

- Switcher (sidebar on web, header line on iOS) lists All shops, each owned
  shop with workload badges, pending claims greyed, and Add another shop.
- All shops overview: four totals, a card per shop with its own counts and
  status (Verified, Finish setup), cross-shop recent orders with a Shop column.
- Copy listings modal: pick target shop, tick listings, callout states the
  stock 0 / hidden rule. Button reads "Copy N listings to <shop>".
- Shop page: sellers see "Own this location too? Add it to your Seller Hub"
  (shipped on web). Onboarding stays per shop; a second shop's walkthrough
  should be shortened later.

## Success

- A 3-shop owner clears all PLACED orders without switching shops.
- Second-location listings set up in under 2 minutes via copy.
- Zero support tickets asking "how do I add my other shop".

## Open questions

- Fast-track or auto-approve a claim on a sibling `Chain` location?
- Persist last-selected shop server-side or per device?
- Shorter onboarding for shop 2+: which steps can be skipped?
