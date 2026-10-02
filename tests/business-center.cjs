const fs=require('fs'),path=require('path'),assert=require('assert/strict'),vm=require('vm');
const {chromium}=require('playwright');
const repo=path.join(__dirname,'..');
const html=fs.readFileSync(path.join(repo,'business-center.html'),'utf8');
for(const f of ['business-center.html','business-app/index.html'])for(const m of fs.readFileSync(path.join(repo,f),'utf8').matchAll(/<script[^>]*>([\s\S]*?)<\/script>/g))if(m[1].trim())new vm.Script(m[1]);
new vm.Script(fs.readFileSync(path.join(repo,'business-app/sw.js'),'utf8'));
const stub=`window.__writes=[];window.__queries=[];window.__testSession=null;window.__cash={settlement_due_this_month:762000,settlement_due_next_month:1164000,vendor_settlement_due_this_month:180000,vendor_settlement_due_next_month:0,card_settlement_due_this_month:582000,card_settlement_due_next_month:1164000};const query=()=>new Proxy({}, {get:(t,k)=>k==='then'?(resolve)=>resolve({data:[],error:null}):(...args)=>{if(['insert','update','upsert'].includes(k))window.__writes.push({op:k,payload:args[0]});if(k==='single')return Promise.resolve({data:{id:'11111111-1111-4111-8111-111111111111'},error:null});if(k==='maybeSingle')return Promise.resolve({data:null,error:null});return query()}});window.supabase={createClient:()=>({auth:{getSession:async()=>({data:{session:window.__testSession}}),onAuthStateChange:()=>{}},from:(name)=>{window.__queries.push(name);return query()},rpc:async(name)=>({data:name==='jk_cashflow_status'?window.__cash:null,error:null})})};`;
(async()=>{
 const browser=await chromium.launch({headless:true,channel:process.env.CHROMIUM_CHANNEL||'msedge'});
 const context=await browser.newContext({viewport:{width:1365,height:1000},timezoneId:'Asia/Seoul'});
 const page=await context.newPage(),errors=[];page.on('pageerror',e=>errors.push(e.message));page.on('dialog',d=>d.dismiss());
 await page.route('**/*',async route=>{const url=route.request().url();if(url==='http://ledger.test/business-center.html')return route.fulfill({contentType:'text/html',body:html});if(url.includes('supabase-js'))return route.fulfill({contentType:'application/javascript',body:stub});if(url.includes('business-tax-close.js'))return route.fulfill({contentType:'application/javascript',body:fs.readFileSync(path.join(repo,'business-tax-close.js'),'utf8')});if(url.includes('business-settlement-excel.js'))return route.fulfill({contentType:'application/javascript',body:fs.readFileSync(path.join(repo,'business-settlement-excel.js'),'utf8')});if(url.includes('business-finance.js'))return route.fulfill({contentType:'application/javascript',body:fs.readFileSync(path.join(repo,'business-finance.js'),'utf8')});if(url.includes('business-finance.css'))return route.fulfill({contentType:'text/css',body:fs.readFileSync(path.join(repo,'business-finance.css'),'utf8')});for(const f of ['business-receipts.js','business-statement-profiles.js'])if(url.includes(f))return route.fulfill({contentType:'application/javascript',body:fs.readFileSync(path.join(repo,f),'utf8')});if(url.includes('business-consultations.js'))return route.fulfill({contentType:'application/javascript',body:fs.readFileSync(path.join(repo,'business-consultations.js'),'utf8')});if(url.includes('business-consultations.css'))return route.fulfill({contentType:'text/css',body:fs.readFileSync(path.join(repo,'business-consultations.css'),'utf8')});const navAsset=new URL(route.request().url()).pathname.split('/').pop();if(['business-navigation.js','business-navigation.css'].includes(navAsset))return route.fulfill({contentType:navAsset.endsWith('.css')?'text/css':'application/javascript',body:fs.readFileSync(path.join(__dirname,'..',navAsset),'utf8')});return route.fulfill({status:404,body:''})});
 await page.goto('http://ledger.test/business-center.html');
 await page.evaluate(()=>window.__realCashflow=loadCashflow);
await page.evaluate(()=>{hideLogin();state.staff=[{id:'staff',name:'테스트판매자',active:true}];openLedger()});
for(const [k,l,expected] of [[1100000,200000,90000],[1100000,0,110000],[100000,100000,0],[100000,200000,0],[170000,319000,0]]){await page.locator('#fK').fill(String(k));await page.locator('#fL').fill(String(l));await page.evaluate(()=>previewCalc());assert.equal(await page.locator('#pvP').textContent(),expected.toLocaleString('ko-KR')+'원');}await page.evaluate(()=>closeModal());

 await page.evaluate(()=>{
   hideLogin();document.querySelectorAll('.page').forEach(e=>e.classList.remove('active'));$('page-ledger').classList.add('active');
   state.staff=[{id:'staff',name:'테스트판매자',active:true}];
   state.ledger=Array.from({length:27},(_,i)=>({id:'00000000-0000-4000-8000-'+String(i).padStart(12,'0'),activation_date:'2026-10-01',customer_name_snapshot:i===0?'<img src=x onerror=alert(1)>':'테스트고객 '+(i+1),customer_phone_snapshot:'01012345678',vendor:'테스트거래처',model_name:'테스트모델',deal_type:'휴대폰',activation_type:'MNP',salesperson_id:'staff',final_margin:780000,cash_received:600000,cash_receipt_method:i?'현금+카드':null,card_received_amount:i?400000:0,card_settlement_amount:i?388000:null,card_settlement_due_date:i?'2026-11-05':null,memo:'메모\n두 번째 줄'}));renderLedger();
 });
 assert.equal(await page.locator('#ledgerBody > tr:not(.ledger-detail-row)').count(),10);
 assert.equal(await page.locator('#ledgerBody img').count(),0);
 assert.match(await page.locator('#ledgerBody').innerText(),/010-1234-5678/);
 await page.locator('#ledgerBody > tr').first().getByRole('button',{name:'상세'}).click();
 assert(await page.locator('.ledger-detail-row').first().isVisible());
 await page.locator('#ledgerBody > tr').first().getByRole('button',{name:'접기'}).click();
 assert(!(await page.locator('.ledger-detail-row').first().isVisible()));
 await page.locator('#ledgerNext').click();assert.match(await page.locator('#ledgerPageText').innerText(),/2 \/ 3/);
 await page.locator('#ledgerSearch').fill('010-1234');assert.match(await page.locator('#ledgerPageText').innerText(),/1 \/ 3/);
 await page.locator('#ledgerSearch').fill('없는고객');assert.match(await page.locator('#ledgerBody').innerText(),/없습니다/);
 await page.locator('#ledgerSearch').fill('');
 for(const width of [360,390,768]){
   await page.setViewportSize({width,height:844});assert(await page.locator('#ledgerMobile').isVisible());assert(!(await page.locator('.ledger-desktop').isVisible()));
   const sizes=await page.evaluate(()=>({width:document.documentElement.clientWidth,scroll:document.documentElement.scrollWidth,card:document.getElementById('ledgerMobile').scrollWidth}));assert(sizes.scroll<=sizes.width,JSON.stringify(sizes));
 }
 await page.locator('#ledgerMobile details').first().locator('summary').click();
 assert(await page.locator('#ledgerMobile .ledger-detail-grid').first().isVisible());
 await page.screenshot({path:path.join(require('os').tmpdir(),'jk-ledger-mobile-test.png'),fullPage:true});
 await page.evaluate(()=>openLedger());
 await page.locator('#fName').fill('테스트');await page.locator('#fPhone').pressSequentially('01012345678');
 assert.equal(await page.locator('#fPhone').inputValue(),'010-1234-5678');
 await page.locator('#fS').fill('600000');await page.locator('#fReceiptMethod').selectOption('카드');
 assert.equal(await page.locator('#fCardReceived').inputValue(),'600,000');assert(await page.locator('#fCardReceived').getAttribute('readonly')!==null);
 const invalid=await page.evaluate(()=>{try{receiptPayload();return false}catch(e){return e.message}});assert(invalid);
 await page.locator('#fCardNet').fill('582000');await page.locator('#fCardSettleDue').fill('2026-11-05');
 const pure=await page.evaluate(()=>receiptPayload());assert.equal(pure.card_received_amount,600000);assert.equal(pure.card_settlement_amount,582000);
 await page.locator('#fReceiptMethod').selectOption('계좌+카드');await page.locator('#fCardReceived').fill('400000');await page.locator('#fCardNet').fill('388000');
 const mixed=await page.evaluate(()=>receiptPayload());assert.equal(mixed.card_received_amount,400000);
 await page.locator('#fCardNet').fill('500000');assert(await page.evaluate(()=>{try{receiptPayload();return false}catch(e){return true}}));await page.locator('#fCardNet').fill('388000');
 await page.evaluate(()=>saveLedgerDraft());await page.evaluate(()=>{closeModal();openLedger()});assert.equal(await page.locator('#fReceiptMethod').inputValue(),'계좌+카드');assert.equal(await page.locator('#fCardNet').inputValue(),'388,000');
 // A successful save must send digits-only phone and both card gross/net values.
 await page.evaluate(()=>{loadLedger=loadDashboard=loadAlerts=loadReport=loadUsed=loadPayback=loadAffiliate=loadSources=loadCashflow=loadSurvival=loadNotificationStatus=checkAffiliateAlerts=async()=>{};return saveLedger()});
 const writes=await page.evaluate(()=>window.__writes);const ledger=writes.find(w=>w.payload.card_received_amount!==undefined);assert(ledger);assert.equal(ledger.payload.customer_phone_snapshot,'01012345678');assert.equal(ledger.payload.card_settlement_due_date,'2026-11-05');assert.equal(ledger.payload.card_received_amount,400000);
 await page.evaluate(()=>openLedger(state.ledger[1].id));await page.waitForTimeout(100);assert.equal(await page.locator('#fReceiptMethod').inputValue(),'현금+카드');assert.equal(await page.locator('#fCardNet').inputValue(),'388,000');assert.equal(await page.locator('#fPhone').inputValue(),'010-1234-5678');
 await page.locator('#fReceiptMethod').selectOption('현금');const cash=await page.evaluate(()=>receiptPayload());assert.equal(cash.card_received_amount,0);assert.equal(cash.card_settlement_due_date,null);assert.equal(cash.card_settlement_amount,null);
 await page.evaluate(()=>{closeModal();openLedger(state.ledger[0].id)});await page.waitForTimeout(100);assert.equal(await page.locator('#fReceiptMethod').inputValue(),'');assert.equal((await page.evaluate(()=>receiptPayload())).cash_receipt_method,null);
 await page.evaluate(()=>{sb.from=(name)=>{const q=new Proxy({}, {get:(t,k)=>k==='then'?(resolve)=>resolve({error:null,data:name==='jk_sales_ledger'?[state.ledger[1]]:[]}):()=>q});return q};return window.__realCashflow()});
 assert.equal(await page.locator('#cashSettlementNext').textContent(),'1,164,000원');assert.match(await page.locator('#cashSettlementNextDetail').textContent(),/카드 1,164,000원/);assert.match(await page.locator('#cashCardReceiptBody').textContent(),/010-1234-5678/);
 const handler=await page.locator('#cashCardReceiptBody button').getAttribute('onclick');new vm.Script(handler);assert.match(handler,/openCardReceiptLedger/);
 await page.evaluate(()=>{closeModal();document.querySelectorAll('.page').forEach(e=>e.classList.remove('active'));$('page-ledger').classList.add('active');renderLedger()});await page.setViewportSize({width:1365,height:1000});await page.screenshot({path:path.join(require('os').tmpdir(),'jk-ledger-desktop-test.png'),fullPage:true});
 assert.deepEqual(errors,[]);await browser.close();console.log('PASS: syntax, desktop/mobile (360/390/768px), pagination/search, escaping, detail expand/collapse, phone input/display/normalized save, pure/mixed/cash validation, draft restore, create/edit payload, legacy records');
})().catch(e=>{console.error(e);process.exit(1)});
