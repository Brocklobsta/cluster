'use strict';
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const Ajv = require('ajv');
const YAML = require('yaml');

const root = path.resolve(__dirname, '../..');
const wrapperPath = path.join(root, 'schemas/truecharts-helmrelease.schema.json');
const wrapper = JSON.parse(fs.readFileSync(wrapperPath, 'utf8'));
const schemaUrl = wrapper.properties.spec.properties.values.$ref;
if (schemaUrl !== 'https://raw.githubusercontent.com/trueforge-org/truecharts/master/charts/library/common/values.schema.json') {
  throw new Error('Unexpected TrueCharts schema source in editor wrapper.');
}

function* helmReleases(dir) {
  for (const entry of fs.readdirSync(dir, {withFileTypes: true})) {
    const file = path.join(dir, entry.name);
    if (entry.isDirectory()) yield* helmReleases(file);
    else if (entry.name === 'helm-release.yaml') yield file;
  }
}
function parse(file) {
  const doc = YAML.parseDocument(fs.readFileSync(file, 'utf8'), {uniqueKeys: true});
  if (doc.errors.length) throw new Error(`${path.relative(root, file)}: ${doc.errors[0].message}`);
  return doc.toJS();
}
function inventory() {
  return [...helmReleases(path.join(root, 'clusters/main/kubernetes'))]
    .filter(file => parse(file)?.spec?.chart?.spec?.sourceRef?.name === 'truecharts')
    .map(file => path.relative(root, file).split(path.sep).join('/')).sort();
}
function checkEditorMapping(files) {
  const settings = JSON.parse(fs.readFileSync(path.join(root, '.vscode/settings.json'), 'utf8'));
  const mapped = settings['yaml.schemas']['./schemas/truecharts-helmrelease.schema.json'].slice().sort();
  if (JSON.stringify(files) !== JSON.stringify(mapped)) {
    throw new Error('VS Code schema mapping differs from TrueCharts release inventory; update .vscode/settings.json.');
  }
  for (const file of files) {
    if (fs.readFileSync(path.join(root, file), 'utf8').includes('yaml-language-server: $schema=')) {
      throw new Error(`${file}: inline schema directive overrides the editor mapping`);
    }
  }
}
async function main() {
  const response = await fetch(schemaUrl, {headers: {'Cache-Control': 'no-cache'}, signal: AbortSignal.timeout(20000)});
  if (!response.ok) throw new Error(`Fetching TrueCharts master schema failed: HTTP ${response.status}`);
  const bytes = Buffer.from(await response.arrayBuffer());
  const schema = JSON.parse(bytes.toString('utf8'));
  const checksum = crypto.createHash('sha256').update(bytes).digest('hex');
  console.log(`Schema: ${schemaUrl} (SHA-256 ${checksum})`);
  const validate = new Ajv({allErrors: true, strict: false, validateFormats: false}).compile(schema);

  if (process.argv.includes('--self-test')) {
    if (!validate({TZ: 'UTC', chartSpecificSetting: true})) throw new Error('Valid values rejected');
    if (validate({TZ: false})) throw new Error('Invalid TZ type accepted');
    wrapper.$id = 'https://cluster.example/schemas/truecharts-helmrelease.schema.json';
    const wrapperAjv = new Ajv({strict: false, validateFormats: false});
    wrapperAjv.addSchema(schema, schemaUrl);
    const wrappedValidate = wrapperAjv.compile(wrapper);
    const release = {apiVersion: 'helm.toolkit.fluxcd.io/v2', kind: 'HelmRelease', spec: {values: {TZ: 'UTC'}}};
    if (!wrappedValidate(release)) throw new Error('Wrapper rejected valid HelmRelease values');
    release.spec.values.TZ = false;
    if (wrappedValidate(release)) throw new Error('Wrapper accepted invalid HelmRelease values');
    const files = inventory();
    checkEditorMapping(files);
    console.log(`Schema self-test and editor mapping passed for ${files.length} TrueCharts releases.`);
    return;
  }
  const report = process.argv.includes('--report');
  const files = inventory();
  checkEditorMapping(files);
  let checked = 0, invalid = 0;
  for (const name of files) {
    const values = parse(path.join(root, name))?.spec?.values;
    if (values == null) continue;
    checked++;
    if (validate(values)) continue;
    invalid++;
    const errors = validate.errors;
    // No values or schema error parameters are printed: HelmRelease values can contain secrets.
    console.log(`${name}: ${errors.length} issue(s)`);
    for (const error of errors.slice(0, 3)) {
      console.log(`  ${error.instancePath || '/'}: ${error.message}`);
    }
  }
  console.log(`Checked ${checked}/${files.length} TrueCharts HelmReleases: ${invalid} with schema issues.`);
  if (invalid && !report) process.exitCode = 1;
}
main().catch(error => { console.error(error.message); process.exitCode = 2; });
