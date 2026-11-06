-- Created for the GelatAI shop operations database.
/*
  Creates the normalized operational schema for shops, employees, products,
  shop assortments, inventory, inbound shipments, and sales.
  The script is idempotent and can be applied to a new or existing database.
*/

SET NOCOUNT ON;
SET XACT_ABORT ON;

BEGIN TRANSACTION;

IF OBJECT_ID(N'dbo.Shop', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.Shop (
        ShopId int IDENTITY(1,1) NOT NULL,
        ShopCode varchar(30) NOT NULL,
        ShopName nvarchar(200) NOT NULL,
        AddressLine1 nvarchar(250) NULL,
        AddressLine2 nvarchar(250) NULL,
        City nvarchar(100) NOT NULL,
        StateProvince nvarchar(100) NULL,
        PostalCode nvarchar(20) NULL,
        CountryCode char(2) NOT NULL,
        CurrencyCode char(3) NULL,
        TimeZoneId nvarchar(100) NOT NULL,
        Latitude decimal(9,6) NULL,
        Longitude decimal(9,6) NULL,
        OpenedOn date NULL,
        ClosedOn date NULL,
        IsActive bit NOT NULL CONSTRAINT DF_Shop_IsActive DEFAULT (1),
        CreatedAtUtc datetime2(0) NOT NULL CONSTRAINT DF_Shop_CreatedAtUtc DEFAULT (SYSUTCDATETIME()),
        UpdatedAtUtc datetime2(0) NOT NULL CONSTRAINT DF_Shop_UpdatedAtUtc DEFAULT (SYSUTCDATETIME()),
        CONSTRAINT PK_Shop PRIMARY KEY (ShopId),
        CONSTRAINT UQ_Shop_ShopCode UNIQUE (ShopCode),
        CONSTRAINT CK_Shop_CountryCode CHECK (CountryCode = UPPER(CountryCode)),
        CONSTRAINT CK_Shop_Latitude CHECK (Latitude IS NULL OR Latitude BETWEEN -90 AND 90),
        CONSTRAINT CK_Shop_Longitude CHECK (Longitude IS NULL OR Longitude BETWEEN -180 AND 180),
        CONSTRAINT CK_Shop_Dates CHECK (ClosedOn IS NULL OR OpenedOn IS NULL OR ClosedOn >= OpenedOn)
    );
END;

IF COL_LENGTH(N'dbo.Shop', N'CurrencyCode') IS NULL
BEGIN
    ALTER TABLE dbo.Shop ADD CurrencyCode char(3) NULL;
END;

IF EXISTS (
    SELECT 1
    FROM sys.columns
    WHERE object_id = OBJECT_ID(N'dbo.Shop')
      AND name = N'AddressLine1'
      AND is_nullable = 0
)
BEGIN
    ALTER TABLE dbo.Shop ALTER COLUMN AddressLine1 nvarchar(250) NULL;
END;

IF OBJECT_ID(N'dbo.Product', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.Product (
        ProductId int IDENTITY(1,1) NOT NULL,
        Sku varchar(50) NOT NULL,
        ProductName nvarchar(200) NOT NULL,
        Category nvarchar(100) NOT NULL,
        Description nvarchar(1000) NULL,
        UnitOfMeasure varchar(20) NOT NULL CONSTRAINT DF_Product_UnitOfMeasure DEFAULT ('unit'),
        StandardPrice decimal(19,4) NOT NULL,
        IsActive bit NOT NULL CONSTRAINT DF_Product_IsActive DEFAULT (1),
        CreatedAtUtc datetime2(0) NOT NULL CONSTRAINT DF_Product_CreatedAtUtc DEFAULT (SYSUTCDATETIME()),
        UpdatedAtUtc datetime2(0) NOT NULL CONSTRAINT DF_Product_UpdatedAtUtc DEFAULT (SYSUTCDATETIME()),
        CONSTRAINT PK_Product PRIMARY KEY (ProductId),
        CONSTRAINT UQ_Product_Sku UNIQUE (Sku),
        CONSTRAINT CK_Product_StandardPrice CHECK (StandardPrice >= 0)
    );
END;

IF OBJECT_ID(N'dbo.SourceSystem', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.SourceSystem (
        SourceSystemId smallint IDENTITY(1,1) NOT NULL,
        SourceSystemCode varchar(50) NOT NULL,
        SourceSystemName nvarchar(200) NOT NULL,
        IsActive bit NOT NULL CONSTRAINT DF_SourceSystem_IsActive DEFAULT (1),
        CONSTRAINT PK_SourceSystem PRIMARY KEY (SourceSystemId),
        CONSTRAINT UQ_SourceSystem_SourceSystemCode UNIQUE (SourceSystemCode)
    );
END;

IF OBJECT_ID(N'dbo.ShopExternalReference', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.ShopExternalReference (
        SourceSystemId smallint NOT NULL,
        ExternalShopKey varchar(100) NOT NULL,
        ShopId int NOT NULL,
        CONSTRAINT PK_ShopExternalReference PRIMARY KEY (SourceSystemId, ExternalShopKey),
        CONSTRAINT UQ_ShopExternalReference_SourceShop UNIQUE (SourceSystemId, ShopId),
        CONSTRAINT FK_ShopExternalReference_SourceSystem FOREIGN KEY (SourceSystemId)
            REFERENCES dbo.SourceSystem (SourceSystemId),
        CONSTRAINT FK_ShopExternalReference_Shop FOREIGN KEY (ShopId) REFERENCES dbo.Shop (ShopId)
    );
END;

IF OBJECT_ID(N'dbo.ProductExternalReference', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.ProductExternalReference (
        SourceSystemId smallint NOT NULL,
        ExternalProductKey nvarchar(200) NOT NULL,
        ProductId int NOT NULL,
        CONSTRAINT PK_ProductExternalReference PRIMARY KEY (SourceSystemId, ExternalProductKey),
        CONSTRAINT UQ_ProductExternalReference_SourceProduct UNIQUE (SourceSystemId, ProductId),
        CONSTRAINT FK_ProductExternalReference_SourceSystem FOREIGN KEY (SourceSystemId)
            REFERENCES dbo.SourceSystem (SourceSystemId),
        CONSTRAINT FK_ProductExternalReference_Product FOREIGN KEY (ProductId) REFERENCES dbo.Product (ProductId)
    );
END;

IF OBJECT_ID(N'dbo.Factory', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.Factory (
        FactoryId int IDENTITY(1,1) NOT NULL,
        FactoryCode varchar(50) NOT NULL,
        FactoryName nvarchar(200) NOT NULL,
        City nvarchar(100) NULL,
        CountryCode char(2) NULL,
        TimeZoneId nvarchar(100) NOT NULL,
        EventhouseDatabaseName nvarchar(200) NULL,
        TelemetryTableName nvarchar(200) NULL,
        IsActive bit NOT NULL CONSTRAINT DF_Factory_IsActive DEFAULT (1),
        CreatedAtUtc datetime2(0) NOT NULL CONSTRAINT DF_Factory_CreatedAtUtc DEFAULT (SYSUTCDATETIME()),
        UpdatedAtUtc datetime2(0) NOT NULL CONSTRAINT DF_Factory_UpdatedAtUtc DEFAULT (SYSUTCDATETIME()),
        CONSTRAINT PK_Factory PRIMARY KEY (FactoryId),
        CONSTRAINT UQ_Factory_FactoryCode UNIQUE (FactoryCode),
        CONSTRAINT CK_Factory_CountryCode CHECK (
            CountryCode IS NULL OR CountryCode = UPPER(CountryCode)
        )
    );
END;

IF OBJECT_ID(N'dbo.Employee', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.Employee (
        EmployeeId int IDENTITY(1,1) NOT NULL,
        ShopId int NOT NULL,
        EmployeeNumber varchar(30) NOT NULL,
        FirstName nvarchar(100) NOT NULL,
        LastName nvarchar(100) NOT NULL,
        JobTitle nvarchar(100) NOT NULL,
        Email nvarchar(320) NULL,
        Phone nvarchar(30) NULL,
        HiredOn date NOT NULL,
        EndedOn date NULL,
        IsActive bit NOT NULL CONSTRAINT DF_Employee_IsActive DEFAULT (1),
        CreatedAtUtc datetime2(0) NOT NULL CONSTRAINT DF_Employee_CreatedAtUtc DEFAULT (SYSUTCDATETIME()),
        UpdatedAtUtc datetime2(0) NOT NULL CONSTRAINT DF_Employee_UpdatedAtUtc DEFAULT (SYSUTCDATETIME()),
        CONSTRAINT PK_Employee PRIMARY KEY (EmployeeId),
        CONSTRAINT UQ_Employee_EmployeeNumber UNIQUE (EmployeeNumber),
        CONSTRAINT FK_Employee_Shop FOREIGN KEY (ShopId) REFERENCES dbo.Shop (ShopId),
        CONSTRAINT CK_Employee_Dates CHECK (EndedOn IS NULL OR EndedOn >= HiredOn)
    );
END;

IF OBJECT_ID(N'dbo.ShopProduct', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.ShopProduct (
        ShopId int NOT NULL,
        ProductId int NOT NULL,
        RetailPrice decimal(19,4) NULL,
        FirstAvailableOn date NULL,
        LastAvailableOn date NULL,
        IsFeatured bit NOT NULL CONSTRAINT DF_ShopProduct_IsFeatured DEFAULT (0),
        FeaturedFrom date NULL,
        FeaturedTo date NULL,
        IsActive bit NOT NULL CONSTRAINT DF_ShopProduct_IsActive DEFAULT (1),
        CreatedAtUtc datetime2(0) NOT NULL CONSTRAINT DF_ShopProduct_CreatedAtUtc DEFAULT (SYSUTCDATETIME()),
        UpdatedAtUtc datetime2(0) NOT NULL CONSTRAINT DF_ShopProduct_UpdatedAtUtc DEFAULT (SYSUTCDATETIME()),
        CONSTRAINT PK_ShopProduct PRIMARY KEY (ShopId, ProductId),
        CONSTRAINT FK_ShopProduct_Shop FOREIGN KEY (ShopId) REFERENCES dbo.Shop (ShopId),
        CONSTRAINT FK_ShopProduct_Product FOREIGN KEY (ProductId) REFERENCES dbo.Product (ProductId),
        CONSTRAINT CK_ShopProduct_RetailPrice CHECK (RetailPrice IS NULL OR RetailPrice >= 0),
        CONSTRAINT CK_ShopProduct_Dates CHECK (
            LastAvailableOn IS NULL
            OR FirstAvailableOn IS NULL
            OR LastAvailableOn >= FirstAvailableOn
        ),
        CONSTRAINT CK_ShopProduct_FeaturedDates CHECK (
            FeaturedTo IS NULL
            OR FeaturedFrom IS NULL
            OR FeaturedTo >= FeaturedFrom
        )
    );
END;

IF COL_LENGTH(N'dbo.ShopProduct', N'IsFeatured') IS NULL
BEGIN
    ALTER TABLE dbo.ShopProduct
        ADD IsFeatured bit NOT NULL
            CONSTRAINT DF_ShopProduct_IsFeatured DEFAULT (0);
END;

IF COL_LENGTH(N'dbo.ShopProduct', N'FeaturedFrom') IS NULL
BEGIN
    ALTER TABLE dbo.ShopProduct ADD FeaturedFrom date NULL;
END;

IF COL_LENGTH(N'dbo.ShopProduct', N'FeaturedTo') IS NULL
BEGIN
    ALTER TABLE dbo.ShopProduct ADD FeaturedTo date NULL;
END;

IF NOT EXISTS (
    SELECT 1
    FROM sys.check_constraints
    WHERE parent_object_id = OBJECT_ID(N'dbo.ShopProduct')
      AND name = N'CK_ShopProduct_FeaturedDates'
)
BEGIN
    ALTER TABLE dbo.ShopProduct WITH CHECK
        ADD CONSTRAINT CK_ShopProduct_FeaturedDates CHECK (
            FeaturedTo IS NULL
            OR FeaturedFrom IS NULL
            OR FeaturedTo >= FeaturedFrom
        );
END;

IF OBJECT_ID(N'dbo.Inventory', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.Inventory (
        ShopId int NOT NULL,
        ProductId int NOT NULL,
        QuantityOnHand decimal(18,3) NOT NULL CONSTRAINT DF_Inventory_QuantityOnHand DEFAULT (0),
        ReorderLevel decimal(18,3) NOT NULL CONSTRAINT DF_Inventory_ReorderLevel DEFAULT (0),
        LastCountedAtUtc datetime2(0) NULL,
        UpdatedAtUtc datetime2(0) NOT NULL CONSTRAINT DF_Inventory_UpdatedAtUtc DEFAULT (SYSUTCDATETIME()),
        CONSTRAINT PK_Inventory PRIMARY KEY (ShopId, ProductId),
        CONSTRAINT FK_Inventory_ShopProduct FOREIGN KEY (ShopId, ProductId)
            REFERENCES dbo.ShopProduct (ShopId, ProductId),
        CONSTRAINT CK_Inventory_QuantityOnHand CHECK (QuantityOnHand >= 0),
        CONSTRAINT CK_Inventory_ReorderLevel CHECK (ReorderLevel >= 0)
    );
END;

IF OBJECT_ID(N'dbo.Shipment', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.Shipment (
        ShipmentId bigint IDENTITY(1,1) NOT NULL,
        ShipmentNumber varchar(50) NOT NULL,
        FactoryId int NOT NULL,
        ShopId int NOT NULL,
        Status varchar(20) NOT NULL CONSTRAINT DF_Shipment_Status DEFAULT ('Planned'),
        DispatchedAtUtc datetime2(0) NULL,
        ExpectedAtUtc datetime2(0) NULL,
        ReceivedAtUtc datetime2(0) NULL,
        ReceivedByEmployeeId int NULL,
        Notes nvarchar(1000) NULL,
        CreatedAtUtc datetime2(0) NOT NULL CONSTRAINT DF_Shipment_CreatedAtUtc DEFAULT (SYSUTCDATETIME()),
        UpdatedAtUtc datetime2(0) NOT NULL CONSTRAINT DF_Shipment_UpdatedAtUtc DEFAULT (SYSUTCDATETIME()),
        CONSTRAINT PK_Shipment PRIMARY KEY (ShipmentId),
        CONSTRAINT UQ_Shipment_ShipmentNumber UNIQUE (ShipmentNumber),
        CONSTRAINT FK_Shipment_Factory FOREIGN KEY (FactoryId) REFERENCES dbo.Factory (FactoryId),
        CONSTRAINT FK_Shipment_Shop FOREIGN KEY (ShopId) REFERENCES dbo.Shop (ShopId),
        CONSTRAINT FK_Shipment_ReceivedByEmployee FOREIGN KEY (ReceivedByEmployeeId)
            REFERENCES dbo.Employee (EmployeeId),
        CONSTRAINT CK_Shipment_Status CHECK (Status IN ('Planned', 'Dispatched', 'Received', 'Cancelled')),
        CONSTRAINT CK_Shipment_ReceivedAt CHECK (ReceivedAtUtc IS NULL OR DispatchedAtUtc IS NULL OR ReceivedAtUtc >= DispatchedAtUtc)
    );
END;

IF COL_LENGTH(N'dbo.Shipment', N'FactoryId') IS NULL
BEGIN
    ALTER TABLE dbo.Shipment ADD FactoryId int NULL;
END;

IF NOT EXISTS (
    SELECT 1
    FROM sys.foreign_keys
    WHERE parent_object_id = OBJECT_ID(N'dbo.Shipment')
      AND name = N'FK_Shipment_Factory'
)
BEGIN
    ALTER TABLE dbo.Shipment WITH CHECK
        ADD CONSTRAINT FK_Shipment_Factory
            FOREIGN KEY (FactoryId) REFERENCES dbo.Factory (FactoryId);
END;

IF OBJECT_ID(N'dbo.ProductionBatch', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.ProductionBatch (
        ProductionBatchId bigint IDENTITY(1,1) NOT NULL,
        BatchNumber varchar(60) NOT NULL,
        FactoryId int NOT NULL,
        ProductId int NOT NULL,
        ProducedAtUtc datetime2(0) NOT NULL,
        ExpiresAtUtc datetime2(0) NULL,
        QuantityProduced decimal(18,3) NOT NULL,
        QuantityAllocated decimal(18,3) NOT NULL CONSTRAINT DF_ProductionBatch_QuantityAllocated DEFAULT (0),
        UnitOfMeasure varchar(20) NOT NULL CONSTRAINT DF_ProductionBatch_UnitOfMeasure DEFAULT ('unit'),
        TelemetryWindowStartUtc datetime2(0) NOT NULL,
        TelemetryWindowEndUtc datetime2(0) NOT NULL,
        TelemetryEventCount bigint NULL,
        TelemetryAnomalyCount bigint NULL,
        QualityStatus varchar(20) NOT NULL CONSTRAINT DF_ProductionBatch_QualityStatus DEFAULT ('Released'),
        CreatedAtUtc datetime2(0) NOT NULL CONSTRAINT DF_ProductionBatch_CreatedAtUtc DEFAULT (SYSUTCDATETIME()),
        CONSTRAINT PK_ProductionBatch PRIMARY KEY (ProductionBatchId),
        CONSTRAINT UQ_ProductionBatch_BatchNumber UNIQUE (BatchNumber),
        CONSTRAINT FK_ProductionBatch_Factory FOREIGN KEY (FactoryId) REFERENCES dbo.Factory (FactoryId),
        CONSTRAINT FK_ProductionBatch_Product FOREIGN KEY (ProductId) REFERENCES dbo.Product (ProductId),
        CONSTRAINT CK_ProductionBatch_QuantityProduced CHECK (QuantityProduced > 0),
        CONSTRAINT CK_ProductionBatch_QuantityAllocated CHECK (
            QuantityAllocated >= 0 AND QuantityAllocated <= QuantityProduced
        ),
        CONSTRAINT CK_ProductionBatch_TelemetryWindow CHECK (
            TelemetryWindowEndUtc > TelemetryWindowStartUtc
        ),
        CONSTRAINT CK_ProductionBatch_QualityStatus CHECK (
            QualityStatus IN ('Released', 'Held', 'Rejected')
        )
    );
END;

IF OBJECT_ID(N'dbo.ShipmentItem', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.ShipmentItem (
        ShipmentId bigint NOT NULL,
        ProductId int NOT NULL,
        ProductionBatchId bigint NOT NULL,
        QuantitySent decimal(18,3) NOT NULL,
        QuantityReceived decimal(18,3) NULL,
        UnitCost decimal(19,4) NULL,
        CONSTRAINT PK_ShipmentItem PRIMARY KEY (ShipmentId, ProductId),
        CONSTRAINT FK_ShipmentItem_Shipment FOREIGN KEY (ShipmentId) REFERENCES dbo.Shipment (ShipmentId),
        CONSTRAINT FK_ShipmentItem_Product FOREIGN KEY (ProductId) REFERENCES dbo.Product (ProductId),
        CONSTRAINT FK_ShipmentItem_ProductionBatch FOREIGN KEY (ProductionBatchId)
            REFERENCES dbo.ProductionBatch (ProductionBatchId),
        CONSTRAINT CK_ShipmentItem_QuantitySent CHECK (QuantitySent > 0),
        CONSTRAINT CK_ShipmentItem_QuantityReceived CHECK (QuantityReceived IS NULL OR QuantityReceived >= 0),
        CONSTRAINT CK_ShipmentItem_UnitCost CHECK (UnitCost IS NULL OR UnitCost >= 0)
    );
END;

IF COL_LENGTH(N'dbo.ShipmentItem', N'ProductionBatchId') IS NULL
BEGIN
    ALTER TABLE dbo.ShipmentItem ADD ProductionBatchId bigint NULL;
END;

IF NOT EXISTS (
    SELECT 1
    FROM sys.foreign_keys
    WHERE parent_object_id = OBJECT_ID(N'dbo.ShipmentItem')
      AND name = N'FK_ShipmentItem_ProductionBatch'
)
BEGIN
    ALTER TABLE dbo.ShipmentItem WITH CHECK
        ADD CONSTRAINT FK_ShipmentItem_ProductionBatch
            FOREIGN KEY (ProductionBatchId) REFERENCES dbo.ProductionBatch (ProductionBatchId);
END;

IF OBJECT_ID(N'dbo.RegistrySimulationRun', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.RegistrySimulationRun (
        RunWeek date NOT NULL,
        BaselineMonth date NOT NULL,
        AppliedAtUtc datetime2(0) NOT NULL CONSTRAINT DF_RegistrySimulationRun_AppliedAtUtc DEFAULT (SYSUTCDATETIME()),
        ChangeCount int NOT NULL,
        CONSTRAINT PK_RegistrySimulationRun PRIMARY KEY (RunWeek),
        CONSTRAINT CK_RegistrySimulationRun_ChangeCount CHECK (ChangeCount >= 0)
    );
END;

IF OBJECT_ID(N'dbo.RegistryChangeLog', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.RegistryChangeLog (
        RegistryChangeLogId bigint IDENTITY(1,1) NOT NULL,
        RunWeek date NOT NULL,
        EntityType varchar(30) NOT NULL,
        EntityKey nvarchar(200) NOT NULL,
        ChangeType varchar(30) NOT NULL,
        ChangeSummary nvarchar(1000) NOT NULL,
        ChangedAtUtc datetime2(0) NOT NULL CONSTRAINT DF_RegistryChangeLog_ChangedAtUtc DEFAULT (SYSUTCDATETIME()),
        CONSTRAINT PK_RegistryChangeLog PRIMARY KEY (RegistryChangeLogId),
        CONSTRAINT FK_RegistryChangeLog_RegistrySimulationRun FOREIGN KEY (RunWeek)
            REFERENCES dbo.RegistrySimulationRun (RunWeek)
    );
END;

IF OBJECT_ID(N'dbo.LogisticsSimulationRun', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.LogisticsSimulationRun (
        RunWeek date NOT NULL,
        AppliedAtUtc datetime2(0) NOT NULL CONSTRAINT DF_LogisticsSimulationRun_AppliedAtUtc DEFAULT (SYSUTCDATETIME()),
        TelemetryWindowStartUtc datetime2(0) NOT NULL,
        TelemetryWindowEndUtc datetime2(0) NOT NULL,
        TelemetryEventCount bigint NOT NULL,
        TelemetryAnomalyCount bigint NOT NULL,
        ProductionBatchCount int NOT NULL,
        ShipmentCount int NOT NULL,
        ShipmentItemCount int NOT NULL,
        CONSTRAINT PK_LogisticsSimulationRun PRIMARY KEY (RunWeek),
        CONSTRAINT CK_LogisticsSimulationRun_Counts CHECK (
            TelemetryEventCount >= 0
            AND TelemetryAnomalyCount >= 0
            AND ProductionBatchCount >= 0
            AND ShipmentCount >= 0
            AND ShipmentItemCount >= 0
        )
    );
END;

IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE object_id = OBJECT_ID(N'dbo.Employee')
      AND name = N'IX_Employee_ShopId_IsActive'
)
BEGIN
    CREATE INDEX IX_Employee_ShopId_IsActive ON dbo.Employee (ShopId, IsActive);
END;

IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE object_id = OBJECT_ID(N'dbo.ShopProduct')
      AND name = N'IX_ShopProduct_ProductId_IsActive'
)
BEGIN
    CREATE INDEX IX_ShopProduct_ProductId_IsActive ON dbo.ShopProduct (ProductId, IsActive);
END;

IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE object_id = OBJECT_ID(N'dbo.Shipment')
      AND name = N'IX_Shipment_ShopId_Status'
)
BEGIN
    CREATE INDEX IX_Shipment_ShopId_Status ON dbo.Shipment (ShopId, Status, ExpectedAtUtc);
END;

IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE object_id = OBJECT_ID(N'dbo.ProductionBatch')
      AND name = N'IX_ProductionBatch_Factory_Product_ProducedAtUtc'
)
BEGIN
    CREATE INDEX IX_ProductionBatch_Factory_Product_ProducedAtUtc
        ON dbo.ProductionBatch (FactoryId, ProductId, ProducedAtUtc);
END;

IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE object_id = OBJECT_ID(N'dbo.Shipment')
      AND name = N'IX_Shipment_Factory_Shop_Status'
)
BEGIN
    CREATE INDEX IX_Shipment_Factory_Shop_Status
        ON dbo.Shipment (FactoryId, ShopId, Status, DispatchedAtUtc);
END;

COMMIT TRANSACTION;
GO

CREATE OR ALTER VIEW dbo.vw_ShopCatalog
AS
SELECT
    sp.ShopId,
    s.ShopCode,
    s.ShopName,
    sp.ProductId,
    p.Sku,
    p.ProductName,
    p.Category,
    COALESCE(sp.RetailPrice, p.StandardPrice) AS RetailPrice,
    sp.IsFeatured,
    sp.FeaturedFrom,
    sp.FeaturedTo,
    i.QuantityOnHand,
    i.ReorderLevel,
    CASE
        WHEN i.QuantityOnHand IS NOT NULL AND i.QuantityOnHand <= i.ReorderLevel THEN CAST(1 AS bit)
        ELSE CAST(0 AS bit)
    END AS NeedsReorder
FROM dbo.ShopProduct AS sp
INNER JOIN dbo.Shop AS s ON s.ShopId = sp.ShopId
INNER JOIN dbo.Product AS p ON p.ProductId = sp.ProductId
LEFT JOIN dbo.Inventory AS i ON i.ShopId = sp.ShopId AND i.ProductId = sp.ProductId
WHERE s.IsActive = 1
  AND p.IsActive = 1
  AND sp.IsActive = 1;
GO

CREATE OR ALTER VIEW dbo.vw_ApiShopCatalogMatch
AS
SELECT
    shopRef.ExternalShopKey AS ApiShopShopId,
    productRef.ExternalProductKey AS ApiShopFlavor,
    s.ShopId,
    s.ShopCode,
    s.ShopName,
    s.City,
    s.CountryCode,
    s.CurrencyCode,
    p.ProductId,
    p.Sku,
    p.ProductName,
    sp.IsFeatured,
    sp.FeaturedFrom,
    sp.FeaturedTo
FROM dbo.SourceSystem AS source
INNER JOIN dbo.ShopExternalReference AS shopRef
    ON shopRef.SourceSystemId = source.SourceSystemId
INNER JOIN dbo.Shop AS s ON s.ShopId = shopRef.ShopId
INNER JOIN dbo.ShopProduct AS sp ON sp.ShopId = s.ShopId
INNER JOIN dbo.Product AS p ON p.ProductId = sp.ProductId
INNER JOIN dbo.ProductExternalReference AS productRef
    ON productRef.SourceSystemId = source.SourceSystemId
   AND productRef.ProductId = p.ProductId
WHERE source.SourceSystemCode = 'apishop'
  AND source.IsActive = 1
  AND s.IsActive = 1
  AND p.IsActive = 1
  AND sp.IsActive = 1;
GO

CREATE OR ALTER VIEW dbo.vw_FactoryShopProductFlow
AS
SELECT
    f.FactoryId,
    f.FactoryCode,
    f.FactoryName,
    pb.ProductionBatchId,
    pb.BatchNumber,
    pb.ProducedAtUtc,
    pb.TelemetryWindowStartUtc,
    pb.TelemetryWindowEndUtc,
    pb.TelemetryEventCount,
    pb.TelemetryAnomalyCount,
    shipment.ShipmentId,
    shipment.ShipmentNumber,
    shipment.Status AS ShipmentStatus,
    shipment.DispatchedAtUtc,
    CAST(shipment.DispatchedAtUtc AS date) AS DispatchDate,
    shipment.ExpectedAtUtc,
    shipment.ReceivedAtUtc,
    CAST(shipment.ReceivedAtUtc AS date) AS ReceivedDate,
    shop.ShopId,
    shop.ShopCode,
    shop.ShopName,
    product.ProductId,
    product.Sku,
    product.ProductName,
    item.QuantitySent,
    item.QuantityReceived,
    pb.UnitOfMeasure
FROM dbo.Shipment AS shipment
INNER JOIN dbo.Factory AS f ON f.FactoryId = shipment.FactoryId
INNER JOIN dbo.ShipmentItem AS item ON item.ShipmentId = shipment.ShipmentId
INNER JOIN dbo.ProductionBatch AS pb ON pb.ProductionBatchId = item.ProductionBatchId
INNER JOIN dbo.Shop AS shop ON shop.ShopId = shipment.ShopId
INNER JOIN dbo.Product AS product ON product.ProductId = item.ProductId;
GO
