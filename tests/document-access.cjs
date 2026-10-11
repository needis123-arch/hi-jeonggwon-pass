const fs=require('fs'),path=require('path'),assert=require('assert/strict'),{chromium}=require('playwright');
const repo=path.join(__dirname,'..'),doc='22222222-2222-4222-8222-222222222222',ledger='11111111-1111-4111-8111-111111111111',password='0007';
const png=Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+j2s8AAAAASUVORK5CYII=','base64');
const stub=`window.__status='none';window.__owner=false;window.__auth=[];window.__session={access_token:'STAFF-JWT'};window.__downloads=0;window.__decisions=[];
window.supabase={createClient:()=>({auth:{getSession:async()=>({data:{session:__session}}),onAuthStateChange:f=>__auth.push(f),signInWithPassword:async()=>({error:null}),signOut:async()=>{__session=null;__auth.forEach(f=>f('SIGNED_OUT'));return {error:null}}},rpc:async(name,args={})=>{
 if(name==='jk_document_access_state')return {data:{owner:__owner,status:__status,email:'synthetic-staff@example.invalid',display_name:'합성 직원',drive_connected:true}};
 if(name==='jk_document_request_access'){__status='pending';return {data:{status:'pending'}};}
 if(name==='jk_document_access_requests')return {data:[{user_id:'33333333-3333-4333-8333-333333333333',email:'synthetic-staff@example.invalid',display_name:'합성 직원',status:__status,version:1,requested_at:'2026-10-10'}]};
 if(name==='jk_document_decide_access'){__status=args.p_action;__decisions.push(args);return {data:null};}
 if(__status!=='approved')return {error:{message:'denied'}};
 if(name==='jk_document_staff_customers')return {data:[{id:'${ledger}',customer_name_snapshot:'합성 서류 고객',customer_phone_snapshot:'01012345678',activation_date:'2026-10-10',vendor:'합성 거래처'}]};
 if(name==='jk_document_staff_files')return {data:[{id:'${doc}',ledger_id:'${ledger}',doc_kind:'신분증 사본',created_at:'2026-10-10',byte_size:100}]};return {data:null};}})};`;
(async()=>{const browser=await chromium.launch({headless:true,channel:'msedge'});try{
 const page=await browser.newPage({viewport:{width:1100,height:950}}),errors=[];page.on('pageerror',e=>errors.push(e.message));page.on('dialog',d=>d.accept());let ciphertext;
 await page.route('**/*',async r=>{const u=new URL(r.request().url());if(u.href.includes('supabase-js'))return r.fulfill({contentType:'application/javascript',body:stub});
  if(u.pathname==='/functions/v1/jk-document-access'){assert.equal(r.request().headers().authorization,'Bearer STAFF-JWT');assert.deepEqual(JSON.parse(r.request().postData()),{action:'download',document_id:doc});const allowed=await page.evaluate(()=>__status==='approved');await page.evaluate(()=>__downloads++);return allowed?r.fulfill({contentType:'application/octet-stream',body:ciphertext}):r.fulfill({status:403,json:{error:'열람 권한이 회수되었습니다.'}});}
  if(u.hostname==='staff.test'&&u.pathname==='/owner.html')return r.fulfill({contentType:'text/html',body:`<div id="documentAccessCard" hidden><p id="documentConnectionStatus"></p><div id="documentAccessRequests"></div></div><script>${stub}</script><script>const sb=supabase.createClient();window.__owner=true;window.__status='pending';</script><script src="/business-document-access.js"></script>`});
  const f=path.join(repo,u.pathname.slice(1));if(u.hostname==='staff.test'&&fs.existsSync(f)&&fs.statSync(f).isFile())return r.fulfill({contentType:f.endsWith('.js')?'application/javascript':'text/html',body:fs.readFileSync(f)});return r.fulfill({status:404});
 });
 await page.goto('https://staff.test/owner.html');await page.locator('[data-document-action=approved]').waitFor();await page.locator('[data-document-action=approved]').click();await page.locator('[data-document-action=revoked]').waitFor();assert.deepEqual(await page.evaluate(()=>__decisions[0]),{p_user_id:'33333333-3333-4333-8333-333333333333',p_action:'approved',p_version:1});await page.locator('[data-document-action=revoked]').click();await page.waitForFunction(()=>__status==='revoked');assert.equal(await page.evaluate(()=>__decisions.length),2);
 assert.deepEqual(errors,[]);console.log('PASS: owner approval/revoke UI and version checks (synthetic only; integrated employee flow is tested in staff-ledger.cjs)');
 }finally{await browser.close()}})().catch(e=>{console.error(e);process.exit(1)});
