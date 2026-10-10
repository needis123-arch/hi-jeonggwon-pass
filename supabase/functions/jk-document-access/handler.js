export const ORIGIN='https://needis123-arch.github.io';
export const REDIRECT=ORIGIN+'/hi-jeonggwon-pass/business-documents-connect.html';
const OWNER='needis123@gmail.com',SCOPE='https://www.googleapis.com/auth/drive.file';
const UUID=/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
class HttpError extends Error{constructor(status,message){super(message);this.status=status;}}
export function createHandler({env,fetchImpl=fetch}){
 const headers={'Access-Control-Allow-Origin':ORIGIN,'Access-Control-Allow-Headers':'authorization,apikey,content-type,x-requested-with','Access-Control-Allow-Methods':'POST,OPTIONS','Vary':'Origin','Cache-Control':'no-store','X-Content-Type-Options':'nosniff'};
 const reply=(body,status=200)=>new Response(JSON.stringify(body),{status,headers:{...headers,'Content-Type':'application/json'}});
 async function rpc(name,body,authorization,server=false){
  const key=server?env.SUPABASE_SERVICE_ROLE_KEY:env.SUPABASE_ANON_KEY;
  const r=await fetchImpl(env.SUPABASE_URL+'/rest/v1/rpc/'+name,{method:'POST',headers:{apikey:key,Authorization:server?'Bearer '+key:authorization,'Content-Type':'application/json'},body:JSON.stringify(body)});
  if(!r.ok)throw new HttpError(r.status===403||r.status===401?403:409,'권한이 변경됐거나 요청을 처리하지 못했습니다. 새로고침 후 다시 확인하세요.');
  const text=await r.text();return text?JSON.parse(text):null;
 }
 async function google(url,token,options={}){
  const r=await fetchImpl(url,{...options,headers:{Authorization:'Bearer '+token,...options.headers}});
  if(!r.ok)throw new HttpError(503,'사장님 구글드라이브 연결을 다시 확인해 주세요.');return r;
 }
 async function tokenRequest(body){
  const r=await fetchImpl('https://oauth2.googleapis.com/token',{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},body:new URLSearchParams(body)});
  if(!r.ok)throw new HttpError(503,'구글 연결 시간이 지났습니다. 사장님이 장부에서 구글드라이브를 다시 연결해 주세요.');
  const data=await r.json();if(!data.access_token)throw new HttpError(503,'구글 연결을 완료하지 못했습니다.');return data;
 }
 return async req=>{
  try{
   if(req.headers.get('Origin')!==ORIGIN)return reply({error:'허용되지 않은 사이트입니다.'},403);
   if(req.method==='OPTIONS')return new Response(null,{status:204,headers});
   if(req.method!=='POST')return reply({error:'지원하지 않는 요청입니다.'},405);
   const authorization=req.headers.get('Authorization')||'';
   if(!authorization.startsWith('Bearer '))throw new HttpError(401,'로그인 후 이용하세요.');
   const auth=await fetchImpl(env.SUPABASE_URL+'/auth/v1/user',{headers:{apikey:env.SUPABASE_ANON_KEY,Authorization:authorization}});
   if(!auth.ok)throw new HttpError(401,'로그인이 만료됐습니다. 다시 로그인하세요.');
   const user=await auth.json();
   if(!user.id||!user.email_confirmed_at||user.is_anonymous)throw new HttpError(403,'이메일을 확인한 계정으로 로그인하세요.');
   const raw=await req.text();if(raw.length>8192)throw new HttpError(400,'요청이 너무 큽니다.');
   let body;try{body=JSON.parse(raw);}catch{throw new HttpError(400,'요청 형식이 올바르지 않습니다.');}
   if(!body||typeof body!=='object'||!['connect','owner-token','download'].includes(body.action))throw new HttpError(400,'지원하지 않는 요청입니다.');
   const state=await rpc('jk_document_access_state',{},authorization);
   if(body.action==='owner-token'){
    if(!state?.owner||String(user.email).toLowerCase()!==OWNER)throw new HttpError(403,'구글 저장소 연결은 사장님만 할 수 있습니다.');
    if(req.headers.get('X-Requested-With')!=='XmlHttpRequest')throw new HttpError(400,'장부에서 연결을 다시 시작하세요.');
    const cfg=await rpc('jk_document_server_credentials',{},authorization,true);
    if(!cfg?.refresh_token)return reply({error:'구글드라이브 최초 연결이 필요합니다.',code:'drive_not_connected'},503);
    if(!cfg.client_id||!cfg.client_secret||!/^[A-Za-z0-9_-]{10,200}$/.test(cfg.folder_id||''))throw new HttpError(503,'구글 저장소 설정을 확인하세요.');
    const tokens=await tokenRequest({client_id:cfg.client_id,client_secret:cfg.client_secret,refresh_token:cfg.refresh_token,grant_type:'refresh_token'});
    return reply({access_token:tokens.access_token,expires_in:tokens.expires_in||3600,folder_id:cfg.folder_id,owner:OWNER});
   }
   if(body.action==='connect'){
    if(!state?.owner||String(user.email).toLowerCase()!==OWNER)throw new HttpError(403,'구글 저장소 연결은 사장님만 할 수 있습니다.');
    if(req.headers.get('X-Requested-With')!=='XmlHttpRequest'||typeof body.code!=='string'||body.code.length<10||body.code.length>4096)throw new HttpError(400,'구글 연결 요청을 다시 시작하세요.');
    const cfg=await rpc('jk_document_server_credentials',{},authorization,true);
    if(!cfg?.client_id||!cfg.client_secret)throw new HttpError(503,'구글 서버 연동 설정이 아직 완료되지 않았습니다.');
    if(body.redirect_uri!==undefined&&body.redirect_uri!==REDIRECT)throw new HttpError(400,'허용되지 않은 연결 주소입니다.');
    const tokens=await tokenRequest({client_id:cfg.client_id,client_secret:cfg.client_secret,code:body.code,redirect_uri:body.redirect_uri||ORIGIN,grant_type:'authorization_code'});
    if(!String(tokens.scope||'').split(' ').includes(SCOPE))throw new HttpError(403,'앱 서류 파일 접근 권한이 필요합니다.');
    const about=await (await google('https://www.googleapis.com/drive/v3/about?fields=user(emailAddress)',tokens.access_token)).json();
    if(String(about.user?.emailAddress||'').toLowerCase()!==OWNER)throw new HttpError(403,OWNER+' 계정으로 연결하세요.');
    const refresh=tokens.refresh_token||cfg.refresh_token;
    if(!refresh)throw new HttpError(503,'구글 계정에서 이 앱 연결을 해제한 뒤 다시 연결해 주세요. 직원 열람용 연결을 완료하지 못했습니다.');
    const q="trashed=false and mimeType='application/vnd.google-apps.folder' and appProperties has { key='jkPurpose' and value='encrypted-ledger-scans-v1' }";
    const folders=await (await google('https://www.googleapis.com/drive/v3/files?q='+encodeURIComponent(q)+'&fields=files(id)&pageSize=20',tokens.access_token)).json();
    let folder=folders.files?.[0]?.id;
    if(!folder){const made=await (await google('https://www.googleapis.com/drive/v3/files?fields=id',tokens.access_token,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({name:'정권통신 장부 서류 (암호화)',mimeType:'application/vnd.google-apps.folder',appProperties:{jkPurpose:'encrypted-ledger-scans-v1'}})})).json();folder=made.id;}
    if(typeof folder!=='string'||!/^[A-Za-z0-9_-]{10,200}$/.test(folder))throw new HttpError(503,'드라이브 서류 폴더를 확인하지 못했습니다.');
    await rpc('jk_document_server_save_connection',{p_refresh_token:refresh,p_folder_id:folder,p_email:OWNER},authorization,true);
    return reply({access_token:tokens.access_token,expires_in:tokens.expires_in||3600,folder_id:folder,owner:OWNER});
   }
   if(state?.status!=='approved')throw new HttpError(403,'서류 열람 승인이 필요합니다. 사장님에게 요청하세요.');
   if(!UUID.test(body.document_id||''))throw new HttpError(400,'서류를 다시 선택하세요.');
   const record=await rpc('jk_document_server_read_record',{p_user_id:user.id,p_document_id:body.document_id},authorization,true);
   if(!record?.drive_file_id||!/^[A-Za-z0-9_-]{10,200}$/.test(record.drive_file_id))throw new HttpError(404,'서류를 찾지 못했습니다.');
   const cfg=await rpc('jk_document_server_credentials',{},authorization,true);
   if(!cfg?.refresh_token||!cfg.client_secret||!cfg.client_id)throw new HttpError(503,'사장님이 구글드라이브를 먼저 연결해야 합니다.');
   const tokens=await tokenRequest({client_id:cfg.client_id,client_secret:cfg.client_secret,refresh_token:cfg.refresh_token,grant_type:'refresh_token'});
   const r=await google('https://www.googleapis.com/drive/v3/files/'+encodeURIComponent(record.drive_file_id)+'?alt=media',tokens.access_token);
   // Check permission again after Google I/O; do not serve a now-revoked user's file.
   await rpc('jk_document_server_read_record',{p_user_id:user.id,p_document_id:body.document_id},authorization,true);
   const bytes=await r.arrayBuffer();
   if(bytes.byteLength<53||bytes.byteLength>20*1024*1024+4096)throw new HttpError(502,'서류 파일 크기를 확인하지 못했습니다.');
   await rpc('jk_document_server_log_read',{p_user_id:user.id,p_document_id:body.document_id},authorization,true);
   return new Response(bytes,{headers:{...headers,'Content-Type':'application/octet-stream','Content-Disposition':'inline'}});
  }catch(e){return reply({error:e instanceof HttpError?e.message:'서류 요청을 처리하지 못했습니다. 잠시 후 다시 시도하세요.'},e instanceof HttpError?e.status:500);}
 };
}
