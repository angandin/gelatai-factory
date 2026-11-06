# Fabric Workspace Export — ws_wu3_gelatai

These are the full item definitions exported from Fabric workspace `ws_wu3_gelatai`
(`97d5eec3-d6d9-44bb-80aa-279e286309b3`), stored in standard Fabric Git-integration format
(each folder has a `.platform` + `definition` parts). They can be redeployed completely.

## Items
| Folder | Type | Original folder in workspace |
|---|---|---|
| GelatAI_lakehouse.Lakehouse | Lakehouse | (Gelat)Analytics |
| GelatAI-rtdata.Eventhouse | Eventhouse | (Gelat)Analytics |
| GelatAI-rtdata.KQLDatabase | KQLDatabase | (Gelat)Analytics |
| GelatAI-eventstream.Eventstream | Eventstream | (Gelat)Analytics |
| GelatAI-eventstream-shops.Eventstream | Eventstream | (Gelat)Analytics |
| GelatAI-rtdashboard.KQLDashboard | KQLDashboard | (Gelat)Analytics |
| sm_gelatai_lh.SemanticModel | SemanticModel | (Gelat)Analytics |
| rp_gelatai_lh.Report | Report | (Gelat)Analytics |
| OperationsAgent_1.OperationsAgent | OperationsAgent | (Gelat)Analytics |
| GelatAI-FactoryAgent.DataAgent | DataAgent | (Gelat)AI |
| GelatAI-activatorflow.Reflex | Reflex | (Gelat)AI |
| GelatAI_shopdb.SQLDatabase | SQLDatabase | Script-deployed |
| nb_update_shop_registry.Notebook | Notebook | Script-deployed |
| nb_copy_shopdb_to_lakehouse.Notebook | Notebook | SQL-to-Delta copy |

Note: the `GelatAI_lakehouse` SQLEndpoint is auto-created with the Lakehouse, so it is not a deployable source item.

## Redeploy options
1. **Fabric Git integration** — connect a target workspace to this folder; Fabric matches items by `.platform` type/displayName.
2. **fabric-cicd** — `pip install fabric-cicd`, then publish this folder to a target workspace.
3. **fabric-export-part-writer.ps1** — helper used to decode the API definitions into this folder.

The `GelatAI_shopdb.SQLDatabase` folder is recreated with its `deploy.ps1`
script because Fabric SQL Database lifecycle and schema deployment require
control-plane creation followed by T-SQL execution.

The `nb_update_shop_registry.Notebook` folder contains the source and deployment
script for the weekly static-registry simulation and its Fabric schedule.

Shop, product, inventory, and shipment operational data is persisted in
`GelatAI_shopdb`. The semantic model reads the SQL Database tables directly
through Direct Lake and does not require a SQL DirectQuery credential.
The [SQL-to-Delta copy notebook](ws_wu3_gelatai/nb_copy_shopdb_to_lakehouse.Notebook/README.md)
also materializes all SQL user tables in `GelatAI_lakehouse.shops` as independent
Delta tables, with full-refresh and row-level validation. These copies do not
change the existing semantic model or report bindings.

After the SQL Database, Lakehouse, and notebook-generated reporting tables exist,
run `ws_wu3_gelatai/deploy-reporting.ps1` to create or update `sm_gelatai_lh` and
`rp_gelatai_lh`. The script discovers the current Lakehouse and semantic model IDs,
rewrites environment-specific bindings in memory, validates the PBIR, and publishes
the definitions. The report's `author-logistics-pages.ps1` generator recreates the
Distribution Overview and Shop Assortment pages deterministically.
