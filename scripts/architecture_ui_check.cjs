/* Read-only acceptance of the standalone architecture walkthrough. */
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const { chromium } = require(process.env.SAVVY_PLAYWRIGHT_MODULE || 'playwright');
const root = path.resolve(__dirname, '..');
const artifacts = path.join(root, '.runtime/architecture');
fs.mkdirSync(artifacts, { recursive: true });
const origin = 'http://127.0.0.1:3105';
const checks = [];
function check(value, name) { assert.ok(value, name); checks.push(name); }

(async () => {
  const browser = await chromium.launch({
    executablePath: process.env.SAVVY_BROWSER_BINARY || (process.platform === 'darwin' ? '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome' : undefined),
    headless: true,
  });
  try {
    const page = await browser.newPage({ viewport: { width: 1440, height: 1050 } });
    const errors = [];
    page.on('pageerror', e => errors.push(e.message));
    page.on('console', m => { if (m.type() === 'error') errors.push(m.text()); });
    await page.goto(origin);
    await page.evaluate(() => document.fonts.ready);
    check(await page.getByRole('tab').count() === 3, 'Three architecture views');
    const components = await page.evaluate(() => Object.keys(DATA.components));
    const nodes = await page.evaluate(() => SAMPLE.policy_graph.nodes.map(n => n.id));
    for (const tab of ['overview', 'architecture', 'engine']) {
      await page.locator(`[data-tab="${tab}"]`).click();
      await page.waitForFunction(tab => document.getElementById(tab).hidden === false, tab);
      check(await page.locator('.panel:visible').count() === 1, `Only ${tab} panel is visible`);
      check(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), `${tab} desktop has no horizontal overflow`);
      await page.evaluate(() => window.scrollTo(0,0));
      await page.screenshot({ path: path.join(artifacts, `${tab}.png`), fullPage: true });
    }
    for (const id of components) {
      await page.evaluate(id => { location.hash = `architecture/component/${id}`; }, id);
      await page.locator('#detail[open]').waitFor();
      check((await page.locator('#detail-title').innerText()).length > 0, `${id} has a component explanation`);
      check(await page.locator('#detail .source-item').count() > 0, `${id} has actual source references`);
      check(await page.locator('#detail a[href*="github.com/"]').count() > 0, `${id} has pinned GitHub links`);
      await page.keyboard.press('Escape');
      await page.locator('#detail[open]').waitFor({ state: 'hidden' });
    }
    await page.locator('[data-tab="engine"]').click();
    for (const id of nodes) {
      await page.evaluate(id => { location.hash = `engine/node/${id}`; }, id);
      await page.locator('#detail[open]').waitFor();
      check(await page.locator('#detail-title').innerText() === id, `${id} opens its exact stored policy node`);
      await page.keyboard.press('Escape');
      await page.locator('#detail[open]').waitFor({ state: 'hidden' });
    }
    await page.locator('[data-tab="overview"]').click();
    const engine = page.locator('#overview-flow [data-component="engine"]');
    await engine.click();
    await page.locator('#detail[open]').waitFor();
    await page.screenshot({ path: path.join(artifacts, 'engine-modal.png') });
    for (let i = 0; i < 12; i++) {
      await page.keyboard.press('Tab');
      check(await page.evaluate(() => document.getElementById('detail').contains(document.activeElement)), 'Native dialog traps keyboard focus');
    }
    await page.keyboard.press('Escape');
    check(await engine.evaluate(el => el === document.activeElement), 'Escape returns focus to the invoking component');
    await page.locator('[data-tab="overview"]').focus();
    await page.keyboard.press('ArrowRight');
    await page.waitForFunction(() => document.getElementById('architecture').hidden === false);
    check(await page.locator('#tab-architecture').evaluate(el => el === document.activeElement), 'Keyboard arrow selects and focuses next tab');
    const source = await browser.newPage();
    const sourceMap = JSON.parse(fs.readFileSync(path.join(root, 'docs/architecture/source-map.json'), 'utf8'));
    for (const name of sourceMap.paths) {
      const response = await page.request.get(`${origin}/source/${name}?raw=1`);
      check(response.status() === 200 && (await response.text()) === fs.readFileSync(path.join(root, name), 'utf8'), `${name} link returns the actual local file`);
    }
    await source.goto(`${origin}/source/apps/api/app/domains/economics/engine.rb#L263`);
    check(await source.locator('#L263').count() === 1, 'Source viewer provides exact line anchors');
    await source.close();
    const denied = await page.request.get(`${origin}/source/.env`);
    check(denied.status() === 404, 'Non-allowlisted files cannot be read');
    const traversal = await page.request.get(`${origin}/source/%2e%2e/%2e%2e/etc/passwd`);
    check(traversal.status() === 404, 'Path traversal cannot access files');
    const hostDenied = await page.request.get(`${origin}/`, { headers: { Host: 'invalid.example' } });
    check(hostDenied.status() === 403, 'Unexpected host header is rejected');
    const writeDenied = await page.request.post(`${origin}/`, { data: 'test' });
    check(writeDenied.status() === 501, 'Preview has no write endpoint');
    const download = await page.request.get(`${origin}/download`);
    check(download.status() === 200 && download.headers()['content-disposition'].includes('attachment'), 'Standalone HTML is downloadable');
    await page.setViewportSize({ width: 390, height: 844 });
    for (const tab of ['overview', 'architecture', 'engine']) {
      await page.locator(`[data-tab="${tab}"]`).click();
      await page.waitForFunction(tab => document.getElementById(tab).hidden === false, tab);
      check(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), `${tab} at 390px has no horizontal overflow`);
      await page.screenshot({ path: path.join(artifacts, `${tab}-mobile.png`), fullPage: true });
    }
    await page.locator('#graph-nodes [data-node="charge"]').click();
    check(await page.locator('#detail').evaluate(el => el.scrollWidth <= el.clientWidth), 'Node modal fits mobile width');
    await page.screenshot({ path: path.join(artifacts, 'node-mobile.png') });
    await page.keyboard.press('Escape');
    await page.setViewportSize({ width: 1440, height: 1050 });
    await page.emulateMedia({ media: 'print' });
    check(await page.locator('.panel:visible').count() === 3, 'Print includes all three views');
    await page.emulateMedia({ media: 'screen' });
    const offline = await browser.newPage();
    const offlineErrors = [];
    offline.on('pageerror', e => offlineErrors.push(e.message));
    await offline.goto('file://' + path.join(root, 'docs/architecture/index.html'));
    await offline.locator('#overview-flow [data-component="engine"]').click();
    check(await offline.locator('#detail[open]').count() === 1 && !offlineErrors.length, 'Downloaded HTML works offline with modal explanations and captured code');
    await offline.close();
    check(errors.length === 0, 'No browser runtime or console errors');
    fs.writeFileSync(path.join(artifacts, 'ui-check.json'), JSON.stringify({ checks, componentCount: components.length, nodeCount: nodes.length, errors }, null, 2));
    console.log(`${checks.length} architecture checks passed; ${components.length} components; ${nodes.length} policy nodes.`);
  } finally { await browser.close(); }
})().catch(error => { console.error(error); process.exitCode = 1; });
