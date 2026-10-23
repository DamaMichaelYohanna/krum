# Krum backend architecture

Krum is organised by business capability, not by Django technical layer:

- `apps/catalog`: products, categories, units, barcode, and pricing
- `apps/inventory`: balances and immutable stock movements
- `apps/purchasing`: supplier stock receipts
- `apps/sales`: checkout and sale reversals
- `apps/customers`: customer balances and payment allocation
- `apps/finance`: expenses, profitability, and payables
- `apps/reporting`: read-only dashboards and exports
- `apps/sync`: idempotent offline ingestion
- `apps/common`: audit and cross-cutting primitives

`store` is the temporary persistence compatibility boundary. It retains the
already-migrated Django model labels, so deployed databases do not require a
risky table rename. New behavior must be placed in the owning `apps/<domain>`
package. A later, separately tested migration can move model ownership one
bounded context at a time while retaining explicit `db_table` names.

HTTP handlers are intentionally thin: validate input, determine the verified
tenant, apply a role policy, then call exactly one domain service. Domain
services own transactions and write audit events. Queries must always begin
with `business=<verified business>` before accepting any client-provided ID.
