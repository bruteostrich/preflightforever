// Rebuild runtime flight facts from a single, explicitly selected client build.
// Download the three CSVs into research/sources/<build>/ and record their
// URLs, retrieval date and SHA256 in manifest.json first. This importer
// deliberately performs no network requests.
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');

const root = path.resolve(__dirname, '..');
const build = process.argv[2] || '1.60.1.71091';
if (!/^1\.60\.\d+\.\d+$/.test(build)) throw new Error('Expected a WoW Forever build such as 1.60.1.71091.');
const source = path.join(root, 'research', 'sources', build);
const manifest = JSON.parse(fs.readFileSync(path.join(source, 'manifest.json'), 'utf8'));
if (manifest.build !== build || !/^\d{4}-\d{2}-\d{2}$/.test(manifest.retrieved)) throw new Error('Missing source build/retrieval provenance.');
const hashes = {};

function csv(text) {
  const records = [];
  let record = [], field = '', quoted = false;
  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (quoted) {
      if (c === '"' && text[i + 1] === '"') { field += '"'; i++; }
      else if (c === '"') quoted = false;
      else field += c;
    } else if (c === '"' && field === '') quoted = true;
    else if (c === ',') { record.push(field); field = ''; }
    else if (c === '\n' || c === '\r') {
      if (c === '\r' && text[i + 1] === '\n') i++;
      record.push(field); field = '';
      if (record.some(value => value !== '')) records.push(record);
      record = [];
    } else field += c;
  }
  if (quoted) throw new Error('Unterminated CSV quoted field.');
  if (field !== '' || record.length) { record.push(field); records.push(record); }
  const header = records.shift();
  if (!header || new Set(header).size !== header.length) throw new Error('Missing or duplicate CSV header.');
  return records.map((values, index) => {
    if (values.length !== header.length) throw new Error(`CSV row ${index + 2} has the wrong column count.`);
    return Object.fromEntries(header.map((key, i) => [key, values[i]]));
  });
}

function load(table, columns) {
  const bytes = fs.readFileSync(path.join(source, `${table}.csv`));
  hashes[table] = crypto.createHash('sha256').update(bytes).digest('hex');
  const entry = manifest.tables && manifest.tables[table];
  if (!entry || entry.sha256 !== hashes[table] || entry.url !== `https://wago.tools/db2/${table}/csv?build=${build}`) {
    throw new Error(`${table}: source hash or URL differs from the recorded manifest.`);
  }
  const rows = csv(bytes.toString('utf8').replace(/^\uFEFF/, ''));
  if (!rows.length || columns.some(column => !(column in rows[0]))) throw new Error(`${table}: missing required columns or rows.`);
  return rows;
}

function number(row, key) {
  if (row[key] === '') throw new Error(`Missing numeric ${key}.`);
  const value = Number(row[key]);
  if (!Number.isFinite(value)) throw new Error(`Invalid numeric ${key}: ${row[key]}`);
  return value;
}

function integer(row, key, minimum = 0) {
  const value = number(row, key);
  if (!Number.isSafeInteger(value) || value < minimum) throw new Error(`Invalid integer ${key}: ${row[key]}`);
  return value;
}

const nodeRows = load('TaxiNodes', ['ID', 'Name_lang', 'Flags', 'CharacterBitNumber', 'ContinentID']);
const pathRows = load('TaxiPath', ['ID', 'FromTaxiNode', 'ToTaxiNode', 'Cost']);
const pointRows = load('TaxiPathNode', ['PathID', 'NodeIndex', 'ContinentID', 'Loc_0', 'Loc_1', 'Loc_2', 'Flags']);
const nodes = new Map();
const nodeIDs = new Set();
for (const row of nodeRows) {
  const id = integer(row, 'ID', 1), flags = integer(row, 'Flags');
  if (nodeIDs.has(id)) throw new Error(`Duplicate taxi node ${id}.`);
  nodeIDs.add(id);
  // Ordinary discoverable faction-compatible flight services only. Nighthaven
  // class services have no character bit; transport anchors lack faction bits.
  if (!(flags & 3) || !integer(row, 'CharacterBitNumber') || /^zzOLD/i.test(row.Name_lang.trim())) continue;
  const continent = integer(row, 'ContinentID');
  if (continent !== 0 && continent !== 1) continue;
  nodes.set(id, { id, continent, faction: flags & 3 });
}

const geometry = new Map();
for (const row of pointRows) {
  const id = integer(row, 'PathID', 1);
  if (!geometry.has(id)) geometry.set(id, []);
  geometry.get(id).push({ index: integer(row, 'NodeIndex'), continent: integer(row, 'ContinentID'),
    x: number(row, 'Loc_0'), y: number(row, 'Loc_1'), z: number(row, 'Loc_2'), flags: integer(row, 'Flags') });
}

const edges = [], seen = new Set();
for (const row of pathRows) {
  const from = integer(row, 'FromTaxiNode'), to = integer(row, 'ToTaxiNode');
  const a = nodes.get(from), b = nodes.get(to);
  if (!a || !b || from === to || a.continent !== b.continent || !(a.faction & b.faction)) continue;
  const id = integer(row, 'ID', 1), cost = integer(row, 'Cost');
  const key = `${from}:${to}`;
  // A duplicated ordered pair needs investigation, not an invented preference.
  if (seen.has(key)) throw new Error(`Multiple native paths for ${key}; resolve explicitly before generating.`);
  seen.add(key);
  const points = (geometry.get(id) || []).sort((x, y) => x.index - y.index);
  if (points.length < 2) throw new Error(`Path ${id} lacks complete geometry.`);
  let yards = 0;
  for (let i = 0; i < points.length; i++) {
    const p = points[i];
    if (p.index !== i || p.continent !== a.continent || (p.flags & 1)) throw new Error(`Path ${id} has a gap, teleport, or map transition.`);
    if (i) {
      const q = points[i - 1];
      yards += Math.hypot(p.x - q.x, p.y - q.y, p.z - q.z);
    }
  }
  yards = Math.round(yards);
  if (!Number.isFinite(yards) || yards <= 0) throw new Error(`Path ${id} has no positive distance.`);
  edges.push({ from, to, yards, id, cost });
}
edges.sort((a, b) => a.from - b.from || a.to - b.to);
if (!edges.length) throw new Error('The selected build contains no ordinary flight connections.');

const lines = [
  '-- Generated by scripts/ImportTaxiData.cjs; do not edit flight facts by hand.',
  `-- Blizzard WoW Forever client build ${build}; game data copyright Blizzard Entertainment.`,
  `-- Source: public wago.tools DB2 CSV exports, retrieved ${manifest.retrieved}.`,
];
for (const table of ['TaxiNodes', 'TaxiPath', 'TaxiPathNode']) {
  lines.push(`-- https://wago.tools/db2/${table}/csv?build=${build}`, `-- SHA256 ${hashes[table]}`);
}
lines.push('-- Ordinary discoverable nodes only: faction bits, character bit, active name, continents 0/1.',
  '-- Directed edges retain native TaxiPath identity/cost; distances sum the full 3D TaxiPathNode geometry.',
  '-- Cost is preserved for auditing, not used as an assumed client routing weight.', '', 'local _, ns = ...',
  `ns.RouteDataBuild = "${build}"`, `ns.RouteDataNodeCount = ${nodes.size}`, '',
  '-- source node ID, destination node ID, rounded yards flown', 'ns.RouteEdges = {');
for (const edge of edges) lines.push(`    ${edge.from},${edge.to},${edge.yards},`);
lines.push('}', '', '-- Native directed-path metadata; fares at the NPC can include discounts.', 'ns.RouteEdgeInfo = {');
let previous;
for (const edge of edges) {
  if (previous !== edge.from) {
    if (previous !== undefined) lines.push('    },');
    previous = edge.from;
    lines.push(`    [${edge.from}] = {`);
  }
  lines.push(`        [${edge.to}] = { pathID = ${edge.id}, cost = ${edge.cost} },`);
}
if (previous !== undefined) lines.push('    },');
lines.push('}', '');
const output = path.join(root, 'RoutesData.lua');
fs.writeFileSync(output, lines.join('\n'));
console.log(`Generated ${path.relative(root, output)}: ${nodes.size} ordinary nodes, ${edges.length} directed links; ${edges.filter(edge => edge.cost === 0).length} zero-fare links. Build ${build}.`);
