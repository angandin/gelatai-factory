SET NOCOUNT ON;
SET XACT_ABORT ON;

BEGIN TRANSACTION;

IF OBJECT_ID(N'dbo.Sale', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.Sale (
        SaleId bigint IDENTITY(1,1) NOT NULL CONSTRAINT PK_Sale PRIMARY KEY,
        SourceSystemId smallint NOT NULL REFERENCES dbo.SourceSystem(SourceSystemId),
        TransactionId uniqueidentifier NOT NULL,
        PayloadHash binary(32) NOT NULL,
        ShopId int NOT NULL REFERENCES dbo.Shop(ShopId),
        TimestampUtc datetime2(6) NOT NULL,
        TimestampLocal datetime2(6) NOT NULL,
        SaleDateLocal date NOT NULL,
        UtcOffsetMinutes smallint NOT NULL,
        TimeZoneId nvarchar(100) NOT NULL,
        City nvarchar(100) NOT NULL,
        CountryCode char(2) NOT NULL,
        CurrencyCode char(3) NOT NULL,
        ServingType varchar(30) NOT NULL,
        SalesChannel varchar(30) NOT NULL,
        PaymentMethod varchar(30) NOT NULL,
        Weather varchar(30) NOT NULL,
        TemperatureC decimal(5,1) NOT NULL,
        FlavorCount int NOT NULL,
        TotalScoops int NOT NULL,
        SubtotalAmount decimal(19,4) NOT NULL,
        DiscountAmount decimal(19,4) NOT NULL,
        NetSalesAmount decimal(19,4) NOT NULL,
        TaxAmount decimal(19,4) NOT NULL,
        TotalAmount decimal(19,4) NOT NULL,
        IngestedAtUtc datetime2(6) NOT NULL CONSTRAINT DF_Sale_IngestedAtUtc DEFAULT SYSUTCDATETIME(),
        CONSTRAINT UQ_Sale_SourceTransaction UNIQUE(SourceSystemId, TransactionId),
        CONSTRAINT CK_Sale_Currency CHECK(CurrencyCode IN ('EUR','USD','JPY')),
        CONSTRAINT CK_Sale_Counts CHECK(FlavorCount BETWEEN 1 AND 6 AND TotalScoops >= FlavorCount),
        CONSTRAINT CK_Sale_Time CHECK(
            UtcOffsetMinutes BETWEEN -840 AND 840
            AND SaleDateLocal = CONVERT(date, TimestampLocal)
            AND TimestampLocal = DATEADD(minute, UtcOffsetMinutes, TimestampUtc)),
        CONSTRAINT CK_Sale_Amounts CHECK(
            SubtotalAmount > 0 AND DiscountAmount >= 0 AND DiscountAmount <= SubtotalAmount
            AND TaxAmount >= 0 AND NetSalesAmount = SubtotalAmount - DiscountAmount
            AND TotalAmount = NetSalesAmount + TaxAmount),
        CONSTRAINT CK_Sale_Dimensions CHECK(
            ServingType IN ('cup','cone','takeaway_tub')
            AND SalesChannel IN ('counter','delivery','click_and_collect')
            AND PaymentMethod IN ('card','cash','mobile_wallet'))
    );
END;

IF OBJECT_ID(N'dbo.SaleItem', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.SaleItem (
        SaleId bigint NOT NULL REFERENCES dbo.Sale(SaleId),
        LineNumber int NOT NULL,
        ProductId int NOT NULL REFERENCES dbo.Product(ProductId),
        Flavor nvarchar(200) NOT NULL,
        Scoops int NOT NULL,
        UnitPrice decimal(19,4) NOT NULL,
        SubtotalAmount decimal(19,4) NOT NULL,
        DiscountAmount decimal(19,4) NOT NULL,
        NetSalesAmount decimal(19,4) NOT NULL,
        TaxAmount decimal(19,4) NOT NULL,
        TotalAmount decimal(19,4) NOT NULL,
        CONSTRAINT PK_SaleItem PRIMARY KEY(SaleId, LineNumber),
        CONSTRAINT UQ_SaleItem_Product UNIQUE(SaleId, ProductId),
        CONSTRAINT CK_SaleItem_Amounts CHECK(
            LineNumber > 0 AND Scoops > 0 AND UnitPrice > 0
            AND SubtotalAmount = UnitPrice * Scoops
            AND DiscountAmount >= 0 AND DiscountAmount <= SubtotalAmount
            AND NetSalesAmount = SubtotalAmount - DiscountAmount
            AND TaxAmount >= 0 AND TotalAmount = NetSalesAmount + TaxAmount)
    );
END;

IF NOT EXISTS(SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID('dbo.Sale') AND name='IX_Sale_ShopDateCurrency')
    CREATE INDEX IX_Sale_ShopDateCurrency ON dbo.Sale(ShopId, SaleDateLocal, CurrencyCode)
        INCLUDE(NetSalesAmount, TaxAmount, TotalAmount);
IF NOT EXISTS(SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID('dbo.Sale') AND name='IX_Sale_DateCurrency')
    CREATE INDEX IX_Sale_DateCurrency ON dbo.Sale(SaleDateLocal, CurrencyCode);
IF NOT EXISTS(SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID('dbo.SaleItem') AND name='IX_SaleItem_Product')
    CREATE INDEX IX_SaleItem_Product ON dbo.SaleItem(ProductId, SaleId);

COMMIT TRANSACTION;
GO

CREATE OR ALTER PROCEDURE dbo.RecordApiShopSale
    @Sale nvarchar(max)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF ISJSON(@Sale) <> 1
        THROW 51000, 'A JSON sale is required.', 1;

    DECLARE @Header TABLE (
        TransactionId uniqueidentifier NOT NULL, ShopKey varchar(100) NOT NULL,
        TimestampUtc datetime2(6) NOT NULL, TimestampLocal datetime2(6) NOT NULL,
        SaleDateLocal date NOT NULL, UtcOffsetMinutes smallint NOT NULL,
        TimeZoneId nvarchar(100) NOT NULL, City nvarchar(100) NOT NULL,
        CountryCode char(2) NOT NULL, CurrencyCode char(3) NOT NULL,
        ServingType varchar(30) NOT NULL, SalesChannel varchar(30) NOT NULL,
        PaymentMethod varchar(30) NOT NULL, Weather varchar(30) NOT NULL,
        TemperatureC decimal(5,1) NOT NULL, FlavorCount int NOT NULL, TotalScoops int NOT NULL,
        SubtotalAmount decimal(19,4) NOT NULL, DiscountAmount decimal(19,4) NOT NULL,
        NetSalesAmount decimal(19,4) NOT NULL, TaxAmount decimal(19,4) NOT NULL,
        TotalAmount decimal(19,4) NOT NULL
    );
    INSERT INTO @Header
    SELECT * FROM OPENJSON(@Sale) WITH (
        TransactionId uniqueidentifier, ShopKey varchar(100),
        TimestampUtc datetime2(6), TimestampLocal datetime2(6),
        SaleDateLocal date, UtcOffsetMinutes smallint,
        TimeZoneId nvarchar(100), City nvarchar(100), CountryCode char(2), CurrencyCode char(3),
        ServingType varchar(30), SalesChannel varchar(30), PaymentMethod varchar(30),
        Weather varchar(30), TemperatureC decimal(5,1), FlavorCount int, TotalScoops int,
        SubtotalAmount decimal(19,4), DiscountAmount decimal(19,4),
        NetSalesAmount decimal(19,4), TaxAmount decimal(19,4), TotalAmount decimal(19,4)
    );
    IF (SELECT COUNT(*) FROM @Header) <> 1
        THROW 51000, 'Exactly one transaction header is required.', 1;

    DECLARE @Items TABLE (
        LineNumber int NOT NULL PRIMARY KEY, Flavor nvarchar(200) NOT NULL,
        Scoops int NOT NULL, UnitPrice decimal(19,4) NOT NULL,
        SubtotalAmount decimal(19,4) NOT NULL, DiscountAmount decimal(19,4) NOT NULL,
        NetSalesAmount decimal(19,4) NOT NULL, TaxAmount decimal(19,4) NOT NULL,
        TotalAmount decimal(19,4) NOT NULL
    );
    INSERT INTO @Items
    SELECT * FROM OPENJSON(@Sale, '$.Items') WITH (
        LineNumber int, Flavor nvarchar(200), Scoops int, UnitPrice decimal(19,4),
        SubtotalAmount decimal(19,4), DiscountAmount decimal(19,4),
        NetSalesAmount decimal(19,4), TaxAmount decimal(19,4), TotalAmount decimal(19,4)
    );

    IF EXISTS (
        SELECT 1 FROM @Header AS h
        CROSS JOIN (
            SELECT COUNT(*) AS Lines, COUNT(DISTINCT Flavor) AS Flavors,
                MIN(LineNumber) AS FirstLine, MAX(LineNumber) AS LastLine, SUM(Scoops) AS Scoops,
                SUM(SubtotalAmount) AS Subtotal, SUM(DiscountAmount) AS Discount,
                SUM(NetSalesAmount) AS Net, SUM(TaxAmount) AS Tax, SUM(TotalAmount) AS Total
            FROM @Items
        ) AS i
        WHERE i.Lines <> h.FlavorCount OR i.Lines <> i.Flavors OR i.FirstLine <> 1
            OR i.LastLine <> i.Lines OR i.Scoops <> h.TotalScoops
            OR i.Subtotal <> h.SubtotalAmount OR i.Discount <> h.DiscountAmount
            OR i.Net <> h.NetSalesAmount OR i.Tax <> h.TaxAmount OR i.Total <> h.TotalAmount
    )
        THROW 51001, 'Sale header and flavor lines do not reconcile.', 1;

    DECLARE @Precision int = (SELECT CASE CurrencyCode WHEN 'JPY' THEN 0 ELSE 2 END FROM @Header);
    IF EXISTS (
        SELECT amount FROM @Header CROSS APPLY (VALUES
            (SubtotalAmount),(DiscountAmount),(NetSalesAmount),(TaxAmount),(TotalAmount)) AS a(amount)
        WHERE ROUND(amount,@Precision) <> amount
        UNION ALL
        SELECT amount FROM @Items CROSS APPLY (VALUES
            (UnitPrice),(SubtotalAmount),(DiscountAmount),(NetSalesAmount),(TaxAmount),(TotalAmount)) AS a(amount)
        WHERE ROUND(amount,@Precision) <> amount
    )
        THROW 51001, 'Amounts must use the currency minor-unit precision.', 1;

    DECLARE @SourceSystemId smallint = (
        SELECT SourceSystemId FROM dbo.SourceSystem WHERE SourceSystemCode='apishop' AND IsActive=1);
    IF @SourceSystemId IS NULL
        THROW 51002, 'The apishop source system is not registered.', 1;
    DECLARE @TransactionId uniqueidentifier = (SELECT TransactionId FROM @Header);
    DECLARE @Hash binary(32) = HASHBYTES('SHA2_256',CONVERT(varbinary(max),@Sale));
    DECLARE @SaleId bigint, @ExistingHash binary(32);

    BEGIN TRY
        BEGIN TRANSACTION;
        SELECT @SaleId=SaleId, @ExistingHash=PayloadHash
        FROM dbo.Sale WITH(UPDLOCK,HOLDLOCK)
        WHERE SourceSystemId=@SourceSystemId AND TransactionId=@TransactionId;
        IF @SaleId IS NOT NULL
        BEGIN
            IF @ExistingHash <> @Hash
                THROW 51003, 'Transaction ID already exists with different sale data.', 1;
            COMMIT TRANSACTION;
            SELECT @SaleId AS SaleId;
            RETURN;
        END;

        DECLARE @ShopId int = (
            SELECT s.ShopId FROM @Header AS h
            JOIN dbo.ShopExternalReference AS r
                ON r.SourceSystemId=@SourceSystemId AND r.ExternalShopKey=h.ShopKey
            JOIN dbo.Shop AS s ON s.ShopId=r.ShopId AND s.IsActive=1
            WHERE s.CountryCode=h.CountryCode AND s.CurrencyCode=h.CurrencyCode
                AND s.TimeZoneId=h.TimeZoneId);
        IF @ShopId IS NULL
            THROW 51002, 'Shop is not registered or its country, currency, or time zone does not match.', 1;
        IF EXISTS (
            SELECT 1 FROM @Items AS i CROSS JOIN @Header AS h
            LEFT JOIN dbo.vw_ApiShopCatalogMatch AS m
                ON m.ApiShopShopId=h.ShopKey AND m.ApiShopFlavor=i.Flavor
            WHERE m.ProductId IS NULL)
            THROW 51002, 'A flavor is not in the active shop assortment.', 1;

        INSERT INTO dbo.Sale (
            SourceSystemId,TransactionId,PayloadHash,ShopId,TimestampUtc,TimestampLocal,
            SaleDateLocal,UtcOffsetMinutes,TimeZoneId,City,CountryCode,CurrencyCode,
            ServingType,SalesChannel,PaymentMethod,Weather,TemperatureC,FlavorCount,TotalScoops,
            SubtotalAmount,DiscountAmount,NetSalesAmount,TaxAmount,TotalAmount)
        SELECT @SourceSystemId,TransactionId,@Hash,@ShopId,TimestampUtc,TimestampLocal,
            SaleDateLocal,UtcOffsetMinutes,TimeZoneId,City,CountryCode,CurrencyCode,
            ServingType,SalesChannel,PaymentMethod,Weather,TemperatureC,FlavorCount,TotalScoops,
            SubtotalAmount,DiscountAmount,NetSalesAmount,TaxAmount,TotalAmount
        FROM @Header;
        SET @SaleId=CONVERT(bigint,SCOPE_IDENTITY());
        INSERT INTO dbo.SaleItem (
            SaleId,LineNumber,ProductId,Flavor,Scoops,UnitPrice,SubtotalAmount,
            DiscountAmount,NetSalesAmount,TaxAmount,TotalAmount)
        SELECT @SaleId,i.LineNumber,m.ProductId,i.Flavor,i.Scoops,i.UnitPrice,i.SubtotalAmount,
            i.DiscountAmount,i.NetSalesAmount,i.TaxAmount,i.TotalAmount
        FROM @Items AS i CROSS JOIN @Header AS h
        JOIN dbo.vw_ApiShopCatalogMatch AS m ON m.ApiShopShopId=h.ShopKey AND m.ApiShopFlavor=i.Flavor;
        IF @@ROWCOUNT <> (SELECT FlavorCount FROM @Header)
            THROW 51002, 'The shop assortment changed while recording the sale.', 1;
        COMMIT TRANSACTION;
        SELECT @SaleId AS SaleId;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
GO

CREATE OR ALTER VIEW dbo.vw_Sales
AS
SELECT s.SaleId,s.TransactionId,s.ShopId,shop.ShopCode,shop.ShopName,
    s.TimestampUtc,s.TimestampLocal,s.SaleDateLocal,s.UtcOffsetMinutes,s.TimeZoneId,
    s.City,s.CountryCode,s.CurrencyCode,s.ServingType,s.SalesChannel,s.PaymentMethod,
    s.Weather,s.TemperatureC,s.FlavorCount,s.TotalScoops,s.SubtotalAmount,
    s.DiscountAmount,s.NetSalesAmount,s.TaxAmount,s.TotalAmount,s.IngestedAtUtc
FROM dbo.Sale AS s JOIN dbo.Shop AS shop ON shop.ShopId=s.ShopId;
GO

CREATE OR ALTER VIEW dbo.vw_SaleItems
AS
SELECT s.SaleId,s.TransactionId,s.ShopId,s.SaleDateLocal,s.TimestampUtc,
    s.City,s.CountryCode,s.CurrencyCode,s.ServingType,s.SalesChannel,
    i.LineNumber,i.ProductId,p.Sku,i.Flavor,i.Scoops,i.UnitPrice,i.SubtotalAmount,
    i.DiscountAmount,i.NetSalesAmount,i.TaxAmount,i.TotalAmount
FROM dbo.SaleItem AS i JOIN dbo.Sale AS s ON s.SaleId=i.SaleId
JOIN dbo.Product AS p ON p.ProductId=i.ProductId;
GO
