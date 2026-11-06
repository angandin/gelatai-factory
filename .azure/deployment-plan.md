# Deployment Plan

Status: Deployed and Verified

## Scheduling update (2026-10-28)

- User explicitly approved deploying the 5-10-minute local-hours schedule to the existing shop app, with the separate Fabric access issue still unresolved.
- Target remains the confirmed subscription, `RG-Gelatai-Factory`, West US 3, `gelatai-shops`.
- Image-only revision update; preserve SQL settings, identities, configuration, and sizing. No new SQL schema, grants, or tenant setting changes.
- Random 300-600-second wait before every sale; generation only during 09:00 inclusive to 23:00 exclusive in each configured shop time zone.
- `OutsideHours` auto-resumes next morning; manual stop remains stopped; rush cannot bypass the schedule.
- Legacy interval configuration is ignored; status reports the sampled interval.

### All validation checks pass (scheduling update)

- [x] Release build/regression tests: 57 passed.
- [x] Isolated preview health and all six local-time statuses; browser displays New York OutsideHours and five open shops.
- [x] ACR build `dsq`, image `apishop:hours-20261028-1037`: Succeeded.
- [x] Current ARM validation and identity/configuration checks.
- [x] Post-deployment health, revision, schedule states, UI, and configuration verification.

### Scheduling deployment results

- Revision `gelatai-shops--hours1028` is Healthy and receives 100% traffic. It is the only active shop revision.
- Image deployed by digest: `sha256:39a5560970af4fd0e63ad8105888fac5e6006d67390f43ed673773c8852bd6a6`.
- HTTPS health and scheduling UI verified. Production sampled intervals: Rome 441s, Florence 597s, Milan 509s, Paris 384s, Tokyo 510s; New York correctly OutsideHours.
- No startup SQL error in the new revision. Each open shop waits 5-10 minutes before its first sale; no immediate restart burst.
- Separate SQL authorization issue recovered during the earlier revision: readback found 23 receipts for each of the six shops (138 headers), 365 lines, and zero financial reconciliation mismatches.
- The database's SQL `db_owner` membership added by the user was not removed or broadened during this scheduling rollout.
- Factory remains `gelatai-factory--freq09251503` using `apifactory:frequency-20260925`.
- Endpoint: https://gelatai-shops.livelysky-69238d7c.westus3.azurecontainerapps.io

## Current rollout: shop direct SQL persistence (2026-10-28)

- User confirmed the existing subscription, resource group, and West US 3 location.
- Replace only `gelatai-shops` with the SQL-backed image; retain its system-assigned identity and existing ACR-pull identity.
- Apply only `sales-schema.sql` using `deploy.ps1 -SalesOnly`; no database creation or registry reseeding.
- User authorized database-item Read and least-privilege SQL permissions for the shop identity if missing. No tenant-wide policy changes.
- Preserve existing shop configuration, one-replica sizing, and factory deployment.
- Do not delete Eventstream/Eventhouse resources or backfill historical events.
- Recipe: Azure CLI targeted image/environment update using the validated `infra/shop.bicep` configuration contract. Do not apply broader Bicep defaults that remove unrelated runtime settings. Preserve the old Event Hub secret for rollback but remove its environment references from the new revision.
- Docker daemon is unavailable locally; use the existing Azure Container Registry build service.

### All validation checks pass (current rollout)

- [x] Core validation: CLI authentication, Bicep compilation, ARM validation, and what-if.
- [x] Build/test verification: Release tests and ACR container build.
- [x] Policy validation for existing resource types and unchanged sizing.
- [x] Identity verification: existing ACR pull, SQL database access, system identity.
- [ ] Post-deployment verification: healthy revision, HTTPS API, sales counters, and persisted SQL facts from all shops.

Historical deployment records below refer to earlier Event Hub versions and are
retained for rollback context, not as proof for this SQL rollout.

### Current rollout results

The authorization blocker recorded below was subsequently resolved; see the scheduling deployment results above.

- Deployed image by digest with `az containerapp update`; provisioning succeeded.
- Revision `gelatai-shops--sql1028` is Healthy, receives 100% traffic, and uses the existing system-assigned identity.
- Endpoint: https://gelatai-shops.livelysky-69238d7c.westus3.azurecontainerapps.io
- New revision has only SQL delivery environment settings. Existing sizing, probes, ACR identity, and previous Event Hub secret were preserved.
- HTTP health is OK; all six shops are Open and keep generating receipts.
- SQL schema migration and granular SQL grants succeeded.
- End-to-end verification is BLOCKED: Fabric rejects the app's login with "Validation of user's permissions failed. Verify the user has the Read item permission." Actual Sale/SaleItem counts remain zero.
- User will check Fabric item permissions and service-principal tenant eligibility later. No tenant-wide changes or broader workspace roles were applied.
- Leave the new revision running and retrying writes at the normal cadence, with repeated errors throttled for 30 minutes. Failed sales are not queued or replayed.
- Do not describe this rollout as end-to-end verified until all six shops persist sales and financial header/line reconciliation is checked.
- Factory deployment and Eventstream/Eventhouse resources were not modified.

## 1. Request

Update and redeploy both simulators with reduced event frequencies:

- Factory machine intervals: 5 seconds becomes 15 seconds; 15 seconds becomes 45 seconds.
- Shops: every shop is limited to no more than two events per minute, including rush mode.

## 2. Mode

MODIFY: deploy a new application component into existing Azure infrastructure.

## 3. Requirements

- Classification: demonstration/development workload
- Scale: small, one always-on replica
- Budget: cost-optimized by reusing existing infrastructure
- Compliance: no customer-identifying data; Event Hub credential remains secret
- Approval: the user explicitly requested deployment to the factory environment

## 4. Azure Context

- Subscription: `ME-M365CPI74487741-angandin-1` (`1e055937-2346-4ba4-9c11-a0b05a0977a7`)
- Resource group: `RG-Gelatai-Factory`
- Location: `westus3`
- Existing Container Apps environment: `gelatai-factory-env`
- Existing ACR: `gelataiacr`
- Existing ACR pull identity: `gelatai-factory-acr-identity`

## 5. Architecture

- Build `apishop/Dockerfile` in the existing ACR as `apishop:latest`.
- Deploy one Container App named `gelatai-shops`.
- Reuse the existing environment and ACR pull identity.
- Use external HTTPS ingress on port 8080.
- Keep one replica for reliable continuous event generation.
- Store the Event Hubs connection string as a Container App secret.
- Configure startup, readiness, and liveness probes against `/health`.

## 6. Deployment Recipe

Azure CLI + Bicep using `infra/shop.bicep`.

## 7. Validation Proof

### Scheduling update validation (2026-10-28, 09:35-09:40 UTC)

- `dotnet test tests\EventHubCooldown.Tests\EventHubCooldown.Tests.csproj --configuration Release --verbosity minimal`: 57 passed, zero failures/skips; both apps build.
- Fake-clock tests verify 300-600-second waits, no startup burst, rush/failure cadence, exact 09:00/23:00 states in Rome/Paris/New York/Tokyo, DST transitions in both directions, cancellation, and persisted enabled state.
- Local console-only HTTP preview: healthy, five local shops Open and New York OutsideHours, all sampled interval bounds valid. Browser verified outside-hours presentation; preview stopped and temporary data removed.
- ACR build `dsq` succeeded; digest `sha256:39a5560970af4fd0e63ad8105888fac5e6006d67390f43ed673773c8852bd6a6`.
- Standard validation helper: CLI/authentication, Bicep compilation, ARM validation, and what-if all PASS.
- Expanded what-if affects only existing `gelatai-shops`; use an image-only update to preserve all other runtime settings.
- Identity/configuration and ACR pull contract unchanged. No infrastructure, scale, SQL migration, SQL role, tenant policy, or factory changes in this rollout.
- Existing Fabric authorization remains a known separate issue; user approved deploying the scheduling change while investigating that permission.

### Current SQL rollout validation (2026-10-28, 09:10-09:20 UTC)

- `validate-deployment.ps1 -Scope group -ResourceGroup RG-Gelatai-Factory -Template .\infra\shop.bicep -Parameters <session parameters> -Subscription 1e055937-2346-4ba4-9c11-a0b05a0977a7`: OVERALL PASS.
- Expanded what-if: one modified resource (`gelatai-shops`), all other resources ignored; no resource deletion. The helper's Create/Modify/Delete counts include property changes, not just resources.
- To avoid unrelated property resets in the Bicep preview, deploy only the new image and SQL environment settings with `az containerapp update`. Preserve ingress, identities, probes, scale, and previous secret needed for rollback.
- `az acr build --registry gelataiacr --image apishop:sql-20261028-1006 .\apishop --no-logs`: run `dsp`, Succeeded.
- Image digest: `sha256:74b04aceb63ec0d1f24197d6ca6b8c1f33f38fa353f96e1a21fbca9d695f34dd`.
- `dotnet test tests\EventHubCooldown.Tests\EventHubCooldown.Tests.csproj --configuration Release --verbosity minimal`: 39 passed, no failures or skipped tests.
- Current subscription and location confirmed by user. No new resource types, resource groups, scale increase, or factory changes.
- Resource-group and inherited policy assignment queries returned no assignments; ARM server validation passed.
- Existing ACR pull identity `03011b3d-3c6e-4baa-b739-311bf62889ea` has AcrPull on the existing registry.
- Shop system identity `b7869e83-a394-4786-b6ea-0e1a7a3ddf9a` resolves to client ID `4e414bfb-2eac-4b32-a16a-a12ab532dbac`.
- User confirmed granting only database-item Read in the Fabric portal. SQL principal creation and minimal grants executed successfully; SQL SID matches the intended client ID.
- `deploy.ps1 -SalesOnly`: succeeded; production Sale/SaleItem/procedure/reporting views read back successfully. No registry reseed or historical backfill.
- Previous healthy shop revision `gelatai-shops--freqstrict0925` and live six-shop configuration recorded in session artifacts for verification/rollback.
- Factory baseline remains `gelatai-factory--freq09251503`, image `apifactory:frequency-20260925`.

Validated on 2026-09-25:

- `validate-deployment.ps1 -Scope group -ResourceGroup RG-Gelatai-Factory -Template .\infra\shop.bicep`: PASS.
- Azure CLI authentication: PASS for `ME-M365CPI74487741-angandin-1`.
- `az bicep build`: PASS.
- `az deployment group validate`: PASS.
- `az deployment group what-if`: PASS with Create: 2, Modify: 0, Delete: 0.
- `docker build --tag apishop:validation .\apishop`: PASS.
- `dotnet build .\apishop\ApiShop.csproj --configuration Release --no-restore`: PASS with zero warnings and errors.
- Local container test: `/health` returned `ok`; six of six shops opened; nine sales sent through the dedicated Event Hub configuration; no send errors logged.
- Assigned Azure policies reviewed; no template conflict identified.
- Static identity review: the Container App registry configuration references the existing `gelatai-factory-acr-identity`; no new role assignment is introduced.

### All validation checks pass

- [x] Core Validation: Azure CLI, authentication, Bicep compile, resource-group validation, and what-if
- [x] Docker Build: build the `apishop` image locally
- [x] Azure Policy Validation: review assigned policies for conflicts
- [x] Role Assignment Verification: confirm the reused identity already has ACR pull access

### Frequency update validation

- [x] Factory release and container builds
- [x] Shop release and container builds
- [x] Factory configuration contains only 15- and 45-second intervals
- [x] Every shop has an interval of at least 31 seconds
- [x] Rush mode cannot bypass the 31-second shop minimum
- [x] Both dependency vulnerability scans are clean

Frequency update proof, 2026-09-25:

- `dotnet build` passed for both projects in Release with zero warnings and errors.
- Docker builds passed for `apifactory:frequency-validation` and `apishop:frequency-validation`.
- Factory source configuration: five machines at 15 seconds and ten machines at 45 seconds.
- Shop source configuration: six shops at 31 seconds, preventing three events from falling in an inclusive rolling 60-second window.
- Shop runtime enforces `Math.Max(31, IntervalSeconds)` for normal, rush, and error-delay paths.
- Shop API rejects configurations below 31 seconds.
- `dotnet list package --vulnerable --include-transitive` found no vulnerable packages in either project.
- Bicep compiled and deployment validation passed. The frequency deployment will use image-only Container App revisions and API configuration updates; it will not apply the broader Bicep what-if.

## 8. Policy and Capacity

- Existing management-group baseline, deny, audit, and deploy/modify policy initiatives apply.
- The deployment will use the same resource group and resource pattern as the compliant factory app.
- West US 3 quota check passed: one managed environment used of 50; the app reuses it.

## 9. Security

- Store the Event Hubs connection string as a Container App secret.
- Do not commit credentials.
- Reuse the existing user-assigned managed identity for ACR image pull.
- Permit HTTPS ingress only; `allowInsecure` is false.

## 10. Verification

- Build and push the container image.
- Confirm the Container App revision is healthy.
- Verify the public HTTPS health endpoint and UI.
- Verify the app emits sales events without Event Hubs send errors.
- Inspect the Fabric Eventstream only after Azure deployment verification.

## 11. Deployment Results

- Factory ACR image: `gelataiacr.azurecr.io/apifactory:frequency-20260925`
- Factory image digest: `sha256:5e708dd67bfb69025727fadefa05b1b03cb7b80d12aadf6337efab570b49afaf`
- Factory active revision: `gelatai-factory--freq09251503`
- Factory endpoint: `https://gelatai-factory.livelysky-69238d7c.westus3.azurecontainerapps.io`
- Factory live configuration: five machines at 15 seconds and twelve machines at 45 seconds; all 17 persisted machines preserved
- Factory measured rate over 97.14 seconds: 59 events, 0.607 events/second, one event every 1.646 seconds
- Shop ACR image: `gelataiacr.azurecr.io/apishop:frequency-20260925-v2`
- Shop image digest: `sha256:39603347efe5efeadacc92afef3303f4f2f8e7f4164e9aaa5c3089746e2b5798`
- Shop active revision: `gelatai-shops--freqstrict0925`
- Shop endpoint: `https://gelatai-shops.livelysky-69238d7c.westus3.azurecontainerapps.io`
- Shop live configuration: six shops at 31 seconds
- Shop rolling-minute verification: every shop produced exactly two events during a 62.11-second observation; the Rome shop remained capped while in rush mode
- Shop API validation: a 30-second configuration returned HTTP 400 and left the live 31-second configuration unchanged
- Environment: `gelatai-factory-env`
- Health: both applications report `ok`; both active revisions are healthy
- Runtime: all factory machines are running; all six shops are open and counters are increasing
- Event Hubs: no startup or send errors in either active revision log
- Live RBAC: `gelatai-factory-acr-identity` has `AcrPull` on `gelataiacr`

## 12. Fabric Verification

- Workspace: `ws_wu3_gelatai`
- Eventstream: `GelatAI-eventstream-shops`
- Source: `gelataishops` (`CustomEndpoint`) — Running
- Stream: `GelatAI-eventstram-shops-stream` (`DefaultStream`) — Running
- Destination: `Eventhouse` targeting `GelatAI-rtdata.shopsraw` — Running
- Retention: 1 day
- Throughput: Low
- End-to-end result: 214 events from six shops observed in `shopsraw` during the 15-minute verification window
- Exported definition: `Fabric/ws_wu3_gelatai/GelatAI-eventstream-shops.Eventstream`
