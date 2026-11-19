'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const path = require('node:path');
const {pathToFileURL} = require('node:url');
const {chromium} = require(process.env.SAVVY_PLAYWRIGHT_MODULE || '../docs/architecture/node_modules/playwright');

const localPage = path.resolve('.runtime/publication/site/evidence/index.html');
const fixture = path.resolve('fixtures/campfire-trace/dimension-walkthrough.json');

async function check() {
  const options = {headless:true, ...(process.env.SAVVY_CHROME_PATH ? {executablePath:process.env.SAVVY_CHROME_PATH} : {})};
  const browser = await chromium.launch(options);
  try {
    const page = await browser.newPage({acceptDownloads:true, viewport:{width:1360,height:980}});
    const requests = [];
    const errors = [];
    page.on('pageerror', error => errors.push(error.message));
    const site = process.env.SAVVY_EVIDENCE_SITE;
    if (site) {
      await page.goto(new URL('/', site).href);
      const link = page.getByRole('link', {name:'Evidence map',exact:true});
      assert.equal(await link.getAttribute('href'), '/evidence/');
      await link.click();
      assert.equal(new URL(page.url()).pathname, '/evidence/');
    } else {
      await page.goto(pathToFileURL(localPage).href);
    }
    await page.context().setOffline(true);
    page.on('request', request => {if (/^https?:/.test(request.url())) requests.push(request.url());});
    const button = page.getByRole('button', {name:'Download gap list (CSV)',exact:true});
    const startingRecord = page.getByRole('combobox', {name:'Starting record',exact:true});
    const input = page.locator('#record-files');
    const review = page.getByRole('button', {name:'Review reporting dimensions',exact:true});
    const preview = page.getByRole('dialog');
    const field = name => preview.getByRole('row').filter({has:page.getByRole('rowheader',{name,exact:true})});

    async function downloadCsv() {
      const [download] = await Promise.all([page.waitForEvent('download'), button.click()]);
      assert.equal(download.suggestedFilename(), 'savvy-reporting-gaps.csv');
      assert.equal(await download.failure(), null);
      return fs.readFile(await download.path(), 'utf8');
    }
    await startingRecord.selectOption({label:'Report or export · report-demo'});
    const expected = page.getByRole('button',{name:'Preview Billing rollup',exact:true});
    await expected.click();
    assert.deepEqual(await field('Total amount').getByRole('cell').allTextContents(), ['—','To confirm']);
    await page.keyboard.press('Escape');
    await preview.waitFor({state:'hidden'});
    await page.waitForFunction(() => document.activeElement.getAttribute('aria-label') === 'Preview Billing rollup');
    await page.getByRole('button',{name:'Preview Campfire accounting',exact:true}).click();
    assert.deepEqual(await field('Record ID').getByRole('cell').allTextContents(), ['journal-demo','Supplied']);
    assert.match(await preview.getByRole('table',{name:'Supplied rows'}).innerText(), /gl-demo/);
    await preview.getByRole('button',{name:'Close',exact:true}).click();
    await review.click();
    const demo = await downloadCsv();
    assert.match(demo, /"Recommended assignment or carry-forward"/);
    assert.match(demo, /"Customer","Prototype handoff gap"/);
    assert.match(demo, /"Cost center","Prototype field gap"/);
    assert.match(demo, /"Invoice · invoice-demo","Accounting package · package-demo"/);
    assert.match(demo, /"Unreviewed field · partner channel","Possible loss in supplied handoff"/);
    assert.doesNotMatch(demo, /"Posting period","Prototype/);
    assert.doesNotMatch(demo, /customer-demo|channel-demo|gl-demo/);
    if (process.env.SAVVY_GAP_SAMPLE_OUTPUT) await fs.writeFile(process.env.SAVVY_GAP_SAMPLE_OUTPUT, demo);

    await input.setInputFiles(fixture);
    await page.waitForFunction(() => document.querySelector('#download-gaps').disabled);
    await page.getByRole('button', {name:'Confirm types & build map',exact:true}).click();
    await startingRecord.selectOption({label:'Calculation · calculation-demo'});
    await review.click();
    assert.match(await downloadCsv(), /"Calculation · calculation-demo","Customer","Prototype handoff gap"/);

    await page.getByRole('button', {name:'Clear imports',exact:true}).click();
    await input.setInputFiles({name:'invoice.json',mimeType:'application/json',
      buffer:Buffer.from('{"kind":"invoice","id":"test-invoice","journal_entry":"unseen-journal","total_amount":"125.00"}')});
    await page.locator('#cycle-anchor').getByText(/test-invoice/).waitFor();
    await page.getByRole('button',{name:'Preview Campfire accounting',exact:true}).click();
    assert.deepEqual(await field('Record ID').getByRole('cell').allTextContents(), ['unseen-journal','Reference']);
    assert.deepEqual(await field('Currency').getByRole('cell').allTextContents(), ['—','To confirm']);
    await preview.getByRole('button',{name:'Close',exact:true}).click();
    await page.getByRole('button', {name:'Clear imports',exact:true}).click();
    await input.setInputFiles({name:'report-columns.csv',mimeType:'text/csv',buffer:Buffer.from('Cost Center,Customer ID,Amount\n')});
    await page.locator('#cycle-anchor').getByText(/Report or export/).waitFor();
    await review.click();
    const single = await downloadCsv();
    assert.match(single, /"Cost center","Prototype field gap"/);
    assert.match(single, /Declared · Cost Center/);
    assert.doesNotMatch(single, /Possible loss in supplied handoff/);
    await page.setViewportSize({width:320,height:900});
    assert.ok(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth));
    await page.getByRole('button',{name:'Preview starting record',exact:true}).click();
    const bounds = await preview.boundingBox();
    assert.ok(bounds.x >= 0 && bounds.x + bounds.width <= 320);
    assert.deepEqual(await field('Columns').getByRole('cell').allTextContents(), ['Cost Center, Customer ID, Amount','Declared']);
    await page.keyboard.press('Escape');
    assert.deepEqual(requests, []);
    assert.deepEqual(errors, []);
    console.log('Evidence map, record previews, offline CSV export, pending import protection and mobile layout passed.');
  } finally {
    await browser.close();
  }
}

check().catch(error => {console.error(error); process.exitCode = 1;});
