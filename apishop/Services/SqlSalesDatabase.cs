using System.Data;
using System.Text.Json;
using ApiShop.Models;
using Azure.Core;
using Microsoft.Data.SqlClient;

namespace ApiShop.Services;

public sealed class SqlSalesDatabase : ISalesDatabase
{
    private readonly string _connectionString;
    private readonly Func<SqlAuthenticationParameters, CancellationToken, Task<SqlAuthenticationToken>>? _tokenCallback;

    public SqlSalesDatabase(string connectionString, TokenCredential? credential = null)
    {
        _connectionString = connectionString;
        if (credential is not null)
        {
            _tokenCallback = async (parameters, ct) =>
            {
                var scope = parameters.Resource.TrimEnd('/') + "/.default";
                var token = await credential.GetTokenAsync(new TokenRequestContext([scope]), ct);
                return new SqlAuthenticationToken(token.Token, token.ExpiresOn);
            };
        }
    }

    public async Task RecordAsync(SaleRecord sale, CancellationToken ct)
    {
        await using var connection = CreateConnection();
        await connection.OpenAsync(ct);
        await using var command = new SqlCommand("dbo.RecordApiShopSale", connection)
        {
            CommandType = CommandType.StoredProcedure
        };
        command.Parameters.Add("@Sale", SqlDbType.NVarChar, -1).Value = JsonSerializer.Serialize(sale);
        await command.ExecuteScalarAsync(ct);
    }

    public async Task<IReadOnlyList<CatalogEntry>> ReadCatalogAsync(CancellationToken ct)
    {
        await using var connection = CreateConnection();
        await connection.OpenAsync(ct);
        await using var command = new SqlCommand("""
            SELECT m.ApiShopShopId,m.ApiShopFlavor,m.CountryCode,m.CurrencyCode,s.TimeZoneId
            FROM dbo.vw_ApiShopCatalogMatch AS m
            JOIN dbo.Shop AS s ON s.ShopId=m.ShopId
            """, connection);
        await using var reader = await command.ExecuteReaderAsync(ct);
        var result = new List<CatalogEntry>();
        while (await reader.ReadAsync(ct))
            result.Add(new CatalogEntry(reader.GetString(0), reader.GetString(1),
                reader.GetString(2), reader.GetString(3), reader.GetString(4)));
        return result;
    }

    private SqlConnection CreateConnection()
    {
        var connection = new SqlConnection(_connectionString);
        if (_tokenCallback is not null)
            connection.AccessTokenCallback = _tokenCallback;
        return connection;
    }
}
