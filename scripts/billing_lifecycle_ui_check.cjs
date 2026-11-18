// Read-only proof of the completed four-capability journeys. Mutation stress is
// separately run against the disposable database; this check is safe for cutover.
const assert=require('node:assert/strict');const fs=require('node:fs');
const {chromium}=require(process.env.SAVVY_PLAYWRIGHT_MODULE||'playwright');
const origin=process.env.SAVVY_PREVIEW_ORIGIN||'http://127.0.0.1:3106';
assert(['http://127.0.0.1:3100','http://127.0.0.1:3104','http://127.0.0.1:3106'].includes(origin));
(async()=>{
const browser=await chromium.launch({executablePath:process.env.SAVVY_BROWSER_BINARY||(process.platform==='darwin'?'/Applications/Google Chrome.app/Contents/MacOS/Google Chrome':undefined),headless:true});
const page=await browser.newPage({viewport:{width:1440,height:1000}});page.setDefaultTimeout(12000);let checks=0;const errors=[],requests=[];
page.on('pageerror',e=>errors.push(e.message));page.on('request',r=>{if(r.url().endsWith('/api/graphql'))requests.push(JSON.parse(r.postData()||'{}').query||'')});
const check=(value,label)=>{assert(value,label);checks++};
const ready=async label=>page.getByRole('heading',{name:label,exact:true}).waitFor();
const nav=async label=>page.getByRole('navigation',{name:'Workspace navigation'}).getByRole('button',{name:label,exact:true}).click();
const identity=async value=>{const detail=page.locator('.aud-presenter details');if(await detail.getAttribute('open')===null)await detail.locator('summary').click();await page.getByLabel('View as').selectOption(value)};
try{
 await page.goto(origin);await ready('Your business at a glance.');
 for(const product of ['advisor','ria']){
  await page.locator('.aud-account-label select').selectOption(product);await ready('Your business at a glance.');
  await nav('Earnings');await ready('Earnings & payouts.');await page.locator('.aud-list>button').first().waitFor();
  check((await page.locator('main').innerText()).includes('Calculated earnings'),'Current engine estimate is separate from approval');
  await page.locator('.aud-list>button').first().click();await page.getByRole('dialog').waitFor();let text=await page.getByRole('dialog').innerText();
  check(text.includes('Net approved earnings')&&text.includes('Payments applied')&&text.includes('Outstanding'),'Earnings distinguishes approved, paid and owed');
  check(text.includes('Earnings composition'),'Earnings opens its component explanation');
  if(product==='advisor')check(text.includes('Salary')&&text.includes('Bonus')&&text.includes('Loan repayment'),'Salary, bonus and loan deduction remain distinguishable');
  check(await page.getByRole('button',{name:'Apply confirmed evidence'}).count()===0,'Client cannot apply cash');await page.keyboard.press('Escape');
  await identity('finance');await ready('Billing, cash & recognition.');
  await page.getByRole('button',{name:/Recognition.*Versioned mock Campfire/}).click();await page.getByRole('dialog').waitFor();text=await page.getByRole('dialog').innerText();
  check(text.includes('Matches the current claim and cash applications'),'Recognition is bound to the actual bill/cash package');
  check(text.includes('Mock journal: mock-october-'),'Accounting journal remains an explicit mock');
  check(text.includes('Cash applications')&&text.includes('Reported AR / credit'),'Finance joins billing, cash and accounting evidence');
  check(!text.includes('No validated accounting outcome'),'Known outcome is displayed without inference');
  check(await page.getByRole('button',{name:'Prepare mock accounting package'}).count()===1,'Finance prepares a versioned handoff');
  await page.keyboard.press('Escape');
  await page.locator('.dw-heading select').selectOption('2026-09-01|2026-10-01');await page.locator('.aud-list>button').filter({hasText:'Credit balance'}).first().waitFor();
  await page.locator('.aud-list>button').filter({hasText:'Credit balance'}).first().click();await page.getByRole('dialog').waitFor();text=await page.getByRole('dialog').innerText();
  check(text.includes('$30.00')&&text.includes('$50.00')&&text.includes('$20.00'),'Excess credit, requested refund and confirmed partial refund stay separate');
  check(text.includes('independently confirmed'),'Refund request is not presented as payment');
  await page.keyboard.press('Escape');await identity('product');await ready('From source records to a client statement.');
  await nav('Data lineage');await ready('Data lineage.');check((await page.locator('main').innerText()).includes('PostgreSQL work queue'),'Actual queue architecture is shown');
  check((await page.locator('main').innerText()).includes('BillingEvaluateJob · Completed'),'Executed batch work has a retained worker receipt');
  await page.getByRole('button',{name:'View attempt →'}).first().click();await page.getByRole('dialog').waitFor();check((await page.getByRole('dialog').innerText()).includes('Work attempt'),'Worker attempt opens as evidence');await page.keyboard.press('Escape');
  await identity('client');await ready('Your business at a glance.');
 }
 fs.mkdirSync('.runtime/lifecycle/results',{recursive:true});
 await identity('finance');await ready('Billing, cash & recognition.');await page.screenshot({path:'.runtime/lifecycle/results/finance-desktop.png'});
 for(const width of [390,320]){
  await page.setViewportSize({width,height:844});check(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),`Finance fits ${width}px`);
  await page.getByRole('button',{name:/Recognition.*Versioned mock Campfire/}).click();await page.getByRole('dialog').waitFor();check(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),`Finance modal fits ${width}px`);await page.keyboard.press('Escape');
 }
 await page.screenshot({path:'.runtime/lifecycle/results/finance-mobile.png'});
 check(requests.every(q=>!/^\s*mutation/.test(q)),'Acceptance is read-only');check(!errors.length,'No browser errors: '+errors.join('; '));
 console.log(JSON.stringify({checks,both_products:true,three_audiences:true,read_only:true,errors}));
}catch(error){fs.mkdirSync('.runtime/lifecycle/results',{recursive:true});await page.screenshot({path:'.runtime/lifecycle/results/lifecycle-ui-failure.png'});throw error}finally{await browser.close()}
})().catch(error=>{console.error(error);process.exitCode=1});
