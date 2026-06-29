# IceCream Agents — Foundry export & redeploy

Exported from Microsoft Foundry project **foundry-proj-01** (parent Foundry **ice-foundry-01**,
`RG-Foundry-01`, sub `1e055937-2346-4ba4-9c11-a0b05a0977a7`). Both are **prompt agents** (LLM +
instructions + tools), so everything needed to redeploy is captured here.

## Contents
| Path | Purpose |
|---|---|
| `IceCreamOperator/definition.json` | Redeployable prompt definition (kind/model/instructions/tools) |
| `IceCreamOperator/agent-export.json` | Full raw export (endpoint, protocols, agent card, version) |
| `IceCreamFactoryManagerV2/definition.json` | Redeployable prompt definition |
| `IceCreamFactoryManagerV2/agent-export.json` | Full raw export |
| `connections.json` | Project connections each agent depends on (recreate per env) |
| `deploy-agents.ps1` | Pushes both agents to a target project (Operator first) |

## Agents
| Agent | Model | Tools / dependencies |
|---|---|---|
| IceCreamOperator | `gpt-4.1-1` | KB MCP `kb-icecreamfactorykb-ffsz1` → AI Search `foundry-01-search` / KB `icecreamfactorykb` |
| IceCreamFactoryManagerV2 | `gpt-5.4` | toolbox `FactoryOperationsSkills`, APIM MCP `mcpgelataifactorymachines`, A2A → IceCreamOperator, Fabric DA `GelatAIFactoryAgent2` |

The Manager calls the Operator (A2A), so **deploy IceCreamOperator first**.

## Redeploy to another environment
1. Ensure the model deployments exist (or pass `-ModelOverride`).
2. Recreate the connections in `connections.json` in the target project (supply secrets; update env-specific URLs/workspace ids). The Manager's a2a/fabric connection ids are full ARM ids in the raw export — switch to short names or update for the target project.
3. Deploy:
   ```powershell
   az login
   ./deploy-agents.ps1 -ProjectEndpoint "https://<account>.services.ai.azure.com/api/projects/<project>"
   ```

> Secrets (search/APIM keys, OAuth) are intentionally not exported. Voice-live metadata is preserved in the raw exports.
