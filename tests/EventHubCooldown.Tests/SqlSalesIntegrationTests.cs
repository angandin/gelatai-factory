using System.Text.RegularExpressions;
using ApiShop.Models;
using ApiShop.Services;
using Microsoft.Data.SqlClient;

namespace EventHubCooldown.Tests;

public sealed class LocalSalesDatabase : IAsyncLifetime
{
    private readonly string _name = "GelataiSalesTest_" + Guid.NewGuid().ToString("N");
    private const string Master = @"Server=(localdb)\MSSQLLocalDB;Database=master;Integrated Security=true;Encrypt=false;Connect Timeout=60";
    private bool _created;
    public string ConnectionString => new SqlConnectionStringBuilder(Master) { InitialCatalog = _name }.ConnectionString;

    public async Task InitializeAsync()
    {
        await ExecuteAsync(Master, $"CREATE DATABASE [{_name}]");
        _created = true;
        try
        {
            foreach (var script in new[] { "schema.sql", "seed-apishop.sql", "sales-schema.sql" })
                await ApplyAsync(script);
        }
        catch (SqlException)
        {
            await DisposeAsync();
            throw;
        }
    }

    public async Task ApplyAsync(string script)
    {
        var sql = await File.ReadAllTextAsync(Path.Combine(AppContext.BaseDirectory, "Sql", script));
        foreach (var batch in Regex.Split(sql, @"(?im)^\s*GO\s*$").Where(batch => !string.IsNullOrWhiteSpace(batch)))
            await ExecuteAsync(ConnectionString, batch);
    }

    public static async Task ExecuteAsync(string connectionString, string sql)
    {
        await using var connection = new SqlConnection(connectionString);
        await connection.OpenAsync();
        await using var command = new SqlCommand(sql, connection);
        await command.ExecuteNonQueryAsync();
    }

    public async Task<long> CountAsync(string table, Guid transactionId)
    {
        Assert.Contains(table, new[] { "Sale", "SaleItem" });
        await using var connection = new SqlConnection(ConnectionString);
        await connection.OpenAsync();
        var query = table == "Sale"
            ? "SELECT COUNT_BIG(*) FROM dbo.Sale WHERE TransactionId=@id"
            : "SELECT COUNT_BIG(*) FROM dbo.SaleItem AS i JOIN dbo.Sale AS s ON s.SaleId=i.SaleId WHERE s.TransactionId=@id";
        await using var command = new SqlCommand(query, connection);
        command.Parameters.Add("@id", System.Data.SqlDbType.UniqueIdentifier).Value = transactionId;
        return Assert.IsType<long>(await command.ExecuteScalarAsync());
    }

    public async Task DisposeAsync()
    {
        if (!_created) return;
        using var pool = new SqlConnection(ConnectionString);
        SqlConnection.ClearPool(pool);
        await ExecuteAsync(Master, $"ALTER DATABASE [{_name}] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE [{_name}]");
        _created = false;
    }
}

[Trait("Category", "LocalSql")]
public sealed class SqlSalesIntegrationTests(LocalSalesDatabase fixture) : IClassFixture<LocalSalesDatabase>
{
    [Fact]
    public async Task HeaderAndLinesAreWrittenAtomicallyAndDuplicateRetriesDoNotDuplicate()
    {
        var database = new SqlSalesDatabase(fixture.ConnectionString);
        var sale = SalesTestData.Sale();
        SalesTestData.SetTotals(sale, 0.9m, 0.81m);
        var record = SaleRecord.FromSale(SalesTestData.Shop(), sale);
        await database.RecordAsync(record, default);
        await database.RecordAsync(record, default);
        Assert.Equal(1, await fixture.CountAsync("Sale", record.TransactionId));
        Assert.Equal(3, await fixture.CountAsync("SaleItem", record.TransactionId));
        var error = await Assert.ThrowsAsync<SqlException>(() =>
            database.RecordAsync(record with { City = "Different city" }, default));
        Assert.Equal(51003, error.Number);
    }

    [Fact]
    public async Task RegisteredDollarAndYenSalesPersistWithCorrectShopTimeZones()
    {
        foreach (var currency in new[] { "USD", "JPY" })
        {
            var shop = SalesTestData.Shop(currency);
            shop.Id = currency == "USD" ? "us-nyc-001" : "jp-tokyo-001";
            shop.CountryCode = currency == "USD" ? "US" : "JP";
            shop.City = currency == "USD" ? "New York" : "Tokyo";
            shop.TimeZoneId = currency == "USD" ? "America/New_York" : "Asia/Tokyo";
            shop.Flavors = currency == "USD" ? ["Vanilla", "Chocolate"] : ["Matcha", "Black Sesame"];
            var sale = SalesTestData.Sale(currency, 11m, 23m);
            sale.ShopId = shop.Id;
            sale.CountryCode = shop.CountryCode;
            sale.City = shop.City;
            sale.TimestampLocal = currency == "USD"
                ? "2026-10-28T19:30:00.1234567-04:00" : "2026-10-29T08:30:00.1234567+09:00";
            for (var index = 0; index < sale.Flavors.Count; index++)
                sale.Flavors[index].Flavor = shop.Flavors[index];
            SalesTestData.SetTotals(sale, 1m, 2m);
            var record = SaleRecord.FromSale(shop, sale);
            await new SqlSalesDatabase(fixture.ConnectionString).RecordAsync(record, default);
            await using var connection = new SqlConnection(fixture.ConnectionString);
            await connection.OpenAsync();
            await using var command = new SqlCommand("""
                SELECT s.CurrencyCode,s.UtcOffsetMinutes,s.TotalAmount,SUM(i.TotalAmount)
                FROM dbo.Sale AS s JOIN dbo.SaleItem AS i ON i.SaleId=s.SaleId
                WHERE s.TransactionId=@id
                GROUP BY s.CurrencyCode,s.UtcOffsetMinutes,s.TotalAmount
                """, connection);
            command.Parameters.Add("@id", System.Data.SqlDbType.UniqueIdentifier).Value = record.TransactionId;
            await using var reader = await command.ExecuteReaderAsync();
            Assert.True(await reader.ReadAsync());
            Assert.Equal(currency, reader.GetString(0));
            Assert.Equal(currency == "USD" ? -240 : 540, reader.GetInt16(1));
            Assert.Equal(35m, reader.GetDecimal(2));
            Assert.Equal(reader.GetDecimal(2), reader.GetDecimal(3));
        }
    }

    [Fact]
    public async Task ConcurrentDuplicateRequestsProduceOnlyOneTransaction()
    {
        var database = new SqlSalesDatabase(fixture.ConnectionString);
        var record = SaleRecord.FromSale(SalesTestData.Shop(), SalesTestData.Sale());
        await Task.WhenAll(Enumerable.Range(0, 8).Select(_ => database.RecordAsync(record, default)));
        Assert.Equal(1, await fixture.CountAsync("Sale", record.TransactionId));
        Assert.Equal(3, await fixture.CountAsync("SaleItem", record.TransactionId));
    }

    [Fact]
    public async Task InvalidLineRollsBackTheAlreadyInsertedHeader()
    {
        var database = new SqlSalesDatabase(fixture.ConnectionString);
        var record = SaleRecord.FromSale(SalesTestData.Shop(), SalesTestData.Sale());
        var items = record.Items.ToArray();
        items[^1] = items[^1] with { UnitPrice = items[^1].UnitPrice + 1 };
        await Assert.ThrowsAsync<SqlException>(() => database.RecordAsync(record with { Items = items }, default));
        Assert.Equal(0, await fixture.CountAsync("Sale", record.TransactionId));
        Assert.Equal(0, await fixture.CountAsync("SaleItem", record.TransactionId));
    }

    [Fact]
    public async Task UnknownRegistryKeysAreRejectedWithoutPartialFacts()
    {
        var database = new SqlSalesDatabase(fixture.ConnectionString);
        var record = SaleRecord.FromSale(SalesTestData.Shop(), SalesTestData.Sale());
        var error = await Assert.ThrowsAsync<SqlException>(() =>
            database.RecordAsync(record with { ShopKey = "unknown" }, default));
        Assert.Equal(51002, error.Number);
        var items = record.Items.ToArray();
        items[0] = items[0] with { Flavor = "unknown" };
        await Assert.ThrowsAsync<SqlException>(() => database.RecordAsync(record with { Items = items }, default));
        Assert.Equal(0, await fixture.CountAsync("Sale", record.TransactionId));
    }

    [Fact]
    public async Task MigrationAndBaseSchemaCanBeRerunWithoutLosingSales()
    {
        var database = new SqlSalesDatabase(fixture.ConnectionString);
        var record = SaleRecord.FromSale(SalesTestData.Shop(), SalesTestData.Sale());
        await database.RecordAsync(record, default);
        await fixture.ApplyAsync("schema.sql");
        await fixture.ApplyAsync("sales-schema.sql");
        await fixture.ApplyAsync("sales-schema.sql");
        Assert.Equal(1, await fixture.CountAsync("Sale", record.TransactionId));
        Assert.Equal(3, await fixture.CountAsync("SaleItem", record.TransactionId));
        var catalog = await database.ReadCatalogAsync(default);
        Assert.Equal(48, catalog.Count);
    }

    [Fact]
    public async Task ReportingGrainsReconcileWithoutRepeatingHeaderAmounts()
    {
        var database = new SqlSalesDatabase(fixture.ConnectionString);
        var sale = SalesTestData.Sale();
        SalesTestData.SetTotals(sale, 0.01m, 0.02m);
        var record = SaleRecord.FromSale(SalesTestData.Shop(), sale);
        await database.RecordAsync(record, default);
        await using var connection = new SqlConnection(fixture.ConnectionString);
        await connection.OpenAsync();
        await using var command = new SqlCommand("""
            SELECT s.NetSalesAmount,s.TotalAmount,s.SaleDateLocal,
                (SELECT SUM(i.NetSalesAmount) FROM dbo.vw_SaleItems AS i WHERE i.TransactionId=s.TransactionId),
                (SELECT SUM(i.TotalAmount) FROM dbo.vw_SaleItems AS i WHERE i.TransactionId=s.TransactionId)
            FROM dbo.vw_Sales AS s WHERE s.TransactionId=@id
            """, connection);
        command.Parameters.Add("@id", System.Data.SqlDbType.UniqueIdentifier).Value = record.TransactionId;
        await using var reader = await command.ExecuteReaderAsync();
        Assert.True(await reader.ReadAsync());
        Assert.Equal(record.NetSalesAmount, reader.GetDecimal(0));
        Assert.Equal(record.TotalAmount, reader.GetDecimal(1));
        Assert.Equal(record.SaleDateLocal, DateOnly.FromDateTime(reader.GetDateTime(2)));
        Assert.Equal(reader.GetDecimal(0), reader.GetDecimal(3));
        Assert.Equal(reader.GetDecimal(1), reader.GetDecimal(4));
    }
}
