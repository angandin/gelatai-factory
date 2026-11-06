# SQL Database to Lakehouse copy

`nb_copy_shopdb_to_lakehouse` reads every user table directly from
`GelatAI_shopdb` using authenticated SQL Server JDBC and writes physical, managed
Delta tables to `GelatAI_lakehouse.shops`, retaining table and column names.
Empty tables are copied too. No shortcuts, mirrored-table reads, or views are used.

## Run

Open the notebook in `ws_wu3_gelatai`, attach `GelatAI_lakehouse` as its default
lakehouse, and run all cells. The runner needs Fabric item-read permissions,
SQL `SELECT` access to all source tables (and visibility of their metadata),
and write access to the lakehouse. The JDBC driver is included in Fabric Spark.
Authentication uses the runner's Entra token; no passwords are stored.

The source is also available in Fabric Git notebook format in
[notebook-content.py](notebook-content.py). The configuration cell contains only
display names; IDs and SQL connection properties are discovered at runtime.

## Refresh and validation

- Each run fully overwrites only the matching tables in `shops`, including schema
  changes. Source deletions are reflected; rerunning does not append duplicates.
- Every copied table is checked for column names/order and Spark types, row count,
  and bidirectional row equality (including duplicates and nulls).
- A successful run writes a timestamped JSON validation report under
  `GelatAI_lakehouse/Files/shops_copy`.
- Source SQL tables are read only. Existing report/model bindings are unchanged.
- Name collisions across SQL schemas and shortcuts within `shops` fail explicitly.
  Tables already in the destination but no longer present in SQL are not deleted.
- Copies commit atomically **per table**, not for the entire database. A failure
  leaves earlier successful tables refreshed; fix the error and rerun all cells.
  Pause source writes if all tables must represent the same business instant.
- SQL types are mapped to Spark/Delta equivalents, preserving the current shop
  schema's values, including decimal precision and UTC timestamps. SQL constraints,
  indexes, collation, defaults, and identity-generation behavior are not copied.
  SQL types without a lossless Spark equivalent require explicit mapping before
  expanding the source schema.
