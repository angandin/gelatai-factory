-- Schema-only bootstrap. Attach the NEW target Lakehouse; never run against the source.
CREATE SCHEMA IF NOT EXISTS dbo;
CREATE SCHEMA IF NOT EXISTS sc_shopdb;
CREATE SCHEMA IF NOT EXISTS sales_analytics;

CREATE TABLE IF NOT EXISTS `dbo`.`machineanomalies` (
    `machine_id` STRING,
    `anomaly_name` STRING,
    `attribute_name` STRING,
    `min_value_anomaly` DOUBLE,
    `max_value_anomaly` DOUBLE
) USING DELTA
TBLPROPERTIES ('delta.minReaderVersion'='1', 'delta.minWriterVersion'='2');

CREATE TABLE IF NOT EXISTS `dbo`.`machineparameters` (
    `factory_id` INTEGER,
    `machine_type` STRING,
    `machine_id` STRING,
    `attribute_name` STRING,
    `min_value` DOUBLE,
    `max_value` DOUBLE
) USING DELTA
TBLPROPERTIES ('delta.minReaderVersion'='1', 'delta.minWriterVersion'='2');

CREATE TABLE IF NOT EXISTS `dbo`.`manuals` (
    `manual` STRING NOT NULL,
    `index_name` STRING NOT NULL
) USING DELTA
TBLPROPERTIES ('delta.stats.extended.collect'='true', 'delta.stats.extended.inject'='true', 'delta.minReaderVersion'='1', 'delta.minWriterVersion'='2');

CREATE TABLE IF NOT EXISTS `dbo`.`manuals_factoryhowwork` (
    `factory_id` STRING NOT NULL,
    `manual` STRING NOT NULL
) USING DELTA
TBLPROPERTIES ('delta.stats.extended.collect'='true', 'delta.stats.extended.inject'='true', 'delta.minReaderVersion'='1', 'delta.minWriterVersion'='2');

CREATE TABLE IF NOT EXISTS `dbo`.`manuals_machineissues` (
    `machine_type` STRING NOT NULL,
    `manual` STRING NOT NULL
) USING DELTA
TBLPROPERTIES ('delta.stats.extended.collect'='true', 'delta.stats.extended.inject'='true', 'delta.minReaderVersion'='1', 'delta.minWriterVersion'='2');

CREATE TABLE IF NOT EXISTS `sales_analytics`.`channel` (
    `channel` STRING
) USING DELTA
TBLPROPERTIES ('delta.stats.extended.collect'='true', 'delta.stats.extended.inject'='true', 'delta.minReaderVersion'='1', 'delta.minWriterVersion'='2');

CREATE TABLE IF NOT EXISTS `sales_analytics`.`currency` (
    `currency` STRING
) USING DELTA
TBLPROPERTIES ('delta.stats.extended.collect'='true', 'delta.stats.extended.inject'='true', 'delta.minReaderVersion'='1', 'delta.minWriterVersion'='2');

CREATE TABLE IF NOT EXISTS `sales_analytics`.`date` (
    `date` TIMESTAMP,
    `year` LONG,
    `month_number` LONG,
    `month` STRING,
    `month_start` TIMESTAMP,
    `weekday_number` LONG,
    `weekday` STRING
) USING DELTA
TBLPROPERTIES ('delta.stats.extended.collect'='true', 'delta.stats.extended.inject'='true', 'delta.minReaderVersion'='1', 'delta.minWriterVersion'='2');

CREATE TABLE IF NOT EXISTS `sales_analytics`.`flavor` (
    `flavor_key` STRING,
    `flavor` STRING
) USING DELTA
TBLPROPERTIES ('delta.stats.extended.collect'='true', 'delta.stats.extended.inject'='true', 'delta.minReaderVersion'='1', 'delta.minWriterVersion'='2');

CREATE TABLE IF NOT EXISTS `sales_analytics`.`local_hour` (
    `hour` LONG
) USING DELTA
TBLPROPERTIES ('delta.stats.extended.collect'='true', 'delta.stats.extended.inject'='true', 'delta.minReaderVersion'='1', 'delta.minWriterVersion'='2');

CREATE TABLE IF NOT EXISTS `sales_analytics`.`payment` (
    `payment` STRING
) USING DELTA
TBLPROPERTIES ('delta.stats.extended.collect'='true', 'delta.stats.extended.inject'='true', 'delta.minReaderVersion'='1', 'delta.minWriterVersion'='2');

CREATE TABLE IF NOT EXISTS `sales_analytics`.`refresh` (
    `refreshed_utc` TIMESTAMP
) USING DELTA
TBLPROPERTIES ('delta.stats.extended.collect'='true', 'delta.stats.extended.inject'='true', 'delta.minReaderVersion'='1', 'delta.minWriterVersion'='2');

CREATE TABLE IF NOT EXISTS `sales_analytics`.`sales` (
    `receipt_key` LONG,
    `shop_key` LONG,
    `flavor_key` STRING,
    `date` TIMESTAMP,
    `currency` STRING,
    `weather` STRING,
    `payment` STRING,
    `channel` STRING,
    `serving` STRING,
    `hour` LONG,
    `temperature` DECIMAL(19,4),
    `temperature_band_start` LONG,
    `temperature_band` STRING,
    `city` STRING,
    `country` STRING,
    `receipt_utc` TIMESTAMP,
    `scoop_quantity` LONG,
    `subtotal_amount` DECIMAL(19,4),
    `discount_amount` DECIMAL(19,4),
    `net_amount` DECIMAL(19,4),
    `tax_amount` DECIMAL(19,4),
    `paid_amount` DECIMAL(19,4)
) USING DELTA
TBLPROPERTIES ('delta.stats.extended.collect'='true', 'delta.stats.extended.inject'='true', 'delta.minReaderVersion'='1', 'delta.minWriterVersion'='2');

CREATE TABLE IF NOT EXISTS `sales_analytics`.`serving` (
    `serving` STRING
) USING DELTA
TBLPROPERTIES ('delta.stats.extended.collect'='true', 'delta.stats.extended.inject'='true', 'delta.minReaderVersion'='1', 'delta.minWriterVersion'='2');

CREATE TABLE IF NOT EXISTS `sales_analytics`.`shop` (
    `shop_key` LONG,
    `shop_name` STRING,
    `city` STRING,
    `country` STRING,
    `time_zone` STRING
) USING DELTA
TBLPROPERTIES ('delta.stats.extended.collect'='true', 'delta.stats.extended.inject'='true', 'delta.minReaderVersion'='1', 'delta.minWriterVersion'='2');

CREATE TABLE IF NOT EXISTS `sales_analytics`.`weather` (
    `weather` STRING
) USING DELTA
TBLPROPERTIES ('delta.stats.extended.collect'='true', 'delta.stats.extended.inject'='true', 'delta.minReaderVersion'='1', 'delta.minWriterVersion'='2');
