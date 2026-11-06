-- CELL: Capture a stable source snapshot from the attached GelatAI_lakehouse.
SET spark.sql.session.timeZone=UTC;
CREATE SCHEMA IF NOT EXISTS sales_analytics;
CACHE TABLE _sales_headers AS SELECT * FROM delta.`{{LAKEHOUSE_TABLES}}/sc_shopdb/Sale`;
CACHE TABLE _sales_lines AS
SELECT i.* FROM delta.`{{LAKEHOUSE_TABLES}}/sc_shopdb/SaleItem` i INNER JOIN _sales_headers s ON s.SaleId=i.SaleId;
CACHE TABLE _sales_shops AS
SELECT ShopId, ShopName, City, CountryCode, TimeZoneId FROM delta.`{{LAKEHOUSE_TABLES}}/sc_shopdb/Shop`;

-- CELL: Stop before publishing if asynchronous mirroring has incomplete receipts.
SELECT assert_true(COUNT(*)=0, 'Mirrored receipts are incomplete or do not reconcile; no analytical tables were updated. Retry after mirroring catches up.')
FROM (
  SELECT s.SaleId
  FROM _sales_headers s LEFT JOIN _sales_lines i ON i.SaleId=s.SaleId
  GROUP BY s.SaleId, s.FlavorCount, s.TotalScoops, s.SubtotalAmount,
    s.DiscountAmount, s.NetSalesAmount, s.TaxAmount, s.TotalAmount
  HAVING COUNT(i.LineNumber)<>s.FlavorCount
    OR COUNT(DISTINCT i.LineNumber)<>s.FlavorCount
    OR COUNT(DISTINCT i.ProductId)<>s.FlavorCount
    OR SUM(i.Scoops)<>s.TotalScoops OR SUM(i.SubtotalAmount)<>s.SubtotalAmount
    OR SUM(i.DiscountAmount)<>s.DiscountAmount OR SUM(i.NetSalesAmount)<>s.NetSalesAmount
    OR SUM(i.TaxAmount)<>s.TaxAmount OR SUM(i.TotalAmount)<>s.TotalAmount
) invalid;
SELECT assert_true(COUNT(*)=0, 'A shop registry key is missing or duplicated; no analytical tables were updated.')
FROM (
  SELECT s.SaleId FROM _sales_headers s LEFT JOIN _sales_shops sh ON sh.ShopId=s.ShopId
  GROUP BY s.SaleId HAVING COUNT(sh.ShopId)<>1
) invalid;

-- CELL: Prepare the line-grain fact; use only allocated line amounts.
CACHE TABLE _sales_fact AS
SELECT CAST(s.SaleId AS BIGINT) AS receipt_key,
  CAST(s.ShopId AS BIGINT) AS shop_key,
  CONCAT(CAST(i.ProductId AS STRING),'|',i.Flavor) AS flavor_key,
  CAST(s.SaleDateLocal AS TIMESTAMP) AS date,
  s.CurrencyCode AS currency, REPLACE(s.Weather,'_',' ') AS weather,
  REPLACE(s.PaymentMethod,'_',' ') AS payment, REPLACE(s.SalesChannel,'_',' ') AS channel,
  REPLACE(s.ServingType,'_',' ') AS serving, CAST(HOUR(s.TimestampLocal) AS BIGINT) AS hour,
  CAST(s.TemperatureC AS DECIMAL(19,4)) AS temperature,
  CAST(FLOOR(s.TemperatureC/5.0)*5 AS BIGINT) AS temperature_band_start,
  CONCAT(CAST(CAST(FLOOR(s.TemperatureC/5.0)*5 AS BIGINT) AS STRING),' to <',
    CAST(CAST(FLOOR(s.TemperatureC/5.0)*5+5 AS BIGINT) AS STRING),' C') AS temperature_band,
  s.City AS city, s.CountryCode AS country, s.TimestampUtc AS receipt_utc,
  CAST(i.Scoops AS BIGINT) AS scoop_quantity,
  CAST(i.SubtotalAmount AS DECIMAL(19,4)) AS subtotal_amount,
  CAST(i.DiscountAmount AS DECIMAL(19,4)) AS discount_amount,
  CAST(i.NetSalesAmount AS DECIMAL(19,4)) AS net_amount,
  CAST(i.TaxAmount AS DECIMAL(19,4)) AS tax_amount,
  CAST(i.TotalAmount AS DECIMAL(19,4)) AS paid_amount
FROM _sales_headers s INNER JOIN _sales_lines i ON i.SaleId=s.SaleId;

-- CELL: Prepare dimensions and a continuous full-year local-date calendar.
CREATE OR REPLACE TEMP VIEW _sales_shop AS
SELECT CAST(sh.ShopId AS BIGINT) AS shop_key,
  sh.ShopName AS shop_name, sh.City AS city, sh.CountryCode AS country, sh.TimeZoneId AS time_zone
FROM _sales_shops sh WHERE EXISTS (SELECT 1 FROM _sales_headers s WHERE s.ShopId=sh.ShopId);
CREATE OR REPLACE TEMP VIEW _sales_flavor AS
SELECT DISTINCT CONCAT(CAST(ProductId AS STRING),'|',Flavor) AS flavor_key, Flavor AS flavor
FROM _sales_lines;
CREATE OR REPLACE TEMP VIEW _sales_date AS
SELECT CAST(d AS TIMESTAMP) AS date, CAST(YEAR(d) AS BIGINT) AS year,
  CAST(MONTH(d) AS BIGINT) AS month_number, DATE_FORMAT(d,'MMMM') AS month,
  CAST(TRUNC(d,'MONTH') AS TIMESTAMP) AS month_start,
  CAST(PMOD(DAYOFWEEK(d)+5,7) AS BIGINT) AS weekday_number, DATE_FORMAT(d,'EEEE') AS weekday
FROM (
  SELECT EXPLODE(SEQUENCE(
    MAKE_DATE(YEAR(COALESCE(MIN(SaleDateLocal),CURRENT_DATE())),1,1),
    MAKE_DATE(YEAR(COALESCE(MAX(SaleDateLocal),CURRENT_DATE())),12,31),
    INTERVAL 1 DAY)) AS d FROM _sales_headers
);
CREATE OR REPLACE TEMP VIEW _sales_currency AS SELECT * FROM VALUES ('EUR'),('USD'),('JPY') AS t(currency);
CREATE OR REPLACE TEMP VIEW _sales_weather AS SELECT * FROM VALUES ('sunny'),('partly cloudy'),('cloudy'),('rain') AS t(weather);
CREATE OR REPLACE TEMP VIEW _sales_payment AS SELECT * FROM VALUES ('card'),('cash'),('mobile wallet') AS t(payment);
CREATE OR REPLACE TEMP VIEW _sales_channel AS SELECT * FROM VALUES ('counter'),('delivery'),('click and collect') AS t(channel);
CREATE OR REPLACE TEMP VIEW _sales_serving AS SELECT * FROM VALUES ('cup'),('cone'),('takeaway tub') AS t(serving);

-- CELL: Validate every relationship key before any Delta data is replaced.
SELECT assert_true(COUNT(*)=0, 'An analytical shop key is null or duplicated; no analytical tables were updated.')
FROM (
  SELECT shop_key FROM _sales_shop GROUP BY shop_key
  HAVING shop_key IS NULL OR COUNT(*)<>1
) invalid;
SELECT assert_true(COUNT(*)=0, 'An analytical relationship key has no dimension member; no analytical tables were updated.')
FROM _sales_fact s
LEFT JOIN _sales_shop sh ON sh.shop_key=s.shop_key
LEFT JOIN _sales_flavor f ON f.flavor_key=s.flavor_key
LEFT JOIN _sales_date d ON d.date=s.date
LEFT JOIN _sales_currency c ON c.currency=s.currency
LEFT JOIN _sales_weather w ON w.weather=s.weather
LEFT JOIN _sales_payment p ON p.payment=s.payment
LEFT JOIN _sales_channel ch ON ch.channel=s.channel
LEFT JOIN _sales_serving sv ON sv.serving=s.serving
WHERE sh.shop_key IS NULL OR f.flavor_key IS NULL OR d.date IS NULL
  OR c.currency IS NULL OR w.weather IS NULL OR p.payment IS NULL
  OR ch.channel IS NULL OR sv.serving IS NULL OR s.hour NOT BETWEEN 0 AND 23;

-- CELL: Publish dimensions before the append-only sales snapshot introduces new keys.
CREATE OR REPLACE TABLE sales_analytics.shop USING DELTA AS SELECT * FROM _sales_shop;
CREATE OR REPLACE TABLE sales_analytics.flavor USING DELTA AS SELECT * FROM _sales_flavor;
CREATE OR REPLACE TABLE sales_analytics.date USING DELTA AS SELECT * FROM _sales_date;
CREATE OR REPLACE TABLE sales_analytics.currency USING DELTA AS SELECT * FROM _sales_currency;
CREATE OR REPLACE TABLE sales_analytics.weather USING DELTA AS SELECT * FROM _sales_weather;
CREATE OR REPLACE TABLE sales_analytics.payment USING DELTA AS SELECT * FROM _sales_payment;
CREATE OR REPLACE TABLE sales_analytics.channel USING DELTA AS SELECT * FROM _sales_channel;
CREATE OR REPLACE TABLE sales_analytics.serving USING DELTA AS SELECT * FROM _sales_serving;
CREATE OR REPLACE TABLE sales_analytics.local_hour USING DELTA AS SELECT CAST(id AS BIGINT) AS hour FROM RANGE(24);

-- CELL: Replace the fact in one Delta commit, then record successful publication time.
CREATE OR REPLACE TABLE sales_analytics.sales USING DELTA AS SELECT * FROM _sales_fact;
CREATE OR REPLACE TABLE sales_analytics.refresh USING DELTA AS SELECT CURRENT_TIMESTAMP() AS refreshed_utc;
SELECT currency, COUNT(*) AS lines, COUNT(DISTINCT receipt_key) AS receipts,
  SUM(net_amount) AS net_sales, SUM(paid_amount) AS paid FROM sales_analytics.sales GROUP BY currency;
UNCACHE TABLE _sales_headers;
UNCACHE TABLE _sales_lines;
UNCACHE TABLE _sales_shops;
UNCACHE TABLE _sales_fact;
