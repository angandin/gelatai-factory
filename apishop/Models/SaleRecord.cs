using System.Globalization;

namespace ApiShop.Models;

public sealed record SaleLineRecord(
    int LineNumber, string Flavor, int Scoops, decimal UnitPrice,
    decimal SubtotalAmount, decimal DiscountAmount, decimal NetSalesAmount,
    decimal TaxAmount, decimal TotalAmount);

public sealed record SaleRecord(
    Guid TransactionId, string ShopKey, DateTime TimestampUtc, DateTime TimestampLocal,
    DateOnly SaleDateLocal, short UtcOffsetMinutes, string TimeZoneId,
    string City, string CountryCode, string CurrencyCode,
    string ServingType, string SalesChannel, string PaymentMethod, string Weather,
    decimal TemperatureC, int FlavorCount, int TotalScoops,
    decimal SubtotalAmount, decimal DiscountAmount, decimal NetSalesAmount,
    decimal TaxAmount, decimal TotalAmount, IReadOnlyList<SaleLineRecord> Items)
{
    public static int CurrencyPrecision(string currency) => currency switch
    {
        "EUR" or "USD" => 2,
        "JPY" => 0,
        _ => throw new ArgumentException($"Unsupported currency '{currency}'.", nameof(currency))
    };

    public static SaleRecord FromSale(ShopDefinition shop, SaleEvent sale)
    {
        var precision = CurrencyPrecision(sale.Currency);
        if (sale.ShopId != shop.Id || sale.Currency != shop.Currency ||
            sale.CountryCode != shop.CountryCode || !Guid.TryParse(sale.TransactionId, out var transactionId))
            throw new ArgumentException("Sale identity and currency must match its configured shop.");
        var utc = DateTimeOffset.Parse(sale.TimestampUtc, CultureInfo.InvariantCulture, DateTimeStyles.RoundtripKind);
        var local = DateTimeOffset.Parse(sale.TimestampLocal, CultureInfo.InvariantCulture, DateTimeStyles.RoundtripKind);
        var expectedLocal = TimeZoneInfo.ConvertTime(utc, TimeZoneInfo.FindSystemTimeZoneById(shop.TimeZoneId));
        if (utc.Offset != TimeSpan.Zero || utc != local || local.Offset != expectedLocal.Offset)
            throw new ArgumentException("Sale timestamps must represent the same instant in the shop time zone.");
        if (sale.Flavors.Count is < 1 or > 6 || sale.FlavorCount != sale.Flavors.Count ||
            sale.TotalScoops != sale.Flavors.Sum(line => line.Scoops) ||
            sale.Flavors.Select(line => line.Flavor).Distinct(StringComparer.OrdinalIgnoreCase).Count() != sale.FlavorCount)
            throw new ArgumentException("Sale flavor and scoop counts do not reconcile.");

        var amounts = sale.Flavors.Select(line => line.LineTotal).ToArray();
        if (sale.Flavors.Any(line => line.Scoops <= 0 || line.UnitPrice <= 0 ||
                line.LineTotal != line.UnitPrice * line.Scoops || !HasPrecision(line.UnitPrice, precision)) ||
            amounts.Any(amount => amount <= 0 || !HasPrecision(amount, precision)) ||
            amounts.Sum() != sale.Subtotal || sale.DiscountAmount < 0 || sale.DiscountAmount > sale.Subtotal ||
            sale.TaxAmount < 0 || sale.TotalPrice != sale.Subtotal - sale.DiscountAmount + sale.TaxAmount ||
            !HasPrecision(sale.DiscountAmount, precision) || !HasPrecision(sale.TaxAmount, precision))
            throw new ArgumentException("Sale monetary amounts do not reconcile at the currency precision.");

        var discounts = Allocate(sale.DiscountAmount, amounts, precision);
        var taxes = Allocate(sale.TaxAmount, amounts, precision);
        var items = sale.Flavors.Select((line, index) => new SaleLineRecord(
            index + 1, line.Flavor, line.Scoops, line.UnitPrice, line.LineTotal,
            discounts[index], line.LineTotal - discounts[index], taxes[index],
            line.LineTotal - discounts[index] + taxes[index])).ToArray();
        return new SaleRecord(transactionId, shop.Id, Microseconds(utc.UtcDateTime),
            Microseconds(local.DateTime), DateOnly.FromDateTime(local.DateTime),
            checked((short)local.Offset.TotalMinutes), shop.TimeZoneId,
            sale.City, sale.CountryCode, sale.Currency, sale.ServingType, sale.SalesChannel,
            sale.PaymentMethod, sale.Weather, Convert.ToDecimal(sale.TemperatureC),
            sale.FlavorCount, sale.TotalScoops, sale.Subtotal, sale.DiscountAmount,
            sale.Subtotal - sale.DiscountAmount, sale.TaxAmount, sale.TotalPrice, items);
    }

    private static bool HasPrecision(decimal amount, int precision) => decimal.Round(amount, precision) == amount;

    private static DateTime Microseconds(DateTime value) => value.AddTicks(-(value.Ticks % 10));

    private static decimal[] Allocate(decimal amount, decimal[] weights, int precision)
    {
        var factor = precision == 0 ? 1m : 100m;
        var units = amount * factor;
        var total = weights.Sum();
        var quotas = weights.Select(weight => units * weight / total).ToArray();
        var allocated = quotas.Select(decimal.Floor).ToArray();
        var remainder = checked((int)(units - allocated.Sum()));
        foreach (var index in Enumerable.Range(0, weights.Length)
            .OrderByDescending(index => quotas[index] - allocated[index])
            .ThenBy(index => index).Take(remainder))
            allocated[index]++;
        return allocated.Select(value => value / factor).ToArray();
    }
}
