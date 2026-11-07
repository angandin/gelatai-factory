import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { createHash } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const root = path.dirname(fileURLToPath(import.meta.url));
const read = relative => fs.readFileSync(path.join(root, relative), 'utf8');
const json = relative => JSON.parse(read(relative).replace(/^\uFEFF/, ''));
const manifest = json('workspace-manifest.json');

test('inventory accounts for every item and its five-folder hierarchy', () => {
  assert.equal(manifest.items.length, 28);
  assert.equal(new Set(manifest.items.map(item => item.sourceId)).size, 28);
  assert.equal(manifest.folders.length, 5);
  assert.equal(manifest.items.filter(item => item.parts.length).length, 24);
  assert.equal(manifest.items.filter(item => item.recreation === 'generated').length, 2);
  assert.equal(manifest.items.filter(item => item.recreation === 'parent-managed').length, 6);
  for (const item of manifest.items) {
    if (item.folderId) assert.ok(manifest.folders.some(folder => folder.id === item.folderId));
    if (item.owner) assert.ok(manifest.items.some(owner => owner.sourceId === item.owner));
    if (item.folder) assert.ok(fs.statSync(path.join(root, item.folder)).isDirectory());
  }
  const localFolders = fs.readdirSync(root, { withFileTypes: true }).filter(entry => entry.isDirectory()).map(entry => entry.name);
  assert.deepEqual(localFolders.sort(), manifest.items.filter(item => item.folder).map(item => item.folder).sort());
});

test('every exported part matches its source hash or the one portable PBIP override', () => {
  let parts = 0;
  for (const item of manifest.items) {
    for (const part of item.parts) {
      const file = path.resolve(root, item.folder, part.path);
      assert.ok(file.startsWith(path.resolve(root, item.folder) + path.sep));
      const bytes = fs.readFileSync(file);
      const override = manifest.localOverrides.find(o => o.folder === item.folder && o.part === part.path);
      assert.equal(createHash('sha256').update(bytes).digest('hex'), override?.sha256 ?? part.sha256, `${item.folder}/${part.path}`);
      if (/\.(json|pbir|pbism)$/.test(part.path) || part.path === '.platform') JSON.parse(bytes.toString('utf8'));
      parts++;
    }
  }
  assert.ok(parts > 200);
  assert.equal(manifest.localOverrides.length, 1);
  assert.deepEqual(json('rp_gelatai_shop_sales.Report/definition.pbir').datasetReference,
    { byPath: { path: '../sm_gelatai_shop_sales.SemanticModel' } });
});

test('SQL recreation covers the captured empty-target schema without seeding', () => {
  const catalog = json('GelatAI_shopdb.SQLDatabase/captured-schema.json');
  const sql = read('GelatAI_shopdb.SQLDatabase/captured-schema.sql');
  assert.equal(catalog.tables.length, 18);
  assert.equal(catalog.columns.length, 189);
  assert.equal(catalog.modules.length, 6);
  assert.equal((sql.match(/CREATE TABLE \[dbo\]\./g) ?? []).length, 18);
  assert.equal((sql.match(/FOREIGN KEY \(/g) ?? []).length, 21);
  assert.match(sql, /THROW/);
  assert.equal(catalog.columns.filter(c => c.tableName === 'ShipmentDetails').length, 20);
  const security = json('GelatAI_shopdb.SQLDatabase/security-template.json');
  assert.equal(security.permissions.length, 5);
  assert.equal(security.roleMemberships.length, 1);
  for (const grant of security.permissions) assert.ok(security.principals.some(p => p.parameter === grant.principalParameter));
  assert.ok(!JSON.stringify(security).includes('principalName'));
  const deployment = read('GelatAI_shopdb.SQLDatabase/deploy.ps1');
  assert.match(deployment, /if \(\$IncludeSeedData\)/);
});

test('Delta metadata and shortcut coverage use native schemas rather than notebook execution', () => {
  const native = json('GelatAI_lakehouse.Lakehouse/native-delta-schema.json');
  const sql = read('GelatAI_lakehouse.Lakehouse/schema-bootstrap.sql');
  assert.equal(native.length, 16);
  assert.equal((sql.match(/CREATE TABLE IF NOT EXISTS/g) ?? []).length, 16);
  assert.ok(!/\bINSERT\b|CREATE OR REPLACE TABLE/.test(sql));
  for (const table of native) {
    assert.match(sql, new RegExp('`' + table.schema + '`\\.`' + table.name + '`'));
    for (const field of JSON.parse(table.metadata.schemaString).fields) {
      assert.ok(sql.includes('`' + field.name + '`'));
    }
    assert.ok(table.protocol.minReaderVersion);
  }
  const lakehouse = manifest.items.find(item => item.type === 'Lakehouse');
  assert.equal(lakehouse.shortcuts.length, 19);
  assert.equal(lakehouse.shortcuts.filter(s => s.path.includes('sc_shopdb')).length, 18);
  const caching = read('GelatAI-rtdata.KQLDatabase/captured-policies.kql');
  assert.match(caching, /policy caching hot=36500d hotindex=36500d/);
});

test('schedules and unavailable configuration remain explicit, never success-shaped stubs', () => {
  const notebooks = manifest.items.filter(item => item.type === 'Notebook');
  const registry = notebooks.find(item => item.displayName === 'nb_update_shop_registry');
  const schedules = Array.isArray(registry.schedules) ? registry.schedules : [registry.schedules];
  assert.equal(schedules.length, 1);
  assert.equal(schedules[0].enabled, true);
  assert.deepEqual(schedules[0].configuration.times, ['02:00']);
  assert.deepEqual(schedules[0].configuration.weekdays, ['Monday']);
  for (const notebook of notebooks.filter(item => item !== registry)) assert.equal(notebook.schedules?.length ?? 0, 0);
  const ontology = manifest.items.find(item => item.displayName === 'Gelantology_v3' && item.type === 'Ontology');
  assert.equal(ontology.recreation, 'blocked');
  assert.equal(ontology.parts.length, 0);
  assert.ok(manifest.blockers.some(blocker => blocker.code === 'ALMOperationBadRequest'));
  assert.ok(manifest.blockers.some(blocker => blocker.code === 'SQL_DATABASE_SETTINGS_UNAVAILABLE'));
  assert.ok(manifest.workspaceRoleAssignments.every(role => role.principalParameter && !role.sourcePrincipalId));
});

test('sales authoring refuses implicit baseline regeneration before touching files', () => {
  const result = spawnSync(process.execPath, [path.join(root, 'author-shop-sales.mjs'), '--model-only'],
    { encoding: 'utf8', env: { ...process.env, ELECTRON_RUN_AS_NODE: '1' } });
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /overwrite-captured-baseline/);
});
