# Fabric workspace baseline: ws_wu3_gelatai

This folder captures the current logical artifacts/configuration of workspace
`ws_wu3_gelatai` (`97d5eec3-d6d9-44bb-80aa-279e286309b3`, West US 3).
The alignment used read-only exports/catalog queries. No Fabric item was created,
updated, deleted, renamed, activated, refreshed or executed.

**Full recreation is currently blocked, not certified.** See the blockers in
[workspace-manifest.json](ws_wu3_gelatai/workspace-manifest.json):

- `Gelantology_v3` cannot export: Fabric rejects an unreferenced shared
  `DirectLake - GelatAI_shopdb` connector expression with `ALMOperationBadRequest`.
  Its metadata file is evidence only, **not a deployable ontology**. Neither the
  live ontology nor its connector was modified. Read-only browser tools were
  unavailable, so no UI capture was possible.
- Item sharing, sensitivity labels, non-public workspace settings, external
  flow activation and parent-managed ontology provisioning are not fully verified.
- SQL database compatibility/collation/isolation settings were not returned by
  read-only catalog inspection. They must not be assumed to match a future target.
- The legacy ontology references an external-workspace Lakehouse and contains a
  literal `WORKSPACE_NAME_PLACEHOLDER` model endpoint. Both are retained as
  exported; their effective service behavior is unverified, not silently repaired.

Git integration or fabric-cicd alone cannot restore this entire workspace.
Current rows, files, event history, notebook output/history and credentials are
excluded. Seeding is optional and disabled by default.

## Inventory and differences

The manifest accounts for all **28 live items**: 24 successful definition exports,
one schema-captured SQL database, one blocked ontology and two generated SQL
endpoints. It also records the five-folder hierarchy and item folder assignments.

| Artifacts | Type |
|---|---|
| GelatAI_lakehouse | Lakehouse |
| GelatAI_shopdb | SQLDatabase |
| GelatAI-rtdata | Eventhouse and KQLDatabase |
| GelatAI-eventstream-factory; GelatAI-eventstream-shops | Eventstream |
| GelatAI-rtdashboard | KQLDashboard |
| sm_gelatai_lh; sm_gelatai_shop_sales | SemanticModel |
| rp_gelatai_lh; rp_gelatai_shop_sales | Report |
| GelatAI-FactoryAgent; GelatAI-ShopAgent; GelatAI-OntologyAgent | DataAgent |
| GelatAI-activatorflow | Reflex |
| nb_update_shop_registry; nb_shop_sales_directlake; MachineFactoryManuals | Notebook |
| Gelantology; Gelantology_v3 (blocked) | Ontology |
| Each ontology's `_graph_...` and `_eh_...` artifacts | GraphModel, Eventhouse, KQLDatabase (six parent-managed items) |
| GelatAI_lakehouse; GelatAI_shopdb | SQLEndpoint (generated, never independently created) |

The repository now includes the previously missing agents, manual notebook,
legacy ontology and both ontologies' backing definitions. The factory Eventstream
folder uses its current name. Repository-only OperationsAgent_1 and the old
SQL-to-Delta copy notebook were removed. The logistics report includes its live
fourth/active page. Other exported definition changes were imported unchanged.

## Schema and configuration sources

- [SQL captured-schema.sql](ws_wu3_gelatai/GelatAI_shopdb.SQLDatabase/captured-schema.sql):
  18 tables, 189 columns, 36 indexes/keys, 21 foreign keys, checks/defaults,
  identity/collation details and six modules. It rejects a nonempty target.
  [Security template](ws_wu3_gelatai/GelatAI_shopdb.SQLDatabase/security-template.json)
  captures application permissions and role memberships using identity parameters.
- [Native Delta metadata](ws_wu3_gelatai/GelatAI_lakehouse.Lakehouse/native-delta-schema.json)
  and [schema-only Spark SQL](ws_wu3_gelatai/GelatAI_lakehouse.Lakehouse/schema-bootstrap.sql):
  16 managed tables in `dbo` and `sales_analytics`. Source table IDs/log versions
  are provenance, not target physical IDs to force. Spark SQL has not been executed
  or engine-validated in this alignment; the JSON preserves the exact metadata.
- **19 Lakehouse shortcuts**: 18 SQL tables in `sc_shopdb`, plus normalized
  telemetry in `dbo`. These replace the removed copy-notebook approach.
- Three KQL databases retain their exact `DatabaseSchema.kql` exports plus
  supplementary captured policies/catalogs. Main database retention/cache is
  36500 days, recoverability disabled and streaming ingestion enabled.
  Its three native tables and two Lakehouse-linked external Delta tables are captured.
- The registry notebook has its captured enabled Monday 02:00 UTC schedule.
  Sales preparation and MachineFactoryManuals have **no schedules**; recreation
  must not invent hourly preparation.
- Workspace roles, discovered connections and prerequisites are manifest entries.
  Resolve principal parameters to approved target identities. Built-in SQL
  service permissions/ownership are target-generated, not replayed from source IDs.

Supplementary SQL/KQL/catalog files and local helpers are **not** definition parts.
Deployment must use the manifest's explicit part lists, not recursively publish
every file. Preserve `.platform` logical IDs for Git identity; do not blindly
replace eventstream node IDs, model lineage tags or business keys.
The sales report intentionally uses a local PBIP `byPath` model binding, recorded
as a hashed override; deployment converts it to a target `byConnection`.

## Future recreation preparation (offline only)

From the repository root:

```powershell
& .\Fabric\ws_wu3_gelatai\prepare-recreation.ps1 `
  -TargetWorkspaceName 'NEW-gelatai-workspace'
```

This defaults to an in-memory dry run, requires a new name, protects the source
name/ID and makes **zero network calls**. It emits phased source-ID templates with
`ready: false` and the explicit blockers. It does not create a workspace.
`-Apply` fails before any network or file operation.

To prepare local definition payloads, supply a target workspace GUID, an external
output directory and a binding-map JSON with `ids` and `values` objects:

- `ids`: source workspace/item/generated-item GUID -> discovered target GUID.
- `values`: exact source KQL/SQL/Power BI endpoint or generated SQL catalog -> target value.
  Do not supply arbitrary lineage/name replacements.

All payloads are validated before writing; unresolved source references fail.
`.platform` and `.schedules` are excluded from definition payloads. The generated
action plan remains a **source configuration template**, not an executable or
fully remapped deployment script. Schedule/shortcut/security provisioning is
listed, not performed. This is not yet a working end-to-end recreation runner.

After resolving blockers through supported read-only capture, a separately
approved deployment must: provision a new capacity-backed workspace/folders and
independent item shells; discover new endpoints/generated resources; initialize
empty SQL/Delta/KQL schemas; remap definitions; then configure shortcuts,
connections, schedules and parameterized access. Discover ontology-owned backing
resources instead of provisioning duplicates. Keep seeds and notebook execution
opt-in. Legacy deployment helpers can perform writes if invoked deliberately;
they were **not run** during alignment and are not full-workspace recreators.

External publishers need newly generated Eventstream CustomEndpoint credentials.
The `anomalysolutionflow` Power Automate flow and manual search indexes
`machines-anomaly-manual` / `factory-functional` are external prerequisites, not
exported implementations or objects to provision here.

## Offline validation

```powershell
node --test .\Fabric\ws_wu3_gelatai\shop-sales.test.mjs `
  .\Fabric\ws_wu3_gelatai\workspace-alignment.test.mjs
& .\Fabric\ws_wu3_gelatai\workspace-alignment.test.ps1
powerbi-report-author validate .\Fabric\ws_wu3_gelatai\rp_gelatai_lh.Report
powerbi-report-author validate .\Fabric\ws_wu3_gelatai\rp_gelatai_shop_sales.Report
```

Hash/catalog and payload-preparation checks do not prove service acceptance.
No deployment, notebook run or refresh is permitted as validation for this task.
Service-exported whitespace is retained for exact hashes, including trailing
spaces/blank lines; the package's `.gitattributes` prevents checkout EOL conversion.
