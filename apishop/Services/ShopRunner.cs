using ApiShop.Models;

namespace ApiShop.Services;

public sealed class ShopRunner
{
    private static readonly string[] ServingTypes = ["cup", "cone", "takeaway_tub"];
    private static readonly string[] SalesChannels = ["counter", "delivery", "click_and_collect"];
    private static readonly string[] PaymentMethods = ["card", "cash", "mobile_wallet"];
    private static readonly (string Name, double Min, double Max)[] WeatherProfiles =
    [
        ("sunny", 20, 35), ("partly_cloudy", 14, 28), ("cloudy", 10, 23), ("rain", 7, 20)
    ];

    private readonly ShopDefinition _shop;
    private readonly ISaleWriter _saleWriter;
    private readonly ILogger _logger;
    private readonly TimeProvider _timeProvider;
    private readonly TimeZoneInfo _timeZone;
    private readonly Random _random = new();
    private volatile bool _running;
    private volatile bool _rush;
    private CancellationTokenSource? _cancellation;
    private Task? _task;

    public ShopState RequestedState => !_running ? ShopState.Closed : _rush ? ShopState.Rush : ShopState.Open;
    public ShopState State => !_running ? ShopState.Closed :
        !IsWithinWorkHours(_timeProvider.GetUtcNow()) ? ShopState.OutsideHours : RequestedState;
    public int IntervalSeconds { get; private set; } = 300;
    public long SalesSent { get; private set; }
    public decimal Revenue { get; private set; }
    public SaleEvent? LastSale { get; private set; }

    public ShopRunner(ShopDefinition shop, ISaleWriter saleWriter, ILogger logger, TimeProvider timeProvider)
    {
        _shop = shop;
        _saleWriter = saleWriter;
        _logger = logger;
        _timeProvider = timeProvider;
        _timeZone = TimeZoneInfo.FindSystemTimeZoneById(shop.TimeZoneId);
    }

    public void Start()
    {
        if (_task is { IsCompleted: false }) return;
        _cancellation = new CancellationTokenSource();
        _running = true;
        _rush = false;
        _task = RunAsync(_cancellation.Token);
    }

    public void Stop()
    {
        _cancellation?.Cancel();
        _task?.Wait(TimeSpan.FromSeconds(5));
        _cancellation?.Dispose();
        _running = false;
    }

    public void SetRush(bool enabled)
    {
        if (!_running) return;
        _rush = enabled;
    }

    private async Task RunAsync(CancellationToken cancellationToken)
    {
        try
        {
            while (!cancellationToken.IsCancellationRequested)
            {
                var now = _timeProvider.GetUtcNow();
                if (!IsWithinWorkHours(now))
                {
                    var local = TimeZoneInfo.ConvertTime(now, _timeZone);
                    var nextOpening = local.Date.AddHours(9);
                    if (local.Hour >= 23) nextOpening = nextOpening.AddDays(1);
                    var openingUtc = TimeZoneInfo.ConvertTimeToUtc(nextOpening, _timeZone);
                    await Task.Delay(openingUtc - now.UtcDateTime, _timeProvider, cancellationToken);
                    continue;
                }

                IntervalSeconds = _random.Next(300, 601);
                await Task.Delay(TimeSpan.FromSeconds(IntervalSeconds), _timeProvider, cancellationToken);
                now = _timeProvider.GetUtcNow();
                if (!IsWithinWorkHours(now)) continue;
                try
                {
                    var sale = GenerateSale(now);
                    LastSale = sale;
                    if (await _saleWriter.WriteAsync(_shop, sale, cancellationToken))
                    {
                        SalesSent++;
                        Revenue += sale.TotalPrice;
                    }
                }
                catch (Exception exception) when (exception is not OperationCanceledException)
                {
                    _logger.LogError(exception, "Shop {ShopId} could not send a sale", _shop.Id);
                }
            }
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
        }
    }

    private bool IsWithinWorkHours(DateTimeOffset utcNow)
    {
        var local = TimeZoneInfo.ConvertTime(utcNow, _timeZone);
        return local.Hour >= 9 && local.Hour < 23;
    }

    private SaleEvent GenerateSale(DateTimeOffset now)
    {
        var flavorCount = WeightedFlavorCount();
        var selectedFlavors = _shop.Flavors.OrderBy(_ => _random.Next()).Take(flavorCount).ToArray();
        var servingType = Pick(ServingTypes, [65, 28, 7]);
        var lines = new List<SaleFlavor>();

        foreach (var flavor in selectedFlavors)
        {
            var scoops = _random.NextDouble() < 0.82 ? 1 : 2;
            var locationPrice = RandomMoney(_shop.MinItemPrice, _shop.MaxItemPrice);
            var formatFactor = servingType == "takeaway_tub" ? 2.4m : 1m;
            var unitPrice = RoundMoney(locationPrice * formatFactor);
            lines.Add(new SaleFlavor
            {
                Flavor = flavor,
                Scoops = scoops,
                UnitPrice = unitPrice,
                LineTotal = RoundMoney(unitPrice * scoops)
            });
        }

        var subtotal = lines.Sum(line => line.LineTotal);
        var discountRate = _random.NextDouble() < 0.12 ? 0.1m : 0m;
        var discount = RoundMoney(subtotal * discountRate);
        var taxRate = _shop.CountryCode.Equals("IT", StringComparison.OrdinalIgnoreCase) ? 0.10m : 0m;
        var tax = RoundMoney((subtotal - discount) * taxRate);
        var total = RoundMoney(subtotal - discount + tax);
        var local = TimeZoneInfo.ConvertTime(now, _timeZone);
        var weather = WeatherProfiles[_random.Next(WeatherProfiles.Length)];

        return new SaleEvent
        {
            EventType = "ice_cream_sale",
            TransactionId = Guid.NewGuid().ToString("N"),
            ShopId = _shop.Id,
            ShopName = _shop.Name,
            City = _shop.City,
            CountryCode = _shop.CountryCode,
            Latitude = _shop.Latitude,
            Longitude = _shop.Longitude,
            Currency = _shop.Currency,
            TimestampUtc = now.ToString("O"),
            TimestampLocal = local.ToString("O"),
            ServingType = servingType,
            SalesChannel = Pick(SalesChannels, [82, 12, 6]),
            PaymentMethod = Pick(PaymentMethods, [66, 24, 10]),
            Weather = weather.Name,
            TemperatureC = Math.Round(weather.Min + _random.NextDouble() * (weather.Max - weather.Min), 1),
            Flavors = lines,
            FlavorCount = lines.Count,
            TotalScoops = lines.Sum(line => line.Scoops),
            Subtotal = subtotal,
            DiscountAmount = discount,
            TaxAmount = tax,
            TotalPrice = total
        };
    }

    private int WeightedFlavorCount()
    {
        var value = _random.Next(100);
        return value switch
        {
            < 8 => 1,
            < 52 => 2,
            < 86 => 3,
            < 95 => 4,
            < 99 => 5,
            _ => 6
        };
    }

    private string Pick(string[] values, int[] weights)
    {
        var roll = _random.Next(weights.Sum());
        for (var i = 0; i < values.Length; i++)
        {
            if (roll < weights[i]) return values[i];
            roll -= weights[i];
        }
        return values[^1];
    }

    private decimal RandomMoney(decimal min, decimal max) =>
        RoundMoney(min + (decimal)_random.NextDouble() * (max - min));

    private decimal RoundMoney(decimal value)
    {
        var decimalPlaces = _shop.Currency.Equals("JPY", StringComparison.OrdinalIgnoreCase) ? 0 : 2;
        return Math.Round(value, decimalPlaces, MidpointRounding.AwayFromZero);
    }
}
