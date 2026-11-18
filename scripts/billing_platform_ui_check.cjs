// Read-only browser acceptance for the shared multi-product workspace.
const assert=require('node:assert/strict');
const fs=require('node:fs');
const {chromium}=require(process.env.SAVVY_PLAYWRIGHT_MODULE||'playwright');
const base=process.env.SAVVY_PREVIEW_ORIGIN||'http://127.0.0.1:3106';
assert(['http://127.0.0.1:3100','http://127.0.0.1:3104','http://127.0.0.1:3106'].includes(base));
(async()=>{
 const browser=await chromium.launch({executablePath:process.env.SAVVY_BROWSER_BINARY||(process.platform==='darwin'?'/Applications/Google Chrome.app/Contents/MacOS/Google Chrome':undefined),headless:true});
 const page=await browser.newPage({viewport:{width:1440,height:1000}}),errors=[],queries=[];let checks=0;
 page.setDefaultTimeout(10000);
 page.on('pageerror',e=>errors.push(e.message));page.on('request',r=>{if(r.url().endsWith('/api/graphql'))queries.push(JSON.parse(r.postData()||'{}').query||'')});
 const check=(v,label)=>{assert(v,label);checks++};
 const nav=async name=>page.getByRole('navigation',{name:'Workspace navigation'}).getByRole('button',{name,exact:true}).click();
 const ready=async text=>page.getByRole('heading',{name:text,exact:true}).waitFor();
 const identity=async audience=>{const d=page.locator('.aud-presenter details');if(await d.getAttribute('open')===null)await d.locator('summary').click();await page.getByLabel('View as').selectOption(audience)};
 try{
 await page.goto(base);await ready('Your business at a glance.');
 for(const business of ['advisor','ria']){
  await page.locator('.aud-account-label select').selectOption(business);await ready('Your business at a glance.');
  check(await page.locator('.dw-heading select').locator('option').count()>=2,'Both products have multiple issued periods');
  await nav('Clients');await ready('Clients & accounts.');
  await page.locator('.aud-list>button').first().waitFor();check(await page.locator('.aud-list>button').count()===3,'Book starts with client groups');
  await page.locator('.aud-list>button').first().click();await page.getByRole('button',{name:'← Back to clients'}).waitFor();
  await page.getByRole('button',{name:'View billing →'}).first().waitFor();check(await page.getByRole('button',{name:'View billing →'}).count()===2,'Accounts are behind a client drilldown');
  await page.getByRole('button',{name:'View billing →'}).first().click();await page.getByRole('dialog').waitFor();
  check((await page.getByRole('dialog').innerText()).includes('Invoice'),'Client drilldown opens its billing documents');await page.keyboard.press('Escape');
  await nav('Statements');await ready('Statements & invoices.');await page.locator('.aud-list>button').filter({hasText:'Invoice ·'}).first().click();await page.getByRole('dialog').waitFor();
  let text=await page.getByRole('dialog').innerText();check(text.includes('PAYER')&&text.includes('DUE')&&text.includes('Calculation basis'),'Traditional invoices carry dates, parties and applied terms');
  check(await page.getByRole('dialog').locator('tbody tr').count()>=2,'Native account allocations are visible');
  if(business==='ria'){check(text.includes('Source-reported · excluded from this bill')&&text.includes('$1,200.00'),'Custody income is separately evidenced, never netted into platform fees')}
  await page.keyboard.press('Escape');await nav('Agreements');await ready('Agreements & terms.');check((await page.locator('main').innerText()).includes('Signed agreement not yet provided'),'Agreement viewer stays honest');
  await identity('product');await ready('From source records to a client statement.');
  await page.getByRole('button',{name:'Change commercial terms →'}).click();await page.getByRole('dialog').waitFor();check(await page.getByRole('button',{name:'Save and compare',exact:true}).count()===1,'Product edits reviewed API policy components');await page.keyboard.press('Escape');
  await nav('Data lineage');await ready('Data lineage.');check((await page.locator('main').innerText()).includes('PostgreSQL work queue'),'Pipeline explains its actual worker');
  await page.getByRole('button',{name:'View execution →'}).first().click();await page.getByRole('dialog').waitFor();check((await page.getByRole('dialog').innerText()).includes('BillingNormalizeJob'),'Execution opens retained evidence');await page.keyboard.press('Escape');
  await nav('Work queue');await ready('Billing requests.');check(!(await page.locator('main').innerText()).includes('INTERNAL_ERROR'),'Review queue opens without requiring pending fixture work');
  await identity('finance');await ready('Billing, cash & recognition.');await page.locator('.aud-list>button').first().waitFor();check(await page.getByRole('button',{name:'Issue correction documents'}).count()===0,'Finance reviews; Product issues');await page.locator('.aud-list>button').first().click();await page.getByRole('dialog').waitFor();check((await page.getByRole('dialog').innerText()).includes('Recognition evidence'),'Finance connects native claims, cash and recognition');await page.keyboard.press('Escape');
  await identity('client');await ready('Your business at a glance.');
 }
 fs.mkdirSync('.runtime/four-capabilities/results',{recursive:true});await page.screenshot({path:'.runtime/four-capabilities/results/billing-desktop.png'});
 for(const width of [390,320]){await page.setViewportSize({width,height:844});check(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),`Client overview fits ${width}px`);await nav('Statements');await ready('Statements & invoices.');await page.locator('.aud-list>button').first().click();await page.getByRole('dialog').waitFor();check(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),`Invoice modal fits ${width}px`);await page.keyboard.press('Escape');await nav('Overview');await ready('Your business at a glance.')}
 await page.screenshot({path:'.runtime/four-capabilities/results/billing-mobile.png'});
 check(queries.every(q=>!/^\s*mutation/.test(q)),'Acceptance sends no mutations');check(!errors.length,'No browser errors: '+errors.join('; '));
 console.log(JSON.stringify({checks,both_products:true,read_only:true,errors}));
 }finally{await browser.close()}
})().catch(e=>{console.error(e);process.exitCode=1});
