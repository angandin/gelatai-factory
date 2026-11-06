-- Run as an authorized Entra administrator after granting the app Fabric item Read.
-- Directory Readers access is required to resolve the managed identity.
SET NOCOUNT ON;
IF DATABASE_PRINCIPAL_ID(N'gelatai-shops') IS NULL
    CREATE USER [gelatai-shops] FROM EXTERNAL PROVIDER;

GRANT EXECUTE ON OBJECT::dbo.RecordApiShopSale TO [gelatai-shops];
GRANT SELECT ON OBJECT::dbo.vw_ApiShopCatalogMatch TO [gelatai-shops];
GRANT SELECT (ShopId, TimeZoneId) ON OBJECT::dbo.Shop TO [gelatai-shops];
