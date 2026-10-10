const fs=require('fs'),path=require('path'),assert=require('assert/strict');
(async()=>{
 const source=fs.readFileSync(path.join(__dirname,'../supabase/functions/jk-document-access/handler.js'),'utf8');
 const {createHandler,ORIGIN,REDIRECT}=await import('data:text/javascript;base64,'+Buffer.from(source).toString('base64'));
 const id='11111111-1111-4111-8111-111111111111',doc='22222222-2222-4222-8222-222222222222';
 let owner=false,approved=false,revokedDuringFetch=false,wrongGoogle=false,unverified=false,authInvalid=false,calls=[];
 const env={SUPABASE_URL:'https://sb.test',SUPABASE_ANON_KEY:'PUBLIC',SUPABASE_SERVICE_ROLE_KEY:'SERVER-ONLY'};
 const json=(x,status=200)=>new Response(JSON.stringify(x),{status});
 const fake=async(url,o={})=>{calls.push({url,o});
  if(url.endsWith('/auth/v1/user'))return json({id,email:owner?'needis123@gmail.com':'staff@example.invalid',email_confirmed_at:unverified?null:'2026-10-10'},authInvalid?401:200);
  const name=url.split('/rpc/')[1];
  if(name){const a=JSON.parse(o.body);if(name.startsWith('jk_document_server_'))assert.equal(o.headers.Authorization,'Bearer SERVER-ONLY');else assert.equal(o.headers.Authorization,'Bearer USER-JWT');
   if(name==='jk_document_access_state')return json({owner,status:approved?'approved':'pending'});
   if(name==='jk_document_server_credentials')return json({client_id:'TESTCLIENT',client_secret:'TESTSECRET',refresh_token:'TESTREFRESH',folder_id:'synthetic_folder_12345'});
   if(name==='jk_document_server_read_record'){assert.deepEqual(a,{p_user_id:id,p_document_id:doc});return approved?json({drive_file_id:'synthetic_file_12345',byte_size:100}):json({error:'revoked'},403);}
   if(name==='jk_document_server_save_connection'){assert.equal(a.p_email,'needis123@gmail.com');assert.equal(a.p_refresh_token,'TESTREFRESH');return new Response('');}
   if(name==='jk_document_server_log_read')return new Response('');
   throw Error(name);
  }
  if(url==='https://oauth2.googleapis.com/token'){const p=new URLSearchParams(o.body);assert.equal(p.get('client_secret'),'TESTSECRET');if(p.get('grant_type')==='authorization_code')assert([ORIGIN,REDIRECT].includes(p.get('redirect_uri')));return json({access_token:'GOOGLE-TEMP',refresh_token:'TESTREFRESH',scope:'https://www.googleapis.com/auth/drive.file',expires_in:3600});}
  assert(url.startsWith('https://www.googleapis.com/drive/v3/'));assert.equal(o.headers.Authorization,'Bearer GOOGLE-TEMP');
  if(url.includes('/about?'))return json({user:{emailAddress:wrongGoogle?'other@example.invalid':'needis123@gmail.com'}});
  if(url.includes('/files?q='))return json({files:[{id:'synthetic_folder_12345'}]});
  if(url.includes('alt=media')){if(revokedDuringFetch)approved=false;return new Response(new Uint8Array(100).fill(5));}
  throw Error(url);
 };
 const handler=createHandler({env,fetchImpl:fake});
 const request=(body,{origin=ORIGIN,bearer=true,csrf=true}={})=>new Request('https://sb.test/functions/v1/jk-document-access',{method:'POST',headers:{Origin:origin,...(bearer?{Authorization:'Bearer USER-JWT'}:{}),...(csrf?{'X-Requested-With':'XmlHttpRequest'}:{})},body:JSON.stringify(body)});
 assert.equal((await handler(request({action:'download',document_id:doc},{origin:'https://evil.invalid'}))).status,403);assert.equal(calls.length,0);
 assert.equal((await handler(request({action:'download',document_id:doc},{bearer:false}))).status,401);
 authInvalid=true;assert.equal((await handler(request({action:'download',document_id:doc}))).status,401);authInvalid=false;
 unverified=true;assert.equal((await handler(request({action:'download',document_id:doc}))).status,403);unverified=false;
 assert.equal((await handler(request(null))).status,400);
 assert.equal((await handler(request({action:'connect',code:'synthetic-code-long'}))).status,403);
 assert.equal((await handler(request({action:'owner-token'}))).status,403);
 assert.equal((await handler(request({action:'download',document_id:doc}))).status,403);assert(!calls.some(c=>c.url.includes('/token')));
 owner=true;assert.equal((await handler(request({action:'owner-token'},{csrf:false}))).status,400);
 assert.equal((await handler(request({action:'owner-token'}))).status,200);
 assert.equal((await handler(request({action:'connect',code:'synthetic-code-long',redirect_uri:'https://evil.invalid'}))).status,400);
 assert.equal((await handler(request({action:'connect',code:'synthetic-code-long',redirect_uri:REDIRECT}))).status,200);
 assert.equal((await handler(request({action:'connect',code:'synthetic-code-long'},{csrf:false}))).status,400);
 wrongGoogle=true;assert.equal((await handler(request({action:'connect',code:'synthetic-code-long'}))).status,403);wrongGoogle=false;
 let r=await handler(request({action:'connect',code:'synthetic-code-long'}));assert.equal(r.status,200);const connected=await r.json();assert.equal(connected.owner,'needis123@gmail.com');assert(!JSON.stringify(connected).includes('TESTSECRET'));assert(!JSON.stringify(connected).includes('TESTREFRESH'));
 owner=false;approved=true;r=await handler(request({action:'download',document_id:doc,p_user_id:'attacker'}));assert.equal(r.status,200);assert.equal(r.headers.get('Cache-Control'),'no-store');assert.equal((await r.arrayBuffer()).byteLength,100);
 revokedDuringFetch=true;r=await handler(request({action:'download',document_id:doc}));assert.equal(r.status,403);assert(!JSON.stringify(await r.json()).includes('TESTSECRET'));
 console.log('PASS: server Auth verification, origin/CSRF, owner-bound Google connection, private Vault use, staff identity binding, pending denial, ciphertext relay, no secret leakage and revocation during Google fetch (all network mocked)');
})().catch(e=>{console.error(e);process.exit(1)});
