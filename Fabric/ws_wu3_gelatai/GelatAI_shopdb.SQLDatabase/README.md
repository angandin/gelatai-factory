# GelatAI Shop Database

`GelatAI_shopdb` is the Fabric SQL Database for shop registry, operational data,
and normalized sales in workspace `ws_wu3_gelatai`. The shop app writes new sales
directly to this database; the factory retains its separate Event Hub path.

## Schema

| Object | Purpose |
|---|---|
| `dbo.Shop` | Shop identity, address, location, time zone, and lifecycle |
| `dbo.Employee` | Employees assigned to a shop |
| `dbo.Product` | Master product catalog |
| `dbo.ShopProduct` | Products assigned and priced for each shop |
| `dbo.SourceSystem` | Registry of systems that produce related data |
| `dbo.ShopExternalReference` | Maps an external `ShopId` to the registry shop |
| `dbo.ProductExternalReference` | Maps an external flavor key to the registry product |
| `dbo.Factory` | Factory identity and Eventhouse telemetry source |
| `dbo.ProductionBatch` | Product output correlated to an Eventhouse telemetry window |
| `dbo.Inventory` | Current stock and reorder level per shop/product |
| `dbo.Shipment` | Factory-to-shop shipment headers |
| `dbo.ShipmentItem` | Products, quantities, and production batches in a shipment |
| `dbo.RegistrySimulationRun` | Idempotency ledger for weekly registry updates |
| `dbo.RegistryChangeLog` | Audit trail of generated weekly registry changes |
| `dbo.LogisticsSimulationRun` | Idempotency and telemetry summary for weekly logistics |
| `dbo.vw_ShopCatalog` | Active shop assortment with inventory/reorder status |
| `dbo.vw_ApiShopCatalogMatch` | Direct bridge from `apishop` event keys to registry IDs |
| `dbo.vw_FactoryShopProductFlow` | End-to-end factory batch, shipment, product, and shop lineage |
| `dbo.Sale` | One transaction header, typed UTC/local dates, currency, and receipt totals |
| `dbo.SaleItem` | One flavor line with product ID and allocated discounts/tax |
| `dbo.RecordApiShopSale` | Atomic, mapping-validated, duplicate-safe header/line write |
| `dbo.vw_Sales` | Transaction-grain reporting without repeated header totals |
| `dbo.vw_SaleItems` | Flavor-grain reporting using additive line amounts |

The `apishop` receipt fields match as follows:

- `ShopId` = `dbo.vw_ApiShopCatalogMatch.ApiShopShopId`
- `Flavors[].Flavor` = `dbo.vw_ApiShopCatalogMatch.ApiShopFlavor`

The companion `nb_update_shop_registry` notebook creates a baseline effective
2026-09-01, then updates inventory, featured flavors, prices, and staffing on
its weekly schedule.

## Deploy from zero

Prerequisites:

- Azure CLI authenticated to the Fabric tenant with `az login`
- Workspace Member or Admin access
- Go `sqlcmd` installed (`winget install Microsoft.Sqlcmd`)

From the repository root:

```powershell
& .\Fabric\ws_wu3_gelatai\GelatAI_shopdb.SQLDatabase\deploy.ps1
```

The deployment is idempotent. It creates the Fabric SQL Database when absent,
waits for provisioning, discovers the generated SQL endpoint, applies
`schema.sql`, and synchronizes the static `apishop` registry through
`seed-apishop.sql`. Re-running it preserves existing operational data and
updates the registry idempotently.

## Add sales storage to the existing database

```powershell
& .\Fabric\ws_wu3_gelatai\GelatAI_shopdb.SQLDatabase\deploy.ps1 -SalesOnly
```

This path applies only [sales-schema.sql](sales-schema.sql). It requires the
database to exist and never creates a database, reseeds catalog data, or drops
sales. Both the base schema and sales migration can be rerun without deleting
sales facts. Full deployment applies base schema, registry seed, then sales schema.

The app submits one parameterized JSON command to `dbo.RecordApiShopSale`;
JSON is parsed into relational columns, not stored as the analytics payload.
Header and lines commit or roll back together. The unique source-system/
transaction-ID key and canonical payload hash make identical retries idempotent.
Conflicting reuse of a transaction ID is rejected.

## App identity and least privilege

The app uses its Container App system-assigned managed identity:

1. Enable the Fabric tenant setting permitting the app's service principal.
2. Grant that identity **Read** on this database item in Fabric.
3. Connect as an authorized Entra administrator to the writable endpoint and run
   [grant-sales-access.sql](grant-sales-access.sql). The identity display name is
   `gelatai-shops`; adjust it if the Container App is renamed. Confirm it resolves
   to the intended system-assigned identity, not the shared ACR-pull identity.
   `FROM EXTERNAL PROVIDER` requires Directory Readers access; duplicate directory
   names must be disambiguated by an administrator before running the script.

The script grants only execution of the sale-recording procedure, SELECT on the
catalog-mapping view, and SELECT on the required shop ID/time-zone columns.
It does not grant DDL, direct sale-table writes, or `db_owner`. All access changes
are manual rollout steps, not app-startup behavior.

Discover `properties.serverFqdn` and `properties.databaseName` through
`GET /v1/workspaces/{workspaceId}/sqlDatabases/{itemId}`. Configure the app with
those values, not the read-only SQL analytics endpoint. SQL connections use
Entra authentication, encryption, and certificate validation, without passwords.
Fabric REST scripts must include `x-ms-fabric-skill: sqldb-cli`.

## Analytics and Lakehouse consumption

[sales-analytics.sql](sales-analytics.sql) demonstrates receipt and flavor
aggregations by shop-local date, shop/country, currency, serving type, and channel.
Always retain currency separation; no FX rates are fabricated.

`NetSalesAmount` excludes tax; `TotalAmount` includes tax. Discounts and tax use
deterministic proportional minor-unit allocation, so corresponding line sums
equal the header exactly. Current currency precision is EUR/USD: 2, JPY: 0.
City/country/currency/time-zone and flavor labels are captured with each sale;
catalog names in reporting joins remain current registry attributes.

The existing SQL-to-Lakehouse notebook discovers all physical user tables and
can include `Sale` and `SaleItem`. It does not copy views, indexes, or constraints.
With continuous sale writes, its per-table copies and equality checks are not a
consistent database-wide snapshot. Pause the shop simulator around a manual
copy, or use a separately designed consistent/incremental ingestion process.
The mirrored SQL analytics endpoint is preferable for heavy BI queries; SQL
views are not mirrored, so recreate analytical joins there or model the physical
tables. Existing notebooks, reports, and semantic models are not changed here.

No Eventhouse history is backfilled and no Eventstream resources are removed.
