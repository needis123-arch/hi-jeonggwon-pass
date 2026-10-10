const fs=require('fs'),path=require('path'),assert=require('assert/strict'),{chromium}=require('playwright');
const source=fs.readFileSync(path.join(__dirname,'../business-document-drive.js'),'utf8');
const fixture=source.replace("const CLIENT_ID=''","const CLIENT_ID='synthetic-test.apps.googleusercontent.com'");
const sdk=`window.google={accounts:{oauth2:{initCodeClient:c=>{window.__config=c;return {requestCode:()=>{if(window.__popupFail)throw new Error('blocked');c.callback(window.__scopeFail?{error:'access_denied'}:{code:'synthetic-authorization-code',scope:c.scope})}}}}}};`;
(async()=>{const browser=await chromium.launch({headless:true,channel:'msedge'});try{
 const page=await browser.newPage(),calls=[],folderCalls=[];let wrongOwner=false,badLocation=false,expired=false,uploaded=0;
 await page.route('**/*',async r=>{const u=new URL(r.request().url()),method=r.request().method();
  if(u.origin==='https://drive.test')return r.fulfill({contentType:u.pathname.endsWith('.js')?'application/javascript':'text/html',body:u.pathname.endsWith('.js')?fixture:`<!doctype html><meta charset="utf-8"><script>window.__auth=[];window.SUPABASE_URL='https://edge.test';window.SUPABASE_KEY='PUBLIC-TEST-KEY';window.sb={auth:{getSession:async()=>({data:{session:{access_token:'TEST-USER-JWT'}}}),onAuthStateChange:f=>__auth.push(f)}};</script><script src="/drive.js"></script>`});
  if(u.href==='https://accounts.google.com/gsi/client')return r.fulfill({contentType:'application/javascript',body:sdk});
  if(u.origin==='https://edge.test'){assert.equal(r.request().headers().authorization,'Bearer TEST-USER-JWT');assert.equal(r.request().headers()['x-requested-with'],'XmlHttpRequest');assert.deepEqual(JSON.parse(r.request().postData()),{action:'connect',code:'synthetic-authorization-code'});return r.fulfill({status:wrongOwner?403:200,json:wrongOwner?{error:'needis123@gmail.com 계정으로 연결하세요.'}:{owner:'needis123@gmail.com',access_token:'SYNTHETIC-TOKEN',folder_id:'synthetic_root_folder_12345',expires_in:3600}});}assert.equal(u.origin,'https://www.googleapis.com');calls.push({path:u.pathname+u.search,method,authorization:r.request().headers().authorization,body:r.request().postDataBuffer()});
  assert.equal(r.request().headers().authorization,'Bearer SYNTHETIC-TOKEN');
  if(expired)return r.fulfill({status:401,json:{error:{errors:[{reason:'authError'}]}}});
  if(u.pathname.endsWith('/about'))return r.fulfill({json:{user:{emailAddress:wrongOwner?'other@example.invalid':'needis123@gmail.com'}}});
  if(u.pathname==='/upload/drive/v3/files'&&method==='POST')return r.fulfill({headers:{'Access-Control-Expose-Headers':'Location',Location:badLocation?'https://unexpected.invalid/upload':'https://www.googleapis.com/upload/drive/v3/files?upload_id=synthetic'},json:{}});
  if(u.pathname==='/upload/drive/v3/files'&&method==='PUT'){uploaded++;return r.fulfill({json:{id:'synthetic_drive_file_12345'}});}
  if(u.pathname==='/drive/v3/files'&&method==='GET')return r.fulfill({json:{files:[]}});
  if(u.pathname==='/drive/v3/files'&&method==='POST'){folderCalls.push(JSON.parse(r.request().postData()));return r.fulfill({json:{id:'synthetic_root_folder_12345'}});}
  if(method==='PATCH')return r.fulfill({json:{id:'synthetic_drive_file_12345',trashed:true}});
  return r.fulfill({contentType:'application/octet-stream',body:'JKDOC001-SYNTHETIC-CIPHERTEXT'});
 });
 await page.goto('https://drive.test');await page.waitForFunction(()=>window.google);
 
 assert.match(await page.evaluate(()=>jkDocumentDrive.upload('ledger','document',new Blob(['encrypted'])).catch(e=>e.message)),/먼저/);assert.equal(calls.length,0);
 await page.evaluate(()=>jkDocumentDrive.connect());assert.equal(await page.evaluate(()=>__config.scope),'https://www.googleapis.com/auth/drive.file');assert.equal(await page.evaluate(()=>__config.include_granted_scopes),false);assert(await page.evaluate(()=>jkDocumentDrive.ready()));
 const id=await page.evaluate(()=>jkDocumentDrive.upload('ledger','document',new Blob(['JKDOC001-SYNTHETIC-CIPHERTEXT'])));assert.equal(id,'synthetic_drive_file_12345');assert.equal(uploaded,1);assert.equal(folderCalls.length,0);
 const media=await page.evaluate(async()=>await (await jkDocumentDrive.download({drive_file_id:'synthetic_drive_file_12345'})).text());assert.match(media,/JKDOC001/);
 await page.evaluate(()=>jkDocumentDrive.trash('synthetic_drive_file_12345'));assert.deepEqual(JSON.parse(calls.at(-1).body.toString()),{trashed:true});assert(!calls.some(c=>c.method==='DELETE'));
 badLocation=true;assert.match(await page.evaluate(()=>jkDocumentDrive.upload('ledger','document',new Blob(['encrypted'])).catch(e=>e.message)),/주소/);assert.equal(uploaded,1);badLocation=false;
 expired=true;assert.match(await page.evaluate(()=>jkDocumentDrive.download({drive_file_id:'synthetic_drive_file_12345'}).catch(e=>e.message)),/다시 연결/);assert(!await page.evaluate(()=>jkDocumentDrive.ready()));expired=false;
 wrongOwner=true;assert.match(await page.evaluate(()=>jkDocumentDrive.connect().catch(e=>e.message)),/needis123@gmail.com/);assert(!await page.evaluate(()=>jkDocumentDrive.ready()));wrongOwner=false;
 await page.evaluate(()=>__popupFail=true);assert.match(await page.evaluate(()=>jkDocumentDrive.connect().catch(e=>e.message)),/창을 열지/);await page.evaluate(()=>__popupFail=false);await page.evaluate(()=>jkDocumentDrive.connect());
 await page.evaluate(()=>__auth.forEach(f=>f('SIGNED_OUT')));assert(!await page.evaluate(()=>jkDocumentDrive.ready()));assert.equal(await page.evaluate(()=>Object.keys(localStorage).length+Object.keys(sessionStorage).length),0);
 console.log('PASS: Drive file-only scope, owner binding, private app folder, encrypted resumable upload, authenticated download, recoverable trash, URL guard, token expiry/logout, popup recovery and no stored tokens (all Google requests mocked)');
 }finally{await browser.close()}})().catch(e=>{console.error(e);process.exit(1)});
