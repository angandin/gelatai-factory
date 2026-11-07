# Shop sales analytics

Open [GelatAI Shop Sales.pbip](./GelatAI%20Shop%20Sales.pbip) in a current
Power BI Desktop with PBIP support. It references the
[sales model](./sm_gelatai_shop_sales.SemanticModel) and
[three-page report](./rp_gelatai_shop_sales.Report).
The captured service metadata is the baseline; the local report binding is
intentionally portable `byPath`. See [workspace manifest](workspace-manifest.json)
for source hashes, overrides and unresolved full-workspace recreation blockers.

## Published artifacts

- [Sales report](https://app.powerbi.com/groups/97d5eec3-d6d9-44bb-80aa-279e286309b3/reports/5909e022-eac9-4d48-94ab-3f5632eccc0e)
- Semantic model: `sm_gelatai_shop_sales`
  (`56fbeb83-e96d-45d4-a408-744fd24f5acf`).
- Pages: Sales at a glance; Products & payment mix; Weather & timing.
- Both Fabric create operations succeeded and the report-to-model binding and
  page inventory were verified.

## Direct Lake source and freshness

The model uses **Direct Lake on OneLake**, not Import or DirectQuery. All 11
partitions are entity partitions referencing Delta tables under
`GelatAI_lakehouse.sales_analytics`. The shared `AzureStorage.DataLake`
expression points at the existing Lakehouse; no SQL endpoint, database
credential or Power Query SQL join is used by the semantic model.

The dedicated `nb_shop_sales_directlake` Fabric notebook prepares those tables
from **only** the existing `sc_shopdb.Sale`, `sc_shopdb.SaleItem` and
`sc_shopdb.Shop` shortcuts. Its source is
[shop-sales-directlake.sql](./shop-sales-directlake.sql); the generated
[notebook](./nb_shop_sales_directlake.Notebook/notebook-content.py) contains
SQL cells and an explicit default Lakehouse dependency.

The captured preparation notebook has **no schedule**, so hourly freshness is
not guaranteed. Recreation must preserve that absence. A future operator may
explicitly choose on-demand or scheduled preparation; neither was performed
during this read-only alignment. Spark runs consume Fabric capacity.
On 2 November 2026 the previously published preparation notebook was absent;
it was restored as `9eb8960b-1eae-43a3-aabc-8a7c482ca96a` and run successfully
for the integer shop-key migration. The replacement notebook currently has
**no schedule**. The former notebook and schedule IDs are no longer current.
Keep **Keep your Direct Lake data up to date** enabled in model settings:
automatic framing makes published Delta changes available without a Power BI
Import refresh schedule. Reopening or refreshing report visuals is still needed
to display newly available data.

The notebook captures cached header/line snapshots, checks exact financial,
scoop and flavor-count reconciliation, and validates dimension coverage before
replacing data. Incomplete mirrored receipts fail the run explicitly rather
than publishing partial sales. A later run retries against a new source snapshot.
Dimensions are published before the append-only sales fact introduces new keys.
Each table replacement is an atomic Delta commit, but all 11 replacements are
**not** one cross-table transaction. An interrupted write phase can leave some
dimension tables newer than the fact; inspect the failed run and rerun it.
`Data As Of UTC` is the last successful analytical publication time, not the
latest receipt or a Power BI refresh timestamp.

Direct Lake uses Microsoft Entra SSO by default. Report viewers need appropriate
OneLake access, or an administrator can bind an explicit fixed-identity cloud
connection in the service. No password, token or app secret is embedded here.
The earlier Import model's `Premium_ASWL_Error` concerned its SQL connection;
it is not a reason to grant database-writer or db_owner permissions to readers.

## Reading the report

- Global filters: local trading date, shop, and currency. Default currency EUR.
- Currency amounts never combine EUR, USD and JPY. Monetary measures return blank
  without exactly one currency. JPY displays zero decimal places.
- Net Sales excludes tax; Total Paid includes tax. Discounts and tax use the
  exact allocated flavor-line amounts, not duplicated header totals.
- Receipts counts distinct sales. A receipt can contain several flavors, so
  flavor receipt counts must not be added together.
- Average Basket under a flavor filter is that flavor's contribution per matching
  receipt, not the complete receipt. Scoops are additive.
- Temperature averages are receipt-weighted rather than flavor-line-weighted.
- Weather is synthetic. No weather causality, profit, customer identity, footfall,
  targets, exchange rates or fabricated prior-period growth are inferred.
- Initial history is a single day. The simulator cadence changed during
  28 October 2026; older receipts remain visible and may precede the new
  09:00-23:00 shop-local schedule.
- `shop_key` is the integer registry `ShopId` in both `sales_analytics.shop` and
  `sales_analytics.sales` (Delta `BIGINT`, semantic model `int64`): for example,
  `1|Paris|FR|Europe/Paris` becomes `1`, and `3|Milan|IT|Europe/Rome` becomes `3`.
  The shop dimension has one row per ID and uses current registry geography/time
  zone. Sales retain receipt-snapshot city/country and local trading timestamps;
  flavor labels preserve their sale-time snapshot.

The model has 11 tables, nine one-way dimension-to-fact relationships and 18
explicit measures. The fact is at receipt/flavor-line grain.

## Regeneration and validation

Run [author-shop-sales.mjs](./author-shop-sales.mjs) with Node.js 20+ and the
Power BI design skill's `assets/base.json` path:

```powershell
node .\author-shop-sales.mjs '<path-to-design-skill>\assets\base.json' --overwrite-captured-baseline
node .\author-shop-sales.mjs --model-only --overwrite-captured-baseline
node --test .\shop-sales.test.mjs
powerbi-report-author validate .\rp_gelatai_shop_sales.Report
```

The generator refuses to overwrite the captured baseline without the explicit
override above. Regeneration deliberately changes that baseline and requires
review/re-export plus refreshed manifest hashes before recreation can be claimed.
It does not publish or modify SQL. The logistics generator similarly requires
`-OverwriteCapturedBaseline` and is not automatically run by deployment.
`--model-only` regenerates the model and analytical notebook, leaving report
files untouched. `FABRIC_WORKSPACE_ID` and `FABRIC_LAKEHOUSE_ID` can override
the current OneLake binding when targeting another environment.
Publish and run the notebook successfully before deploying the model.
For the integer shop-key migration, regenerate with `--model-only`, publish the
updated notebook, and run it to rebuild **both** analytical tables from the
original integer `ShopId`. This preserves sales history without parsing old
composite strings. Then update both model `Shop Key` columns to `int64` and
refresh Direct Lake framing. The existing one-way relationship stays unchanged.
Do not refresh/query the model during the two-table type migration: Delta
replacements are not a cross-table transaction. Rerun a failed notebook before
updating the model. Future hourly runs use the same integer keys.
The operational SQL tables and logistics model already use integer `ShopId`;
their foreign keys need no migration. The app's external shop codes and SQL
mapping keys are separate identifiers and remain unchanged.

The live migration completed on 2 November 2026. Both analytical `shop_key`
columns were verified as `BIGINT`, both model keys as `int64`, and all nine
relationships were preserved. All 11 Direct Lake partitions refreshed without
warnings. SQL and live DAX checks confirmed six shops, 2,162 flavor lines and
827 receipts, with zero duplicate/orphan shop keys and no missing or mismatched
source lines up to the published snapshot. Later simulator receipts are picked
up by the next preparation run.
For an existing model, round-trip its live definition to preserve metadata;
replace source mappings/partitions, not business objects or report bindings.
Import partition objects cannot be converted in place: the Direct Lake
partitions deliberately have new names ending in `Direct Lake`. Replacing the
old partitions allowed the existing semantic model and report IDs to survive.
Publication must convert the local `definition.pbir` byPath reference to a
byConnection reference to the deployed semantic model ID.

Validation completed: PBIR preflight (zero errors/warnings), official Microsoft
TOM deserialization, all 67 report field bindings against the deployed model,
all three published page names, and SQL header/line monetary reconciliation.
The source remains continuously writable by the simulator.

Nine offline invariant tests cover integer shop keys, report layout and binding, financial
semantics, all 11 Direct Lake entity partitions and physical-column mappings,
notebook source binding, reconciliation gates and publication order.

Direct Lake deployment was verified on 28 October 2026:

- The notebook completed; all 11 actual Delta tables were discovered in the
  Lakehouse. The fact's Delta log confirmed physical types and protocol.
- The exported live model passed official TOM validation: 11 Direct Lake entity
  partitions, nine relationships, 18 measures, all 67 report field bindings.
- Framing refreshed all 11 partitions successfully with **zero warnings**.
  Five invalid DAX currency-format expressions were corrected; JPY still uses
  no decimals and EUR/USD use two.
- Live DAX matched independently queried Delta totals: 509 flavor lines,
  191 distinct receipts, six shops and 25 flavors. Header/line reconciliation
  found zero mismatched receipts. Multi-currency money remains blank.
- The original report remains bound to the same semantic model. The only model
  connection is OneLake (`AzureDataLakeStorage`); no SQL connection remains.
- The hourly notebook schedule is enabled and its persisted interval was checked.

**Remaining validation:** rendered inspection of every page.
Desktop is not installed (`DESKTOP_EXE_NOT_FOUND`); browser verification was
also blocked by the interactive sign-in requirement. Offline validation does
not claim to replace rendered inspection.
