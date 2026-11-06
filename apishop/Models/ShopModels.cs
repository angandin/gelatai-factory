namespace ApiShop.Models;

public sealed class ShopDefinition
{
    public required string Id { get; set; }
    public required string Name { get; set; }
    public required string City { get; set; }
    public required string CountryCode { get; set; }
    public required string Currency { get; set; }
    public required string TimeZoneId { get; set; }
    public double Latitude { get; set; }
    public double Longitude { get; set; }
    public decimal MinItemPrice { get; set; }
    public decimal MaxItemPrice { get; set; }
    public List<string> Flavors { get; set; } = [];
}

public sealed class SimulatorConfig
{
    public List<ShopDefinition> Shops { get; set; } = [];
}

public enum ShopState
{
    Closed,
    Open,
    Rush,
    OutsideHours
}

public sealed class ShopStatus
{
    public required string Id { get; set; }
    public required string Name { get; set; }
    public required string City { get; set; }
    public required string CountryCode { get; set; }
    public required string Currency { get; set; }
    public ShopState State { get; set; }
    public int IntervalSeconds { get; set; }
    public long SalesSent { get; set; }
    public decimal Revenue { get; set; }
}

public sealed class ShopPersistedState
{
    public required string Id { get; set; }
    public ShopState State { get; set; }
}

public sealed class SaleFlavor
{
    public required string Flavor { get; set; }
    public int Scoops { get; set; }
    public decimal UnitPrice { get; set; }
    public decimal LineTotal { get; set; }
}

public sealed class SaleEvent
{
    public required string EventType { get; set; }
    public required string TransactionId { get; set; }
    public required string ShopId { get; set; }
    public required string ShopName { get; set; }
    public required string City { get; set; }
    public required string CountryCode { get; set; }
    public double Latitude { get; set; }
    public double Longitude { get; set; }
    public required string Currency { get; set; }
    public required string TimestampUtc { get; set; }
    public required string TimestampLocal { get; set; }
    public required string ServingType { get; set; }
    public required string SalesChannel { get; set; }
    public required string PaymentMethod { get; set; }
    public required string Weather { get; set; }
    public double TemperatureC { get; set; }
    public List<SaleFlavor> Flavors { get; set; } = [];
    public int FlavorCount { get; set; }
    public int TotalScoops { get; set; }
    public decimal Subtotal { get; set; }
    public decimal DiscountAmount { get; set; }
    public decimal TaxAmount { get; set; }
    public decimal TotalPrice { get; set; }
}
