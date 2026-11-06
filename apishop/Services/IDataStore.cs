using System.Text;
using Azure;
using Azure.Identity;
using Azure.Storage.Files.Shares;
using Azure.Storage.Files.Shares.Models;

namespace ApiShop.Services;

public interface IDataStore
{
    bool Exists(string name);
    string? Read(string name);
    void Write(string name, string content);
}

public sealed class LocalDataStore : IDataStore
{
    private readonly string _directory;

    public LocalDataStore(string directory)
    {
        _directory = directory;
        Directory.CreateDirectory(_directory);
    }

    public bool Exists(string name) => File.Exists(Path.Combine(_directory, name));
    public string? Read(string name) => Exists(name) ? File.ReadAllText(Path.Combine(_directory, name)) : null;
    public void Write(string name, string content) => File.WriteAllText(Path.Combine(_directory, name), content);
}

public sealed class AzureFileShareDataStore : IDataStore
{
    private readonly ShareClient _share;
    private readonly ILogger<AzureFileShareDataStore> _logger;

    public AzureFileShareDataStore(string accountName, string shareName, ILogger<AzureFileShareDataStore> logger)
    {
        _logger = logger;
        var options = new ShareClientOptions { ShareTokenIntent = ShareTokenIntent.Backup };
        var service = new ShareServiceClient(
            new Uri($"https://{accountName}.file.core.windows.net"),
            new DefaultAzureCredential(),
            options);
        _share = service.GetShareClient(shareName);
    }

    private ShareFileClient GetFile(string name) => _share.GetRootDirectoryClient().GetFileClient(name);

    public bool Exists(string name)
    {
        try
        {
            return GetFile(name).Exists();
        }
        catch (RequestFailedException exception)
        {
            _logger.LogWarning(exception, "Could not check whether {Name} exists", name);
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
        var bytes = Encoding.UTF8.GetBytes(content);
        var file = GetFile(name);
        file.Create(bytes.Length);
        if (bytes.Length == 0) return;
        using var stream = new MemoryStream(bytes);
        file.UploadRange(new HttpRange(0, bytes.Length), stream);
    }
}
