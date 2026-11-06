import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.dirname(fileURLToPath(import.meta.url));
const model = path.join(root, 'sm_gelatai_shop_sales.SemanticModel');
const report = path.join(root, 'rp_gelatai_shop_sales.Report');
const json = file => JSON.parse(fs.readFileSync(file, 'utf8'));
const table = name => fs.readFileSync(path.join(model, 'definition', 'tables', `${name}.tmdl`), 'utf8');
const analyticalSql = fs.readFileSync(path.join(root, 'shop-sales-directlake.sql'), 'utf8').replaceAll('\r\n', '\n');
const pagesDir = path.join(report, 'definition', 'pages');
const pages = json(path.join(pagesDir, 'pages.json')).pageOrder.map(id => ({
  ...json(path.join(pagesDir, id, 'page.json')),
  visuals: fs.readdirSync(path.join(pagesDir, id, 'visuals')).map(v => json(path.join(pagesDir, id, 'visuals', v, 'visual.json')))
}));

test('all three requested pages contain data-bound visuals and navigation', () => {
  assert.deepEqual(pages.map(p => p.displayName), ['Sales at a glance', 'Products & payment mix', 'Weather & timing']);
  assert.equal(pages.reduce((n, p) => n + p.visuals.length, 0), 39);
  for (const page of pages) {
    assert.ok(page.visuals.filter(v => v.visual.query).length >= 6);
    assert.ok(page.visuals.some(v => v.visual.visualType === 'pageNavigator'));
    assert.equal(page.width, 1920);
    assert.equal(page.height, 1080);
  }
});

test('all visuals fit the canvas, align to the grid, and have no overlapping siblings', () => {
  for (const page of pages) {
    const names = new Set();
    for (const visual of page.visuals) {
      assert.ok(!names.has(visual.name)); names.add(visual.name);
      const { x, y, width, height } = visual.position;
      assert.ok(x >= 0 && y >= 0 && x + width <= page.width && y + height <= page.height);
      for (const v of [x, y, width, height]) assert.equal(v % 8, 0);
      assert.ok(visual.visual.visualContainerObjects.general[0].properties.altText);
    }
    for (let i = 0; i < page.visuals.length; i++) {
      for (let j = i + 1; j < page.visuals.length; j++) {
        const a = page.visuals[i].position, b = page.visuals[j].position;
        const overlaps = a.x < b.x + b.width && b.x < a.x + a.width && a.y < b.y + b.height && b.y < a.y + a.height;
        assert.ok(!overlaps, `${page.displayName}: ${page.visuals[i].name} overlaps ${page.visuals[j].name}`);
      }
    }
  }
});

test('date, shop and currency slicers sync; EUR defaults to strict single selection', () => {
  for (const page of pages) {
    const slicers = page.visuals.filter(v => v.visual.visualType === 'slicer').sort((a, b) => a.position.x - b.position.x);
    assert.equal(slicers.length, 3);
    assert.deepEqual(slicers.map(v => v.visual.syncGroup.groupName), ['DateSync', 'ShopSync', 'CurrencySync']);
    const currency = slicers[2].visual;
    assert.equal(currency.objects.selection[0].properties.strictSingleSelect.expr.Literal.Value, 'true');
    assert.equal(currency.objects.general[0].properties.filter.filter.Where[0].Condition.In.Values[0][0].Literal.Value, "'EUR'");
    for (const v of slicers) assert.ok(v.position.height >= 80);
  }
});

test('money is currency guarded and only allocated line amounts enter the fact', () => {
  const sales = table('Sales');
  for (const name of ['Net Sales', 'Total Paid', 'Discount', 'Tax']) {
    assert.match(sales, new RegExp(`measure '${name}' = IF\\(HASONEVALUE\\('Currency'\\[Currency\\]\\), SUM\\('Sales'`));
  }
  const factSql = analyticalSql.split('CACHE TABLE _sales_fact AS')[1].split('-- CELL:')[0];
  for (const name of ['Subtotal', 'Discount', 'NetSales', 'Tax', 'Total']) assert.ok(factSql.includes(`i.${name}Amount`));
  assert.ok(!factSql.includes('s.NetSalesAmount') && !factSql.includes('s.TotalAmount'));
  assert.ok(sales.includes("DISTINCTCOUNT('Sales'[Receipt Key])"));
  assert.ok(sales.includes("AVERAGEX(VALUES('Sales'[Receipt Key]), CALCULATE(MAX('Sales'[Temperature])))"));
  assert.ok(sales.includes('formatStringDefinition = IF('));
  const formats = [...sales.matchAll(/formatStringDefinition = (.+)/g)].map(m => m[1]);
  assert.equal(formats.length, 5);
  for (const format of formats) {
    assert.ok(format.includes('UNICHAR(34)'));
    assert.ok(!format.includes('\\"'), 'DAX strings must not use JavaScript backslash quote escaping');
  }
});

test('top-ten filter selects rank at most ten, not the bottom-ranked flavors', () => {
  const ranked = pages[1].visuals.find(v => v.filterConfig);
  const comparison = ranked.filterConfig.filters[0].filter.Where[0].Condition.Comparison;
  assert.equal(comparison.ComparisonKind, 4);
  assert.equal(comparison.Right.Literal.Value, '10L');
});

test('calendar, relationships and local project binding preserve the intended star', () => {
  const relations = fs.readFileSync(path.join(model, 'definition', 'relationships.tmdl'), 'utf8');
  assert.equal((relations.match(/crossFilteringBehavior: oneDirection/g) ?? []).length, 9);
  assert.ok(!relations.includes('bothDirections'));
  assert.ok(table('Date').includes('dataCategory: Time'));
  assert.ok(analyticalSql.includes('EXPLODE(SEQUENCE('));
  assert.ok(analyticalSql.includes('PMOD(DAYOFWEEK(d)+5,7)'));
  assert.equal(json(path.join(report, 'definition.pbir')).datasetReference.byPath.path, '../sm_gelatai_shop_sales.SemanticModel');
  assert.equal(fs.readdirSync(path.join(model, 'definition', 'tables')).length, 11);
});

test('shop keys are integer registry IDs in the fact, dimension and model', () => {
  const factSql = analyticalSql.split('CACHE TABLE _sales_fact AS')[1].split('-- CELL:')[0];
  const shopSql = analyticalSql.split('CREATE OR REPLACE TEMP VIEW _sales_shop AS')[1]
    .split('CREATE OR REPLACE TEMP VIEW _sales_flavor AS')[0];
  assert.match(factSql, /CAST\(s\.ShopId AS BIGINT\) AS shop_key/);
  assert.match(shopSql, /CAST\(sh\.ShopId AS BIGINT\) AS shop_key/);
  assert.match(shopSql, /sh\.City AS city, sh\.CountryCode AS country, sh\.TimeZoneId AS time_zone/);
  assert.match(shopSql, /FROM _sales_shops sh WHERE EXISTS/);
  assert.ok(!analyticalSql.includes("CONCAT(CAST(s.ShopId AS STRING),'|'"));
  for (const name of ['Shop', 'Sales']) {
    assert.match(table(name), /column 'Shop Key'\n\t\tdataType: int64\n\t\tisHidden/);
    assert.match(table(name), /column 'Shop Key'[\s\S]*?\t\tsummarizeBy: none\n\t\tsourceColumn: shop_key/);
  }
  assert.match(table('Shop'), /column 'Shop Key'\n\t\tdataType: int64\n\t\tisHidden\n\t\tisKey/);
  const relations = fs.readFileSync(path.join(model, 'definition', 'relationships.tmdl'), 'utf8');
  assert.match(relations, /fromColumn: Sales\.'Shop Key'\n\ttoColumn: 'Shop'\.'Shop Key'/);
  assert.ok(analyticalSql.indexOf('HAVING shop_key IS NULL OR COUNT(*)<>1') <
    analyticalSql.indexOf('CREATE OR REPLACE TABLE'));
});

test('all eleven tables use true Direct Lake entity partitions and physical Delta columns', () => {
  const expressions = fs.readFileSync(path.join(model, 'definition', 'expressions.tmdl'), 'utf8');
  assert.match(expressions, /AzureStorage\.DataLake\("https:\/\/onelake\.dfs\.fabric\.microsoft\.com\//);
  assert.ok(!expressions.includes('Sql.Database'));
  for (const file of fs.readdirSync(path.join(model, 'definition', 'tables'))) {
    const source = table(path.basename(file, '.tmdl'));
    assert.match(source, /partition '[^']+' = entity\n\t\tmode: directLake/);
    assert.match(source, /schemaName: sales_analytics/);
    assert.match(source, /expressionSource: 'DirectLake - Shop Sales'/);
    assert.ok(!/mode: import|Sql\.Database|#table\(/.test(source));
    for (const mapping of source.matchAll(/sourceColumn: (.+)/g)) assert.match(mapping[1], /^[a-z_]+$/);
  }
});

test('notebook reads only the intended shortcuts and validates before publishing', () => {
  const notebook = json(path.join(root, 'nb_shop_sales_directlake.Notebook', 'notebook-content.ipynb'));
  assert.equal(notebook.nbformat, 4);
  assert.equal(notebook.metadata.dependencies.lakehouse.default_lakehouse_name, 'GelatAI_lakehouse');
  assert.equal(notebook.cells.length, 7);
  for (const cell of notebook.cells) {
    assert.equal(cell.cell_type, 'code');
    assert.equal(cell.execution_count, null);
    assert.deepEqual(cell.outputs, []);
    assert.ok(cell.source.every(s => s.endsWith('\n')));
    assert.ok(cell.source[0].startsWith('%%sql'));
  }
  const dependency = notebook.metadata.dependencies.lakehouse;
  const renderedSql = analyticalSql.replaceAll('{{LAKEHOUSE_TABLES}}',
    `abfss://${dependency.default_lakehouse_workspace_id}@onelake.dfs.fabric.microsoft.com/${dependency.default_lakehouse}/Tables`);
  assert.equal(notebook.cells.map(c => c.source.slice(1).join('')).join('\n').trim(), renderedSql.trim());
  for (const source of ['sc_shopdb/Sale', 'sc_shopdb/SaleItem', 'sc_shopdb/Shop']) assert.ok(analyticalSql.includes(source));
  const firstWrite = analyticalSql.indexOf('CREATE OR REPLACE TABLE');
  assert.ok(analyticalSql.indexOf('SUM(i.TotalAmount)<>s.TotalAmount') < firstWrite);
  assert.ok(analyticalSql.indexOf('sh.shop_key IS NULL') < firstWrite);
  assert.ok(analyticalSql.indexOf('sales_analytics.shop USING DELTA') < analyticalSql.indexOf('sales_analytics.sales USING DELTA'));
  assert.equal((analyticalSql.match(/CREATE OR REPLACE TABLE sales_analytics\./g) ?? []).length, 11);
});
