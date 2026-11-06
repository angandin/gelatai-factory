using ApiShop.Models;

namespace EventHubCooldown.Tests;

public sealed class SaleRecordTests
{
    [Theory]
    [InlineData("EUR", 2)]
    [InlineData("USD", 2)]
    [InlineData("JPY", 0)]
    public void AllocationReconcilesEveryHeaderAtCurrencyPrecision(string currency, int precision)
    {
        var random = new Random(23);
        for (var count = 1; count <= 6; count++)
        for (var iteration = 0; iteration < 50; iteration++)
        {
            var prices = Enumerable.Range(0, count).Select(_ => (decimal)random.Next(1, 200)).ToArray();
            var sale = SalesTestData.Sale(currency, prices);
            SalesTestData.SetTotals(sale,
                decimal.Round(sale.Subtotal * 0.1m, precision, MidpointRounding.AwayFromZero),
                decimal.Round(sale.Subtotal * 0.09m, precision, MidpointRounding.AwayFromZero));
            var record = SaleRecord.FromSale(SalesTestData.Shop(currency), sale);
            Assert.Equal(sale.Subtotal, record.Items.Sum(item => item.SubtotalAmount));
            Assert.Equal(sale.DiscountAmount, record.Items.Sum(item => item.DiscountAmount));
            Assert.Equal(sale.TaxAmount, record.Items.Sum(item => item.TaxAmount));
            Assert.Equal(sale.TotalPrice, record.Items.Sum(item => item.TotalAmount));
            Assert.Equal(record.NetSalesAmount, record.Items.Sum(item => item.NetSalesAmount));
            Assert.All(record.Items, item =>
            {
                Assert.Equal(decimal.Round(item.DiscountAmount, precision), item.DiscountAmount);
                Assert.Equal(decimal.Round(item.TaxAmount, precision), item.TaxAmount);
                Assert.InRange(item.DiscountAmount, 0, item.SubtotalAmount);
            });
        }
    }

    [Fact]
    public void EqualRemaindersAreAllocatedDeterministicallyInLineOrder()
    {
        var sale = SalesTestData.Sale("EUR", 1, 1, 1);
        SalesTestData.SetTotals(sale, 0.01m, 0.02m);
        var record = SaleRecord.FromSale(SalesTestData.Shop(), sale);
        Assert.Equal([0.01m, 0m, 0m], record.Items.Select(item => item.DiscountAmount));
        Assert.Equal([0.01m, 0.01m, 0m], record.Items.Select(item => item.TaxAmount));
    }

    [Fact]
    public void FullDiscountAndUnequalWeightsCannotCreateNegativeNetSales()
    {
        var sale = SalesTestData.Sale("EUR", 0.01m, 0.02m, 0.99m);
        SalesTestData.SetTotals(sale, sale.Subtotal, 0);
        var record = SaleRecord.FromSale(SalesTestData.Shop(), sale);
        Assert.All(record.Items, item => Assert.Equal(0, item.NetSalesAmount));
    }

    [Fact]
    public void TypedTimestampsPreserveLocalTradingDayAndMicrosecondPrecision()
    {
        var record = SaleRecord.FromSale(SalesTestData.Shop(), SalesTestData.Sale());
        Assert.Equal(new DateOnly(2026, 10, 29), record.SaleDateLocal);
        Assert.Equal(28, record.TimestampUtc.Day);
        Assert.Equal(60, record.UtcOffsetMinutes);
        Assert.Equal(0, record.TimestampUtc.Ticks % 10);
        Assert.Equal(record.TimestampUtc.AddHours(1), record.TimestampLocal);
    }

    [Fact]
    public void InvalidReceiptsFailExplicitly()
    {
        var sale = SalesTestData.Sale();
        sale.TotalPrice++;
        Assert.Throws<ArgumentException>(() => SaleRecord.FromSale(SalesTestData.Shop(), sale));
        sale = SalesTestData.Sale("JPY", 1.01m);
        Assert.Throws<ArgumentException>(() => SaleRecord.FromSale(SalesTestData.Shop("JPY"), sale));
        sale = SalesTestData.Sale();
        sale.TimestampLocal = "2026-10-29T02:30:00+03:00";
        Assert.Throws<ArgumentException>(() => SaleRecord.FromSale(SalesTestData.Shop(), sale));
        Assert.Throws<ArgumentException>(() => SaleRecord.CurrencyPrecision("UNKNOWN"));
    }
}
