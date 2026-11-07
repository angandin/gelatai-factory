# Fabric notebook source

# METADATA ********************

# META {
# META   "kernel_info": {
# META     "name": "synapse_pyspark"
# META   },
# META   "dependencies": {
# META     "lakehouse": {
# META       "default_lakehouse": "92e59539-b5cf-4ae0-babe-fa481abc416d",
# META       "default_lakehouse_name": "GelatAI_lakehouse",
# META       "default_lakehouse_workspace_id": "97d5eec3-d6d9-44bb-80aa-279e286309b3",
# META       "known_lakehouses": [
# META         {
# META           "id": "92e59539-b5cf-4ae0-babe-fa481abc416d"
# META         }
# META       ]
# META     }
# META   }
# META }

# CELL ********************

# MAGIC %%sql
# MAGIC -- CELL: Capture a stable source snapshot from the attached GelatAI_lakehouse.
# MAGIC SET spark.sql.session.timeZone=UTC;
# MAGIC CREATE SCHEMA IF NOT EXISTS sales_analytics;
# MAGIC CACHE TABLE _sales_headers AS SELECT * FROM delta.`abfss://97d5eec3-d6d9-44bb-80aa-279e286309b3@onelake.dfs.fabric.microsoft.com/92e59539-b5cf-4ae0-babe-fa481abc416d/Tables/sc_shopdb/Sale`;
# MAGIC CACHE TABLE _sales_lines AS
# MAGIC SELECT i.* FROM delta.`abfss://97d5eec3-d6d9-44bb-80aa-279e286309b3@onelake.dfs.fabric.microsoft.com/92e59539-b5cf-4ae0-babe-fa481abc416d/Tables/sc_shopdb/SaleItem` i INNER JOIN _sales_headers s ON s.SaleId=i.SaleId;
# MAGIC CACHE TABLE _sales_shops AS
# MAGIC SELECT ShopId, ShopName, City, CountryCode, TimeZoneId FROM delta.`abfss://97d5eec3-d6d9-44bb-80aa-279e286309b3@onelake.dfs.fabric.microsoft.com/92e59539-b5cf-4ae0-babe-fa481abc416d/Tables/sc_shopdb/Shop`;


# METADATA ********************

# META {
# META   "language": "sparksql",
# META   "language_group": "synapse_pyspark"
# META }

# CELL ********************

# MAGIC %%sql
# MAGIC -- CELL: Stop before publishing if asynchronous mirroring has incomplete receipts.
# MAGIC SELECT assert_true(COUNT(*)=0, 'Mirrored receipts are incomplete or do not reconcile; no analytical tables were updated. Retry after mirroring catches up.')
# MAGIC FROM (
# MAGIC   SELECT s.SaleId
# MAGIC   FROM _sales_headers s LEFT JOIN _sales_lines i ON i.SaleId=s.SaleId
# MAGIC   GROUP BY s.SaleId, s.FlavorCount, s.TotalScoops, s.SubtotalAmount,
# MAGIC     s.DiscountAmount, s.NetSalesAmount, s.TaxAmount, s.TotalAmount
# MAGIC   HAVING COUNT(i.LineNumber)<>s.FlavorCount
# MAGIC     OR COUNT(DISTINCT i.LineNumber)<>s.FlavorCount
# MAGIC     OR COUNT(DISTINCT i.ProductId)<>s.FlavorCount
# MAGIC     OR SUM(i.Scoops)<>s.TotalScoops OR SUM(i.SubtotalAmount)<>s.SubtotalAmount
# MAGIC     OR SUM(i.DiscountAmount)<>s.DiscountAmount OR SUM(i.NetSalesAmount)<>s.NetSalesAmount
# MAGIC     OR SUM(i.TaxAmount)<>s.TaxAmount OR SUM(i.TotalAmount)<>s.TotalAmount
# MAGIC ) invalid;
# MAGIC SELECT assert_true(COUNT(*)=0, 'A shop registry key is missing or duplicated; no analytical tables were updated.')
# MAGIC FROM (
# MAGIC   SELECT s.SaleId FROM _sales_headers s LEFT JOIN _sales_shops sh ON sh.ShopId=s.ShopId
# MAGIC   GROUP BY s.SaleId HAVING COUNT(sh.ShopId)<>1
# MAGIC ) invalid;


# METADATA ********************

# META {
# META   "language": "sparksql",
# META   "language_group": "synapse_pyspark"
# META }

# CELL ********************

# MAGIC %%sql
# MAGIC -- CELL: Prepare the line-grain fact; use only allocated line amounts.
# MAGIC CACHE TABLE _sales_fact AS
# MAGIC SELECT CAST(s.SaleId AS BIGINT) AS receipt_key,
# MAGIC   CAST(s.ShopId AS BIGINT) AS shop_key,
# MAGIC   CONCAT(CAST(i.ProductId AS STRING),'|',i.Flavor) AS flavor_key,
# MAGIC   CAST(s.SaleDateLocal AS TIMESTAMP) AS date,
# MAGIC   s.CurrencyCode AS currency, REPLACE(s.Weather,'_',' ') AS weather,
# MAGIC   REPLACE(s.PaymentMethod,'_',' ') AS payment, REPLACE(s.SalesChannel,'_',' ') AS channel,
# MAGIC   REPLACE(s.ServingType,'_',' ') AS serving, CAST(HOUR(s.TimestampLocal) AS BIGINT) AS hour,
# MAGIC   CAST(s.TemperatureC AS DECIMAL(19,4)) AS temperature,
# MAGIC   CAST(FLOOR(s.TemperatureC/5.0)*5 AS BIGINT) AS temperature_band_start,
# MAGIC   CONCAT(CAST(CAST(FLOOR(s.TemperatureC/5.0)*5 AS BIGINT) AS STRING),' to <',
# MAGIC     CAST(CAST(FLOOR(s.TemperatureC/5.0)*5+5 AS BIGINT) AS STRING),' C') AS temperature_band,
# MAGIC   s.City AS city, s.CountryCode AS country, s.TimestampUtc AS receipt_utc,
# MAGIC   CAST(i.Scoops AS BIGINT) AS scoop_quantity,
# MAGIC   CAST(i.SubtotalAmount AS DECIMAL(19,4)) AS subtotal_amount,
# MAGIC   CAST(i.DiscountAmount AS DECIMAL(19,4)) AS discount_amount,
# MAGIC   CAST(i.NetSalesAmount AS DECIMAL(19,4)) AS net_amount,
# MAGIC   CAST(i.TaxAmount AS DECIMAL(19,4)) AS tax_amount,
# MAGIC   CAST(i.TotalAmount AS DECIMAL(19,4)) AS paid_amount
# MAGIC FROM _sales_headers s INNER JOIN _sales_lines i ON i.SaleId=s.SaleId;


# METADATA ********************

# META {
# META   "language": "sparksql",
# META   "language_group": "synapse_pyspark"
# META }

# CELL ********************

# MAGIC %%sql
# MAGIC -- CELL: Prepare dimensions and a continuous full-year local-date calendar.
# MAGIC CREATE OR REPLACE TEMP VIEW _sales_shop AS
# MAGIC SELECT CAST(sh.ShopId AS BIGINT) AS shop_key,
# MAGIC   sh.ShopName AS shop_name, sh.City AS city, sh.CountryCode AS country, sh.TimeZoneId AS time_zone
# MAGIC FROM _sales_shops sh WHERE EXISTS (SELECT 1 FROM _sales_headers s WHERE s.ShopId=sh.ShopId);
# MAGIC CREATE OR REPLACE TEMP VIEW _sales_flavor AS
# MAGIC SELECT DISTINCT CONCAT(CAST(ProductId AS STRING),'|',Flavor) AS flavor_key, Flavor AS flavor
# MAGIC FROM _sales_lines;
# MAGIC CREATE OR REPLACE TEMP VIEW _sales_date AS
# MAGIC SELECT CAST(d AS TIMESTAMP) AS date, CAST(YEAR(d) AS BIGINT) AS year,
# MAGIC   CAST(MONTH(d) AS BIGINT) AS month_number, DATE_FORMAT(d,'MMMM') AS month,
# MAGIC   CAST(TRUNC(d,'MONTH') AS TIMESTAMP) AS month_start,
# MAGIC   CAST(PMOD(DAYOFWEEK(d)+5,7) AS BIGINT) AS weekday_number, DATE_FORMAT(d,'EEEE') AS weekday
# MAGIC FROM (
# MAGIC   SELECT EXPLODE(SEQUENCE(
# MAGIC     MAKE_DATE(YEAR(COALESCE(MIN(SaleDateLocal),CURRENT_DATE())),1,1),
# MAGIC     MAKE_DATE(YEAR(COALESCE(MAX(SaleDateLocal),CURRENT_DATE())),12,31),
# MAGIC     INTERVAL 1 DAY)) AS d FROM _sales_headers
# MAGIC );
# MAGIC CREATE OR REPLACE TEMP VIEW _sales_currency AS SELECT * FROM VALUES ('EUR'),('USD'),('JPY') AS t(currency);
# MAGIC CREATE OR REPLACE TEMP VIEW _sales_weather AS SELECT * FROM VALUES ('sunny'),('partly cloudy'),('cloudy'),('rain') AS t(weather);
# MAGIC CREATE OR REPLACE TEMP VIEW _sales_payment AS SELECT * FROM VALUES ('card'),('cash'),('mobile wallet') AS t(payment);
# MAGIC CREATE OR REPLACE TEMP VIEW _sales_channel AS SELECT * FROM VALUES ('counter'),('delivery'),('click and collect') AS t(channel);
# MAGIC CREATE OR REPLACE TEMP VIEW _sales_serving AS SELECT * FROM VALUES ('cup'),('cone'),('takeaway tub') AS t(serving);


# METADATA ********************

# META {
# META   "language": "sparksql",
# META   "language_group": "synapse_pyspark"
# META }

# CELL ********************

# MAGIC %%sql
# MAGIC -- CELL: Validate every relationship key before any Delta data is replaced.
# MAGIC SELECT assert_true(COUNT(*)=0, 'An analytical shop key is null or duplicated; no analytical tables were updated.')
# MAGIC FROM (
# MAGIC   SELECT shop_key FROM _sales_shop GROUP BY shop_key
# MAGIC   HAVING shop_key IS NULL OR COUNT(*)<>1
# MAGIC ) invalid;
# MAGIC SELECT assert_true(COUNT(*)=0, 'An analytical relationship key has no dimension member; no analytical tables were updated.')
# MAGIC FROM _sales_fact s
# MAGIC LEFT JOIN _sales_shop sh ON sh.shop_key=s.shop_key
# MAGIC LEFT JOIN _sales_flavor f ON f.flavor_key=s.flavor_key
# MAGIC LEFT JOIN _sales_date d ON d.date=s.date
# MAGIC LEFT JOIN _sales_currency c ON c.currency=s.currency
# MAGIC LEFT JOIN _sales_weather w ON w.weather=s.weather
# MAGIC LEFT JOIN _sales_payment p ON p.payment=s.payment
# MAGIC LEFT JOIN _sales_channel ch ON ch.channel=s.channel
# MAGIC LEFT JOIN _sales_serving sv ON sv.serving=s.serving
# MAGIC WHERE sh.shop_key IS NULL OR f.flavor_key IS NULL OR d.date IS NULL
# MAGIC   OR c.currency IS NULL OR w.weather IS NULL OR p.payment IS NULL
# MAGIC   OR ch.channel IS NULL OR sv.serving IS NULL OR s.hour NOT BETWEEN 0 AND 23;


# METADATA ********************

# META {
# META   "language": "sparksql",
# META   "language_group": "synapse_pyspark"
# META }

# CELL ********************

# MAGIC %%sql
# MAGIC -- CELL: Publish dimensions before the append-only sales snapshot introduces new keys.
# MAGIC CREATE OR REPLACE TABLE sales_analytics.shop USING DELTA AS SELECT * FROM _sales_shop;
# MAGIC CREATE OR REPLACE TABLE sales_analytics.flavor USING DELTA AS SELECT * FROM _sales_flavor;
# MAGIC CREATE OR REPLACE TABLE sales_analytics.date USING DELTA AS SELECT * FROM _sales_date;
# MAGIC CREATE OR REPLACE TABLE sales_analytics.currency USING DELTA AS SELECT * FROM _sales_currency;
# MAGIC CREATE OR REPLACE TABLE sales_analytics.weather USING DELTA AS SELECT * FROM _sales_weather;
# MAGIC CREATE OR REPLACE TABLE sales_analytics.payment USING DELTA AS SELECT * FROM _sales_payment;
# MAGIC CREATE OR REPLACE TABLE sales_analytics.channel USING DELTA AS SELECT * FROM _sales_channel;
# MAGIC CREATE OR REPLACE TABLE sales_analytics.serving USING DELTA AS SELECT * FROM _sales_serving;
# MAGIC CREATE OR REPLACE TABLE sales_analytics.local_hour USING DELTA AS SELECT CAST(id AS BIGINT) AS hour FROM RANGE(24);


# METADATA ********************

# META {
# META   "language": "sparksql",
# META   "language_group": "synapse_pyspark"
# META }

# CELL ********************

# MAGIC %%sql
# MAGIC -- CELL: Replace the fact in one Delta commit, then record successful publication time.
# MAGIC CREATE OR REPLACE TABLE sales_analytics.sales USING DELTA AS SELECT * FROM _sales_fact;
# MAGIC CREATE OR REPLACE TABLE sales_analytics.refresh USING DELTA AS SELECT CURRENT_TIMESTAMP() AS refreshed_utc;
# MAGIC SELECT currency, COUNT(*) AS lines, COUNT(DISTINCT receipt_key) AS receipts,
# MAGIC   SUM(net_amount) AS net_sales, SUM(paid_amount) AS paid FROM sales_analytics.sales GROUP BY currency;
# MAGIC UNCACHE TABLE _sales_headers;
# MAGIC UNCACHE TABLE _sales_lines;
# MAGIC UNCACHE TABLE _sales_shops;
# MAGIC UNCACHE TABLE _sales_fact;


# METADATA ********************

# META {
# META   "language": "sparksql",
# META   "language_group": "synapse_pyspark"
# META }
