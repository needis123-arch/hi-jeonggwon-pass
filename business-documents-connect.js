(() => {
 'use strict';
 const CLIENT='296636406674-rd44edn55es8urma78ttta4476roph3i.apps.googleusercontent.com',OWNER='needis123@gmail.com',SCOPE='https://www.googleapis.com/auth/drive.file',URL='https://ielwjiftulcolzfmhkwl.supabase.co',KEY='sb_publishable_wSENSDMotRXyYWzy8BT7LQ_ROiOjZoh';
 const client=supabase.createClient(URL,KEY),button=document.getElementById('connect'),status=document.getElementById('status'),redirect=location.origin+location.pathname,nonceKey='jk-document-oauth-state';
 let owner=false;
 async function init(){
  try{
   const {data,error}=await client.auth.getSession();if(error||!data?.session?.access_token)throw new Error('먼저 사장님 계정으로 장부에 로그인하세요.');
   const state=await client.rpc('jk_document_access_state');if(state.error||!state.data?.owner)throw new Error('저장소 연결은 사장님만 할 수 있습니다.');owner=true;
   const result=window.jkDocumentConnectionResponse;window.jkDocumentConnectionResponse=null;
   if(result.code||result.error){
    let saved;try{saved=JSON.parse(sessionStorage.getItem(nonceKey)||'null');}catch{}sessionStorage.removeItem(nonceKey);
    if(!saved||result.state!==saved.nonce||Date.now()-saved.time>10*60*1000||saved.user!==state.data.email)throw new Error('구글 연결 확인 시간이 지났거나 연결 요청이 맞지 않습니다. 다시 시작하세요.');
    if(result.error)throw new Error('구글 파일 접근을 허용해야 연결할 수 있습니다. 다시 시작하세요.');
    status.textContent='구글 저장소 연결을 안전하게 마무리하는 중입니다.';
    const response=await fetch(URL+'/functions/v1/jk-document-access',{method:'POST',headers:{Authorization:'Bearer '+data.session.access_token,apikey:KEY,'Content-Type':'application/json','X-Requested-With':'XmlHttpRequest'},body:JSON.stringify({action:'connect',code:result.code,redirect_uri:redirect}),cache:'no-store'});result.code='';
    const connected=await response.json();if(!response.ok)throw new Error(connected.error||'구글 연결을 완료하지 못했습니다.');
    if(connected.owner!==OWNER)throw new Error('저장 계정을 확인하지 못했습니다.');
    // Do not persist the temporary access token. The owner's main screen can refresh it.
    status.textContent='구글 서류 저장소 연결 완료. 환경설정으로 돌아가세요.';document.getElementById('back').textContent='연결 완료 · 환경설정 열기';
   }else status.textContent=state.data.drive_connected?'이미 연결된 저장소입니다. 필요할 때 다시 연결할 수 있습니다.':'아래 버튼을 눌러 구글 계정에서 앱 서류 파일 접근을 허용하세요.';
  }catch(e){status.textContent=e.message;}
  if(owner){const script=document.createElement('script');script.src='https://accounts.google.com/gsi/client';script.async=true;script.onload=()=>{button.disabled=false;};script.onerror=()=>{status.textContent='구글 연결 화면을 불러오지 못했습니다. 새로고침하세요.';};document.head.append(script);}
 }
 button.onclick=()=>{
  if(!owner)return;
  try{const nonce=crypto.randomUUID();sessionStorage.setItem(nonceKey,JSON.stringify({nonce,time:Date.now(),user:OWNER}));
   google.accounts.oauth2.initCodeClient({client_id:CLIENT,scope:SCOPE,include_granted_scopes:false,ux_mode:'redirect',redirect_uri:redirect,state:nonce,login_hint:OWNER,select_account:true}).requestCode();
  }catch{sessionStorage.removeItem(nonceKey);status.textContent='현재 화면 연결을 시작하지 못했습니다. 브라우저 설정을 확인하세요.';}
 };
 init();
})();
