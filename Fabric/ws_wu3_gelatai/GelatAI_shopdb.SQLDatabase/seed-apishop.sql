-- Created for the GelatAI shop operations database.
/*
  Synchronizes static shop, flavor, assortment, and external-key registry data
  with the apishop configuration. Sales facts are written separately by apishop.
*/

SET NOCOUNT ON;
SET XACT_ABORT ON;

BEGIN TRANSACTION;

MERGE dbo.Factory AS target
USING (
    VALUES (
        'gelatai-factory-001',
        N'GelatAI Central Factory',
        N'Bologna',
        'IT',
        N'Europe/Rome',
        N'GelatAI-rtdata',
        N'machinesraw'
    )
) AS source (
    FactoryCode,
    FactoryName,
    City,
    CountryCode,
    TimeZoneId,
    EventhouseDatabaseName,
    TelemetryTableName
)
ON target.FactoryCode = source.FactoryCode
WHEN MATCHED THEN
    UPDATE SET
        FactoryName = source.FactoryName,
        City = source.City,
        CountryCode = source.CountryCode,
        TimeZoneId = source.TimeZoneId,
        EventhouseDatabaseName = source.EventhouseDatabaseName,
        TelemetryTableName = source.TelemetryTableName,
        IsActive = 1,
        UpdatedAtUtc = SYSUTCDATETIME()
WHEN NOT MATCHED THEN
    INSERT (
        FactoryCode,
        FactoryName,
        City,
        CountryCode,
        TimeZoneId,
        EventhouseDatabaseName,
        TelemetryTableName
    )
    VALUES (
        source.FactoryCode,
        source.FactoryName,
        source.City,
        source.CountryCode,
        source.TimeZoneId,
        source.EventhouseDatabaseName,
        source.TelemetryTableName
    );

MERGE dbo.SourceSystem AS target
USING (
    VALUES ('apishop', N'GelatAI Shop Sales Simulator')
) AS source (SourceSystemCode, SourceSystemName)
ON target.SourceSystemCode = source.SourceSystemCode
WHEN MATCHED THEN
    UPDATE SET
        SourceSystemName = source.SourceSystemName,
        IsActive = 1
WHEN NOT MATCHED THEN
    INSERT (SourceSystemCode, SourceSystemName)
    VALUES (source.SourceSystemCode, source.SourceSystemName);

DECLARE @Shops TABLE (
    ShopCode varchar(30) NOT NULL,
    ShopName nvarchar(200) NOT NULL,
    City nvarchar(100) NOT NULL,
    CountryCode char(2) NOT NULL,
    CurrencyCode char(3) NOT NULL,
    TimeZoneId nvarchar(100) NOT NULL,
    Latitude decimal(9,6) NOT NULL,
    Longitude decimal(9,6) NOT NULL
);

INSERT INTO @Shops (
    ShopCode,
    ShopName,
    City,
    CountryCode,
    CurrencyCode,
    TimeZoneId,
    Latitude,
    Longitude
)
VALUES
    ('it-roma-001', N'Gelateria Trastevere', N'Rome', 'IT', 'EUR', N'Europe/Rome', 41.889700, 12.469500),
    ('it-firenze-001', N'Arno Gelato', N'Florence', 'IT', 'EUR', N'Europe/Rome', 43.769600, 11.255800),
    ('it-milano-001', N'Navigli Cream', N'Milan', 'IT', 'EUR', N'Europe/Rome', 45.464200, 9.190000),
    ('fr-paris-001', N'Glace du Marais', N'Paris', 'FR', 'EUR', N'Europe/Paris', 48.856600, 2.352200),
    ('us-nyc-001', N'Brooklyn Scoops', N'New York', 'US', 'USD', N'America/New_York', 40.712800, -74.006000),
    ('jp-tokyo-001', N'Sakura Ice', N'Tokyo', 'JP', 'JPY', N'Asia/Tokyo', 35.676200, 139.650300);

MERGE dbo.Shop AS target
USING @Shops AS source
ON target.ShopCode = source.ShopCode
WHEN MATCHED THEN
    UPDATE SET
        ShopName = source.ShopName,
        City = source.City,
        CountryCode = source.CountryCode,
        CurrencyCode = source.CurrencyCode,
        TimeZoneId = source.TimeZoneId,
        Latitude = source.Latitude,
        Longitude = source.Longitude,
        IsActive = 1,
        UpdatedAtUtc = SYSUTCDATETIME()
WHEN NOT MATCHED THEN
    INSERT (
        ShopCode,
        ShopName,
        City,
        CountryCode,
        CurrencyCode,
        TimeZoneId,
        Latitude,
        Longitude
    )
    VALUES (
        source.ShopCode,
        source.ShopName,
        source.City,
        source.CountryCode,
        source.CurrencyCode,
        source.TimeZoneId,
        source.Latitude,
        source.Longitude
    );

DECLARE @Products TABLE (
    Sku varchar(50) NOT NULL,
    ProductName nvarchar(200) NOT NULL
);

INSERT INTO @Products (Sku, ProductName)
VALUES
    ('FLAVOR-AMARENA', N'Amarena'),
    ('FLAVOR-BLACK-SESAME', N'Black Sesame'),
    ('FLAVOR-CHOCOLATE', N'Chocolate'),
    ('FLAVOR-COFFEE', N'Coffee'),
    ('FLAVOR-COOKIE-DOUGH', N'Cookie Dough'),
    ('FLAVOR-CREMA', N'Crema'),
    ('FLAVOR-DARK-CHOCOLATE', N'Dark Chocolate'),
    ('FLAVOR-FIORDILATTE', N'Fiordilatte'),
    ('FLAVOR-HAZELNUT', N'Hazelnut'),
    ('FLAVOR-HOJICHA', N'Hojicha'),
    ('FLAVOR-LEMON', N'Lemon'),
    ('FLAVOR-MANGO', N'Mango'),
    ('FLAVOR-MATCHA', N'Matcha'),
    ('FLAVOR-MINT-CHIP', N'Mint Chip'),
    ('FLAVOR-PISTACHIO', N'Pistachio'),
    ('FLAVOR-PRALINE', N'Praline'),
    ('FLAVOR-RASPBERRY', N'Raspberry'),
    ('FLAVOR-RICOTTA-FIG', N'Ricotta and Fig'),
    ('FLAVOR-SAKURA', N'Sakura'),
    ('FLAVOR-SALTED-CARAMEL', N'Salted Caramel'),
    ('FLAVOR-STRAWBERRY', N'Strawberry'),
    ('FLAVOR-STRACCIATELLA', N'Stracciatella'),
    ('FLAVOR-TIRAMISU', N'Tiramisu'),
    ('FLAVOR-VANILLA', N'Vanilla'),
    ('FLAVOR-YUZU', N'Yuzu');

MERGE dbo.Product AS target
USING @Products AS source
ON target.Sku = source.Sku
WHEN MATCHED THEN
    UPDATE SET
        ProductName = source.ProductName,
        Category = N'Ice Cream Flavor',
        UnitOfMeasure = 'scoop',
        IsActive = 1,
        UpdatedAtUtc = SYSUTCDATETIME()
WHEN NOT MATCHED THEN
    INSERT (Sku, ProductName, Category, UnitOfMeasure, StandardPrice)
    VALUES (source.Sku, source.ProductName, N'Ice Cream Flavor', 'scoop', 0);

DECLARE @Assortments TABLE (
    ShopCode varchar(30) NOT NULL,
    ProductName nvarchar(200) NOT NULL,
    PRIMARY KEY (ShopCode, ProductName)
);

INSERT INTO @Assortments (ShopCode, ProductName)
VALUES
    ('it-roma-001', N'Pistachio'), ('it-roma-001', N'Stracciatella'),
    ('it-roma-001', N'Hazelnut'), ('it-roma-001', N'Dark Chocolate'),
    ('it-roma-001', N'Lemon'), ('it-roma-001', N'Fiordilatte'),
    ('it-roma-001', N'Tiramisu'), ('it-roma-001', N'Amarena'),
    ('it-firenze-001', N'Pistachio'), ('it-firenze-001', N'Stracciatella'),
    ('it-firenze-001', N'Crema'), ('it-firenze-001', N'Chocolate'),
    ('it-firenze-001', N'Mango'), ('it-firenze-001', N'Coffee'),
    ('it-firenze-001', N'Ricotta and Fig'), ('it-firenze-001', N'Lemon'),
    ('it-milano-001', N'Pistachio'), ('it-milano-001', N'Salted Caramel'),
    ('it-milano-001', N'Stracciatella'), ('it-milano-001', N'Hazelnut'),
    ('it-milano-001', N'Chocolate'), ('it-milano-001', N'Vanilla'),
    ('it-milano-001', N'Raspberry'), ('it-milano-001', N'Coffee'),
    ('fr-paris-001', N'Vanilla'), ('fr-paris-001', N'Chocolate'),
    ('fr-paris-001', N'Salted Caramel'), ('fr-paris-001', N'Pistachio'),
    ('fr-paris-001', N'Strawberry'), ('fr-paris-001', N'Lemon'),
    ('fr-paris-001', N'Praline'), ('fr-paris-001', N'Coffee'),
    ('us-nyc-001', N'Vanilla'), ('us-nyc-001', N'Chocolate'),
    ('us-nyc-001', N'Cookie Dough'), ('us-nyc-001', N'Strawberry'),
    ('us-nyc-001', N'Mint Chip'), ('us-nyc-001', N'Salted Caramel'),
    ('us-nyc-001', N'Pistachio'), ('us-nyc-001', N'Coffee'),
    ('jp-tokyo-001', N'Matcha'), ('jp-tokyo-001', N'Black Sesame'),
    ('jp-tokyo-001', N'Vanilla'), ('jp-tokyo-001', N'Yuzu'),
    ('jp-tokyo-001', N'Strawberry'), ('jp-tokyo-001', N'Chocolate'),
    ('jp-tokyo-001', N'Sakura'), ('jp-tokyo-001', N'Hojicha');

MERGE dbo.ShopProduct AS target
USING (
    SELECT s.ShopId, p.ProductId
    FROM @Assortments AS a
    INNER JOIN dbo.Shop AS s ON s.ShopCode = a.ShopCode
    INNER JOIN dbo.Product AS p ON p.ProductName = a.ProductName
) AS source
ON target.ShopId = source.ShopId
AND target.ProductId = source.ProductId
WHEN MATCHED THEN
    UPDATE SET
        IsActive = 1,
        UpdatedAtUtc = SYSUTCDATETIME()
WHEN NOT MATCHED THEN
    INSERT (ShopId, ProductId)
    VALUES (source.ShopId, source.ProductId);

DECLARE @SourceSystemId smallint = (
    SELECT SourceSystemId
    FROM dbo.SourceSystem
    WHERE SourceSystemCode = 'apishop'
);

MERGE dbo.ShopExternalReference AS target
USING (
    SELECT @SourceSystemId AS SourceSystemId, s.ShopCode AS ExternalShopKey, s.ShopId
    FROM dbo.Shop AS s
    INNER JOIN @Shops AS configured ON configured.ShopCode = s.ShopCode
) AS source
ON target.SourceSystemId = source.SourceSystemId
AND target.ExternalShopKey = source.ExternalShopKey
WHEN MATCHED THEN
    UPDATE SET ShopId = source.ShopId
WHEN NOT MATCHED THEN
    INSERT (SourceSystemId, ExternalShopKey, ShopId)
    VALUES (source.SourceSystemId, source.ExternalShopKey, source.ShopId);

MERGE dbo.ProductExternalReference AS target
USING (
    SELECT @SourceSystemId AS SourceSystemId, p.ProductName AS ExternalProductKey, p.ProductId
    FROM dbo.Product AS p
    INNER JOIN @Products AS configured ON configured.Sku = p.Sku
) AS source
ON target.SourceSystemId = source.SourceSystemId
AND target.ExternalProductKey = source.ExternalProductKey
WHEN MATCHED THEN
    UPDATE SET ProductId = source.ProductId
WHEN NOT MATCHED THEN
    INSERT (SourceSystemId, ExternalProductKey, ProductId)
    VALUES (source.SourceSystemId, source.ExternalProductKey, source.ProductId);

COMMIT TRANSACTION;
GO
