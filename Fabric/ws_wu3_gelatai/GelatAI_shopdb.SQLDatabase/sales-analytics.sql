SET NOCOUNT ON;

-- Transaction grain: count receipts and aggregate without repeating header totals.
SELECT SaleDateLocal, ShopId, CountryCode, CurrencyCode, ServingType, SalesChannel,
    COUNT_BIG(*) AS Transactions, SUM(TotalScoops) AS Scoops,
    SUM(NetSalesAmount) AS NetSalesExcludingTax, SUM(TaxAmount) AS Tax,
    SUM(TotalAmount) AS TotalPaid
FROM dbo.vw_Sales
GROUP BY SaleDateLocal, ShopId, CountryCode, CurrencyCode, ServingType, SalesChannel;

-- Flavor grain: discounts and tax are allocated, so line amounts remain additive.
SELECT SaleDateLocal, ShopId, CountryCode, CurrencyCode, ProductId, Flavor,
    SUM(Scoops) AS Scoops, SUM(NetSalesAmount) AS NetSalesExcludingTax,
    SUM(TaxAmount) AS Tax, SUM(TotalAmount) AS TotalPaid
FROM dbo.vw_SaleItems
GROUP BY SaleDateLocal, ShopId, CountryCode, CurrencyCode, ProductId, Flavor;
