/* Google token lives only in memory. Drive receives encrypted .jkdoc bytes,
   with no password or original filename. Never request full-Drive access. */
(() => {
 'use strict';
 const CLIENT_ID='296636406674-rd44edn55es8urma78ttta4476roph3i.apps.googleusercontent.com',OWNER='needis123@gmail.com',SCOPE='https://www.googleapis.com/auth/drive.file';
 const API='https://www.googleapis.com/drive/v3/',UPLOAD='https://www.googleapis.com/upload/drive/v3/files';
 let sdkReady=false,token='',until=0,folder='',pending=null,generation=0;
 function clear(){token='';until=0;folder='';}
 function ready(){return Boolean(token&&Date.now()<until);}
 function notify(){document.dispatchEvent(new Event('jk-document-drive-state'));}
 function configured(){return Boolean(CLIENT_ID);}
 function requireToken(){if(!ready()){clear();notify();throw new Error('먼저 구글드라이브 연결을 눌러 본인 계정을 연결하세요.');}}
 async function responseError(response){
  let reason='';try{const body=await response.json();reason=body.error?.errors?.[0]?.reason||'';}catch{}
  if(reason==='storageQuotaExceeded')throw new Error('구글드라이브 저장 공간이 부족합니다. 용량을 확인하세요.');
  if(response.status===401){clear();notify();throw new Error('구글 연결 시간이 지났습니다. 다시 연결하세요.');}
  if(response.status===403)throw new Error('구글드라이브 권한을 확인하세요. 앱 파일 접근 허용과 Drive API 설정이 필요합니다.');
  if(response.status===404)throw new Error('드라이브에서 서류를 찾지 못했습니다. 연결한 계정과 드라이브 휴지통을 확인하세요.');
  throw new Error('구글드라이브 요청에 실패했습니다. 인터넷 연결을 확인하고 다시 시도하세요.');
 }
 async function request(path,options={}){
  requireToken();const r=await fetch(API+path,{...options,headers:{Authorization:'Bearer '+token,...options.headers},cache:'no-store'});
  if(!r.ok)await responseError(r);return r;
 }
 async function json(path,options){return (await request(path,options)).json();}
 function init(){
  if(!configured())return;
  const script=document.createElement('script');script.src='https://accounts.google.com/gsi/client';script.async=true;
  script.onload=()=>{sdkReady=true;notify();};
  script.onerror=notify;document.head.append(script);
 }
 function connect(){
  if(!configured())return Promise.reject(new Error('구글 연동 설정이 아직 완료되지 않았습니다. 설정 완료 후 연결할 수 있습니다.'));
  if(!sdkReady)return Promise.reject(new Error('구글 연결 화면을 불러오는 중입니다. 잠시 뒤 다시 눌러 주세요.'));
  if(pending)return Promise.reject(new Error('열려 있는 구글 연결 창을 먼저 완료하세요.'));
  return new Promise((resolve,reject)=>{
   const p=pending={resolve,reject},epoch=generation;
   const finish=()=>{if(pending===p)pending=null;};
   const fail=error=>{if(pending!==p)return;finish();clear();notify();reject(error);};
   try{
    const client=google.accounts.oauth2.initCodeClient({client_id:CLIENT_ID,scope:SCOPE,include_granted_scopes:false,login_hint:OWNER,select_account:true,ux_mode:'popup',
     callback:async r=>{
      if(pending!==p||epoch!==generation)return;
      if(r.error||!r.code||!String(r.scope||'').split(' ').includes(SCOPE)){fail(new Error('구글드라이브 연결을 허용해야 이용할 수 있습니다.'));return;}
      try{
       const {data,error}=await sb.auth.getSession();if(error||!data?.session?.access_token)throw new Error('장부에 먼저 로그인하세요.');
       const response=await fetch(SUPABASE_URL+'/functions/v1/jk-document-access',{method:'POST',headers:{Authorization:'Bearer '+data.session.access_token,apikey:SUPABASE_KEY,'Content-Type':'application/json','X-Requested-With':'XmlHttpRequest'},body:JSON.stringify({action:'connect',code:r.code}),cache:'no-store'});
       const connected=await response.json();if(!response.ok)throw new Error(connected.error||'구글 서버 연결을 완료하지 못했습니다.');
       if(pending!==p||epoch!==generation)return;
       if(connected.owner!==OWNER||!connected.access_token||!/^[A-Za-z0-9_-]{10,200}$/.test(connected.folder_id||''))throw new Error('구글 저장 계정과 서류 폴더를 확인하지 못했습니다.');
       clear();token=connected.access_token;folder=connected.folder_id;until=Date.now()+Math.max(0,Number(connected.expires_in||3600)-30)*1000;finish();notify();resolve();
      }catch(e){fail(e);}
     },error_callback:()=>fail(new Error('구글 연결 창을 완료하지 못했습니다. 연결 버튼을 다시 눌러 주세요.'))
    });client.requestCode();
   }catch{fail(new Error('구글 연결 창을 열지 못했습니다. 브라우저의 팝업 설정을 확인하세요.'));}
  });
 }
 async function rootFolder(){
  if(folder)return folder;
  const q="trashed=false and mimeType='application/vnd.google-apps.folder' and appProperties has { key='jkPurpose' and value='encrypted-ledger-scans-v1' }";
  const listed=await json('files?q='+encodeURIComponent(q)+'&fields=files(id)&pageSize=20');
  if(listed.files?.length){folder=listed.files[0].id;return folder;}
  const created=await json('files?fields=id',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({name:'정권통신 장부 서류 (암호화)',mimeType:'application/vnd.google-apps.folder',appProperties:{jkPurpose:'encrypted-ledger-scans-v1'}})});
  if(!created.id)throw new Error('드라이브 서류 폴더를 만들지 못했습니다.');folder=created.id;return folder;
 }
 async function upload(ledgerId,id,blob){
  requireToken();const parent=await rootFolder();
  const start=await fetch(UPLOAD+'?uploadType=resumable&fields=id',{method:'POST',headers:{Authorization:'Bearer '+token,'Content-Type':'application/json','X-Upload-Content-Type':'application/octet-stream','X-Upload-Content-Length':String(blob.size)},body:JSON.stringify({name:id+'.jkdoc',mimeType:'application/octet-stream',parents:[parent],appProperties:{jkLedger:ledgerId,jkDocument:id}})});
  if(!start.ok)await responseError(start);
  const location=start.headers.get('Location'),target=location&&new URL(location);
  if(!target||target.origin!=='https://www.googleapis.com'||!target.pathname.startsWith('/upload/drive/v3/files'))throw new Error('구글 업로드 주소를 확인하지 못했습니다.');
  requireToken();const done=await fetch(target.href,{method:'PUT',headers:{Authorization:'Bearer '+token,'Content-Type':'application/octet-stream'},body:blob});
  if(!done.ok)await responseError(done);const file=await done.json();if(!file.id)throw new Error('드라이브 파일 연결 정보를 받지 못했습니다.');return file.id;
 }
 async function download(row){return (await request('files/'+encodeURIComponent(row.drive_file_id)+'?alt=media')).blob();}
 async function trash(id){await json('files/'+encodeURIComponent(id)+'?fields=id,trashed',{method:'PATCH',headers:{'Content-Type':'application/json'},body:JSON.stringify({trashed:true})});}
 window.jkDocumentDrive={configured,ready,connect,upload,download,trash,clear,owner:OWNER};
 function cancel(){generation++;const p=pending;pending=null;clear();p?.reject(new Error('로그인이 끝나 구글 연결을 중단했습니다.'));notify();}
 document.addEventListener('DOMContentLoaded',()=>{init();sb.auth.onAuthStateChange(e=>{if(e==='SIGNED_OUT')cancel();});},{once:true});
 window.addEventListener('pagehide',cancel);
})();
