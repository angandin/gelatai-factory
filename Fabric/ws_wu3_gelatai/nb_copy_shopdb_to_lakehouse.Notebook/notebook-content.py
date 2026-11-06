# Fabric notebook source

# METADATA ********************

# META {
# META   "kernel_info": {
# META     "name": "synapse_pyspark"
# META   }
# META }

# MARKDOWN ********************

# # Copy shop SQL tables to Lakehouse Delta tables
# Reads all user tables directly from GelatAI_shopdb, including empty tables.
# Writes independent, managed Delta tables in GelatAI_lakehouse.shops.
# Reruns replace the destination contents; the SQL database is never modified.
# SQL keys, indexes, identity generation and defaults are not replicated.
# Each table is read separately: pause source writers for a consistent database-wide snapshot.

# CELL ********************

workspace_name = "ws_wu3_gelatai"
database_display_name = "GelatAI_shopdb"
lakehouse_display_name = "GelatAI_lakehouse"
target_schema = "shops"

# CELL ********************

from collections import Counter
from datetime import datetime, timezone
import json

import notebookutils
import requests
from pyspark import StorageLevel


def fabric_get(url):
    response = requests.get(
        url,
        headers={
            "Authorization": f"Bearer {notebookutils.credentials.getToken('https://api.fabric.microsoft.com')}",
            "x-ms-fabric-skill": "spark-authoring-cli",
        },
        timeout=60,
    )
    response.raise_for_status()
    return response.json()


def fabric_list(url):
    items = []
    while url:
        page = fabric_get(url)
        items.extend(page["value"])
        url = page.get("continuationUri")
    return items


def find_item(item_type, display_name):
    items = fabric_list(f"{workspace_url}/items?type={item_type}")
    matches = [item for item in items if item["displayName"] == display_name]
    if len(matches) != 1:
        raise RuntimeError(
            f"Expected one {item_type} named {display_name!r}; found {len(matches)}."
        )
    return matches[0]


def spark_identifier(value):
    return "`" + value.replace("`", "``") + "`"


def sql_identifier(value):
    return "[" + value.replace("]", "]]") + "]"


def read_sql(query):
    return (
        spark.read.format("jdbc")
        .option("url", jdbc_url)
        .option("driver", "com.microsoft.sqlserver.jdbc.SQLServerDriver")
        .option("accessToken", notebookutils.credentials.getToken("https://database.windows.net/"))
        .option("query", query)
        .option("fetchsize", "10000")
        .load()
    )


workspace_id = notebookutils.runtime.context["currentWorkspaceId"]
workspace_url = f"https://api.fabric.microsoft.com/v1/workspaces/{workspace_id}"
workspace = fabric_get(workspace_url)
if workspace["displayName"] != workspace_name:
    raise RuntimeError(f"Run this notebook in workspace {workspace_name!r}.")
if not workspace.get("capacityId"):
    raise RuntimeError("The workspace has no assigned Fabric capacity.")

database = find_item("SQLDatabase", database_display_name)
lakehouse = find_item("Lakehouse", lakehouse_display_name)
database_details = fabric_get(f"{workspace_url}/sqlDatabases/{database['id']}")
lakehouse_details = fabric_get(f"{workspace_url}/lakehouses/{lakehouse['id']}")
if not lakehouse_details["properties"].get("defaultSchema"):
    raise RuntimeError("The destination lakehouse must have schemas enabled.")
if notebookutils.runtime.context.get("defaultLakehouseId") != lakehouse["id"]:
    raise RuntimeError(f"Attach {lakehouse_display_name!r} as the default lakehouse and restart the session.")

server = database_details["properties"]["serverFqdn"].replace(",", ":")
database_name = database_details["properties"]["databaseName"]
jdbc_url = (
    f"jdbc:sqlserver://{server};databaseName={database_name};"
    "encrypt=true;trustServerCertificate=false;loginTimeout=30;"
)
spark.conf.set("spark.sql.session.timeZone", "UTC")

source_tables = read_sql("""
SELECT s.name AS source_schema, t.name AS table_name
FROM sys.tables AS t
INNER JOIN sys.schemas AS s ON s.schema_id = t.schema_id
WHERE t.is_ms_shipped = 0
""").collect()
if not source_tables:
    raise RuntimeError("No SQL user tables were found. Check source permissions.")
source_tables.sort(key=lambda row: (row.source_schema, row.table_name))

# SQL schemas are flattened into shops, so duplicate table names cannot be copied safely.
name_counts = Counter(row.table_name.casefold() for row in source_tables)
duplicates = [name for name, count in name_counts.items() if count > 1]
if duplicates:
    raise RuntimeError(f"Source table names collide across SQL schemas: {duplicates}")

schema_path = f"Tables/{target_schema}"
shortcuts = fabric_list(f"{workspace_url}/items/{lakehouse['id']}/shortcuts")
for shortcut in shortcuts:
    shortcut_path = f"{shortcut['path'].strip('/')}/{shortcut['name']}".casefold()
    target_path = schema_path.casefold()
    if shortcut_path == target_path or shortcut_path.startswith(target_path + "/"):
        raise RuntimeError(
            f"Destination contains a shortcut at {shortcut_path!r}; remove it before copying."
        )

namespace = ".".join(
    spark_identifier(part)
    for part in (workspace_name, lakehouse_display_name, target_schema)
)
spark.sql(f"CREATE SCHEMA IF NOT EXISTS {namespace}")
print(f"Copying {len(source_tables)} SQL tables to {namespace}")

# CELL ********************

results = []
started_at = datetime.now(timezone.utc)
for source_table in source_tables:
    sql_table = ".".join(
        sql_identifier(part) for part in (source_table.source_schema, source_table.table_name)
    )
    target_table = f"{namespace}.{spark_identifier(source_table.table_name)}"
    print(f"Copying {sql_table} -> {target_table}")
    source = read_sql(f"SELECT * FROM {sql_table}").persist(StorageLevel.MEMORY_AND_DISK)
    try:
        source_count = source.count()
        source.write.format("delta").mode("overwrite").option(
            "overwriteSchema", "true"
        ).saveAsTable(target_table)
        destination = spark.table(target_table)
        source_types = [(field.name, field.dataType) for field in source.schema]
        destination_types = [(field.name, field.dataType) for field in destination.schema]
        if source_types != destination_types:
            raise RuntimeError(f"Column names, order or types differ for {target_table}.")
        destination_count = destination.count()
        if destination_count != source_count:
            raise RuntimeError(
                f"Row count mismatch for {target_table}: SQL={source_count}, Delta={destination_count}."
            )
        if (
            source.exceptAll(destination).limit(1).count()
            or destination.exceptAll(source).limit(1).count()
        ):
            raise RuntimeError(f"Row values differ for {target_table}.")
        detail = spark.sql(f"DESCRIBE DETAIL {target_table}").first()
        if detail.format != "delta":
            raise RuntimeError(f"{target_table} is not a physical Delta table.")
        results.append({
            "source": f"{source_table.source_schema}.{source_table.table_name}",
            "target": f"{lakehouse_display_name}.{target_schema}.{source_table.table_name}",
            "rows": destination_count,
            "format": detail.format,
            "location": detail.location,
            "validated": True,
        })
        print(f"Validated {target_table}: {destination_count} rows")
    finally:
        source.unpersist()

completed_at = datetime.now(timezone.utc)
summary = {
    "status": "Completed",
    "started_at": started_at.isoformat(),
    "completed_at": completed_at.isoformat(),
    "workspace_id": workspace_id,
    "database_id": database["id"],
    "lakehouse_id": lakehouse["id"],
    "tables": results,
}
audit_directory = (
    f"abfss://{workspace_id}@onelake.dfs.fabric.microsoft.com/"
    f"{lakehouse['id']}/Files/shops_copy"
)
notebookutils.fs.mkdirs(audit_directory)
audit_path = f"{audit_directory}/{started_at.strftime('%Y%m%dT%H%M%S%fZ')}.json"
notebookutils.fs.put(audit_path, json.dumps(summary, indent=2), False)
print(json.dumps(summary, indent=2))
print(f"Validation report: {audit_path}")
