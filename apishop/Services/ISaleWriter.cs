using System.Data.Common;
using System.Text.Json;
using ApiShop.Models;
using Azure.Identity;

namespace ApiShop.Services;

public sealed record CatalogEntry(
    string ShopKey, string Flavor, string CountryCode, string CurrencyCode, string TimeZoneId);

public sealed record CatalogValidationResult(bool IsAvailable, IReadOnlyList<string> Errors);

public interface ISalesDatabase
{
    Task RecordAsync(SaleRecord sale, CancellationToken ct);
    Task<IReadOnlyList<CatalogEntry>> ReadCatalogAsync(CancellationToken ct);
}

public interface ISaleWriter
{
    Task<bool> WriteAsync(ShopDefinition shop, SaleEvent sale, CancellationToken ct = default);
    Task<CatalogValidationResult> ValidateConfigurationAsync(SimulatorConfig config, CancellationToken ct = default);
}

public sealed class ConsoleSaleWriter(ILogger<ConsoleSaleWriter> logger) : ISaleWriter
{
    public Task<bool> WriteAsync(ShopDefinition shop, SaleEvent sale, CancellationToken ct = default)
    {
        ct.ThrowIfCancellationRequested();
        logger.LogInformation("[Sale] {ShopId}: {Payload}", shop.Id, JsonSerializer.Serialize(sale));
        return Task.FromResult(true);
    }

    public Task<CatalogValidationResult> ValidateConfigurationAsync(SimulatorConfig config, CancellationToken ct = default)
        => Task.FromResult(new CatalogValidationResult(true, []));
}

public sealed class SqlSaleWriter(
    ISalesDatabase database,
    ILogger<SqlSaleWriter> logger,
    TimeProvider timeProvider) : ISaleWriter
{
    private static readonly TimeSpan ErrorLogCooldown = TimeSpan.FromMinutes(30);
    private readonly object _errorLogLock = new();
    private long? _lastErrorLoggedAt;

    public async Task<bool> WriteAsync(ShopDefinition shop, SaleEvent sale, CancellationToken ct = default)
    {
        ct.ThrowIfCancellationRequested();
        var record = SaleRecord.FromSale(shop, sale);
        try
        {
            await database.RecordAsync(record, ct);
            return true;
        }
        catch (Exception ex) when (IsDatabaseFailure(ex, ct))
        {
            LogFailure(ex);
            return false;
        }
    }

    public async Task<CatalogValidationResult> ValidateConfigurationAsync(SimulatorConfig config, CancellationToken ct = default)
    {
        try
        {
            var catalog = await database.ReadCatalogAsync(ct);
            var errors = new List<string>();
            foreach (var shop in config.Shops)
            {
                var registered = catalog.Where(row =>
                    row.ShopKey.Equals(shop.Id, StringComparison.OrdinalIgnoreCase)).ToArray();
                if (registered.Length == 0)
                {
                    errors.Add($"Shop '{shop.Id}' is not in the active SQL registry.");
                    continue;
                }
                if (registered.Any(row => row.CountryCode != shop.CountryCode ||
                    row.CurrencyCode != shop.Currency || row.TimeZoneId != shop.TimeZoneId))
                    errors.Add($"Shop '{shop.Id}' country, currency, or time zone does not match the SQL registry.");
                foreach (var flavor in shop.Flavors)
                    if (!registered.Any(row => row.Flavor.Equals(flavor, StringComparison.OrdinalIgnoreCase)))
                        errors.Add($"Flavor '{flavor}' is not in the active assortment for shop '{shop.Id}'.");
            }
            return new CatalogValidationResult(true, errors);
        }
        catch (Exception ex) when (IsDatabaseFailure(ex, ct))
        {
            LogFailure(ex);
            return new CatalogValidationResult(false, []);
        }
    }

    private static bool IsDatabaseFailure(Exception exception, CancellationToken ct) =>
        !ct.IsCancellationRequested && exception is DbException or IOException or TimeoutException
            or AuthenticationFailedException or OperationCanceledException;

    private void LogFailure(Exception exception)
    {
        lock (_errorLogLock)
        {
            if (_lastErrorLoggedAt is long loggedAt && timeProvider.GetElapsedTime(loggedAt) < ErrorLogCooldown)
                return;
            _lastErrorLoggedAt = timeProvider.GetTimestamp();
            var error = exception.GetBaseException();
            var message = error.Message.ReplaceLineEndings(" ");
            logger.LogError(
                "SQL sale operation failed ({ErrorType}): {Message}. Write attempts continue; further SQL errors are not logged for 30 minutes.",
                error.GetType().Name, message.Length > 512 ? message[..512] : message);
        }
    }
}
