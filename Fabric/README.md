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
| GelatAI-rtdashboard.KQLDashboard | KQLDashboard | (Gelat)Analytics |
| sm_gelatai_lh.SemanticModel | SemanticModel | (Gelat)Analytics |
| rp_gelatai_lh.Report | Report | (Gelat)Analytics |
| OperationsAgent_1.OperationsAgent | OperationsAgent | (Gelat)Analytics |
| GelatAI-FactoryAgent.DataAgent | DataAgent | (Gelat)AI |
| GelatAI-activatorflow.Reflex | Reflex | (Gelat)AI |

Note: the `GelatAI_lakehouse` SQLEndpoint is auto-created with the Lakehouse, so it is not a deployable source item.

## Redeploy options
1. **Fabric Git integration** — connect a target workspace to this folder; Fabric matches items by `.platform` type/displayName.
2. **fabric-cicd** — `pip install fabric-cicd`, then publish this folder to a target workspace.
3. **fabric-export-part-writer.ps1** — helper used to decode the API definitions into this folder.
