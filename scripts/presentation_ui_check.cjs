// Read-only browser acceptance against a running, seeded synthetic app.
const assert = require('node:assert/strict');
const { chromium } = require(process.env.SAVVY_PLAYWRIGHT_MODULE || 'playwright');
const base = process.env.SAVVY_PREVIEW_ORIGIN || 'http://127.0.0.1:3104';
assert(['http://127.0.0.1:3100','http://127.0.0.1:3104','http://127.0.0.1:3106'].includes(base));
(async()=>{
 const executablePath=process.env.SAVVY_BROWSER_BINARY || (process.platform==='darwin'?'/Applications/Google Chrome.app/Contents/MacOS/Google Chrome':undefined);
 const browser=await chromium.launch({executablePath,headless:true});
 const page=await browser.newPage({viewport:{width:1440,height:1000}});
 const errors=[];page.on('pageerror',e=>errors.push(e.message));
 const householdQueries=[];let householdMode=true;
 page.on('request',req=>{if(householdMode&&req.url().endsWith('/api/graphql')){try{householdQueries.push(JSON.parse(req.postData()||'{}').query||'')}catch{}}});
 let checks=0;const check=(value,label)=>{assert(value,label);checks++};
 const text=()=>page.locator('main').innerText();
 const nav=async(name)=>{await page.getByRole('navigation',{name:'Workspace navigation'}).getByRole('button',{name,exact:true}).click()};
 const ready=async(value)=>{await page.getByText(value,{exact:true}).first().waitFor()};
 const identity=async(value)=>{const d=page.locator('.aud-presenter details');if(!await d.getAttribute('open').then(v=>v!==null))await d.locator('summary').click();await page.getByLabel('View as').selectOption(value)};
 try{
 await page.goto(base);await ready('Your business at a glance.');
 let t=await text();check(t.includes('$1,000.00')&&t.includes('$500.00')&&t.includes('$200.00'),'Overview uses household invoice, credit and outstanding cash');check(t.includes('Your compensation')&&t.includes('$5,000.00')&&t.includes('Client fees billed'),'Advisor entitlements are distinct from client fees');check(!t.includes('Sep ')&&!t.includes('September'),'No legacy period on default overview');
 await page.getByRole('button',{name:'View statement →',exact:true}).click();await page.getByRole('button',{name:'Invoice details →',exact:true}).waitFor();
 check(await page.locator('table tbody tr').count()===2,'Two traditional invoice lines');
 check((await text()).includes('$600.00')&&(await text()).includes('$400.00'),'Allocation amounts visible');
 await page.getByRole('button',{name:'Invoice details →',exact:true}).click();await page.getByRole('dialog').waitFor();check((await page.getByRole('dialog').innerText()).includes('Feb 28, 2027'),'Invoice displays inclusive service dates');await page.keyboard.press('Escape');check(await page.getByRole('dialog').count()===0,'Escape closes invoice details');
 await nav('Agreements');await ready('Applied billing terms');await page.getByRole('button',{name:/Original invoice terms/}).click();await page.getByRole('dialog').waitFor();check((await page.getByRole('dialog').innerText()).includes('1.2%'),'Applied terms rate visible');await page.keyboard.press('Escape');
 check(await page.getByRole('button',{name:/View .*PDF/}).count()>0 || (await text()).includes('Form ADV'),'Real public disclosures remain available');
 await nav('Clients');await ready('Clients & accounts.');check(await page.locator('main .aud-list button').count()===1,'Book shows household before account drilldown');await page.getByRole('button',{name:/Alder household/}).click();await page.getByRole('button',{name:'Invoice details →',exact:true}).waitFor();
 await identity('product');await ready('How the billing engine arrives at the charge');
 check(!((await text()).includes('Sep ')||(await text()).includes('September')),'Product stays in household period');
 for(const title of ['Select billable assets','Apply agreed terms','Calculate the charge','Allocate to accounts']){
  await page.getByRole('button').filter({hasText:title}).click();await page.getByRole('dialog').waitFor();check((await page.getByRole('dialog').innerText()).length>60,`${title} opens evidence`);await page.keyboard.press('Escape');
 }
 check(!(await text()).includes('Publish reviewed policy'),'Review decisions stay in the dedicated queue');
 check(await page.getByRole('link',{name:'Explore the technical architecture ↗'}).getAttribute('href')==='https://savvy.beanshop.top/','Product links public architecture');
 await nav('Work queue');await ready('Household terms requests');check(!(await text()).includes('Advisor business · Compensation'),'Queue contains household requests only');
 await identity('finance');await ready('Household billing: cash and recognition');t=await text();check(t.includes('$1,000.00')&&t.includes('$500.00')&&t.includes('$300.00')&&t.includes('$200.00'),'Finance separates invoice, credit, confirmed refund and balance');check(!t.includes('Quarterly service')&&!t.includes('Sep '),'Unrelated finance fixtures absent');check(t.includes('Original receipt')&&t.includes('Loan cash advance')&&t.includes('$12,000.00'),'Finance shows separately evidenced cash');
 await nav('Work queue');await ready('Household terms requests');t=await text();check(!t.includes('Approve as Legal')&&!t.includes('Publish reviewed policy')&&!t.includes('Assign a published policy'),'Finance queue has no Legal or operator actions');
 if(await page.locator('.dw-change').filter({hasText:'Comparison ID:'}).count())check(await page.getByRole('button',{name:'Approve as Finance',exact:true}).count()>0,'Finance receives comparison review controls');
 check(!householdQueries.some(q=>/audienceSummary|medallionWorkspace|productWorkspace/.test(q)),'Household screens make no unused baseline workspace reads');
 await nav('Finance');await ready('Household billing: cash and recognition');
 await page.getByRole('button',{name:'View balance evidence →'}).click();await page.getByRole('dialog').waitFor();check((await page.getByRole('dialog').innerText()).includes('$200.00'),'Refund evidence opens');await page.keyboard.press('Escape');
 await identity('client');await ready('Your business at a glance.');
 householdMode=false;await page.getByLabel('Billing example').selectOption('book');await ready('Your business at a glance.');check((await text()).includes('Sep '),'Historical business book remains accessible');check(!(await text()).includes('Household billing'),'Household not appended to book');
 await identity('finance');await nav('Work queue');await ready('Work queue.');t=await text();check(!t.includes('Simulate Legal review')&&!t.includes('Publish reviewed policy')&&!t.includes('Assign published terms')&&!t.includes('Calculate impact'),'Book Finance queue does not offer Legal or operator decisions');await identity('client');await ready('Your business at a glance.');
 await page.locator('.aud-account-label select').selectOption('ria');await ready('How your terms compare');check(!(await text()).includes('FEBRUARY 2027'),'RIA book does not mix periods');
 await page.getByLabel('Billing example').selectOption('household');await ready('Your business at a glance.');
 if(process.env.SAVVY_SCREENSHOT)await page.screenshot({path:process.env.SAVVY_SCREENSHOT.replace('.png','-desktop.png'),fullPage:true});
 await page.setViewportSize({width:390,height:844});check(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),'Mobile overview has no horizontal overflow');
 await nav('Statements');await page.getByRole('button',{name:'Invoice details →',exact:true}).waitFor();check(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),'Mobile statement has no page overflow');
 if(process.env.SAVVY_SCREENSHOT)await page.screenshot({path:process.env.SAVVY_SCREENSHOT,fullPage:true});
 await identity('product');await ready('How the billing engine arrives at the charge');check(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),'Mobile Product has no page overflow');
 await identity('finance');await ready('Household billing: cash and recognition');check(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),'Mobile Finance has no page overflow');
 check(errors.length===0,`No browser errors: ${errors.join('; ')}`);console.log(JSON.stringify({checks,base,errors}));
 }finally{await browser.close()}
})().catch(e=>{console.error(e);process.exitCode=1});
