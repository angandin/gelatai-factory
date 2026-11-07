-- Schema-only capture of the current workspace. Run only against an empty target SQL Database.
SET NOCOUNT ON;
SET XACT_ABORT ON;
IF EXISTS (SELECT 1 FROM sys.tables WHERE is_ms_shipped = 0)
    THROW 50000, 'Captured schema requires an empty database; no objects were changed.', 1;
GO

CREATE TABLE [dbo].[Employee] (
    [EmployeeId] int IDENTITY(1,1) NOT NULL,
    [ShopId] int NOT NULL,
    [EmployeeNumber] varchar(30) COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
    [FirstName] nvarchar(100) COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
    [LastName] nvarchar(100) COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
    [JobTitle] nvarchar(100) COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
    [Email] nvarchar(320) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
    [Phone] nvarchar(30) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
    [HiredOn] date NOT NULL,
    [EndedOn] date NULL,
    [IsActive] bit NOT NULL CONSTRAINT [DF_Employee_IsActive] DEFAULT ((1)),
    [CreatedAtUtc] datetime2(0) NOT NULL CONSTRAINT [DF_Employee_CreatedAtUtc] DEFAULT (sysutcdatetime()),
    [UpdatedAtUtc] datetime2(0) NOT NULL CONSTRAINT [DF_Employee_UpdatedAtUtc] DEFAULT (sysutcdatetime())
);
GO

CREATE TABLE [dbo].[Factory] (
    [FactoryId] int IDENTITY(1,1) NOT NULL,
    [FactoryCode] varchar(50) COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
    [FactoryName] nvarchar(200) COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
    [City] nvarchar(100) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
    [CountryCode] char(2) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
    [TimeZoneId] nvarchar(100) COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
    [EventhouseDatabaseName] nvarchar(200) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
    [TelemetryTableName] nvarchar(200) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
    [IsActive] bit NOT NULL CONSTRAINT [DF_Factory_IsActive] DEFAULT ((1)),
    [CreatedAtUtc] datetime2(0) NOT NULL CONSTRAINT [DF_Factory_CreatedAtUtc] DEFAULT (sysutcdatetime()),
    [UpdatedAtUtc] datetime2(0) NOT NULL CONSTRAINT [DF_Factory_UpdatedAtUtc] DEFAULT (sysutcdatetime())
);
GO

CREATE TABLE [dbo].[Inventory] (
    [ShopId] int NOT NULL,
    [ProductId] int NOT NULL,
    [QuantityOnHand] decimal(18,3) NOT NULL CONSTRAINT [DF_Inventory_QuantityOnHand] DEFAULT ((0)),
    [ReorderLevel] decimal(18,3) NOT NULL CONSTRAINT [DF_Inventory_ReorderLevel] DEFAULT ((0)),
    [LastCountedAtUtc] datetime2(0) NULL,
    [UpdatedAtUtc] datetime2(0) NOT NULL CONSTRAINT [DF_Inventory_UpdatedAtUtc] DEFAULT (sysutcdatetime())
);
GO

CREATE TABLE [dbo].[LogisticsSimulationRun] (
    [RunWeek] date NOT NULL,
    [AppliedAtUtc] datetime2(0) NOT NULL CONSTRAINT [DF_LogisticsSimulationRun_AppliedAtUtc] DEFAULT (sysutcdatetime()),
    [TelemetryWindowStartUtc] datetime2(0) NOT NULL,
    [TelemetryWindowEndUtc] datetime2(0) NOT NULL,
    [TelemetryEventCount] bigint NOT NULL,
    [TelemetryAnomalyCount] bigint NOT NULL,
    [ProductionBatchCount] int NOT NULL,
    [ShipmentCount] int NOT NULL,
    [ShipmentItemCount] int NOT NULL
);
GO

CREATE TABLE [dbo].[Product] (
    [ProductId] int IDENTITY(1,1) NOT NULL,
    [Sku] varchar(50) COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
    [ProductName] nvarchar(200) COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
    [Category] nvarchar(100) COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
    [Description] nvarchar(1000) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
    [UnitOfMeasure] varchar(20) COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL CONSTRAINT [DF_Product_UnitOfMeasure] DEFAULT ('unit'),
    [StandardPrice] decimal(19,4) NOT NULL,
    [IsActive] bit NOT NULL CONSTRAINT [DF_Product_IsActive] DEFAULT ((1)),
    [CreatedAtUtc] datetime2(0) NOT NULL CONSTRAINT [DF_Product_CreatedAtUtc] DEFAULT (sysutcdatetime()),
    [UpdatedAtUtc] datetime2(0) NOT NULL CONSTRAINT [DF_Product_UpdatedAtUtc] DEFAULT (sysutcdatetime())
);
GO

CREATE TABLE [dbo].[ProductExternalReference] (
    [SourceSystemId] smallint NOT NULL,
    [ExternalProductKey] nvarchar(200) COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
    [ProductId] int NOT NULL
);
GO

CREATE TABLE [dbo].[ProductionBatch] (
    [ProductionBatchId] bigint IDENTITY(1,1) NOT NULL,
    [BatchNumber] varchar(60) COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
    [FactoryId] int NOT NULL,
    [ProductId] int NOT NULL,
    [ProducedAtUtc] datetime2(0) NOT NULL,
    [ExpiresAtUtc] datetime2(0) NULL,
    [QuantityProduced] decimal(18,3) NOT NULL,
    [QuantityAllocated] decimal(18,3) NOT NULL CONSTRAINT [DF_ProductionBatch_QuantityAllocated] DEFAULT ((0)),
    [UnitOfMeasure] varchar(20) COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL CONSTRAINT [DF_ProductionBatch_UnitOfMeasure] DEFAULT ('unit'),
    [TelemetryWindowStartUtc] datetime2(0) NOT NULL,
    [TelemetryWindowEndUtc] datetime2(0) NOT NULL,
    [TelemetryEventCount] bigint NULL,
    [TelemetryAnomalyCount] bigint NULL,
    [QualityStatus] varchar(20) COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL CONSTRAINT [DF_ProductionBatch_QualityStatus] DEFAULT ('Released'),
    [CreatedAtUtc] datetime2(0) NOT NULL CONSTRAINT [DF_ProductionBatch_CreatedAtUtc] DEFAULT (sysutcdatetime())
);
GO

CREATE TABLE [dbo].[RegistryChangeLog] (
    [RegistryChangeLogId] bigint IDENTITY(1,1) NOT NULL,
    [RunWeek] date NOT NULL,
    [EntityType] varchar(30) COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
    [EntityKey] nvarchar(200) COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
    [ChangeType] varchar(30) COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
    [ChangeSummary] nvarchar(1000) COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
    [ChangedAtUtc] datetime2(0) NOT NULL CONSTRAINT [DF_RegistryChangeLog_ChangedAtUtc] DEFAULT (sysutcdatetime())
);
GO

CREATE TABLE [dbo].[RegistrySimulationRun] (
    [RunWeek] date NOT NULL,
    [BaselineMonth] date NOT NULL,
    [AppliedAtUtc] datetime2(0) NOT NULL CONSTRAINT [DF_RegistrySimulationRun_AppliedAtUtc] DEFAULT (sysutcdatetime()),
    [ChangeCount] int NOT NULL
);
GO

CREATE TABLE [dbo].[Sale] (
    [SaleId] bigint IDENTITY(1,1) NOT NULL,
    [SourceSystemId] smallint NOT NULL,
    [TransactionId] uniqueidentifier NOT NULL,
    [PayloadHash] binary(32) NOT NULL,
    [ShopId] int NOT NULL,
    [TimestampUtc] datetime2(6) NOT NULL,
    [TimestampLocal] datetime2(6) NOT NULL,
    [SaleDateLocal] date NOT NULL,
    [UtcOffsetMinutes] smallint NOT NULL,
    [TimeZoneId] nvarchar(100) COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
    [City] nvarchar(100) COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
    [CountryCode] char(2) COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
    [CurrencyCode] char(3) COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
    [ServingType] varchar(30) COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
    [SalesChannel] varchar(30) COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
    [PaymentMethod] varchar(30) COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
    [Weather] varchar(30) COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
    [TemperatureC] decimal(5,1) NOT NULL,
    [FlavorCount] int NOT NULL,
    [TotalScoops] int NOT NULL,
    [SubtotalAmount] decimal(19,4) NOT NULL,
    [DiscountAmount] decimal(19,4) NOT NULL,
    [NetSalesAmount] decimal(19,4) NOT NULL,
    [TaxAmount] decimal(19,4) NOT NULL,
    [TotalAmount] decimal(19,4) NOT NULL,
    [IngestedAtUtc] datetime2(6) NOT NULL CONSTRAINT [DF_Sale_IngestedAtUtc] DEFAULT (sysutcdatetime())
);
GO

CREATE TABLE [dbo].[SaleItem] (
    [SaleId] bigint NOT NULL,
    [LineNumber] int NOT NULL,
    [ProductId] int NOT NULL,
    [Flavor] nvarchar(200) COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
    [Scoops] int NOT NULL,
    [UnitPrice] decimal(19,4) NOT NULL,
    [SubtotalAmount] decimal(19,4) NOT NULL,
    [DiscountAmount] decimal(19,4) NOT NULL,
    [NetSalesAmount] decimal(19,4) NOT NULL,
    [TaxAmount] decimal(19,4) NOT NULL,
    [TotalAmount] decimal(19,4) NOT NULL
);
GO

CREATE TABLE [dbo].[Shipment] (
    [ShipmentId] bigint IDENTITY(1,1) NOT NULL,
    [ShipmentNumber] varchar(50) COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
    [ShopId] int NOT NULL,
    [Status] varchar(20) COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL CONSTRAINT [DF_Shipment_Status] DEFAULT ('Planned'),
    [DispatchedAtUtc] datetime2(0) NULL,
    [ExpectedAtUtc] datetime2(0) NULL,
    [ReceivedAtUtc] datetime2(0) NULL,
    [ReceivedByEmployeeId] int NULL,
    [Notes] nvarchar(1000) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
    [CreatedAtUtc] datetime2(0) NOT NULL CONSTRAINT [DF_Shipment_CreatedAtUtc] DEFAULT (sysutcdatetime()),
    [UpdatedAtUtc] datetime2(0) NOT NULL CONSTRAINT [DF_Shipment_UpdatedAtUtc] DEFAULT (sysutcdatetime()),
    [FactoryId] int NULL
);
GO

CREATE TABLE [dbo].[ShipmentDetails] (
    [ShipmentId] bigint NOT NULL,
    [ShipmentNumber] varchar(255) COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
    [ShopId] int NOT NULL,
    [Status] varchar(50) COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
    [DispatchedAtUtc] datetime2(7) NULL,
    [ExpectedAtUtc] datetime2(7) NULL,
    [ReceivedAtUtc] datetime2(7) NULL,
    [ReceivedByEmployeeId] int NULL,
    [Notes] nvarchar(max) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
    [ShipmentCreatedAtUtc] datetime2(7) NOT NULL,
    [ShipmentUpdatedAtUtc] datetime2(7) NOT NULL,
    [FactoryId] int NULL,
    [ProductId] int NOT NULL,
    [Sku] varchar(255) COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
    [ProductName] nvarchar(255) COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
    [Category] nvarchar(255) COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
    [QuantitySent] decimal(18,2) NOT NULL,
    [QuantityReceived] decimal(18,2) NULL,
    [UnitCost] decimal(18,2) NULL,
    [ProductionBatchId] bigint NULL
);
GO

CREATE TABLE [dbo].[ShipmentItem] (
    [ShipmentId] bigint NOT NULL,
    [ProductId] int NOT NULL,
    [QuantitySent] decimal(18,3) NOT NULL,
    [QuantityReceived] decimal(18,3) NULL,
    [UnitCost] decimal(19,4) NULL,
    [ProductionBatchId] bigint NULL
);
GO

CREATE TABLE [dbo].[Shop] (
    [ShopId] int IDENTITY(1,1) NOT NULL,
    [ShopCode] varchar(30) COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
    [ShopName] nvarchar(200) COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
    [AddressLine1] nvarchar(250) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
    [AddressLine2] nvarchar(250) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
    [City] nvarchar(100) COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
    [StateProvince] nvarchar(100) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
    [PostalCode] nvarchar(20) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
    [CountryCode] char(2) COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
    [TimeZoneId] nvarchar(100) COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
    [Latitude] decimal(9,6) NULL,
    [Longitude] decimal(9,6) NULL,
    [OpenedOn] date NULL,
    [ClosedOn] date NULL,
    [IsActive] bit NOT NULL CONSTRAINT [DF_Shop_IsActive] DEFAULT ((1)),
    [CreatedAtUtc] datetime2(0) NOT NULL CONSTRAINT [DF_Shop_CreatedAtUtc] DEFAULT (sysutcdatetime()),
    [UpdatedAtUtc] datetime2(0) NOT NULL CONSTRAINT [DF_Shop_UpdatedAtUtc] DEFAULT (sysutcdatetime()),
    [CurrencyCode] char(3) COLLATE SQL_Latin1_General_CP1_CI_AS NULL
);
GO

CREATE TABLE [dbo].[ShopExternalReference] (
    [SourceSystemId] smallint NOT NULL,
    [ExternalShopKey] varchar(100) COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
    [ShopId] int NOT NULL
);
GO

CREATE TABLE [dbo].[ShopProduct] (
    [ShopId] int NOT NULL,
    [ProductId] int NOT NULL,
    [RetailPrice] decimal(19,4) NULL,
    [FirstAvailableOn] date NULL,
    [LastAvailableOn] date NULL,
    [IsActive] bit NOT NULL CONSTRAINT [DF_ShopProduct_IsActive] DEFAULT ((1)),
    [CreatedAtUtc] datetime2(0) NOT NULL CONSTRAINT [DF_ShopProduct_CreatedAtUtc] DEFAULT (sysutcdatetime()),
    [UpdatedAtUtc] datetime2(0) NOT NULL CONSTRAINT [DF_ShopProduct_UpdatedAtUtc] DEFAULT (sysutcdatetime()),
    [IsFeatured] bit NOT NULL CONSTRAINT [DF_ShopProduct_IsFeatured] DEFAULT ((0)),
    [FeaturedFrom] date NULL,
    [FeaturedTo] date NULL
);
GO

CREATE TABLE [dbo].[SourceSystem] (
    [SourceSystemId] smallint IDENTITY(1,1) NOT NULL,
    [SourceSystemCode] varchar(50) COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
    [SourceSystemName] nvarchar(200) COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
    [IsActive] bit NOT NULL CONSTRAINT [DF_SourceSystem_IsActive] DEFAULT ((1))
);
GO

CREATE NONCLUSTERED INDEX [IX_Employee_ShopId_IsActive] ON [dbo].[Employee] ([ShopId] ASC, [IsActive] ASC);
GO

ALTER TABLE [dbo].[Employee] ADD CONSTRAINT [PK_Employee] PRIMARY KEY CLUSTERED ([EmployeeId] ASC);
GO

ALTER TABLE [dbo].[Employee] ADD CONSTRAINT [UQ_Employee_EmployeeNumber] UNIQUE NONCLUSTERED ([EmployeeNumber] ASC);
GO

ALTER TABLE [dbo].[Factory] ADD CONSTRAINT [PK_Factory] PRIMARY KEY CLUSTERED ([FactoryId] ASC);
GO

ALTER TABLE [dbo].[Factory] ADD CONSTRAINT [UQ_Factory_FactoryCode] UNIQUE NONCLUSTERED ([FactoryCode] ASC);
GO

ALTER TABLE [dbo].[Inventory] ADD CONSTRAINT [PK_Inventory] PRIMARY KEY CLUSTERED ([ShopId] ASC, [ProductId] ASC);
GO

ALTER TABLE [dbo].[LogisticsSimulationRun] ADD CONSTRAINT [PK_LogisticsSimulationRun] PRIMARY KEY CLUSTERED ([RunWeek] ASC);
GO

ALTER TABLE [dbo].[Product] ADD CONSTRAINT [PK_Product] PRIMARY KEY CLUSTERED ([ProductId] ASC);
GO

ALTER TABLE [dbo].[Product] ADD CONSTRAINT [UQ_Product_Sku] UNIQUE NONCLUSTERED ([Sku] ASC);
GO

ALTER TABLE [dbo].[ProductExternalReference] ADD CONSTRAINT [PK_ProductExternalReference] PRIMARY KEY CLUSTERED ([SourceSystemId] ASC, [ExternalProductKey] ASC);
GO

ALTER TABLE [dbo].[ProductExternalReference] ADD CONSTRAINT [UQ_ProductExternalReference_SourceProduct] UNIQUE NONCLUSTERED ([SourceSystemId] ASC, [ProductId] ASC);
GO

CREATE NONCLUSTERED INDEX [IX_ProductionBatch_Factory_Product_ProducedAtUtc] ON [dbo].[ProductionBatch] ([FactoryId] ASC, [ProductId] ASC, [ProducedAtUtc] ASC);
GO

ALTER TABLE [dbo].[ProductionBatch] ADD CONSTRAINT [PK_ProductionBatch] PRIMARY KEY CLUSTERED ([ProductionBatchId] ASC);
GO

ALTER TABLE [dbo].[ProductionBatch] ADD CONSTRAINT [UQ_ProductionBatch_BatchNumber] UNIQUE NONCLUSTERED ([BatchNumber] ASC);
GO

ALTER TABLE [dbo].[RegistryChangeLog] ADD CONSTRAINT [PK_RegistryChangeLog] PRIMARY KEY CLUSTERED ([RegistryChangeLogId] ASC);
GO

ALTER TABLE [dbo].[RegistrySimulationRun] ADD CONSTRAINT [PK_RegistrySimulationRun] PRIMARY KEY CLUSTERED ([RunWeek] ASC);
GO

CREATE NONCLUSTERED INDEX [IX_Sale_DateCurrency] ON [dbo].[Sale] ([SaleDateLocal] ASC, [CurrencyCode] ASC);
GO

CREATE NONCLUSTERED INDEX [IX_Sale_ShopDateCurrency] ON [dbo].[Sale] ([ShopId] ASC, [SaleDateLocal] ASC, [CurrencyCode] ASC) INCLUDE ([NetSalesAmount], [TaxAmount], [TotalAmount]);
GO

ALTER TABLE [dbo].[Sale] ADD CONSTRAINT [PK_Sale] PRIMARY KEY CLUSTERED ([SaleId] ASC);
GO

ALTER TABLE [dbo].[Sale] ADD CONSTRAINT [UQ_Sale_SourceTransaction] UNIQUE NONCLUSTERED ([SourceSystemId] ASC, [TransactionId] ASC);
GO

CREATE NONCLUSTERED INDEX [IX_SaleItem_Product] ON [dbo].[SaleItem] ([ProductId] ASC, [SaleId] ASC);
GO

ALTER TABLE [dbo].[SaleItem] ADD CONSTRAINT [PK_SaleItem] PRIMARY KEY CLUSTERED ([SaleId] ASC, [LineNumber] ASC);
GO

ALTER TABLE [dbo].[SaleItem] ADD CONSTRAINT [UQ_SaleItem_Product] UNIQUE NONCLUSTERED ([SaleId] ASC, [ProductId] ASC);
GO

CREATE NONCLUSTERED INDEX [IX_Shipment_Factory_Shop_Status] ON [dbo].[Shipment] ([FactoryId] ASC, [ShopId] ASC, [Status] ASC, [DispatchedAtUtc] ASC);
GO

CREATE NONCLUSTERED INDEX [IX_Shipment_ShopId_Status] ON [dbo].[Shipment] ([ShopId] ASC, [Status] ASC, [ExpectedAtUtc] ASC);
GO

ALTER TABLE [dbo].[Shipment] ADD CONSTRAINT [PK_Shipment] PRIMARY KEY CLUSTERED ([ShipmentId] ASC);
GO

ALTER TABLE [dbo].[Shipment] ADD CONSTRAINT [UQ_Shipment_ShipmentNumber] UNIQUE NONCLUSTERED ([ShipmentNumber] ASC);
GO

ALTER TABLE [dbo].[ShipmentItem] ADD CONSTRAINT [PK_ShipmentItem] PRIMARY KEY CLUSTERED ([ShipmentId] ASC, [ProductId] ASC);
GO

ALTER TABLE [dbo].[Shop] ADD CONSTRAINT [PK_Shop] PRIMARY KEY CLUSTERED ([ShopId] ASC);
GO

ALTER TABLE [dbo].[Shop] ADD CONSTRAINT [UQ_Shop_ShopCode] UNIQUE NONCLUSTERED ([ShopCode] ASC);
GO

ALTER TABLE [dbo].[ShopExternalReference] ADD CONSTRAINT [PK_ShopExternalReference] PRIMARY KEY CLUSTERED ([SourceSystemId] ASC, [ExternalShopKey] ASC);
GO

ALTER TABLE [dbo].[ShopExternalReference] ADD CONSTRAINT [UQ_ShopExternalReference_SourceShop] UNIQUE NONCLUSTERED ([SourceSystemId] ASC, [ShopId] ASC);
GO

CREATE NONCLUSTERED INDEX [IX_ShopProduct_ProductId_IsActive] ON [dbo].[ShopProduct] ([ProductId] ASC, [IsActive] ASC);
GO

ALTER TABLE [dbo].[ShopProduct] ADD CONSTRAINT [PK_ShopProduct] PRIMARY KEY CLUSTERED ([ShopId] ASC, [ProductId] ASC);
GO

ALTER TABLE [dbo].[SourceSystem] ADD CONSTRAINT [PK_SourceSystem] PRIMARY KEY CLUSTERED ([SourceSystemId] ASC);
GO

ALTER TABLE [dbo].[SourceSystem] ADD CONSTRAINT [UQ_SourceSystem_SourceSystemCode] UNIQUE NONCLUSTERED ([SourceSystemCode] ASC);
GO

ALTER TABLE [dbo].[Employee] WITH CHECK ADD CONSTRAINT [CK_Employee_Dates] CHECK ([EndedOn] IS NULL OR [EndedOn]>=[HiredOn]);
GO

ALTER TABLE [dbo].[Factory] WITH CHECK ADD CONSTRAINT [CK_Factory_CountryCode] CHECK ([CountryCode] IS NULL OR [CountryCode]=upper([CountryCode]));
GO

ALTER TABLE [dbo].[Inventory] WITH CHECK ADD CONSTRAINT [CK_Inventory_QuantityOnHand] CHECK ([QuantityOnHand]>=(0));
GO

ALTER TABLE [dbo].[Inventory] WITH CHECK ADD CONSTRAINT [CK_Inventory_ReorderLevel] CHECK ([ReorderLevel]>=(0));
GO

ALTER TABLE [dbo].[LogisticsSimulationRun] WITH CHECK ADD CONSTRAINT [CK_LogisticsSimulationRun_Counts] CHECK ([TelemetryEventCount]>=(0) AND [TelemetryAnomalyCount]>=(0) AND [ProductionBatchCount]>=(0) AND [ShipmentCount]>=(0) AND [ShipmentItemCount]>=(0));
GO

ALTER TABLE [dbo].[Product] WITH CHECK ADD CONSTRAINT [CK_Product_StandardPrice] CHECK ([StandardPrice]>=(0));
GO

ALTER TABLE [dbo].[ProductionBatch] WITH CHECK ADD CONSTRAINT [CK_ProductionBatch_QualityStatus] CHECK ([QualityStatus]='Rejected' OR [QualityStatus]='Held' OR [QualityStatus]='Released');
GO

ALTER TABLE [dbo].[ProductionBatch] WITH CHECK ADD CONSTRAINT [CK_ProductionBatch_QuantityAllocated] CHECK ([QuantityAllocated]>=(0) AND [QuantityAllocated]<=[QuantityProduced]);
GO

ALTER TABLE [dbo].[ProductionBatch] WITH CHECK ADD CONSTRAINT [CK_ProductionBatch_QuantityProduced] CHECK ([QuantityProduced]>(0));
GO

ALTER TABLE [dbo].[ProductionBatch] WITH CHECK ADD CONSTRAINT [CK_ProductionBatch_TelemetryWindow] CHECK ([TelemetryWindowEndUtc]>[TelemetryWindowStartUtc]);
GO

ALTER TABLE [dbo].[RegistrySimulationRun] WITH CHECK ADD CONSTRAINT [CK_RegistrySimulationRun_ChangeCount] CHECK ([ChangeCount]>=(0));
GO

ALTER TABLE [dbo].[Sale] WITH CHECK ADD CONSTRAINT [CK_Sale_Amounts] CHECK ([SubtotalAmount]>(0) AND [DiscountAmount]>=(0) AND [DiscountAmount]<=[SubtotalAmount] AND [TaxAmount]>=(0) AND [NetSalesAmount]=([SubtotalAmount]-[DiscountAmount]) AND [TotalAmount]=([NetSalesAmount]+[TaxAmount]));
GO

ALTER TABLE [dbo].[Sale] WITH CHECK ADD CONSTRAINT [CK_Sale_Counts] CHECK ([FlavorCount]>=(1) AND [FlavorCount]<=(6) AND [TotalScoops]>=[FlavorCount]);
GO

ALTER TABLE [dbo].[Sale] WITH CHECK ADD CONSTRAINT [CK_Sale_Currency] CHECK ([CurrencyCode]='JPY' OR [CurrencyCode]='USD' OR [CurrencyCode]='EUR');
GO

ALTER TABLE [dbo].[Sale] WITH CHECK ADD CONSTRAINT [CK_Sale_Dimensions] CHECK (([ServingType]='takeaway_tub' OR [ServingType]='cone' OR [ServingType]='cup') AND ([SalesChannel]='click_and_collect' OR [SalesChannel]='delivery' OR [SalesChannel]='counter') AND ([PaymentMethod]='mobile_wallet' OR [PaymentMethod]='cash' OR [PaymentMethod]='card'));
GO

ALTER TABLE [dbo].[Sale] WITH CHECK ADD CONSTRAINT [CK_Sale_Time] CHECK ([UtcOffsetMinutes]>=(-840) AND [UtcOffsetMinutes]<=(840) AND [SaleDateLocal]=CONVERT([date],[TimestampLocal]) AND [TimestampLocal]=dateadd(minute,[UtcOffsetMinutes],[TimestampUtc]));
GO

ALTER TABLE [dbo].[SaleItem] WITH CHECK ADD CONSTRAINT [CK_SaleItem_Amounts] CHECK ([LineNumber]>(0) AND [Scoops]>(0) AND [UnitPrice]>(0) AND [SubtotalAmount]=[UnitPrice]*[Scoops] AND [DiscountAmount]>=(0) AND [DiscountAmount]<=[SubtotalAmount] AND [NetSalesAmount]=([SubtotalAmount]-[DiscountAmount]) AND [TaxAmount]>=(0) AND [TotalAmount]=([NetSalesAmount]+[TaxAmount]));
GO

ALTER TABLE [dbo].[Shipment] WITH CHECK ADD CONSTRAINT [CK_Shipment_ReceivedAt] CHECK ([ReceivedAtUtc] IS NULL OR [DispatchedAtUtc] IS NULL OR [ReceivedAtUtc]>=[DispatchedAtUtc]);
GO

ALTER TABLE [dbo].[Shipment] WITH CHECK ADD CONSTRAINT [CK_Shipment_Status] CHECK ([Status]='Cancelled' OR [Status]='Received' OR [Status]='Dispatched' OR [Status]='Planned');
GO

ALTER TABLE [dbo].[ShipmentItem] WITH CHECK ADD CONSTRAINT [CK_ShipmentItem_QuantityReceived] CHECK ([QuantityReceived] IS NULL OR [QuantityReceived]>=(0));
GO

ALTER TABLE [dbo].[ShipmentItem] WITH CHECK ADD CONSTRAINT [CK_ShipmentItem_QuantitySent] CHECK ([QuantitySent]>(0));
GO

ALTER TABLE [dbo].[ShipmentItem] WITH CHECK ADD CONSTRAINT [CK_ShipmentItem_UnitCost] CHECK ([UnitCost] IS NULL OR [UnitCost]>=(0));
GO

ALTER TABLE [dbo].[Shop] WITH CHECK ADD CONSTRAINT [CK_Shop_CountryCode] CHECK ([CountryCode]=upper([CountryCode]));
GO

ALTER TABLE [dbo].[Shop] WITH CHECK ADD CONSTRAINT [CK_Shop_Dates] CHECK ([ClosedOn] IS NULL OR [OpenedOn] IS NULL OR [ClosedOn]>=[OpenedOn]);
GO

ALTER TABLE [dbo].[Shop] WITH CHECK ADD CONSTRAINT [CK_Shop_Latitude] CHECK ([Latitude] IS NULL OR [Latitude]>=(-90) AND [Latitude]<=(90));
GO

ALTER TABLE [dbo].[Shop] WITH CHECK ADD CONSTRAINT [CK_Shop_Longitude] CHECK ([Longitude] IS NULL OR [Longitude]>=(-180) AND [Longitude]<=(180));
GO

ALTER TABLE [dbo].[ShopProduct] WITH CHECK ADD CONSTRAINT [CK_ShopProduct_Dates] CHECK ([LastAvailableOn] IS NULL OR [FirstAvailableOn] IS NULL OR [LastAvailableOn]>=[FirstAvailableOn]);
GO

ALTER TABLE [dbo].[ShopProduct] WITH CHECK ADD CONSTRAINT [CK_ShopProduct_FeaturedDates] CHECK ([FeaturedTo] IS NULL OR [FeaturedFrom] IS NULL OR [FeaturedTo]>=[FeaturedFrom]);
GO

ALTER TABLE [dbo].[ShopProduct] WITH CHECK ADD CONSTRAINT [CK_ShopProduct_RetailPrice] CHECK ([RetailPrice] IS NULL OR [RetailPrice]>=(0));
GO

ALTER TABLE [dbo].[Employee] WITH CHECK ADD CONSTRAINT [FK_Employee_Shop] FOREIGN KEY ([ShopId]) REFERENCES [dbo].[Shop] ([ShopId]) ON DELETE NO ACTION ON UPDATE NO ACTION;
GO

ALTER TABLE [dbo].[Inventory] WITH CHECK ADD CONSTRAINT [FK_Inventory_ShopProduct] FOREIGN KEY ([ShopId], [ProductId]) REFERENCES [dbo].[ShopProduct] ([ShopId], [ProductId]) ON DELETE NO ACTION ON UPDATE NO ACTION;
GO

ALTER TABLE [dbo].[ProductExternalReference] WITH CHECK ADD CONSTRAINT [FK_ProductExternalReference_Product] FOREIGN KEY ([ProductId]) REFERENCES [dbo].[Product] ([ProductId]) ON DELETE NO ACTION ON UPDATE NO ACTION;
GO

ALTER TABLE [dbo].[ProductExternalReference] WITH CHECK ADD CONSTRAINT [FK_ProductExternalReference_SourceSystem] FOREIGN KEY ([SourceSystemId]) REFERENCES [dbo].[SourceSystem] ([SourceSystemId]) ON DELETE NO ACTION ON UPDATE NO ACTION;
GO

ALTER TABLE [dbo].[ProductionBatch] WITH CHECK ADD CONSTRAINT [FK_ProductionBatch_Factory] FOREIGN KEY ([FactoryId]) REFERENCES [dbo].[Factory] ([FactoryId]) ON DELETE NO ACTION ON UPDATE NO ACTION;
GO

ALTER TABLE [dbo].[ProductionBatch] WITH CHECK ADD CONSTRAINT [FK_ProductionBatch_Product] FOREIGN KEY ([ProductId]) REFERENCES [dbo].[Product] ([ProductId]) ON DELETE NO ACTION ON UPDATE NO ACTION;
GO

ALTER TABLE [dbo].[RegistryChangeLog] WITH CHECK ADD CONSTRAINT [FK_RegistryChangeLog_RegistrySimulationRun] FOREIGN KEY ([RunWeek]) REFERENCES [dbo].[RegistrySimulationRun] ([RunWeek]) ON DELETE NO ACTION ON UPDATE NO ACTION;
GO

ALTER TABLE [dbo].[Sale] WITH CHECK ADD CONSTRAINT [FK__Sale__ShopId__1D7B6025] FOREIGN KEY ([ShopId]) REFERENCES [dbo].[Shop] ([ShopId]) ON DELETE NO ACTION ON UPDATE NO ACTION;
GO

ALTER TABLE [dbo].[Sale] WITH CHECK ADD CONSTRAINT [FK__Sale__SourceSyst__1C873BEC] FOREIGN KEY ([SourceSystemId]) REFERENCES [dbo].[SourceSystem] ([SourceSystemId]) ON DELETE NO ACTION ON UPDATE NO ACTION;
GO

ALTER TABLE [dbo].[SaleItem] WITH CHECK ADD CONSTRAINT [FK__SaleItem__Produc__27F8EE98] FOREIGN KEY ([ProductId]) REFERENCES [dbo].[Product] ([ProductId]) ON DELETE NO ACTION ON UPDATE NO ACTION;
GO

ALTER TABLE [dbo].[SaleItem] WITH CHECK ADD CONSTRAINT [FK__SaleItem__SaleId__2704CA5F] FOREIGN KEY ([SaleId]) REFERENCES [dbo].[Sale] ([SaleId]) ON DELETE NO ACTION ON UPDATE NO ACTION;
GO

ALTER TABLE [dbo].[Shipment] WITH CHECK ADD CONSTRAINT [FK_Shipment_Factory] FOREIGN KEY ([FactoryId]) REFERENCES [dbo].[Factory] ([FactoryId]) ON DELETE NO ACTION ON UPDATE NO ACTION;
GO

ALTER TABLE [dbo].[Shipment] WITH CHECK ADD CONSTRAINT [FK_Shipment_ReceivedByEmployee] FOREIGN KEY ([ReceivedByEmployeeId]) REFERENCES [dbo].[Employee] ([EmployeeId]) ON DELETE NO ACTION ON UPDATE NO ACTION;
GO

ALTER TABLE [dbo].[Shipment] WITH CHECK ADD CONSTRAINT [FK_Shipment_Shop] FOREIGN KEY ([ShopId]) REFERENCES [dbo].[Shop] ([ShopId]) ON DELETE NO ACTION ON UPDATE NO ACTION;
GO

ALTER TABLE [dbo].[ShipmentItem] WITH CHECK ADD CONSTRAINT [FK_ShipmentItem_Product] FOREIGN KEY ([ProductId]) REFERENCES [dbo].[Product] ([ProductId]) ON DELETE NO ACTION ON UPDATE NO ACTION;
GO

ALTER TABLE [dbo].[ShipmentItem] WITH CHECK ADD CONSTRAINT [FK_ShipmentItem_ProductionBatch] FOREIGN KEY ([ProductionBatchId]) REFERENCES [dbo].[ProductionBatch] ([ProductionBatchId]) ON DELETE NO ACTION ON UPDATE NO ACTION;
GO

ALTER TABLE [dbo].[ShipmentItem] WITH CHECK ADD CONSTRAINT [FK_ShipmentItem_Shipment] FOREIGN KEY ([ShipmentId]) REFERENCES [dbo].[Shipment] ([ShipmentId]) ON DELETE NO ACTION ON UPDATE NO ACTION;
GO

ALTER TABLE [dbo].[ShopExternalReference] WITH CHECK ADD CONSTRAINT [FK_ShopExternalReference_Shop] FOREIGN KEY ([ShopId]) REFERENCES [dbo].[Shop] ([ShopId]) ON DELETE NO ACTION ON UPDATE NO ACTION;
GO

ALTER TABLE [dbo].[ShopExternalReference] WITH CHECK ADD CONSTRAINT [FK_ShopExternalReference_SourceSystem] FOREIGN KEY ([SourceSystemId]) REFERENCES [dbo].[SourceSystem] ([SourceSystemId]) ON DELETE NO ACTION ON UPDATE NO ACTION;
GO

ALTER TABLE [dbo].[ShopProduct] WITH CHECK ADD CONSTRAINT [FK_ShopProduct_Product] FOREIGN KEY ([ProductId]) REFERENCES [dbo].[Product] ([ProductId]) ON DELETE NO ACTION ON UPDATE NO ACTION;
GO

ALTER TABLE [dbo].[ShopProduct] WITH CHECK ADD CONSTRAINT [FK_ShopProduct_Shop] FOREIGN KEY ([ShopId]) REFERENCES [dbo].[Shop] ([ShopId]) ON DELETE NO ACTION ON UPDATE NO ACTION;
GO

CREATE   PROCEDURE dbo.RecordApiShopSale
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

CREATE   VIEW dbo.vw_ApiShopCatalogMatch
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

CREATE   VIEW dbo.vw_FactoryShopProductFlow
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

CREATE   VIEW dbo.vw_SaleItems
AS
SELECT s.SaleId,s.TransactionId,s.ShopId,s.SaleDateLocal,s.TimestampUtc,
    s.City,s.CountryCode,s.CurrencyCode,s.ServingType,s.SalesChannel,
    i.LineNumber,i.ProductId,p.Sku,i.Flavor,i.Scoops,i.UnitPrice,i.SubtotalAmount,
    i.DiscountAmount,i.NetSalesAmount,i.TaxAmount,i.TotalAmount
FROM dbo.SaleItem AS i JOIN dbo.Sale AS s ON s.SaleId=i.SaleId
JOIN dbo.Product AS p ON p.ProductId=i.ProductId;
GO

CREATE   VIEW dbo.vw_Sales
AS
SELECT s.SaleId,s.TransactionId,s.ShopId,shop.ShopCode,shop.ShopName,
    s.TimestampUtc,s.TimestampLocal,s.SaleDateLocal,s.UtcOffsetMinutes,s.TimeZoneId,
    s.City,s.CountryCode,s.CurrencyCode,s.ServingType,s.SalesChannel,s.PaymentMethod,
    s.Weather,s.TemperatureC,s.FlavorCount,s.TotalScoops,s.SubtotalAmount,
    s.DiscountAmount,s.NetSalesAmount,s.TaxAmount,s.TotalAmount,s.IngestedAtUtc
FROM dbo.Sale AS s JOIN dbo.Shop AS shop ON shop.ShopId=s.ShopId;
GO

CREATE   VIEW dbo.vw_ShopCatalog
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
