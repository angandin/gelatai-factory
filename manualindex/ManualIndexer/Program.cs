using Azure;
using Azure.Identity;
using Azure.Search.Documents;
using Azure.Search.Documents.Indexes;
using Azure.Search.Documents.Indexes.Models;
using Azure.Search.Documents.Models;
using OpenAI.Embeddings;
using System.Text.RegularExpressions;
using UglyToad.PdfPig;
using Azure.AI.OpenAI;

const string SearchEndpoint = "https://foundry-01-search.search.windows.net";
const string IndexName = "machines-anomaly-manual";
const string FoundryEndpoint = "https://ice-foundry-01.cognitiveservices.azure.com";
const string EmbeddingDeployment = "text-embedding-3-large";

var apiKey = Environment.GetEnvironmentVariable("AZURE_SEARCH_ADMIN_KEY")
    ?? throw new InvalidOperationException("Set AZURE_SEARCH_ADMIN_KEY environment variable");
var searchCredential = new AzureKeyCredential(apiKey);
var indexClient = new SearchIndexClient(new Uri(SearchEndpoint), searchCredential);

// Embedding client using DefaultAzureCredential (since local auth is disabled on Foundry)
var azureOpenAiClient = new AzureOpenAIClient(new Uri(FoundryEndpoint), new DefaultAzureCredential());
var embeddingClient = azureOpenAiClient.GetEmbeddingClient(EmbeddingDeployment);

// Step 1: Delete and recreate the index
Console.WriteLine("Deleting existing index...");
try { await indexClient.DeleteIndexAsync(IndexName, default(CancellationToken)); } catch { }
await Task.Delay(2000);
Console.WriteLine("Creating search index...");
await CreateIndexAsync(indexClient);

// Step 2: Extract and chunk the PDF
Console.WriteLine("Extracting PDF content...");
var pdfPath = Path.Combine(AppContext.BaseDirectory, "..", "..", "..", "..", "machines_anomaly.pdf");
pdfPath = Path.GetFullPath(pdfPath);
if (!File.Exists(pdfPath))
{
    pdfPath = Path.Combine(Directory.GetCurrentDirectory(), "..", "machines_anomaly.pdf");
    pdfPath = Path.GetFullPath(pdfPath);
}
Console.WriteLine($"PDF path: {pdfPath}");

var chunks = ExtractChunks(pdfPath);
Console.WriteLine($"Extracted {chunks.Count} chunks");

// Step 3: Generate embeddings for each chunk
Console.WriteLine("Generating embeddings...");
var contentTexts = chunks.Select(c => (string)c["content"]).ToList();
var embeddings = await embeddingClient.GenerateEmbeddingsAsync(contentTexts);
for (int i = 0; i < chunks.Count; i++)
{
    chunks[i]["content_vector"] = embeddings.Value[i].ToFloats().ToArray();
}
Console.WriteLine($"  Generated {embeddings.Value.Count} embeddings");

// Step 4: Upload documents in batches
Console.WriteLine("Uploading documents to index...");
var searchClient = new SearchClient(new Uri(SearchEndpoint), IndexName, searchCredential);

const int batchSize = 10;
for (int i = 0; i < chunks.Count; i += batchSize)
{
    var batch = chunks.Skip(i).Take(batchSize).ToList();
    var actions = batch.Select(c => IndexDocumentsAction.Upload(c)).ToList();
    var indexBatch = IndexDocumentsBatch.Create(actions.ToArray());
    await searchClient.IndexDocumentsAsync(indexBatch);
    Console.WriteLine($"  Uploaded batch {i / batchSize + 1}: {batch.Count} documents");
}

Console.WriteLine("Done! Index created and documents uploaded with vectors.");

// --- Functions ---

static async Task CreateIndexAsync(SearchIndexClient indexClient)
{
    const string vectorSearchProfileName = "vector-profile";
    const string vectorAlgorithmName = "hnsw-algorithm";
    const string vectorizerName = "openai-vectorizer";
    const string semanticConfigName = "semantic-config";

    var fields = new List<SearchField>
    {
        new SimpleField("id", SearchFieldDataType.String) { IsKey = true, IsFilterable = true },
        new SearchableField("machine_type") { IsFilterable = true, IsSortable = true, IsFacetable = true },
        new SearchableField("anomaly_type") { IsFilterable = true, IsSortable = true, IsFacetable = true },
        new SearchableField("content"),
        new SimpleField("section_number", SearchFieldDataType.String) { IsFilterable = true },
        new VectorSearchField("content_vector", 3072, vectorSearchProfileName),
    };

    var index = new SearchIndex(IndexName)
    {
        Fields = fields,
        CorsOptions = new CorsOptions(new[] { "*" }) { MaxAgeInSeconds = 300 },
        VectorSearch = new VectorSearch
        {
            Algorithms =
            {
                new HnswAlgorithmConfiguration(vectorAlgorithmName)
                {
                    Parameters = new HnswParameters
                    {
                        Metric = VectorSearchAlgorithmMetric.Cosine
                    }
                }
            },
            Profiles =
            {
                new VectorSearchProfile(vectorSearchProfileName, vectorAlgorithmName)
                {
                    VectorizerName = vectorizerName
                }
            },
            Vectorizers =
            {
                new AzureOpenAIVectorizer(vectorizerName)
                {
                    Parameters = new AzureOpenAIVectorizerParameters
                    {
                        ResourceUri = new Uri("https://ice-foundry-01.cognitiveservices.azure.com"),
                        DeploymentName = "text-embedding-3-large",
                        ModelName = "text-embedding-3-large"
                    }
                }
            }
        },
        SemanticSearch = new SemanticSearch
        {
            DefaultConfigurationName = semanticConfigName,
            Configurations =
            {
                new SemanticConfiguration(semanticConfigName, new SemanticPrioritizedFields
                {
                    TitleField = new SemanticField("machine_type"),
                    ContentFields =
                    {
                        new SemanticField("content")
                    },
                    KeywordsFields =
                    {
                        new SemanticField("anomaly_type")
                    }
                })
            }
        }
    };

    await indexClient.CreateOrUpdateIndexAsync(index);
    Console.WriteLine($"  Index '{IndexName}' created/updated successfully.");
}

static List<SearchDocument> ExtractChunks(string pdfPath)
{
    var fullText = ExtractPdfText(pdfPath);
    var chunks = new List<SearchDocument>();

    var sections = ParseMachineAnomalySections(fullText);

    foreach (var section in sections)
    {
        var id = $"{Sanitize(section.MachineName)}-{Sanitize(section.AnomalyType)}".ToLowerInvariant();
        var doc = new SearchDocument
        {
            ["id"] = id,
            ["machine_type"] = section.MachineName,
            ["anomaly_type"] = section.AnomalyType,
            ["content"] = section.FullContent,
            ["section_number"] = section.SectionNumber
        };
        chunks.Add(doc);
    }

    return chunks;
}

static string ExtractPdfText(string pdfPath)
{
    using var document = PdfDocument.Open(pdfPath);
    var text = string.Join("\n", document.GetPages().Select(p => p.Text));
    return text;
}

static List<AnomalySection> ParseMachineAnomalySections(string text)
{
    var sections = new List<AnomalySection>();

    // Normalize line endings
    text = text.Replace("\r\n", "\n").Replace("\r", "\n");

    // Extract machine names from "3.X MachineName" headers
    var machineNames = new Dictionary<string, string>();
    var machinePattern = new Regex(@"3\.(\d+)\s+([A-Z][A-Za-z\s]+?)(?:\n|$)");
    foreach (Match m in machinePattern.Matches(text))
    {
        machineNames[m.Groups[1].Value] = m.Groups[2].Value.Trim();
    }

    // Find each anomaly subsection (3.X.Y)
    var allSubsections = Regex.Matches(text, @"3\.(\d+)\.(\d+)\s+(.+?)(?=3\.\d+[\.\s]|\Z)", RegexOptions.Singleline);

    foreach (Match match in allSubsections)
    {
        var machineNum = match.Groups[1].Value;
        var anomalyNum = match.Groups[2].Value;
        var content = match.Groups[3].Value.Trim();

        var machineName = machineNames.ContainsKey(machineNum) ? machineNames[machineNum] : $"Machine {machineNum}";

        // Extract anomaly type (first line)
        var lines = content.Split('\n', 2);
        var anomalyType = lines[0].Trim();
        var body = lines.Length > 1 ? lines[1].Trim() : "";

        // Extract affected parameters
        var paramMatch = Regex.Match(body, @"Affected parameters:\s*(.+?)(?:\n|$)");
        var affectedParams = paramMatch.Success ? paramMatch.Groups[1].Value.Trim() : "";

        // Extract issue description
        var descMatch = Regex.Match(body, @"Issue description:\s*(.+?)(?=Required operator action:|$)", RegexOptions.Singleline);
        var description = descMatch.Success ? descMatch.Groups[1].Value.Trim() : "";

        // Extract required action
        var actionMatch = Regex.Match(body, @"Required operator action:\s*(.+?)(?=(?:Caution|Warning|Note):|$)", RegexOptions.Singleline);
        var action = actionMatch.Success ? actionMatch.Groups[1].Value.Trim() : "";

        // Extract warnings/notes
        var warningMatch = Regex.Match(body, @"(?:Caution|Warning|Note):\s*(.+?)$", RegexOptions.Singleline);
        var warnings = warningMatch.Success ? warningMatch.Groups[1].Value.Trim() : "";

        sections.Add(new AnomalySection
        {
            SectionNumber = $"3.{machineNum}.{anomalyNum}",
            MachineName = machineName,
            AnomalyType = anomalyType,
            AffectedParameters = affectedParams,
            IssueDescription = description,
            RequiredAction = action,
            WarningsNotes = warnings,
            FullContent = $"{machineName} - {anomalyType}\n{body}"
        });
    }

    return sections;
}

static string Sanitize(string input)
{
    return Regex.Replace(input, @"[^a-zA-Z0-9]", "-").Trim('-');
}

record AnomalySection
{
    public string SectionNumber { get; init; } = "";
    public string MachineName { get; init; } = "";
    public string AnomalyType { get; init; } = "";
    public string AffectedParameters { get; init; } = "";
    public string IssueDescription { get; init; } = "";
    public string RequiredAction { get; init; } = "";
    public string WarningsNotes { get; init; } = "";
    public string FullContent { get; init; } = "";
}
