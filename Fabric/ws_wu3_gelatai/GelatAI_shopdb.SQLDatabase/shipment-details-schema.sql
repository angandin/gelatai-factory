SET NOCOUNT ON;
SET XACT_ABORT ON;

IF OBJECT_ID(N'dbo.ShipmentDetails', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.ShipmentDetails (
        ShipmentId bigint NOT NULL,
        ShipmentNumber varchar(255) NOT NULL,
        ShopId int NOT NULL,
        Status varchar(50) NOT NULL,
        DispatchedAtUtc datetime2(7) NULL,
        ExpectedAtUtc datetime2(7) NULL,
        ReceivedAtUtc datetime2(7) NULL,
        ReceivedByEmployeeId int NULL,
        Notes nvarchar(max) NULL,
        ShipmentCreatedAtUtc datetime2(7) NOT NULL,
        ShipmentUpdatedAtUtc datetime2(7) NOT NULL,
        FactoryId int NULL,
        ProductId int NOT NULL,
        Sku varchar(255) NOT NULL,
        ProductName nvarchar(255) NOT NULL,
        Category nvarchar(255) NOT NULL,
        QuantitySent decimal(18,2) NOT NULL,
        QuantityReceived decimal(18,2) NULL,
        UnitCost decimal(18,2) NULL,
        ProductionBatchId bigint NULL
    );
END;
