const fs=require('fs'),path=require('path'),assert=require('assert/strict'),vm=require('vm'),{chromium}=require('playwright');
const repo=path.join(__dirname,'..');
const stub=`window.__queries=[];const query=()=>new Proxy({}, {get:(t,k)=>k==='then'?resolve=>resolve({data:[],error:null}):()=>query()});window.supabase={createClient:()=>({auth:{getSession:async()=>({data:{session:null}}),onAuthStateChange:()=>{}},from:n=>{__queries.push(n);return query()},rpc:async()=>({data:null,error:null})})};`;
(async()=>{
 const browser=await chromium.launch({headless:true,channel:'msedge'}),page=await browser.newPage({viewport:{width:1365,height:1000}}),errors=[],assets=[];
 page.on('pageerror',e=>errors.push(e.message));
 await page.route('**/*',r=>{const u=new URL(r.request().url());assets.push(u.pathname);if(u.href.includes('supabase-js'))return r.fulfill({contentType:'application/javascript',body:stub});const f=path.join(repo,u.pathname.slice(1));if(u.hostname==='navigation.test'&&fs.existsSync(f)&&fs.statSync(f).isFile())return r.fulfill({contentType:f.endsWith('.js')?'application/javascript':f.endsWith('.css')?'text/css':'text/html',body:fs.readFileSync(f)});return r.fulfill({status:404,body:''})});
 await page.goto('https://navigation.test/business-center.html?page=quotes&consultId=new');
 await page.evaluate(()=>{hideLogin();go('costs');$('alertCenterBadge').textContent='3';$('alertCenterBadge').style.display='inline-block'});
 assert.equal(await page.locator('.nav-group').count(),3);
 assert.equal(await page.locator('.cost-menu-card').count(),4);
 assert.equal(await page.locator('[data-page="quotes"],#page-quotes').count(),0);
 assert(!assets.some(x=>/quote|workflow/.test(x)));
 assert.equal(await page.locator('#alertCenterBadge').textContent(),'3');
 await page.screenshot({path:path.join(process.env.TEST_OUTPUT_DIR||require('os').tmpdir(),'jk-final-menu-desktop.png'),fullPage:true});
 await page.locator('.cost-menu-card[data-section-route="finance"]').click();assert(await page.locator('#page-finance').isVisible());
 await page.evaluate(()=>go('ledger'));await page.locator('#page-ledger .section-menu [data-section-route="payback"]').click();assert(await page.locator('#page-payback').isVisible());
 await page.locator('#page-payback .section-menu [data-section-route="ledger"]').click();assert(await page.locator('#page-ledger').isVisible());
 for(const width of [360,390,768]){await page.setViewportSize({width,height:844});await page.evaluate(()=>go('costs'));assert(await page.evaluate(()=>document.documentElement.scrollWidth<=document.documentElement.clientWidth));assert.equal(await page.locator('.mobile-menu-grid [data-page="quotes"]').count(),0)}
 await page.setViewportSize({width:390,height:844});await page.screenshot({path:path.join(process.env.TEST_OUTPUT_DIR||require('os').tmpdir(),'jk-final-menu-mobile.png'),fullPage:true});
 await page.evaluate(async()=>{history.replaceState(null,'','?page=quotes');localStorage.setItem('jk-active-page','quotes');sb.auth.getSession=async()=>({data:{session:{user:{email:'test@example.test'}}}});loadAll=async()=>{};await sessionChanged()});assert(await page.locator('#page-dashboard').isVisible());
 assert(!await page.evaluate(()=>__queries.some(n=>/jk_inventory|jk_work|jk_quotes/.test(n))));
 assert.deepEqual(errors,[]);await browser.close();console.log('PASS: grouped navigation, four cost pages, badges, mobile widths, removed quote route recovery, no new DB dependency');
})().catch(e=>{console.error(e);process.exit(1)});
