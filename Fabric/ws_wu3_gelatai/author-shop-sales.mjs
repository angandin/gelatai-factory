import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { fileURLToPath } from 'node:url';

// Deterministic source generator. Does not publish or change the source database.
const root = path.dirname(fileURLToPath(import.meta.url));
const modelName = 'sm_gelatai_shop_sales';
const reportName = 'rp_gelatai_shop_sales';
const modelDir = path.join(root, `${modelName}.SemanticModel`);
const reportDir = path.join(root, `${reportName}.Report`);
const workspaceId = process.env.FABRIC_WORKSPACE_ID ?? '97d5eec3-d6d9-44bb-80aa-279e286309b3';
const lakehouseId = process.env.FABRIC_LAKEHOUSE_ID ?? '92e59539-b5cf-4ae0-babe-fa481abc416d';
const physicalName = name => name.toLowerCase().replaceAll(' ', '_');
const id = text => crypto.createHash('sha256').update(text).digest('hex').slice(0, 20);
const write = (file, value) => {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, typeof value === 'string' ? value : `${JSON.stringify(value, null, 2)}\n`);
};
const q = name => `'${name.replaceAll("'", "''")}'`;
const schema = suffix => `https://developer.microsoft.com/json-schemas/fabric/item/report/${suffix}/schema.json`;
const tables = [];
const relationships = [];
const salesColumns = [
  ['Receipt Key', 'int64'], ['Shop Key', 'int64'], ['Flavor Key', 'string'],
  ['Date', 'dateTime'], ['Currency', 'string'], ['Weather', 'string'], ['Payment', 'string'],
  ['Channel', 'string'], ['Serving', 'string'], ['Hour', 'int64'], ['Temperature', 'decimal'],
  ['Temperature Band', 'string', false, 'Temperature Band Start'], ['Temperature Band Start', 'int64'],
  ['City', 'string', false], ['Country', 'string', false], ['Receipt UTC', 'dateTime'],
  ['Scoop Quantity', 'int64'], ['Subtotal Amount', 'decimal'], ['Discount Amount', 'decimal'],
  ['Net Amount', 'decimal'], ['Tax Amount', 'decimal'], ['Paid Amount', 'decimal']
];
const measures = [];
const measure = (name, expression, format, description, money = false) => measures.push({ name, expression, format, description, money });
for (const [name, column, description] of [
  ['Net Sales', 'Net Amount', 'Allocated line net sales after discounts, excluding tax. One currency required.'],
  ['Total Paid', 'Paid Amount', 'Allocated line payments including tax. One currency required.'],
  ['Discount', 'Discount Amount', 'Allocated discounts; never repeats the receipt header amount.'],
  ['Tax', 'Tax Amount', 'Allocated receipt taxes. One currency required.']
]) measure(name, `IF(HASONEVALUE('Currency'[Currency]), SUM('Sales'[${column}]))`, '#,##0.00', description, true);
measure('Receipts', "DISTINCTCOUNT('Sales'[Receipt Key])", '#,##0', 'Distinct receipts, not flavor lines. Non-additive across flavors.');
measure('Scoops', "SUM('Sales'[Scoop Quantity])", '#,##0', 'Scoops sold in the selected flavor lines.');
measure('Scoops per Receipt', 'DIVIDE([Scoops], [Receipts])', '0.0', 'Selected scoops divided by distinct matching receipts.');
measure('Average Basket', 'DIVIDE([Net Sales], [Receipts])', '#,##0.00', 'Net sales per matching receipt; under flavor filters this is the selected flavor contribution, not the full basket.', true);
measure('Discount Rate', "DIVIDE(SUM('Sales'[Discount Amount]), SUM('Sales'[Subtotal Amount]))", '0.0%', 'Allocated discount divided by pre-discount subtotal.');
measure('Average Temperature', "AVERAGEX(VALUES('Sales'[Receipt Key]), CALCULATE(MAX('Sales'[Temperature])))", '0.0" C"', 'Receipt-weighted average simulated temperature; not a line-weighted average.');
for (const dim of ['Payment', 'Channel', 'Serving']) {
  measure(`${dim} Share`, `DIVIDE([Receipts], CALCULATE([Receipts], ALLSELECTED('${dim}')))`, '0.0%', `Share of selected receipts for each ${dim.toLowerCase()} category.`);
}
measure('Flavor Share', "DIVIDE([Net Sales], CALCULATE([Net Sales], ALLSELECTED('Flavor')))", '0.0%', 'Share of selected flavor net sales; based on additive line money.');
measure('Flavor Rank', "IF(NOT ISBLANK([Net Sales]), RANKX(ALLSELECTED('Flavor'), [Net Sales], , DESC, DENSE))", '0', 'Dense ranking within selected flavors, used for the top ten.');
measure('Latest Receipt UTC', "MAX('Sales'[Receipt UTC])", 'yyyy-MM-dd HH:mm" UTC"', 'Latest source receipt time, distinct from refresh time.');
measure('Data As Of UTC', "MAX('Refresh'[Refreshed UTC])", 'yyyy-MM-dd HH:mm" UTC"', 'UTC timestamp of the last successful analytical Delta table publication.');
measure('Currency Guidance', 'IF(HASONEVALUE(\'Currency\'[Currency]), "Amounts in " & SELECTEDVALUE(\'Currency\'[Currency]) & " | net sales exclude tax", "Select exactly one currency to display amounts")', '@', 'Currency context and explanation when monetary measures are blank.');

function table(name, columns, description, key = null, extraMeasures = []) {
  tables.push({ name, columns, description, key, measures: extraMeasures });
}
table('Sales', salesColumns, 'One row per receipt flavor line. Only allocated line amounts are additive.', null, measures);
table('Shop', [['Shop Key', 'int64', true], ['Shop Name', 'string', false], ['City', 'string', false], ['Country', 'string', false], ['Time Zone', 'string', false]],
  'One row per integer registry ShopId, with current registry display name, city, country and time zone.', 'Shop Key');
table('Flavor', [['Flavor Key', 'string', true], ['Flavor', 'string', false]],
  'Flavor labels as recorded on the sale.', 'Flavor Key');
table('Date', [['Date', 'dateTime', false], ['Year', 'int64', false], ['Month Number', 'int64', true], ['Month', 'string', false, 'Month Number'], ['Month Start', 'dateTime', false], ['Weekday Number', 'int64', true], ['Weekday', 'string', false, 'Weekday Number']], 'Continuous local trading calendar, spanning full years of available sales.', 'Date');
for (const name of ['Currency', 'Weather', 'Payment', 'Channel', 'Serving']) {
  table(name, [[name, 'string', false]], `Available ${name.toLowerCase()} categories.`, name);
}
table('Local Hour', [['Hour', 'int64', false]], 'Hour of the receipt in each shop local time, not UTC.', 'Hour');
table('Refresh', [['Refreshed UTC', 'dateTime', true]], 'Single-row analytical publication metadata utility.');
for (const [dim, key, factKey] of [['Shop', 'Shop Key'], ['Flavor', 'Flavor Key'], ['Date', 'Date'], ['Currency', 'Currency'], ['Weather', 'Weather'], ['Payment', 'Payment'], ['Channel', 'Channel'], ['Serving', 'Serving'], ['Local Hour', 'Hour']]) {
  relationships.push(`relationship ${q(`Sales to ${dim}`)}\n\tfromColumn: Sales.${q(factKey ?? key)}\n\ttoColumn: ${q(dim)}.${q(key)}\n\tcrossFilteringBehavior: oneDirection\n`);
}
write(path.join(modelDir, 'definition.pbism'), {
  $schema: 'https://developer.microsoft.com/json-schemas/fabric/item/semanticModel/definitionProperties/1.0.0/schema.json',
  version: '4.2', settings: { qnaEnabled: true }
});
write(path.join(modelDir, 'definition', 'database.tmdl'), 'database\n\tcompatibilityLevel: 1702\n\tcompatibilityMode: powerBI\n');
write(path.join(modelDir, 'definition', 'model.tmdl'), `model Model\n\tculture: en-US\n\tdefaultPowerBIDataSourceVersion: powerBI_V3\n\tsourceQueryCulture: en-US\n\tdiscourageImplicitMeasures\n\n${tables.map(t => `ref table ${q(t.name)}`).join('\n')}\n\nref expression 'DirectLake - Shop Sales'\n`);
write(path.join(modelDir, 'definition', 'expressions.tmdl'), `expression 'DirectLake - Shop Sales' =\n\t\tAzureStorage.DataLake("https://onelake.dfs.fabric.microsoft.com/${workspaceId}/${lakehouseId}", [HierarchicalNavigation=true])\n`);
write(path.join(modelDir, 'definition', 'relationships.tmdl'), relationships.join('\n'));
for (const t of tables) {
  let text = `/// ${t.description}\ntable ${q(t.name)}\n`;
  if (t.name === 'Date') text += '\tdataCategory: Time\n';
  if (t.name === 'Refresh') text += '\tisHidden\n';
  for (const m of t.measures) {
    text += `\n\t/// ${m.description}\n\tmeasure ${q(m.name)} = ${m.expression}\n${m.money ? '' : `\t\tformatString: ${m.format}\n`}\t\tdisplayFolder: ${m.money ? 'Sales amounts' : 'Sales insights'}\n`;
    if (m.money) text += '\t\tformatStringDefinition = IF(SELECTEDVALUE(\'Currency\'[Currency]) = "JPY", "#,##0", "#,##0.00") & " " & UNICHAR(34) & SELECTEDVALUE(\'Currency\'[Currency], "") & UNICHAR(34)\n';
  }
  for (const [name, type, hidden = true, sort] of t.columns) {
    text += `\n\tcolumn ${q(name)}\n\t\tdataType: ${type}\n`;
    if (hidden) text += '\t\tisHidden\n';
    if (t.key === name) text += '\t\tisKey\n';
    text += `\t\tsummarizeBy: none\n\t\tsourceColumn: ${physicalName(name)}\n`;
    if (type === 'dateTime' && !name.includes('UTC')) text += '\t\tformatString: yyyy-MM-dd\n\t\tannotation UnderlyingDateTimeDataType = Date\n';
    if (sort) text += `\t\tsortByColumn: ${q(sort)}\n`;
    if (name === 'City' || name === 'Country') text += `\t\tdataCategory: ${name}\n`;
  }
  text += `\n\tpartition ${q(`${t.name} Direct Lake`)} = entity\n\t\tmode: directLake\n\t\tsource\n\t\t\tentityName: ${physicalName(t.name)}\n\t\t\tschemaName: sales_analytics\n\t\t\texpressionSource: 'DirectLake - Shop Sales'\n`;
  write(path.join(modelDir, 'definition', 'tables', `${t.name}.tmdl`), text);
}

const notebookSql = fs.readFileSync(path.join(root, 'shop-sales-directlake.sql'), 'utf8')
  .replaceAll('\r\n', '\n')
  .replaceAll('{{LAKEHOUSE_TABLES}}', `abfss://${workspaceId}@onelake.dfs.fabric.microsoft.com/${lakehouseId}/Tables`);
write(path.join(root, 'nb_shop_sales_directlake.Notebook', 'notebook-content.ipynb'), {
  nbformat: 4, nbformat_minor: 5,
  metadata: {
    kernelspec: { name: 'synapse_pyspark', display_name: 'Synapse PySpark' },
    language_info: { name: 'python' },
    dependencies: { lakehouse: {
      default_lakehouse: lakehouseId, default_lakehouse_name: 'GelatAI_lakehouse',
      default_lakehouse_workspace_id: workspaceId, known_lakehouses: [{ id: lakehouseId }]
    } }
  },
  cells: notebookSql.split(/(?=^-- CELL:)/m).filter(s => s.trim()).map((sql, index) => ({
    id: `shop-sales-${index + 1}`, cell_type: 'code', metadata: {},
    execution_count: null, outputs: [],
    source: `%%sql\n${sql.trim()}\n`.match(/[^\n]*\n/g)
  }))
});

if (process.argv.includes('--model-only')) {
  console.log(`Generated ${tables.length} Direct Lake tables and the analytical notebook; report files unchanged.`);
  process.exit(0);
}

const lit = value => ({ expr: { Literal: { Value: typeof value === 'string' ? `'${value.replaceAll("'", "''")}'` : typeof value === 'boolean' ? String(value) : `${value}D` } } });
const color = value => ({ solid: { color: lit(value) } });
const obj = properties => [{ properties }];
const selectorObj = (properties, selector = { id: 'default' }) => [{ properties, selector }];
const field = (table, name, kind = 'Column') => ({ [kind]: { Expression: { SourceRef: { Entity: table } }, Property: name } });
const projection = (table, name, kind = 'Column', displayName) => ({
  field: field(table, name, kind), queryRef: `${table}.${name}`, nativeQueryRef: displayName ?? name
});
const role = (...projections) => ({ projections });
const colors = { 'Net Sales': '#087E8B', Receipts: '#2463A6', 'Average Basket': '#7057A3', 'Scoops per Receipt': '#475569' };
const pages = [];
let current;
let sequence = 0;
const vco = (title, alt = title) => ({
  title: obj({ show: lit(Boolean(title)), text: lit(title ?? ''), fontSize: lit(15), fontFamily: lit('Segoe UI Semibold'), fontColor: color('#172B4D'), titleWrap: lit(true) }),
  background: obj({ show: lit(true), color: color('#FFFFFF'), transparency: lit(0) }),
  border: obj({ show: lit(false), radius: lit(8) }),
  padding: obj({ top: lit(16), bottom: lit(16), left: lit(16), right: lit(16) }),
  visualHeader: obj({ show: lit(false) }),
  general: obj({ altText: lit(alt ?? '') })
});
function visual(key, type, box, title, queryState, objects = {}) {
  const name = id(`${current.name}-${key}`);
  const result = {
    $schema: schema('definition/visualContainer/2.9.0'), name,
    position: { x: box[0], y: box[1], width: box[2], height: box[3], z: sequence * 1000, tabOrder: sequence++ * 1000 },
    visual: { visualType: type, ...(queryState ? { query: { queryState } } : {}), objects, visualContainerObjects: vco(title) }
  };
  current.visuals.push(result);
  return result;
}
function textbox(key, text, box, size = 14, ink = '#475569') {
  const v = visual(key, 'textbox', box, null, null, {
    general: obj({ paragraphs: [{ textRuns: [{ value: text, textStyle: { fontFamily: 'Segoe UI', fontSize: `${size}pt`, color: ink } }] }] })
  });
  v.visual.visualContainerObjects = {
    ...vco(null, text), background: obj({ show: lit(false) }), padding: obj({ top: lit(0), bottom: lit(0), left: lit(0), right: lit(0) })
  };
}
function slicer(table, column, title, box, mode = 'Dropdown') {
  const v = visual(`slicer-${table}`, 'slicer', box, null, { Values: role(projection(table, column)) }, {
    data: obj({ mode: lit(mode) }), header: obj({ show: lit(true), text: lit(title) })
  });
  v.visual.visualContainerObjects.padding = obj({ top: lit(8), bottom: lit(8), left: lit(8), right: lit(8) });
  v.visual.syncGroup = { groupName: `${table}Sync`, fieldChanges: true, filterChanges: true };
  if (table === 'Currency') {
    v.visual.objects.selection = obj({ strictSingleSelect: lit(true), selectAllCheckboxEnabled: lit(false) });
    v.visual.objects.general = obj({ filter: { filter: {
      Version: 2, From: [{ Name: 'c', Entity: 'Currency', Type: 0 }],
      Where: [{ Condition: { In: { Expressions: [{ Column: { Expression: { SourceRef: { Source: 'c' } }, Property: 'Currency' } }], Values: [[{ Literal: { Value: "'EUR'" } }]] } } }]
    } } });
  }
}
function chart(key, title, dim, col, measureName, box, vertical = false, ascending = false, tooltipMeasures = []) {
  const v = visual(key, vertical ? 'columnChart' : 'barChart', box, title, {
    Category: role(projection(dim, col)), Y: role(projection('Sales', measureName, 'Measure')),
    ...(tooltipMeasures.length ? { Tooltips: role(...tooltipMeasures.map(m => projection('Sales', m, 'Measure'))) } : {})
  }, {
    dataPoint: obj({ defaultColor: color(colors[measureName] ?? '#087E8B') }),
    labels: obj({ show: lit(true), fontSize: lit(12), color: color('#172B4D') }),
    categoryAxis: obj({ show: lit(true), axisType: lit('Categorical'), fontSize: lit(12), labelColor: color('#475569'), showAxisTitle: lit(false) }),
    valueAxis: obj({ show: lit(false), start: lit(0), gridlineShow: lit(false), showAxisTitle: lit(false) }),
    legend: obj({ show: lit(false) })
  });
  v.visual.query.sortDefinition = { sort: [{ field: ascending ? field(dim, col) : field('Sales', measureName, 'Measure'), direction: ascending ? 'Ascending' : 'Descending' }], isDefaultSort: true };
  return v;
}
function matrix(key, title, dim, col, names, box) {
  return visual(key, 'pivotTable', box, title, {
    Rows: role(projection(dim, col)), Values: role(...names.map(n => projection('Sales', n, 'Measure', n === 'Receipts' && dim === 'Flavor' ? 'Receipts containing flavor' : n)))
  }, { columnHeaders: obj({ columnAdjustment: lit('growToFit'), autoSizeColumnWidth: lit(true), fontSize: lit(12) }), values: obj({ fontSize: lit(12) }), rowHeaders: obj({ fontSize: lit(12) }) });
}
function page(name, subtitle) {
  current = { name, id: id(name), visuals: [] }; pages.push(current); sequence = 0;
  textbox('brand', 'GELATAI  /  SHOP SALES', [32, 24, 720, 32], 12, '#087E8B');
  textbox('title', name, [32, 64, 864, 64], 30, '#172B4D');
  textbox('subtitle', subtitle, [32, 136, 880, 48], 12);
  slicer('Date', 'Date', 'Local trading date', [960, 48, 344, 112], 'Between');
  slicer('Shop', 'Shop Name', 'Shop', [1328, 48, 312, 112]);
  slicer('Currency', 'Currency', 'Currency', [1664, 48, 224, 112]);
  const nav = visual('navigation', 'pageNavigator', [1040, 984, 848, 64], null, null, {
    text: selectorObj({ fontSize: lit(12), fontColor: color('#172B4D'), fontFamily: lit('Segoe UI Semibold') }),
    fill: [...selectorObj({ show: lit(true), fillColor: color('#E2E8F0') }), ...selectorObj({ show: lit(true), fillColor: color('#D8EEF0') }, { id: 'selected' })],
    layout: obj({ cellPadding: lit(8) })
  });
  nav.visual.visualContainerObjects.background = obj({ show: lit(false) });
}

page('Sales at a glance', 'Recorded sales, not forecasts. Select one currency; no exchange-rate conversion.');
for (const [index, name] of ['Net Sales', 'Receipts', 'Average Basket', 'Scoops per Receipt'].entries()) {
  const v = visual(`kpi-${name}`, 'cardVisual', [32 + index * 232, 208, 208, 168], name, { Data: role(projection('Sales', name, 'Measure')) }, {
    value: selectorObj({ fontSize: lit(28), fontFamily: lit('DIN'), fontColor: color(colors[name]), labelDisplayUnits: lit('1') }),
    label: selectorObj({ show: lit(false) }),
    outline: selectorObj({ show: lit(false) }),
    accentBar: selectorObj({ show: lit(true), color: color(colors[name]), position: lit('Top'), width: lit(4) })
  });
  v.visual.visualContainerObjects.general = obj({ altText: lit(measures.find(m => m.name === name).description) });
}
chart('shop-ranking', 'Which shops generate the most sales?', 'Shop', 'Shop Name', 'Net Sales', [960, 208, 928, 736], false, false, ['Receipts', 'Average Basket', 'Total Paid']);
chart('daily-sales', 'Sales by local trading day', 'Date', 'Date', 'Net Sales', [32, 400, 904, 248], true, true, ['Receipts', 'Discount', 'Tax']);
chart('channel', 'Where do orders come from?', 'Channel', 'Channel', 'Receipts', [32, 672, 904, 272], false, false, ['Channel Share']);
textbox('footnote', 'Simulated data | Net sales exclude tax | Limited history; cadence changed on 28 Oct 2026.', [32, 984, 984, 64], 11);

page('Products & payment mix', 'Allocated flavor sales and distinct receipts. A receipt may contain several flavors.');
const flavorChart = chart('flavors', 'Top 10 flavors by net sales', 'Flavor', 'Flavor', 'Net Sales', [32, 208, 1064, 472], false, false, ['Scoops', 'Receipts', 'Flavor Share']);
flavorChart.filterConfig = { filters: [{
  name: `Filter${id('topten')}0000`, type: 'Advanced', field: field('Sales', 'Flavor Rank', 'Measure'), howCreated: 'User',
  filter: { Version: 2, From: [{ Name: 's', Entity: 'Sales', Type: 0 }], Where: [{ Condition: { Comparison: { ComparisonKind: 4, Left: { Measure: { Expression: { SourceRef: { Source: 's' } }, Property: 'Flavor Rank' } }, Right: { Literal: { Value: '10L' } } } } }] }
}] };
chart('payment', 'How do customers pay?', 'Payment', 'Payment', 'Receipts', [1120, 208, 768, 224], false, false, ['Payment Share']);
chart('serving', 'Which serving formats sell?', 'Serving', 'Serving', 'Receipts', [1120, 456, 768, 224], false, false, ['Serving Share']);
matrix('flavor-detail', 'Flavor contribution and reach', 'Flavor', 'Flavor', ['Net Sales', 'Scoops', 'Receipts', 'Flavor Share'], [32, 704, 1856, 240]);
textbox('footnote', 'Flavor receipt counts overlap. Flavor-filtered basket values represent selected contribution, not the full basket.', [32, 984, 984, 64], 11);

page('Weather & timing', 'Explore associations, not causes. Weather is simulated; sample sizes are shown in tooltips.');
chart('weather', 'Receipts by simulated weather', 'Weather', 'Weather', 'Receipts', [32, 208, 904, 328], false, false, ['Average Basket', 'Average Temperature']);
chart('temperature', 'Average basket by temperature band', 'Sales', 'Temperature Band', 'Average Basket', [960, 208, 928, 328], true, true, ['Receipts']);
chart('hours', 'When are receipts recorded locally?', 'Local Hour', 'Hour', 'Receipts', [32, 560, 1064, 384], true, true, ['Average Basket']);
matrix('weather-detail', 'Weather sample and basket size', 'Weather', 'Weather', ['Receipts', 'Average Basket', 'Average Temperature', 'Net Sales'], [1120, 560, 768, 384]);
textbox('footnote', 'Local shop times | Earlier cadence affects volumes | Simulated weather cannot establish demand impact.', [32, 984, 984, 64], 11);

const themeFile = 'GelatAI-Sales-Calm-61a7de42.json';
const baseTheme = process.argv[2];
if (!baseTheme) throw new Error('Pass the skill base theme path as the first argument.');
const theme = JSON.parse(fs.readFileSync(baseTheme, 'utf8'));
theme.name = themeFile;
theme.dataColors = ['#087E8B', '#2463A6', '#7057A3', '#475569', '#A65B24', '#8E4975'];
for (const [name, cls] of Object.entries(theme.textClasses)) {
  cls.fontFace = name === 'callout' ? 'DIN' : 'Segoe UI';
  cls.color = '#172B4D';
}
theme.textClasses.label.fontSize = 12;
theme.textClasses.title.fontSize = 15;
theme.visualStyles['*']['*'].visualHeader = [{ show: false }];
// These names collide with internal card objects in the capability metadata.
// Apply container safeguards per visual instead of ambiguous type-theme keys.
for (const key of ['border', 'padding', 'spacing']) delete theme.visualStyles.cardVisual['*'][key];
write(path.join(reportDir, 'StaticResources', 'RegisteredResources', themeFile), theme);
write(path.join(reportDir, 'definition.pbir'), {
  $schema: schema('definitionProperties/2.0.0'), version: '4.0',
  datasetReference: { byPath: { path: `../${modelName}.SemanticModel` } }
});
write(path.join(reportDir, 'definition', 'version.json'), { $schema: schema('definition/versionMetadata/1.0.0'), version: '2.0.0' });
write(path.join(reportDir, 'definition', 'report.json'), {
  $schema: schema('definition/report/3.3.0'),
  themeCollection: { customTheme: { name: themeFile, type: 'RegisteredResources', reportVersionAtImport: { visual: '2.9.0', page: '2.1.0', report: '3.3.0' } } },
  resourcePackages: [{ name: 'RegisteredResources', type: 'RegisteredResources', items: [{ name: themeFile, path: themeFile, type: 'CustomTheme' }] }],
  settings: { useStylableVisualContainerHeader: true, exportDataMode: 'AllowSummarized', defaultDrillFilterOtherVisuals: true }
});
write(path.join(reportDir, 'definition', 'pages', 'pages.json'), { $schema: schema('definition/pagesMetadata/1.0.0'), pageOrder: pages.map(p => p.id), activePageName: pages[0].id });
for (const p of pages) {
  const dir = path.join(reportDir, 'definition', 'pages', p.id);
  write(path.join(dir, 'page.json'), {
    $schema: schema('definition/page/2.1.0'), name: p.id, displayName: p.name, width: 1920, height: 1080, displayOption: 'FitToPage',
    objects: { background: obj({ color: color('#F4F7FA'), transparency: lit(0) }) }
  });
  for (const v of p.visuals) write(path.join(dir, 'visuals', v.name, 'visual.json'), v);
}
for (const [dir, type, name] of [[modelDir, 'SemanticModel', modelName], [reportDir, 'Report', reportName]]) {
  write(path.join(dir, '.platform'), { $schema: 'https://developer.microsoft.com/json-schemas/fabric/gitIntegration/platformProperties/2.0.0/schema.json', metadata: { type, displayName: name }, config: { version: '2.0', logicalId: crypto.createHash('md5').update(name).digest('hex').replace(/^(.{8})(.{4})(.{4})(.{4})(.{12})$/, '$1-$2-$3-$4-$5') } });
}
write(path.join(root, 'GelatAI Shop Sales.pbip'), {
  $schema: 'https://developer.microsoft.com/json-schemas/fabric/pbip/pbipProperties/1.0.0/schema.json', version: '1.0',
  artifacts: [{ report: { path: `${reportName}.Report` } }], settings: { enableAutoRecovery: true }
});
console.log(`Generated ${tables.length} tables, ${measures.length} measures, ${relationships.length} relationships, ${pages.length} pages, ${pages.reduce((n, p) => n + p.visuals.length, 0)} visuals.`);
