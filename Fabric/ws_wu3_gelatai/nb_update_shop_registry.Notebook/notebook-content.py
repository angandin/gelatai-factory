# Fabric notebook source

# METADATA ********************

# META {
# META   "kernel_info": {
# META     "name": "synapse_pyspark"
# META   }
# META }

# MARKDOWN ********************

# # Weekly Shop Registry Simulation
# Creates the September 2026 baseline and applies one idempotent update per calendar week.

# CELL ********************

# Fabric notebook source

# This value is intentionally fixed so all generated registry records remain
# valid from the month requested when the simulation was created.
baseline_month = "2026-09-01"
simulation_date = ""  # Optional ISO date override for testing; blank uses UTC today.
database_display_name = "GelatAI_shopdb"
kql_database_display_name = "GelatAI-rtdata"

from datetime import date, datetime, timezone, timedelta
import struct

import pandas as pd
import pyodbc
import requests
from notebookutils import credentials, runtime


def get_fabric_sql_database(workspace_id: str, display_name: str) -> dict:
    token = credentials.getToken("https://api.fabric.microsoft.com")
    headers = {
        "Authorization": f"Bearer {token}",
        "x-ms-fabric-skill": "spark-authoring-cli",
    }
    url = f"https://api.fabric.microsoft.com/v1/workspaces/{workspace_id}/sqlDatabases"
    matches = []

    while url:
        response = requests.get(url, headers=headers, timeout=60)
        response.raise_for_status()
        payload = response.json()
        matches.extend(item for item in payload.get("value", []) if item["displayName"] == display_name)
        url = payload.get("continuationUri")

    if len(matches) != 1:
        raise RuntimeError(
            f"Expected exactly one SQL database named '{display_name}' in workspace "
            f"'{workspace_id}', found {len(matches)}."
        )

    details_url = (
        f"https://api.fabric.microsoft.com/v1/workspaces/{workspace_id}"
        f"/sqlDatabases/{matches[0]['id']}"
    )
    response = requests.get(details_url, headers=headers, timeout=60)
    response.raise_for_status()
    return response.json()


def get_fabric_item(workspace_id: str, item_type: str, display_name: str) -> dict:
    token = credentials.getToken("https://api.fabric.microsoft.com")
    headers = {
        "Authorization": f"Bearer {token}",
        "x-ms-fabric-skill": "spark-authoring-cli",
    }
    url = (
        f"https://api.fabric.microsoft.com/v1/workspaces/{workspace_id}"
        f"/items?type={item_type}"
    )
    matches = []

    while url:
        response = requests.get(url, headers=headers, timeout=60)
        response.raise_for_status()
        payload = response.json()
        matches.extend(item for item in payload.get("value", []) if item["displayName"] == display_name)
        url = payload.get("continuationUri")

    if len(matches) != 1:
        raise RuntimeError(
            f"Expected exactly one {item_type} named '{display_name}' in workspace "
            f"'{workspace_id}', found {len(matches)}."
        )

    endpoint_names = {
        "KQLDatabase": "kqlDatabases",
    }
    endpoint_name = endpoint_names.get(item_type)
    if endpoint_name is None:
        raise ValueError(f"No item-detail endpoint mapping exists for '{item_type}'.")

    details_url = (
        f"https://api.fabric.microsoft.com/v1/workspaces/{workspace_id}"
        f"/{endpoint_name}/{matches[0]['id']}"
    )
    response = requests.get(details_url, headers=headers, timeout=60)
    response.raise_for_status()
    return response.json()


def query_factory_telemetry(
    kql_database: dict,
    window_start: datetime,
    window_end: datetime,
) -> tuple[int, int]:
    properties = kql_database["properties"]
    query_service_uri = properties["queryServiceUri"].rstrip("/")
    database_name = properties.get("databaseName", kql_database["displayName"])
    token = credentials.getToken("kusto")
    window_start_text = window_start.strftime("%Y-%m-%dT%H:%M:%SZ")
    window_end_text = window_end.strftime("%Y-%m-%dT%H:%M:%SZ")
    query = f"""
machinesraw
| where todatetime(timestamp) >= datetime({window_start_text})
    and todatetime(timestamp) < datetime({window_end_text})
| extend anomaly = tostring(parse_json(payload).anomaly)
| summarize
    TelemetryEventCount = count(),
    TelemetryAnomalyCount = countif(isnotempty(anomaly) and anomaly != "none")
"""
    response = requests.post(
        f"{query_service_uri}/v2/rest/query",
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
        },
        json={"db": database_name, "csl": query},
        timeout=120,
    )
    response.raise_for_status()
    payload = response.json()
    tables = payload if isinstance(payload, list) else payload.get("Tables", [])
    primary = next((table for table in tables if table.get("TableKind") == "PrimaryResult"), None)
    if primary is None or not primary.get("Rows"):
        raise RuntimeError("The Eventhouse telemetry query returned no primary result.")

    row = primary["Rows"][0]
    return int(row[0]), int(row[1])


def connect_with_entra_token(server: str, database: str) -> pyodbc.Connection:
    token = credentials.getToken("https://database.windows.net/")
    token_bytes = token.encode("utf-16-le")
    token_struct = struct.pack(f"<I{len(token_bytes)}s", len(token_bytes), token_bytes)
    connection_string = (
        "DRIVER={ODBC Driver 18 for SQL Server};"
        f"SERVER={server};DATABASE={database};"
        "Encrypt=yes;TrustServerCertificate=no;"
    )
    return pyodbc.connect(
        connection_string,
        attrs_before={1256: token_struct},
        autocommit=False,
    )


context = runtime.context
workspace_id = context["currentWorkspaceId"]
database_item = get_fabric_sql_database(workspace_id, database_display_name)
server_fqdn = database_item["properties"]["serverFqdn"]
database_name = database_item["properties"]["databaseName"]

effective_date = date.fromisoformat(simulation_date) if simulation_date else datetime.now(timezone.utc).date()
baseline_date = date.fromisoformat(baseline_month)
run_week = effective_date - timedelta(days=effective_date.weekday())
week_index = max(0, (run_week - baseline_date).days // 7)
telemetry_window_end = datetime.combine(run_week, datetime.min.time(), tzinfo=timezone.utc)
telemetry_window_start = telemetry_window_end - timedelta(days=7)
kql_database = get_fabric_item(workspace_id, "KQLDatabase", kql_database_display_name)
telemetry_event_count, telemetry_anomaly_count = query_factory_telemetry(
    kql_database,
    telemetry_window_start,
    telemetry_window_end,
)

print(
    f"workspace={workspace_id}, database={database_display_name}, "
    f"baseline={baseline_date}, run_week={run_week}, week_index={week_index}, "
    f"telemetry_events={telemetry_event_count}, telemetry_anomalies={telemetry_anomaly_count}"
)

sql = """
SET NOCOUNT ON;
SET XACT_ABORT ON;

BEGIN TRANSACTION;

IF EXISTS (SELECT 1 FROM dbo.RegistrySimulationRun WHERE RunWeek = ?)
BEGIN
    COMMIT TRANSACTION;
    SELECT CAST(0 AS bit) AS Applied, CAST(0 AS int) AS ChangeCount;
    RETURN;
END;

DECLARE @RunWeek date = ?;
DECLARE @BaselineMonth date = ?;
DECLARE @WeekIndex int = ?;
DECLARE @ChangeCount int = 0;
DECLARE @Affected int = 0;
DECLARE @IsBaseline bit =
    CASE WHEN EXISTS (SELECT 1 FROM dbo.RegistrySimulationRun) THEN 0 ELSE 1 END;

INSERT INTO dbo.RegistrySimulationRun (RunWeek, BaselineMonth, ChangeCount)
VALUES (@RunWeek, @BaselineMonth, 0);

IF @IsBaseline = 1
BEGIN
    UPDATE dbo.Shop
    SET OpenedOn = COALESCE(OpenedOn, @BaselineMonth),
        UpdatedAtUtc = SYSUTCDATETIME()
    WHERE IsActive = 1;
    SET @Affected = @@ROWCOUNT;
    SET @ChangeCount += @Affected;

    UPDATE dbo.ShopProduct
    SET FirstAvailableOn = COALESCE(FirstAvailableOn, @BaselineMonth),
        RetailPrice = CASE s.CurrencyCode
            WHEN 'JPY' THEN 420 + ((sp.ProductId % 6) * 40)
            WHEN 'USD' THEN CAST(4.50 + ((sp.ProductId % 6) * 0.35) AS decimal(19,4))
            ELSE CAST(2.80 + ((sp.ProductId % 6) * 0.30) AS decimal(19,4))
        END,
        UpdatedAtUtc = SYSUTCDATETIME()
    FROM dbo.ShopProduct AS sp
    INNER JOIN dbo.Shop AS s ON s.ShopId = sp.ShopId
    WHERE sp.IsActive = 1;
    SET @Affected = @@ROWCOUNT;
    SET @ChangeCount += @Affected;

    INSERT INTO dbo.Employee (
        ShopId,
        EmployeeNumber,
        FirstName,
        LastName,
        JobTitle,
        HiredOn
    )
    SELECT
        s.ShopId,
        CONCAT(s.ShopCode, '-E0', staff.Slot),
        staff.FirstName,
        CONCAT(s.City, N' Team'),
        staff.JobTitle,
        @BaselineMonth
    FROM dbo.Shop AS s
    CROSS APPLY (
        VALUES
            (1, N'Alex', N'Shop Manager'),
            (2, N'Sam', N'Gelato Specialist'),
            (3, N'Jordan', N'Shop Associate')
    ) AS staff (Slot, FirstName, JobTitle)
    WHERE s.IsActive = 1
      AND NOT EXISTS (
          SELECT 1
          FROM dbo.Employee AS existing
          WHERE existing.EmployeeNumber = CONCAT(s.ShopCode, '-E0', staff.Slot)
      );
    SET @Affected = @@ROWCOUNT;
    SET @ChangeCount += @Affected;

    MERGE dbo.Inventory AS target
    USING (
        SELECT
            sp.ShopId,
            sp.ProductId,
            CAST(30 + ((sp.ShopId * 7 + sp.ProductId * 11) % 45) AS decimal(18,3)) AS QuantityOnHand,
            CAST(12 + ((sp.ProductId * 3) % 8) AS decimal(18,3)) AS ReorderLevel
        FROM dbo.ShopProduct AS sp
        WHERE sp.IsActive = 1
    ) AS source
    ON target.ShopId = source.ShopId
    AND target.ProductId = source.ProductId
    WHEN MATCHED THEN
        UPDATE SET
            QuantityOnHand = source.QuantityOnHand,
            ReorderLevel = source.ReorderLevel,
            LastCountedAtUtc = SYSUTCDATETIME(),
            UpdatedAtUtc = SYSUTCDATETIME()
    WHEN NOT MATCHED THEN
        INSERT (ShopId, ProductId, QuantityOnHand, ReorderLevel, LastCountedAtUtc)
        VALUES (
            source.ShopId,
            source.ProductId,
            source.QuantityOnHand,
            source.ReorderLevel,
            SYSUTCDATETIME()
        );
    SET @Affected = @@ROWCOUNT;
    SET @ChangeCount += @Affected;

    INSERT INTO dbo.RegistryChangeLog (
        RunWeek,
        EntityType,
        EntityKey,
        ChangeType,
        ChangeSummary
    )
    VALUES (
        @RunWeek,
        'Registry',
        N'apishop',
        'BaselineCreated',
        N'Created the initial shop, employee, assortment, price, and inventory state.'
    );
END;

UPDATE inventory
SET
    QuantityOnHand = CASE
        WHEN inventory.QuantityOnHand - demand.WeeklyDemand <= inventory.ReorderLevel
            THEN inventory.QuantityOnHand - demand.WeeklyDemand + demand.Replenishment
        ELSE inventory.QuantityOnHand - demand.WeeklyDemand
    END,
    LastCountedAtUtc = SYSUTCDATETIME(),
    UpdatedAtUtc = SYSUTCDATETIME()
FROM dbo.Inventory AS inventory
CROSS APPLY (
    SELECT
        CAST(4 + ((inventory.ShopId * 13 + inventory.ProductId * 5 + @WeekIndex) % 10) AS decimal(18,3))
            AS WeeklyDemand,
        CAST(28 + ((inventory.ProductId * 7 + @WeekIndex) % 18) AS decimal(18,3))
            AS Replenishment
) AS demand;
SET @Affected = @@ROWCOUNT;
SET @ChangeCount += @Affected;

UPDATE dbo.ShopProduct
SET
    IsFeatured = 0,
    FeaturedFrom = NULL,
    FeaturedTo = NULL,
    UpdatedAtUtc = SYSUTCDATETIME()
WHERE IsFeatured = 1;

;WITH ranked AS (
    SELECT
        sp.ShopId,
        sp.ProductId,
        ROW_NUMBER() OVER (PARTITION BY sp.ShopId ORDER BY sp.ProductId) AS ProductRank,
        COUNT(*) OVER (PARTITION BY sp.ShopId) AS ProductCount
    FROM dbo.ShopProduct AS sp
    WHERE sp.IsActive = 1
),
selected AS (
    SELECT ShopId, ProductId
    FROM ranked
    WHERE ProductRank = ((@WeekIndex + ShopId) % ProductCount) + 1
)
UPDATE sp
SET
    IsFeatured = 1,
    FeaturedFrom = @RunWeek,
    FeaturedTo = DATEADD(day, 6, @RunWeek),
    UpdatedAtUtc = SYSUTCDATETIME()
FROM dbo.ShopProduct AS sp
INNER JOIN selected
    ON selected.ShopId = sp.ShopId
   AND selected.ProductId = sp.ProductId;
SET @Affected = @@ROWCOUNT;
SET @ChangeCount += @Affected;

INSERT INTO dbo.RegistryChangeLog (
    RunWeek,
    EntityType,
    EntityKey,
    ChangeType,
    ChangeSummary
)
SELECT
    @RunWeek,
    'ShopProduct',
    CONCAT(s.ShopCode, N'/', p.Sku),
    'FeaturedFlavor',
    CONCAT(N'Featured ', p.ProductName, N' for the week.')
FROM dbo.ShopProduct AS sp
INNER JOIN dbo.Shop AS s ON s.ShopId = sp.ShopId
INNER JOIN dbo.Product AS p ON p.ProductId = sp.ProductId
WHERE sp.IsFeatured = 1;

IF @WeekIndex > 0 AND @WeekIndex % 4 = 0
BEGIN
    UPDATE dbo.ShopProduct
    SET
        RetailPrice = ROUND(RetailPrice * 1.02, CASE WHEN s.CurrencyCode = 'JPY' THEN 0 ELSE 2 END),
        UpdatedAtUtc = SYSUTCDATETIME()
    FROM dbo.ShopProduct AS sp
    INNER JOIN dbo.Shop AS s ON s.ShopId = sp.ShopId
    WHERE sp.IsActive = 1
      AND sp.RetailPrice IS NOT NULL;
    SET @Affected = @@ROWCOUNT;
    SET @ChangeCount += @Affected;

    INSERT INTO dbo.RegistryChangeLog (
        RunWeek,
        EntityType,
        EntityKey,
        ChangeType,
        ChangeSummary
    )
    VALUES (
        @RunWeek,
        'ShopProduct',
        N'all',
        'QuarterlyPriceReview',
        N'Applied a 2 percent catalog price adjustment.'
    );
END;

IF @WeekIndex > 0 AND @WeekIndex % 8 = 0
BEGIN
    ;WITH departing AS (
        SELECT
            e.EmployeeId,
            e.ShopId,
            ROW_NUMBER() OVER (PARTITION BY e.ShopId ORDER BY e.EmployeeId DESC) AS EmployeeRank
        FROM dbo.Employee AS e
        WHERE e.IsActive = 1
          AND e.JobTitle <> N'Shop Manager'
    )
    UPDATE employee
    SET
        EndedOn = @RunWeek,
        IsActive = 0,
        UpdatedAtUtc = SYSUTCDATETIME()
    FROM dbo.Employee AS employee
    INNER JOIN departing
        ON departing.EmployeeId = employee.EmployeeId
       AND departing.EmployeeRank = 1;
    SET @Affected = @@ROWCOUNT;
    SET @ChangeCount += @Affected;

    INSERT INTO dbo.Employee (
        ShopId,
        EmployeeNumber,
        FirstName,
        LastName,
        JobTitle,
        HiredOn
    )
    SELECT
        s.ShopId,
        CONCAT(s.ShopCode, '-W', RIGHT(CONCAT('000', @WeekIndex), 3)),
        N'Taylor',
        CONCAT(s.City, N' Team'),
        N'Shop Associate',
        @RunWeek
    FROM dbo.Shop AS s
    WHERE s.IsActive = 1;
    SET @Affected = @@ROWCOUNT;
    SET @ChangeCount += @Affected;

    INSERT INTO dbo.RegistryChangeLog (
        RunWeek,
        EntityType,
        EntityKey,
        ChangeType,
        ChangeSummary
    )
    VALUES (
        @RunWeek,
        'Employee',
        N'all-shops',
        'StaffRotation',
        N'Applied the scheduled eight-week employee rotation.'
    );
END;

UPDATE dbo.RegistrySimulationRun
SET ChangeCount = @ChangeCount
WHERE RunWeek = @RunWeek;

COMMIT TRANSACTION;

SELECT CAST(1 AS bit) AS Applied, @ChangeCount AS ChangeCount;
"""

connection = connect_with_entra_token(server_fqdn, database_name)
try:
    cursor = connection.cursor()
    cursor.execute(
        sql,
        run_week,
        run_week,
        baseline_date,
        week_index,
    )
    result = cursor.fetchone()
    connection.commit()
    applied = bool(result.Applied)
    change_count = int(result.ChangeCount)
finally:
    connection.close()

print(f"applied={applied}, change_count={change_count}")

logistics_sql = """
SET NOCOUNT ON;
SET XACT_ABORT ON;

BEGIN TRANSACTION;

IF EXISTS (SELECT 1 FROM dbo.LogisticsSimulationRun WHERE RunWeek = ?)
BEGIN
    COMMIT TRANSACTION;
    SELECT
        CAST(0 AS bit) AS Applied,
        CAST(0 AS int) AS ProductionBatchCount,
        CAST(0 AS int) AS ShipmentCount,
        CAST(0 AS int) AS ShipmentItemCount;
    RETURN;
END;

DECLARE @RunWeek date = ?;
DECLARE @TelemetryWindowStartUtc datetime2(0) = ?;
DECLARE @TelemetryWindowEndUtc datetime2(0) = ?;
DECLARE @TelemetryEventCount bigint = ?;
DECLARE @TelemetryAnomalyCount bigint = ?;
DECLARE @FactoryId int = (
    SELECT FactoryId
    FROM dbo.Factory
    WHERE FactoryCode = 'gelatai-factory-001'
      AND IsActive = 1
);
DECLARE @HealthFactor decimal(9,4) = CASE
    WHEN @TelemetryEventCount = 0 THEN 0.7500
    ELSE 1.0000 - (
        CASE
            WHEN CAST(@TelemetryAnomalyCount AS decimal(19,4)) / @TelemetryEventCount > 0.2500
                THEN 0.2500
            ELSE CAST(@TelemetryAnomalyCount AS decimal(19,4)) / @TelemetryEventCount
        END
    )
END;

IF @FactoryId IS NULL
BEGIN
    THROW 51000, 'The active GelatAI factory registry record was not found.', 1;
END;

UPDATE shipment
SET
    Status = 'Received',
    ReceivedAtUtc = COALESCE(shipment.ExpectedAtUtc, @TelemetryWindowEndUtc),
    UpdatedAtUtc = SYSUTCDATETIME()
FROM dbo.Shipment AS shipment
WHERE shipment.Status = 'Dispatched'
  AND shipment.ExpectedAtUtc <= @TelemetryWindowEndUtc;

UPDATE item
SET QuantityReceived = item.QuantitySent
FROM dbo.ShipmentItem AS item
INNER JOIN dbo.Shipment AS shipment ON shipment.ShipmentId = item.ShipmentId
WHERE shipment.Status = 'Received'
  AND item.QuantityReceived IS NULL;

;WITH received AS (
    SELECT
        shipment.ShopId,
        item.ProductId,
        SUM(item.QuantityReceived) AS QuantityReceived
    FROM dbo.Shipment AS shipment
    INNER JOIN dbo.ShipmentItem AS item ON item.ShipmentId = shipment.ShipmentId
    WHERE shipment.Status = 'Received'
      AND shipment.ReceivedAtUtc >= @TelemetryWindowStartUtc
      AND shipment.ReceivedAtUtc < @TelemetryWindowEndUtc
    GROUP BY shipment.ShopId, item.ProductId
)
UPDATE inventory
SET
    QuantityOnHand = inventory.QuantityOnHand + received.QuantityReceived,
    LastCountedAtUtc = SYSUTCDATETIME(),
    UpdatedAtUtc = SYSUTCDATETIME()
FROM dbo.Inventory AS inventory
INNER JOIN received
    ON received.ShopId = inventory.ShopId
   AND received.ProductId = inventory.ProductId;

INSERT INTO dbo.ProductionBatch (
    BatchNumber,
    FactoryId,
    ProductId,
    ProducedAtUtc,
    ExpiresAtUtc,
    QuantityProduced,
    UnitOfMeasure,
    TelemetryWindowStartUtc,
    TelemetryWindowEndUtc,
    TelemetryEventCount,
    TelemetryAnomalyCount,
    QualityStatus
)
SELECT
    CONCAT(
        'BAT-',
        CONVERT(char(8), @RunWeek, 112),
        '-',
        RIGHT(CONCAT('00000', p.ProductId), 5)
    ),
    @FactoryId,
    p.ProductId,
    DATEADD(hour, 6 + (p.ProductId % 10), @TelemetryWindowEndUtc),
    DATEADD(day, 60, @TelemetryWindowEndUtc),
    CAST(COUNT(sp.ShopId) * 30.0 * @HealthFactor AS decimal(18,3)),
    p.UnitOfMeasure,
    @TelemetryWindowStartUtc,
    @TelemetryWindowEndUtc,
    @TelemetryEventCount,
    @TelemetryAnomalyCount,
    CASE
        WHEN @TelemetryEventCount > 0
         AND CAST(@TelemetryAnomalyCount AS decimal(19,4)) / @TelemetryEventCount > 0.2000
            THEN 'Held'
        ELSE 'Released'
    END
FROM dbo.Product AS p
INNER JOIN dbo.ShopProduct AS sp
    ON sp.ProductId = p.ProductId
   AND sp.IsActive = 1
WHERE p.IsActive = 1
GROUP BY p.ProductId, p.UnitOfMeasure;

DECLARE @ProductionBatchCount int = @@ROWCOUNT;

INSERT INTO dbo.Shipment (
    ShipmentNumber,
    FactoryId,
    ShopId,
    Status,
    DispatchedAtUtc,
    ExpectedAtUtc,
    Notes
)
SELECT
    CONCAT('SHP-', CONVERT(char(8), @RunWeek, 112), '-', s.ShopCode),
    @FactoryId,
    s.ShopId,
    'Dispatched',
    DATEADD(hour, 18, @TelemetryWindowEndUtc),
    DATEADD(day, CASE WHEN s.CountryCode = 'IT' THEN 2 ELSE 4 END, @TelemetryWindowEndUtc),
    CONCAT(
        N'Weekly allocation based on Eventhouse telemetry window. Events: ',
        @TelemetryEventCount,
        N'; anomalies: ',
        @TelemetryAnomalyCount,
        N'.'
    )
FROM dbo.Shop AS s
WHERE s.IsActive = 1;

DECLARE @ShipmentCount int = @@ROWCOUNT;

INSERT INTO dbo.ShipmentItem (
    ShipmentId,
    ProductId,
    ProductionBatchId,
    QuantitySent,
    UnitCost
)
SELECT
    shipment.ShipmentId,
    sp.ProductId,
    batch.ProductionBatchId,
    CAST(
        10
        + ((shipment.ShopId * 11 + sp.ProductId * 7 + DATEPART(iso_week, @RunWeek)) % 9)
        AS decimal(18,3)
    ),
    CAST(
        CASE
            WHEN shop.CurrencyCode = 'JPY' THEN 240 + ((sp.ProductId % 5) * 20)
            ELSE 1.40 + ((sp.ProductId % 5) * 0.15)
        END
        AS decimal(19,4)
    )
FROM dbo.Shipment AS shipment
INNER JOIN dbo.Shop AS shop ON shop.ShopId = shipment.ShopId
INNER JOIN dbo.ShopProduct AS sp
    ON sp.ShopId = shipment.ShopId
   AND sp.IsActive = 1
INNER JOIN dbo.ProductionBatch AS batch
    ON batch.FactoryId = shipment.FactoryId
   AND batch.ProductId = sp.ProductId
   AND batch.TelemetryWindowStartUtc = @TelemetryWindowStartUtc
   AND batch.TelemetryWindowEndUtc = @TelemetryWindowEndUtc
WHERE shipment.ShipmentNumber LIKE CONCAT('SHP-', CONVERT(char(8), @RunWeek, 112), '-%')
  AND batch.QualityStatus = 'Released';

DECLARE @ShipmentItemCount int = @@ROWCOUNT;

;WITH allocated AS (
    SELECT
        item.ProductionBatchId,
        SUM(item.QuantitySent) AS QuantityAllocated
    FROM dbo.ShipmentItem AS item
    INNER JOIN dbo.Shipment AS shipment ON shipment.ShipmentId = item.ShipmentId
    WHERE shipment.ShipmentNumber LIKE CONCAT('SHP-', CONVERT(char(8), @RunWeek, 112), '-%')
    GROUP BY item.ProductionBatchId
)
UPDATE batch
SET QuantityAllocated = allocated.QuantityAllocated
FROM dbo.ProductionBatch AS batch
INNER JOIN allocated ON allocated.ProductionBatchId = batch.ProductionBatchId;

INSERT INTO dbo.LogisticsSimulationRun (
    RunWeek,
    TelemetryWindowStartUtc,
    TelemetryWindowEndUtc,
    TelemetryEventCount,
    TelemetryAnomalyCount,
    ProductionBatchCount,
    ShipmentCount,
    ShipmentItemCount
)
VALUES (
    @RunWeek,
    @TelemetryWindowStartUtc,
    @TelemetryWindowEndUtc,
    @TelemetryEventCount,
    @TelemetryAnomalyCount,
    @ProductionBatchCount,
    @ShipmentCount,
    @ShipmentItemCount
);

INSERT INTO dbo.RegistryChangeLog (
    RunWeek,
    EntityType,
    EntityKey,
    ChangeType,
    ChangeSummary
)
VALUES (
    @RunWeek,
    'Shipment',
    CONCAT('week-', CONVERT(char(8), @RunWeek, 112)),
    'FactoryAllocation',
    CONCAT(
        N'Created ',
        @ProductionBatchCount,
        N' production batches, ',
        @ShipmentCount,
        N' shipments, and ',
        @ShipmentItemCount,
        N' shipment lines from the factory telemetry window.'
    )
);

COMMIT TRANSACTION;

SELECT
    CAST(1 AS bit) AS Applied,
    @ProductionBatchCount AS ProductionBatchCount,
    @ShipmentCount AS ShipmentCount,
    @ShipmentItemCount AS ShipmentItemCount;
"""

connection = connect_with_entra_token(server_fqdn, database_name)
try:
    cursor = connection.cursor()
    cursor.execute(
        logistics_sql,
        run_week,
        run_week,
        telemetry_window_start,
        telemetry_window_end,
        telemetry_event_count,
        telemetry_anomaly_count,
    )
    logistics_result = cursor.fetchone()
    connection.commit()
    logistics_applied = bool(logistics_result.Applied)
    production_batch_count = int(logistics_result.ProductionBatchCount)
    shipment_count = int(logistics_result.ShipmentCount)
    shipment_item_count = int(logistics_result.ShipmentItemCount)
finally:
    connection.close()

print(
    f"logistics_applied={logistics_applied}, production_batches={production_batch_count}, "
    f"shipments={shipment_count}, shipment_items={shipment_item_count}"
)

connection = connect_with_entra_token(server_fqdn, database_name)
try:
    summary = pd.read_sql(
        """
        SELECT
            r.RunWeek,
            r.BaselineMonth,
            r.AppliedAtUtc,
            r.ChangeCount,
            (SELECT COUNT(*) FROM dbo.Shop WHERE IsActive = 1) AS ActiveShops,
            (SELECT COUNT(*) FROM dbo.Employee WHERE IsActive = 1) AS ActiveEmployees,
            (SELECT COUNT(*) FROM dbo.ShopProduct WHERE IsActive = 1) AS ActiveAssignments,
            (SELECT COUNT(*) FROM dbo.ShopProduct WHERE IsFeatured = 1) AS FeaturedProducts,
            (SELECT COUNT(*) FROM dbo.ProductionBatch) AS ProductionBatches,
            (SELECT COUNT(*) FROM dbo.Shipment) AS Shipments,
            (SELECT COUNT(*) FROM dbo.ShipmentItem) AS ShipmentItems
        FROM dbo.RegistrySimulationRun AS r
        WHERE r.RunWeek = ?
        """,
        connection,
        params=[run_week],
    )
finally:
    connection.close()

display(summary)

workspace_name = context["currentWorkspaceName"]
legacy_lakehouse_prefix = f"`{workspace_name}`.`GelatAI_lakehouse`.`dbo`"
for legacy_table in (
    "dim_shop",
    "dim_product",
    "shop_availability",
    "shipment_flow",
):
    spark.sql(f"DROP TABLE IF EXISTS {legacy_lakehouse_prefix}.`{legacy_table}`")
    print(f"removed_legacy_lakehouse_copy={legacy_table}")

# METADATA ********************

# META {
# META   "language": "python",
# META   "language_group": "synapse_pyspark"
# META }
