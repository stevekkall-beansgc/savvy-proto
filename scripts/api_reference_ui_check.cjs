// Public, read-only documentation acceptance. No application commands are invoked.
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const {chromium}=require(process.env.SAVVY_PLAYWRIGHT_MODULE||'playwright');
const origin=process.env.ARCHITECTURE_ORIGIN||'http://127.0.0.1:3107';
const root=path.resolve(__dirname,'..');
(async()=>{
 const browser=await chromium.launch({executablePath:process.env.SAVVY_BROWSER_BINARY||(process.platform==='darwin'?'/Applications/Google Chrome.app/Contents/MacOS/Google Chrome':undefined),headless:true});
 const page=await browser.newPage({viewport:{width:1440,height:1000}}),errors=[],requests=[];let checks=0;
 page.on('pageerror',e=>errors.push(e.message));page.on('console',m=>{if(m.type()==='error')errors.push(m.text())});page.on('request',r=>requests.push({method:r.method(),url:r.url()}));
 const check=(ok,label)=>{assert(ok,label);checks++};
 try{
 await page.goto(origin);await page.getByRole('link',{name:'API reference',exact:true}).click();await page.getByRole('heading',{name:'API reference.',exact:true}).waitFor();
 check(await page.locator('#operation-list .operation').count()===23,'Every SDL operation is listed');
 await page.getByLabel('Search operations').fill('audienceStatement');check(await page.locator('#operation-list .operation:visible').count()===1,'Search filters operations');
 await page.locator('#audienceStatement summary').click();check((await page.locator('#audienceStatement pre').innerText()).includes('query AudienceStatement'),'Statement request body expands');
 await page.getByLabel('Search operations').fill('');await page.getByLabel('Area',{exact:true}).selectOption({label:'Internal Finance'});check(await page.locator('#operation-list .operation:visible').count()===2,'Area filters Finance reads and commands');
 await page.getByLabel('Area',{exact:true}).selectOption('');
 for(const name of ['openapi.yaml','schema.graphql']){const response=await page.request.get(origin+'/api/'+name);check(response.status()===200,`${name} is downloadable`);check((await response.text())===fs.readFileSync(path.join(root,name==='openapi.yaml'?'docs/api/openapi.yaml':'contracts/schema.graphql'),'utf8'),`${name} matches the validated source`)}
 await page.locator('#disclosureCommand summary').click();check((await page.locator('#disclosureCommand').innerText()).includes('ASSIGN_POLICY'),'Policy actions are listed');
 check((await page.locator('main').innerText()).includes('not implemented yet'),'Agent interfaces are marked as future work');
 await page.locator('#commands .operation').first().locator('summary').click();check((await page.locator('#commands .operation').first().innerText()).includes('33/2500'),'Draft policy uses exact rational rate');
 const output=path.join(root,'.runtime/publication');fs.mkdirSync(output,{recursive:true});
 await page.evaluate(()=>window.scrollTo(0,0));
 await page.screenshot({path:path.join(output,'api-reference-desktop.png'),fullPage:false});
 for(const width of [390,320]){await page.setViewportSize({width,height:844});check(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),`API reference fits ${width}px`)}
 await page.evaluate(()=>window.scrollTo(0,0));
 await page.screenshot({path:path.join(output,'api-reference-mobile.png'),fullPage:false});
 check(requests.every(r=>r.method==='GET'),'Documentation makes no mutating requests');check(requests.every(r=>new URL(r.url).origin===new URL(origin).origin),'No requests to the billing application or external scripts');check(errors.length===0,'No browser errors: '+errors.join('; '));
 console.log(JSON.stringify({checks,origin,errors}));
 }finally{await browser.close()}
})().catch(e=>{console.error(e);process.exitCode=1});
