using System.Collections.Concurrent;
using System.Text.Json;
using ApiShop.Models;

namespace ApiShop.Services;

public sealed class ShopSimulatorManager(
    ISaleWriter saleWriter,
    ILogger<ShopSimulatorManager> logger,
    IDataStore store,
    TimeProvider timeProvider)
{
    private const string StateFileName = "shop-state.json";
    private readonly ConcurrentDictionary<string, ShopRunner> _runners = new();
    private SimulatorConfig _config = new();
    private bool _suppressPersist;

    public SimulatorConfig GetConfig() => _config;

    public void UpdateConfig(SimulatorConfig config)
    {
        _suppressPersist = true;
        StopAll();
        _suppressPersist = false;
        _config = config;
    }

    public bool StartShop(string shopId)
    {
        var shop = _config.Shops.FirstOrDefault(candidate => candidate.Id == shopId);
        if (shop is null || _runners.ContainsKey(shopId)) return false;
        var runner = new ShopRunner(shop, saleWriter, logger, timeProvider);
        if (!_runners.TryAdd(shopId, runner)) return false;
        runner.Start();
        PersistState();
        return true;
    }

    public bool StopShop(string shopId)
    {
        if (!_runners.TryRemove(shopId, out var runner)) return false;
        runner.Stop();
        PersistState();
        return true;
    }

    public bool SetRush(string shopId, bool enabled)
    {
        if (!_runners.TryGetValue(shopId, out var runner)) return false;
        runner.SetRush(enabled);
        PersistState();
        return true;
    }

    public void StartAll()
    {
        _suppressPersist = true;
        foreach (var shop in _config.Shops) StartShop(shop.Id);
        _suppressPersist = false;
        RestoreState();
    }

    public void StopAll()
    {
        foreach (var id in _runners.Keys.ToArray()) StopShop(id);
    }

    public List<ShopStatus> GetAllStatus() => _config.Shops.Select(GetStatus).ToList();

    public ShopStatus? GetShopStatus(string shopId)
    {
        var shop = _config.Shops.FirstOrDefault(candidate => candidate.Id == shopId);
        return shop is null ? null : GetStatus(shop);
    }

    public SaleEvent? GetLatestSale(string shopId) =>
        _runners.TryGetValue(shopId, out var runner) ? runner.LastSale : null;

    private ShopStatus GetStatus(ShopDefinition shop)
    {
        var running = _runners.TryGetValue(shop.Id, out var runner);
        return new ShopStatus
        {
            Id = shop.Id,
            Name = shop.Name,
            City = shop.City,
            CountryCode = shop.CountryCode,
            Currency = shop.Currency,
            State = running ? runner!.State : ShopState.Closed,
            IntervalSeconds = running ? runner!.IntervalSeconds : 300,
            SalesSent = running ? runner!.SalesSent : 0,
            Revenue = running ? runner!.Revenue : 0
        };
    }

    private void PersistState()
    {
        if (_suppressPersist) return;
        try
        {
            var states = _config.Shops.Select(shop => new ShopPersistedState
            {
                Id = shop.Id,
                State = _runners.TryGetValue(shop.Id, out var runner) ? runner.RequestedState : ShopState.Closed
            });
            store.Write(StateFileName, JsonSerializer.Serialize(states, new JsonSerializerOptions { WriteIndented = true }));
        }
        catch (Exception exception)
        {
            logger.LogWarning(exception, "Could not persist shop state");
        }
    }

    private void RestoreState()
    {
        if (!store.Exists(StateFileName)) return;
        try
        {
            var json = store.Read(StateFileName);
            var states = json is null ? null : JsonSerializer.Deserialize<List<ShopPersistedState>>(json);
            if (states is null) return;
            foreach (var state in states)
            {
                if (state.State == ShopState.Closed) StopShop(state.Id);
                else if (state.State == ShopState.Rush) SetRush(state.Id, true);
            }
        }
        catch (Exception exception)
        {
            logger.LogWarning(exception, "Could not restore shop state");
        }
    }
}
