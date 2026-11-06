using System.Data.Common;
using ApiShop.Models;
using ApiShop.Services;

namespace EventHubCooldown.Tests;

internal static class SalesTestData
{
    public static ShopDefinition Shop(string currency = "EUR") => new()
    {
        Id = "it-roma-001", Name = "Test shop", City = "Rome", CountryCode = "IT",
        Currency = currency, TimeZoneId = "Europe/Rome", MinItemPrice = 2,
        MaxItemPrice = 3,
        Flavors = ["Pistachio", "Stracciatella", "Dark Chocolate", "Lemon", "Fiordilatte", "Tiramisu"]
    };

    public static SaleEvent Sale(string currency = "EUR", params decimal[] prices)
    {
        if (prices.Length == 0) prices = [2m, 3m, 4m];
        var subtotal = prices.Sum();
        return new SaleEvent
        {
            EventType = "ice_cream_sale", TransactionId = Guid.NewGuid().ToString("N"),
            ShopId = "it-roma-001", ShopName = "Test shop", City = "Rome",
            CountryCode = "IT", Currency = currency, Latitude = 41.89, Longitude = 12.47,
            TimestampUtc = "2026-10-28T23:30:00.1234567+00:00",
            TimestampLocal = "2026-10-29T00:30:00.1234567+01:00",
            ServingType = "cup", SalesChannel = "counter", PaymentMethod = "card",
            Weather = "sunny", TemperatureC = 24.5,
            Flavors = prices.Select((price, index) => new SaleFlavor
            {
                Flavor = Shop().Flavors[index], Scoops = 1, UnitPrice = price, LineTotal = price
            }).ToList(),
            FlavorCount = prices.Length, TotalScoops = prices.Length,
            Subtotal = subtotal, DiscountAmount = 0, TaxAmount = 0, TotalPrice = subtotal
        };
    }

    public static void SetTotals(SaleEvent sale, decimal discount, decimal tax)
    {
        sale.DiscountAmount = discount;
        sale.TaxAmount = tax;
        sale.TotalPrice = sale.Subtotal - discount + tax;
    }
}

internal sealed class TestSalesDatabase : ISalesDatabase
{
    private int _attempts;
    public int Attempts => Volatile.Read(ref _attempts);
    public Exception? Failure { get; set; }
    public Func<CancellationToken, Task>? BeforeWrite { get; set; }
    public List<SaleRecord> Recorded { get; } = [];
    public IReadOnlyList<CatalogEntry> Catalog { get; set; } = SalesTestData.Shop().Flavors
        .Select(flavor => new CatalogEntry("it-roma-001", flavor, "IT", "EUR", "Europe/Rome")).ToArray();

    public async Task RecordAsync(SaleRecord sale, CancellationToken ct)
    {
        Interlocked.Increment(ref _attempts);
        if (BeforeWrite is not null) await BeforeWrite(ct);
        ct.ThrowIfCancellationRequested();
        if (Failure is not null) throw Failure;
        lock (Recorded) Recorded.Add(sale);
    }

    public Task<IReadOnlyList<CatalogEntry>> ReadCatalogAsync(CancellationToken ct)
    {
        ct.ThrowIfCancellationRequested();
        if (Failure is not null) throw Failure;
        return Task.FromResult(Catalog);
    }
}

internal sealed class TestDatabaseException(string message) : DbException(message);
