using System.Text;
using Azure;
using Azure.Identity;
using Azure.Storage.Files.Shares;
using Azure.Storage.Files.Shares.Models;

namespace ApiFactory.Services;

/// <summary>
/// Abstraction for persisting small JSON documents (config + state).
/// Implementations target either the local filesystem or Azure Files via REST + managed identity.
/// </summary>
public interface IDataStore
{
    bool Exists(string name);
    string? Read(string name);
    void Write(string name, string content);
}

/// <summary>
/// Local filesystem store. Used for development or when no storage account is configured.
/// </summary>
public class LocalDataStore : IDataStore
{
    private readonly string _dir;

    public LocalDataStore(string dir)
    {
        _dir = dir;
        if (!Directory.Exists(_dir)) Directory.CreateDirectory(_dir);
    }

    public bool Exists(string name) => File.Exists(Path.Combine(_dir, name));

    public string? Read(string name)
    {
        var path = Path.Combine(_dir, name);
        return File.Exists(path) ? File.ReadAllText(path) : null;
    }

    public void Write(string name, string content) => File.WriteAllText(Path.Combine(_dir, name), content);
}

/// <summary>
/// Azure Files store that authenticates with a managed identity (OAuth) over the FileREST API.
/// Requires the identity to hold the "Storage File Data Privileged Contributor" role on the account.
/// No storage account key is used, so it works when shared-key access is disabled by policy.
/// </summary>
public class AzureFileShareDataStore : IDataStore
{
    private readonly ShareClient _share;
    private readonly ILogger<AzureFileShareDataStore> _logger;

    public AzureFileShareDataStore(string accountName, string shareName, ILogger<AzureFileShareDataStore> logger)
    {
        _logger = logger;

        // DefaultAzureCredential picks up the user-assigned identity via AZURE_CLIENT_ID when set.
        var credential = new DefaultAzureCredential();
        var serviceUri = new Uri($"https://{accountName}.file.core.windows.net");
        var options = new ShareClientOptions
        {
            // Required for OAuth/token-based access to the FileREST data plane.
            ShareTokenIntent = ShareTokenIntent.Backup
        };

        var serviceClient = new ShareServiceClient(serviceUri, credential, options);
        _share = serviceClient.GetShareClient(shareName);
    }

    private ShareFileClient GetFile(string name) => _share.GetRootDirectoryClient().GetFileClient(name);

    public bool Exists(string name)
    {
        try
        {
            return GetFile(name).Exists();
        }
        catch (RequestFailedException ex)
        {
            _logger.LogWarning(ex, "Exists check failed for {Name}", name);
            return false;
        }
    }

    public string? Read(string name)
    {
        var file = GetFile(name);
        if (!file.Exists()) return null;

        ShareFileDownloadInfo download = file.Download();
        using var reader = new StreamReader(download.Content, Encoding.UTF8);
        return reader.ReadToEnd();
    }

    public void Write(string name, string content)
    {
        var file = GetFile(name);
        var bytes = Encoding.UTF8.GetBytes(content);

        // Create (or resize) the file to the exact payload length, then write from offset 0.
        file.Create(bytes.Length);
        if (bytes.Length > 0)
        {
            using var ms = new MemoryStream(bytes);
            file.UploadRange(new HttpRange(0, bytes.Length), ms);
        }
    }
}
