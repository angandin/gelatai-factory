# Weekly Shop Registry Notebook

`nb_update_shop_registry` creates an initial registry state effective
2026-09-01 and applies one deterministic, idempotent update per calendar week.

Weekly changes include:

- production batches correlated to the preceding Eventhouse telemetry window;
- factory-to-shop shipments and product/batch shipment lines;
- receipt of due shipments and corresponding inventory increases;
- stock consumption and replenishment;
- one rotating featured flavor per shop;
- a 2% catalog price review every four weeks;
- employee rotation every eight weeks;
- an auditable run ledger and change log.

The notebook discovers `GelatAI_shopdb` and `GelatAI-rtdata` dynamically in its
current workspace. It uses factory telemetry event/anomaly counts to adjust
production and retains the exact telemetry window on every production batch.
It authenticates with Entra access tokens and contains no connection string,
password, or secret.

The SQL Database is the only persisted copy of shop, product, inventory, and
shipment data. The notebook does not publish reporting copies to the Lakehouse.
It idempotently removes the four legacy Delta copies (`dim_shop`, `dim_product`,
`shop_availability`, and `shipment_flow`) if they exist.

Deploy or update the notebook and its Monday 02:00 UTC schedule:

```powershell
& .\Fabric\ws_wu3_gelatai\nb_update_shop_registry.Notebook\deploy.ps1
```
