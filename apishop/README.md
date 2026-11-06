# GelatAI Shop Sales Simulator

A pixel-art ASP.NET Core application that simulates realistic ice cream sales from shops around the world, with an Italy-heavy sample network.

## Sales storage

The application writes directly to the writable SQL endpoint of the existing
Fabric SQL Database `GelatAI_shopdb`. It no longer publishes to Event Hubs or
Eventhouse. The factory simulator still uses its existing Event Hub path.

Each committed transaction has one `dbo.Sale` header and one `dbo.SaleItem` row
per selected flavor. Both are written atomically using `dbo.RecordApiShopSale`.
The existing shop/product registry supplies relational IDs; unknown or inactive
shop/flavor mappings are rejected, not automatically registered.

The latest-sale API retains its existing receipt shape, including:

- Shop ID, name, city, country, coordinates, currency, and local time zone
- One to six distinct flavors, weighted so two or three are most common
- Scoops, serving type, sales channel, and payment method
- Location-calibrated unit prices, subtotal, discount, tax, and total
- UTC and local timestamps
- Simulated weather and temperature for demand analysis
- A non-identifying transaction ID

No customer-identifying data is generated.

### Analytics-ready amounts and dates

- Timestamps are persisted as typed UTC/local values, shop-local trading date,
  time-zone ID, and offset. Precision is microseconds for SQL/Delta compatibility.
- Discount and tax are allocated proportionally to flavor subtotals. Largest
  fractional remainders receive the remaining minor units, with line order
  breaking ties, so every line sum exactly matches its header.
- EUR and USD use two decimal places; JPY uses zero. Other currencies are rejected.
- `NetSalesAmount` is subtotal minus discount, excluding tax.
  `TotalAmount` is net sales plus tax (the amount paid).
- Always group monetary measures by `CurrencyCode`. There is no FX conversion.
- Use header grain for transaction counts and line grain for flavor analytics;
  never sum header totals after joining each header to multiple flavor lines.
- The UI's `salesSent` field now counts recorded sales. Its compatible `revenue`
  field remains the recorded amount paid, including tax, labeled `TOTAL PAID`.
- Duplicate retries with the same transaction ID and canonical writer payload
  return the existing sale; conflicting payloads for the same ID fail explicitly.

See the [schema, reporting examples, and access scripts](../Fabric/ws_wu3_gelatai/GelatAI_shopdb.SQLDatabase/README.md).

## Run locally

```powershell
Set-Location .\apishop
dotnet run
```

Open `http://localhost:5000`. The development launch profile explicitly selects
console-only simulation: receipts appear in the application log and no SQL
connection is attempted. Console-mode counters reflect simulated output, not
database records. SQL failures never trigger a console fallback.

## Configure Fabric SQL

Discover the writable `serverFqdn` and physical `databaseName` from the Fabric
SQL Database API or its connection settings. Do not use the read-only SQL
analytics endpoint or assume the physical database name equals the display name.

For local SQL development with your `az login` identity:

```powershell
$env:Sales__Destination = 'Sql'
$env:Sql__Server = '<discovered-server>,1433'
$env:Sql__Database = '<discovered-physical-database-name>'
$env:Sql__Authentication = 'Developer'
dotnet run
```

Production uses `Sales__Destination=Sql`, `Sql__Authentication=ManagedIdentity`,
and the shop Container App's **system-assigned identity**, with encrypted SQL
connections and certificate validation. Missing production SQL settings fail
explicitly at startup. Database unavailability does not block HTTP startup.
No database password or access token is stored in configuration.

`POST /simulator/config` checks all shop/flavor mappings before saving or
restarting runners. Unknown keys or mismatched country/currency/time-zone data
return 400; unavailable SQL returns 503 without changing the existing configuration.
The write procedure also validates registry mappings on every transaction.

### SQL outages

The first failed SQL operation logs one compact, single-line error without a
stack trace. Further SQL error logs are suppressed across all shops for 30
minutes. Every generated sale still attempts a write at the normal interval:
there is **no write cooldown**. Latest receipts remain available locally.
Failed sales are not retained, queued, or replayed, and do not increase recorded
sale/revenue counters.

The first failure at or after the 30-minute logging window logs another error
and starts a new window. Successful sends do not reset the logging window.
The logging throttle is per app process, resets on restart, and is independent
for each replica. Cancellation propagates without being logged as an outage.
Container Apps forwards console errors to its configured Log Analytics workspace.

## Configure shops and prices

Edit `shops.json`. `MinItemPrice` and `MaxItemPrice` are local-currency base prices per flavor item. Takeaway tubs apply a larger format multiplier. JPY values are rounded to whole yen; other configured currencies use two decimal places. Italian sales include a simulated 10% tax amount; other countries currently emit zero tax so downstream consumers do not mistake a generic rate for a local fiscal rule.

Use IANA time zone IDs such as `Europe/Rome` and define at least six available flavors per shop.

Each shop waits a newly randomized 5–10 minutes before every sale, including its
first sale after startup or reopening. Sales are generated only from **09:00
inclusive to 23:00 exclusive in that shop's configured time zone**, including
automatic daylight-saving adjustments. A wait that crosses closing time produces
no sale; the shop sleeps until the next local 09:00 and then resumes its normal
random wait. No overnight sales are queued or caught up.

`OutsideHours` means the simulator is enabled but the shop is outside its local
work hours; it automatically resumes the following morning. `Closed` means
manually stopped and remains stopped until explicitly started. Rush mode is
visual only and cannot bypass the schedule. The old configurable
`intervalSeconds` input is no longer used (legacy saved JSON is still accepted);
the status field of that name reports the most recently sampled 300–600-second
interval. Timing is identical for successful and failed writes.

## Prepared rollout (run only when ready to change live resources)

1. From the repository root, apply the additive sales migration to the existing database without reseeding
   the registry:

   ```powershell
   & .\Fabric\ws_wu3_gelatai\GelatAI_shopdb.SQLDatabase\deploy.ps1 -SalesOnly
   ```

2. Grant the shop system-assigned identity Fabric item **Read** on this database
   and enable the required service-principal Fabric tenant setting. Then, as an
   authorized Entra administrator, run `grant-sales-access.sql` on the writable
   endpoint. The script grants procedure execution and only required catalog
   reads, not `db_owner`. See the database README for prerequisites.

```powershell
az acr build --registry <acr-name> --image apishop:latest .\apishop
```

3. From the repository root, build the image as above and deploy the dedicated
   shop template using the discovered SQL settings:

```powershell
az deployment group create --resource-group <resource-group> --template-file .\infra\shop.bicep --parameters containerImage='<acr-name>.azurecr.io/apishop:latest' sqlServer='<discovered-server>,1433' sqlDatabase='<discovered-physical-database-name>'
```

Allow outbound SQL connectivity on port 1433 and redirect ports 11000-11999.
The template does not create or grant access to the Fabric database. Existing
Eventstream/Eventhouse resources and historical events are left untouched.
Migrating old events or disabling unused resources is a separate action.

## Verification

From the repository root:

```powershell
dotnet test .\tests\EventHubCooldown.Tests\EventHubCooldown.Tests.csproj --configuration Release
```

`LocalSql` tests require SQL Server LocalDB `MSSQLLocalDB` on Windows. They create
and remove an isolated, uniquely named database and verify the actual migration,
atomic writes, duplicate handling, rollback, and reporting grains without
touching Fabric. Portable-only runs can use `--filter "Category!=LocalSql"`, but
do not verify the SQL contract.
