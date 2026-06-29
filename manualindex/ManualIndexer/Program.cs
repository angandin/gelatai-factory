using Azure;
using Azure.Identity;
using Azure.Search.Documents;
using Azure.Search.Documents.Indexes;
using Azure.Search.Documents.Indexes.Models;
using Azure.Search.Documents.Models;
using OpenAI.Embeddings;
using System.Text;
using System.Text.RegularExpressions;
using UglyToad.PdfPig;
using Azure.AI.OpenAI;

const string SearchEndpoint = "https://foundry-01-search.search.windows.net";
const string FoundryEndpoint = "https://ice-foundry-01.cognitiveservices.azure.com";
const string EmbeddingDeployment = "text-embedding-3-large";

// Select which manual to index based on the first command-line argument.
//   (none) | "anomaly"  -> machines_anomaly.pdf                         -> "machines-anomaly-manual"
//   "factory"           -> Industrial_Ice_Cream_Factory_Manual...pdf    -> "factory-functional"
//   "gelato"            -> professional_italian_gelato.pdf             -> "flavor-maker" (one doc per flavor)
//   "dump-factory"      -> extract factory text to a file (no Azure calls)
//   "dump-gelato"       -> print parsed gelato flavors (no Azure calls)
var mode = (args.Length > 0 ? args[0] : "anomaly").ToLowerInvariant();

if (mode == "dump-gelato")
{
    var path = ResolvePdfPath("professional_italian_gelato.pdf");
    var rawLines = ExtractPdfLines(path);
    var rawOut = Path.Combine(AppContext.BaseDirectory, "gelato_lines.txt");
    File.WriteAllText(rawOut, rawLines);
    Console.WriteLine($"Dumped {rawLines.Length} chars to {rawOut}");

    var parsed = ExtractGelatoChunks(path);
    Console.WriteLine($"Parsed {parsed.Count} flavors:");
    var parseOut = Path.Combine(AppContext.BaseDirectory, "gelato_parsed.txt");
    var psb = new StringBuilder();
    foreach (var c in parsed)
    {
        psb.AppendLine($"=== [{c["flavor_number"]}] {c["flavor_name"]} (id={c["id"]}) ===");
        psb.AppendLine($"Raw materials: {c["raw_materials"]}");
        psb.AppendLine($"Process: {c["process"]}");
        psb.AppendLine($"Technical difference: {c["technical_difference"]}");
        psb.AppendLine();
        Console.WriteLine($"  [{c["flavor_number"],-5}] {c["flavor_name"]}");
    }
    File.WriteAllText(parseOut, psb.ToString());
    Console.WriteLine($"Wrote structured parse to {parseOut}");
    return;
}

if (mode == "dump-factory")
{
    var path = ResolvePdfPath("Industrial_Ice_Cream_Factory_Manual_Completed.pdf");
    var dumpText = ExtractPdfText(path);
    var dumpOut = Path.Combine(AppContext.BaseDirectory, "factory_dump.txt");
    File.WriteAllText(dumpOut, dumpText);
    Console.WriteLine($"Dumped {dumpText.Length} chars to {dumpOut}");

    var parsed = ExtractFactoryChunks(path);
    Console.WriteLine($"Parsed {parsed.Count} sections:");
    foreach (var c in parsed)
    {
        var preview = ((string)c["content"]).Replace("\n", " ");
        if (preview.Length > 90) preview = preview.Substring(0, 90);
        Console.WriteLine($"  [{c["section_number"],-12}] {c["section_title"]}  ::  {preview}");
    }
    return;
}

string indexName;
string pdfFileName;
Func<string, List<SearchDocument>> extractor;
Func<SearchIndexClient, string, Task> createIndex;

if (mode == "factory")
{
    indexName = "factory-functional";
    pdfFileName = "Industrial_Ice_Cream_Factory_Manual_Completed.pdf";
    extractor = ExtractFactoryChunks;
    createIndex = CreateFactoryIndexAsync;
}
else if (mode == "gelato")
{
    indexName = "flavor-maker";
    pdfFileName = "professional_italian_gelato.pdf";
    extractor = ExtractGelatoChunks;
    createIndex = CreateGelatoIndexAsync;
}
else
{
    indexName = "machines-anomaly-manual";
    pdfFileName = "machines_anomaly.pdf";
    extractor = ExtractAnomalyChunks;
    createIndex = CreateAnomalyIndexAsync;
}

Console.WriteLine($"Mode: {mode} -> index '{indexName}'");

var apiKey = Environment.GetEnvironmentVariable("AZURE_SEARCH_ADMIN_KEY")
    ?? throw new InvalidOperationException("Set AZURE_SEARCH_ADMIN_KEY environment variable");
var searchCredential = new AzureKeyCredential(apiKey);
var indexClient = new SearchIndexClient(new Uri(SearchEndpoint), searchCredential);

// Embedding client using DefaultAzureCredential (since local auth is disabled on Foundry)
var azureOpenAiClient = new AzureOpenAIClient(new Uri(FoundryEndpoint), new DefaultAzureCredential());
var embeddingClient = azureOpenAiClient.GetEmbeddingClient(EmbeddingDeployment);

// Step 1: Delete and recreate the index
Console.WriteLine("Deleting existing index...");
try { await indexClient.DeleteIndexAsync(indexName, default(CancellationToken)); } catch { }
await Task.Delay(2000);
Console.WriteLine("Creating search index...");
await createIndex(indexClient, indexName);

// Step 2: Extract and chunk the PDF
Console.WriteLine("Extracting PDF content...");
var pdfPath = ResolvePdfPath(pdfFileName);
Console.WriteLine($"PDF path: {pdfPath}");

var chunks = extractor(pdfPath);
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
var searchClient = new SearchClient(new Uri(SearchEndpoint), indexName, searchCredential);

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

// --- Shared helpers ---

static string ResolvePdfPath(string fileName)
{
    var p = Path.Combine(AppContext.BaseDirectory, "..", "..", "..", "..", fileName);
    p = Path.GetFullPath(p);
    if (!File.Exists(p))
    {
        p = Path.Combine(Directory.GetCurrentDirectory(), "..", fileName);
        p = Path.GetFullPath(p);
    }
    return p;
}

static string ExtractPdfText(string pdfPath)
{
    using var document = PdfDocument.Open(pdfPath);
    var text = string.Join("\n", document.GetPages().Select(p => p.Text));
    return text;
}

// Reconstructs text with real line breaks by grouping words by their vertical
// position on each page. PdfPig's page.Text flattens a whole page into a single
// line, which makes heading-based chunking impossible; this preserves layout.
static string ExtractPdfLines(string pdfPath)
{
    using var document = PdfDocument.Open(pdfPath);
    var sb = new StringBuilder();
    foreach (var page in document.GetPages())
    {
        var lines = page.GetWords()
            .GroupBy(w => Math.Round(w.BoundingBox.Bottom))
            .OrderByDescending(g => g.Key) // PDF origin is bottom-left: higher Y = top of page
            .Select(g => string.Join(" ", g.OrderBy(w => w.BoundingBox.Left).Select(w => w.Text)));
        foreach (var line in lines)
            sb.AppendLine(line);
    }
    return sb.ToString();
}

static string Sanitize(string input)
{
    return Regex.Replace(input, @"[^a-zA-Z0-9]", "-").Trim('-');
}

// --- Machine anomaly manual (existing) ---

static async Task CreateAnomalyIndexAsync(SearchIndexClient indexClient, string indexName)
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

    var index = new SearchIndex(indexName)
    {
        Fields = fields,
        CorsOptions = new CorsOptions(new[] { "*" }) { MaxAgeInSeconds = 300 },
        VectorSearch = BuildVectorSearch(vectorSearchProfileName, vectorAlgorithmName, vectorizerName),
        SemanticSearch = new SemanticSearch
        {
            DefaultConfigurationName = semanticConfigName,
            Configurations =
            {
                new SemanticConfiguration(semanticConfigName, new SemanticPrioritizedFields
                {
                    TitleField = new SemanticField("machine_type"),
                    ContentFields = { new SemanticField("content") },
                    KeywordsFields = { new SemanticField("anomaly_type") }
                })
            }
        }
    };

    await indexClient.CreateOrUpdateIndexAsync(index);
    Console.WriteLine($"  Index '{indexName}' created/updated successfully.");
}

static List<SearchDocument> ExtractAnomalyChunks(string pdfPath)
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

// --- Industrial ice cream factory manual ---

static async Task CreateFactoryIndexAsync(SearchIndexClient indexClient, string indexName)
{
    const string vectorSearchProfileName = "vector-profile";
    const string vectorAlgorithmName = "hnsw-algorithm";
    const string vectorizerName = "openai-vectorizer";
    const string semanticConfigName = "semantic-config";

    var fields = new List<SearchField>
    {
        new SimpleField("id", SearchFieldDataType.String) { IsKey = true, IsFilterable = true },
        new SearchableField("section_title") { IsFilterable = true, IsSortable = true, IsFacetable = true },
        new SimpleField("section_number", SearchFieldDataType.String) { IsFilterable = true, IsSortable = true },
        new SearchableField("content"),
        new VectorSearchField("content_vector", 3072, vectorSearchProfileName),
    };

    var index = new SearchIndex(indexName)
    {
        Fields = fields,
        CorsOptions = new CorsOptions(new[] { "*" }) { MaxAgeInSeconds = 300 },
        VectorSearch = BuildVectorSearch(vectorSearchProfileName, vectorAlgorithmName, vectorizerName),
        SemanticSearch = new SemanticSearch
        {
            DefaultConfigurationName = semanticConfigName,
            Configurations =
            {
                new SemanticConfiguration(semanticConfigName, new SemanticPrioritizedFields
                {
                    TitleField = new SemanticField("section_title"),
                    ContentFields = { new SemanticField("content") }
                })
            }
        }
    };

    await indexClient.CreateOrUpdateIndexAsync(index);
    Console.WriteLine($"  Index '{indexName}' created/updated successfully.");
}

static List<SearchDocument> ExtractFactoryChunks(string pdfPath)
{
    var fullText = ExtractPdfLines(pdfPath);
    var sections = ParseFactoryManualSections(fullText);

    var chunks = new List<SearchDocument>();
    var seenIds = new HashSet<string>();
    foreach (var section in sections)
    {
        var baseId = Sanitize($"{section.SectionNumber}-{section.Title}").ToLowerInvariant();
        if (string.IsNullOrEmpty(baseId)) baseId = "section";
        var id = baseId;
        var suffix = 1;
        while (!seenIds.Add(id))
        {
            id = $"{baseId}-{suffix++}";
        }

        var content = string.IsNullOrWhiteSpace(section.Title)
            ? section.Body
            : $"{section.Title}\n{section.Body}";

        chunks.Add(new SearchDocument
        {
            ["id"] = id,
            ["section_title"] = section.Title,
            ["section_number"] = section.SectionNumber,
            ["content"] = content
        });
    }

    return chunks;
}

static List<FactorySection> ParseFactoryManualSections(string text)
{
    // Normalize line endings.
    text = text.Replace("\r\n", "\n").Replace("\r", "\n");

    // Remove repeated page footers, e.g. "Industrial Ice Cream Factory Manual - 7".
    text = Regex.Replace(text, @"Industrial Ice Cream Factory Manual\s*-\s*\d+", " ");

    // Skip the front matter / table of contents: start parsing at the real
    // Section 1 heading (its last occurrence in the document).
    var bodyStart = text.LastIndexOf("1. Factory mission", StringComparison.OrdinalIgnoreCase);
    if (bodyStart > 0)
    {
        text = text.Substring(bodyStart);
    }

    // Heading patterns (longest / most specific first):
    //   "Appendix A. Title"
    //   "A.1 Title"          (appendix subsection)
    //   "2.1 Title"          (numbered subsection)
    //   "3. Title"           (top-level section)
    var headingRegex = new Regex(
        @"(?:Appendix\s+[A-Z]\.\s+[A-Z][^\n]*)" +
        @"|(?:\b[A-Z]\.\d{1,2}\s+[A-Z][^\n]*)" +
        @"|(?:\b\d{1,2}\.\d{1,2}\s+[A-Z][^\n]*)" +
        @"|(?:\b\d{1,2}\.\s+[A-Z][^\n]*)");

    var matches = headingRegex.Matches(text);
    var sections = new List<FactorySection>();

    for (int i = 0; i < matches.Count; i++)
    {
        var heading = matches[i].Value.Trim();
        var start = matches[i].Index + matches[i].Length;
        var end = (i + 1 < matches.Count) ? matches[i + 1].Index : text.Length;
        var body = text.Substring(start, end - start).Trim();

        // Collapse runs of whitespace for cleaner content.
        body = Regex.Replace(body, @"[ \t]+", " ");
        body = Regex.Replace(body, @"\n{3,}", "\n\n");

        var (number, title) = SplitFactoryHeading(heading);

        // Skip empty/noise sections.
        if (string.IsNullOrWhiteSpace(title) && string.IsNullOrWhiteSpace(body))
            continue;

        sections.Add(new FactorySection
        {
            SectionNumber = number,
            Title = title,
            Body = body
        });
    }

    return sections;
}

// --- Professional Italian gelato guide: one Azure Search document per flavor ---

static async Task CreateGelatoIndexAsync(SearchIndexClient indexClient, string indexName)
{
    const string vectorSearchProfileName = "vector-profile";
    const string vectorAlgorithmName = "hnsw-algorithm";
    const string vectorizerName = "openai-vectorizer";
    const string semanticConfigName = "semantic-config";

    var fields = new List<SearchField>
    {
        new SimpleField("id", SearchFieldDataType.String) { IsKey = true, IsFilterable = true },
        new SearchableField("flavor_name") { IsFilterable = true, IsSortable = true, IsFacetable = true },
        new SimpleField("flavor_number", SearchFieldDataType.String) { IsFilterable = true, IsSortable = true },
        new SearchableField("raw_materials"),
        new SearchableField("process"),
        new SearchableField("technical_difference"),
        new SearchableField("content"),
        new VectorSearchField("content_vector", 3072, vectorSearchProfileName),
    };

    var index = new SearchIndex(indexName)
    {
        Fields = fields,
        CorsOptions = new CorsOptions(new[] { "*" }) { MaxAgeInSeconds = 300 },
        VectorSearch = BuildVectorSearch(vectorSearchProfileName, vectorAlgorithmName, vectorizerName),
        SemanticSearch = new SemanticSearch
        {
            DefaultConfigurationName = semanticConfigName,
            Configurations =
            {
                new SemanticConfiguration(semanticConfigName, new SemanticPrioritizedFields
                {
                    TitleField = new SemanticField("flavor_name"),
                    ContentFields =
                    {
                        new SemanticField("content"),
                        new SemanticField("raw_materials"),
                        new SemanticField("process"),
                        new SemanticField("technical_difference"),
                    }
                })
            }
        }
    };

    await indexClient.CreateOrUpdateIndexAsync(index);
}

static List<SearchDocument> ExtractGelatoChunks(string pdfPath)
{
    var flavors = ParseGelatoFlavors(pdfPath);
    var docs = new List<SearchDocument>();
    var seenIds = new HashSet<string>();

    foreach (var f in flavors)
    {
        var baseId = Sanitize($"{f.Number}-{f.Name}");
        var id = baseId;
        var suffix = 1;
        while (!seenIds.Add(id))
            id = $"{baseId}-{suffix++}";

        var sb = new StringBuilder();
        sb.AppendLine(f.Name);
        if (!string.IsNullOrWhiteSpace(f.RawMaterials)) sb.AppendLine($"Raw materials: {f.RawMaterials}");
        if (!string.IsNullOrWhiteSpace(f.Process)) sb.AppendLine($"Process: {f.Process}");
        if (!string.IsNullOrWhiteSpace(f.TechnicalDifference)) sb.AppendLine($"Technical difference: {f.TechnicalDifference}");

        docs.Add(new SearchDocument
        {
            ["id"] = id,
            ["flavor_name"] = f.Name,
            ["flavor_number"] = f.Number,
            ["raw_materials"] = f.RawMaterials,
            ["process"] = f.Process,
            ["technical_difference"] = f.TechnicalDifference,
            ["content"] = sb.ToString().Trim(),
        });
    }

    return docs;
}

static List<FlavorEntry> ParseGelatoFlavors(string pdfPath)
{
    var text = ExtractPdfLines(pdfPath);

    // Remove page footers like "Page 4" / "Page 4 of 10".
    text = Regex.Replace(text, @"(?im)^\s*Page\s+\d+(\s+of\s+\d+)?\s*$", "");

    // Scope to Section 4 (the flavor catalog): from the first flavor heading
    // up to the start of Section 5 (cross-flavor troubleshooting).
    var startMatch = Regex.Match(text, @"4\.1\s+Fior di latte", RegexOptions.IgnoreCase);
    var start = startMatch.Success ? startMatch.Index : 0;

    var endMatch = Regex.Match(text, @"(?im)^\s*5\.\s+\S", RegexOptions.None);
    var end = (endMatch.Success && endMatch.Index > start) ? endMatch.Index : text.Length;

    var region = text.Substring(start, end - start);

    // Find every flavor heading "4.N FlavorName" and slice the body until the next one.
    var headingRegex = new Regex(@"(?m)^\s*(4\.\d{1,2})\s+(.+?)\s*$");
    var matches = headingRegex.Matches(region);

    var flavors = new List<FlavorEntry>();
    for (int i = 0; i < matches.Count; i++)
    {
        var m = matches[i];
        var number = m.Groups[1].Value.Trim();
        var name = m.Groups[2].Value.Trim();

        var bodyStart = m.Index + m.Length;
        var bodyEnd = (i + 1 < matches.Count) ? matches[i + 1].Index : region.Length;
        var body = region.Substring(bodyStart, bodyEnd - bodyStart).Trim();

        var rawMaterials = Regex.Match(body, @"Raw materials:\s*(.+?)(?=Process:|Technical difference:|$)", RegexOptions.Singleline);
        var process = Regex.Match(body, @"Process:\s*(.+?)(?=Technical difference:|Raw materials:|$)", RegexOptions.Singleline);
        var technical = Regex.Match(body, @"Technical difference:\s*(.+?)(?=Raw materials:|Process:|$)", RegexOptions.Singleline);

        flavors.Add(new FlavorEntry
        {
            Number = number,
            Name = name,
            RawMaterials = CleanFlavorText(rawMaterials.Success ? rawMaterials.Groups[1].Value : ""),
            Process = CleanFlavorText(process.Success ? process.Groups[1].Value : ""),
            TechnicalDifference = CleanFlavorText(technical.Success ? technical.Groups[1].Value : ""),
        });
    }

    return flavors;
}

static string CleanFlavorText(string s)
{
    if (string.IsNullOrWhiteSpace(s)) return "";
    s = Regex.Replace(s, @"\s+", " ");
    return s.Trim();
}

static (string number, string title) SplitFactoryHeading(string heading)
{
    var appendix = Regex.Match(heading, @"^(Appendix\s+[A-Z])\.\s+(.*)$");
    if (appendix.Success)
        return (appendix.Groups[1].Value.Trim(), appendix.Groups[2].Value.Trim());

    var sub = Regex.Match(heading, @"^([A-Z]\.\d{1,2}|\d{1,2}\.\d{1,2})\s+(.*)$");
    if (sub.Success)
        return (sub.Groups[1].Value.Trim(), sub.Groups[2].Value.Trim());

    var top = Regex.Match(heading, @"^(\d{1,2})\.\s+(.*)$");
    if (top.Success)
        return (top.Groups[1].Value.Trim(), top.Groups[2].Value.Trim());

    return ("", heading.Trim());
}

static VectorSearch BuildVectorSearch(string profileName, string algorithmName, string vectorizerName)
{
    return new VectorSearch
    {
        Algorithms =
        {
            new HnswAlgorithmConfiguration(algorithmName)
            {
                Parameters = new HnswParameters { Metric = VectorSearchAlgorithmMetric.Cosine }
            }
        },
        Profiles =
        {
            new VectorSearchProfile(profileName, algorithmName) { VectorizerName = vectorizerName }
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
    };
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

record FactorySection
{
    public string SectionNumber { get; init; } = "";
    public string Title { get; init; } = "";
    public string Body { get; init; } = "";
}

record FlavorEntry
{
    public string Number { get; init; } = "";
    public string Name { get; init; } = "";
    public string RawMaterials { get; init; } = "";
    public string Process { get; init; } = "";
    public string TechnicalDifference { get; init; } = "";
}
