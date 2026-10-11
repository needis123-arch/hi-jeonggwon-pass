(() => {
 'use strict';
 const URL='https://ielwjiftulcolzfmhkwl.supabase.co',KEY='sb_publishable_wSENSDMotRXyYWzy8BT7LQ_ROiOjZoh';
 const client=window.supabase.createClient(URL,KEY,{auth:{persistSession:true,autoRefreshToken:true}}),$=id=>document.getElementById(id);
 const esc=s=>String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
 let approved=false,epoch=0,viewEpoch=0,offset=0,customers=[],files=[],busy=false,search='';
 function message(s=''){$('message').textContent=s;}
 let authBusy=false,mailUntil=0,mailTimer;
 const mailRedirect=location.origin+location.pathname;
 function authError(error){
  const code=error?.code||'';
  if(code==='email_not_confirmed')return '가입한 이메일의 인증이 아직 완료되지 않았습니다. 받은메일함·스팸함에서 가입 확인 메일을 열고 인증 링크를 눌러 주세요. 계정 만들기를 반복할 필요는 없습니다.';
  if(code==='over_email_send_rate_limit'||code==='over_request_rate_limit'||error?.status===429)return '인증 메일 발송 제한에 걸렸습니다. 먼저 받은메일함·스팸함의 기존 가입 확인 메일을 확인하세요. 메일이 없다면 표시된 대기시간 후 다시 보내기를 눌러 주세요.';
  if(code==='email_address_not_authorized')return '현재 가입 메일 발송 설정이 이 이메일 주소를 허용하지 않습니다. 사장님에게 메일 발송 설정 확인을 요청하세요.';
  if(code==='signup_disabled')return '현재 서버에서 신규 가입이 중지되어 있습니다. 사장님에게 가입 설정 확인을 요청하세요.';
  if(code==='user_already_exists')return '이미 가입한 계정입니다. 로그인해 주세요. 이메일 인증 전이면 가입 확인 메일을 먼저 확인하세요.';
  if(code==='email_address_invalid'||code==='validation_failed')return '이메일 주소 형식을 확인하세요.';
  if(code==='weak_password')return '계정 비밀번호를 10자 이상으로 설정하고 다른 비밀번호를 사용해 주세요.';
  if(code==='invalid_credentials')return '이메일 또는 계정 비밀번호가 맞지 않습니다. 서류 비밀번호 4자리와 계정 비밀번호는 별개입니다.';
  if(code==='provider_disabled'||code==='validation_failed_google')return '구글 로그인 연결 설정이 아직 완료되지 않았습니다. 사장님에게 확인을 요청하세요.';
  if(code==='access_denied')return '구글 로그인이 취소되었습니다. 본인 구글 계정을 선택하고 다시 로그인하세요.';
  return '로그인·가입 요청을 처리하지 못했습니다. 연결을 확인하고 다시 시도하세요.'+(code?' (오류: '+String(code).replace(/[^a-z0-9_]/gi,'').slice(0,60)+')':'');
 }
 function mailButtons(){
  const seconds=Math.max(0,Math.ceil((mailUntil-Date.now())/1000));
  $('googleLogin').disabled=authBusy;$('login').disabled=authBusy;$('signup').disabled=authBusy||seconds>0;$('resend').disabled=authBusy||seconds>0;
  $('resend').textContent=seconds?'인증 메일 다시 보내기 · '+seconds+'초 후':'인증 메일 다시 보내기';
  if(!seconds&&mailTimer){clearInterval(mailTimer);mailTimer=null;}
 }
 function mailWait(seconds){mailUntil=Date.now()+seconds*1000;if(!mailTimer)mailTimer=setInterval(mailButtons,1000);mailButtons();}
 function checkAuthError(error){
  if(!error)return;
  if(error.code==='over_email_send_rate_limit'||error.code==='over_request_rate_limit'||error.status===429){
   const retry=String(error.message||'').match(/after (\d+) seconds/i);mailWait(retry?Math.min(3600,Math.max(1,Number(retry[1]))):3600);
  }
  throw new Error(authError(error));
 }
 async function authAction(f){if(authBusy)return;authBusy=true;mailButtons();try{await action(f);}finally{authBusy=false;mailButtons();}}
 function email(){const value=$('email').value.trim();if(!value||!$('email').checkValidity())throw new Error('올바른 이메일 주소를 입력하세요.');return value;}
 const viewer=jkDocumentViewer.mount({preview:$('preview'),title:$('fileTitle'),input:$('docPassword'),message,isActive:()=>approved,onBusy:value=>{busy=value;},getFile:async(row,password)=>{
  const {data,error}=await client.auth.getSession();if(error||!data?.session?.access_token)throw new Error('다시 로그인하세요.');
  const response=await fetch(URL+'/functions/v1/jk-document-access',{method:'POST',headers:{Authorization:'Bearer '+data.session.access_token,apikey:KEY,'Content-Type':'application/json'},body:JSON.stringify({action:'download',document_id:row.id}),cache:'no-store'});
  if(!response.ok){let text='서류를 불러오지 못했습니다.';try{text=(await response.json()).error||text;}catch{}if(response.status===401||response.status===403){clear();message(text);}throw new Error(text);}
  const content=await window.jkDocumentCrypto.decrypt(await response.blob(),password,row);$('lock').hidden=false;return content;
 }});
 function lock(){jkDocumentViewer.session.lock();$('lock').hidden=true;}
 function clear(){const previousMessage=$('message').textContent;viewEpoch++;lock();message(previousMessage);approved=false;customers=[];files=[];viewer.setRows([],'');$('directory').hidden=true;$('customers').replaceChildren();$('files').replaceChildren();$('selected').textContent='고객을 선택하세요.';$('unlock').hidden=true;}
 async function rpc(name,args={}){const {data,error}=await client.rpc(name,args);if(error)throw new Error('승인 또는 로그인이 변경됐습니다. 승인 상태 새로고침을 눌러 주세요.');return data;}
 async function state(){
  const n=++epoch;
  try{
   const {data,error}=await client.auth.getSession();if(n!==epoch)return;if(error)throw error;
   const session=data?.session;$('loginCard').hidden=Boolean(session);$('requestCard').hidden=!session;
   if(!session){clear();return;}
   const s=await rpc('jk_document_access_state');if(n!==epoch)return;
   $('identity').textContent=s.email;$('name').value=s.display_name||$('name').value;
   approved=!s.owner&&s.status==='approved';$('requestForm').hidden=s.owner||['pending','approved'].includes(s.status);
   $('status').textContent=s.owner?'사장님 계정입니다.':({none:'열람 신청 전',pending:'사장님 승인 대기 중',approved:'서류 열람 승인 완료',rejected:'이번 신청이 거절되었습니다.',revoked:'열람 권한이 회수되었습니다.'}[s.status]||'상태 확인 필요');
   $('requestHelp').textContent=s.owner?'사장님은 장부의 서류 보기와 환경설정 승인 메뉴를 이용하세요.':approved?(s.drive_connected?'서류 비밀번호는 사장님에게 별도로 안내받으세요.':'사장님의 구글 저장소 연결이 필요합니다.'):'승인 전에는 고객 목록과 사진을 볼 수 없습니다.';
   if(!approved){clear();return;}$('directory').hidden=false;
  }catch(e){if(n===epoch){clear();message(e.message||'이메일을 확인한 후 다시 로그인하세요.');}}
 }
 async function list(){
  if(!approved)return;const n=epoch;
  try{const rows=await rpc('jk_document_staff_customers',{p_search:search,p_offset:offset});if(n!==epoch||!approved)return;customers=rows||[];
   $('customers').innerHTML=customers.length?customers.map((r,i)=>`<button class="customer" data-customer="${i}"><b>${esc(r.customer_name_snapshot||'고객')}</b><br>${esc((r.customer_phone_snapshot||'').replace(/^(\d{3})(\d{4})(\d{4})$/,'$1-$2-$3'))}<br><span class="muted">${esc(r.activation_date)} · ${esc(r.vendor)}</span></button>`).join(''):'<p>조건에 맞는 구글 저장소 서류가 없습니다.</p>';
   $('previous').disabled=offset===0;$('next').disabled=customers.length<50;$('pageNumber').textContent=`${offset/50+1}쪽`;
  }catch(e){clear();message(e.message);}
 }
 async function choose(i){
  viewer.clear();viewEpoch++;files=[];$('files').replaceChildren();$('unlock').hidden=true;const r=customers[i];if(!r)return;const n=viewEpoch;
  $('selected').textContent=`${r.customer_name_snapshot||'고객'} · ${r.activation_date}`;
  document.querySelectorAll('[data-customer]').forEach(b=>b.setAttribute('aria-current',String(Number(b.dataset.customer)===i)));
  try{const rows=await rpc('jk_document_staff_files',{p_ledger_id:r.id});if(n!==viewEpoch||!approved)return;files=rows||[];
   $('files').innerHTML=files.map((d,j)=>`<button data-file="${j}">${esc(d.doc_kind)} · 보기</button>`).join('');$('unlock').hidden=!files.length;viewer.setRows(files,r.customer_name_snapshot+'_'+r.activation_date);
  }catch(e){clear();message(e.message);}
 }
 function show(i){if(!busy&&approved&&files[i])viewer.show(files[i]);}
 async function action(f){message();try{await f();}catch(e){message(e.message||'요청을 처리하지 못했습니다.');}}
 $('googleLogin').onclick=()=>authAction(async()=>{
  $('password').value='';
  const {error}=await client.auth.signInWithOAuth({provider:'google',options:{redirectTo:mailRedirect,scopes:'openid email profile',queryParams:{prompt:'select_account'}}});
  checkAuthError(error);
 });
 $('login').onclick=()=>authAction(async()=>{const {error}=await client.auth.signInWithPassword({email:email(),password:$('password').value});$('password').value='';checkAuthError(error);await state();await list();});
 $('signup').onclick=()=>{if(Date.now()<mailUntil)return;authAction(async()=>{const address=email(),password=$('password').value;if(password.length<10)throw new Error('10자 이상 계정 비밀번호를 입력하세요.');const {data,error}=await client.auth.signUp({email:address,password,options:{emailRedirectTo:mailRedirect}});$('password').value='';checkAuthError(error);await state();if(data?.session){await list();}else{mailWait(60);message('가입 확인 메일을 요청했습니다. 받은메일함·스팸함에서 인증 링크를 눌러 주세요. 이미 가입했다면 새 메일이 오지 않을 수 있습니다. 인증 후에는 계정 만들기 대신 로그인하세요.');}});};
 $('resend').onclick=()=>{if(Date.now()<mailUntil)return;authAction(async()=>{const {error}=await client.auth.resend({type:'signup',email:email(),options:{emailRedirectTo:mailRedirect}});checkAuthError(error);mailWait(60);message('가입 확인 메일을 다시 요청했습니다. 받은메일함·스팸함을 확인하고 인증 후 로그인하세요.');});};
 $('request').onclick=()=>action(async()=>{const name=$('name').value.trim();if(!name)throw new Error('직원 이름을 입력하세요.');await rpc('jk_document_request_access',{p_name:name});await state();});
 $('refresh').onclick=()=>action(async()=>{await state();await list();});
 $('logout').onclick=()=>action(async()=>{epoch++;clear();await client.auth.signOut();await state();});
 $('find').onclick=()=>action(async()=>{viewer.clear();offset=0;search=$('search').value.trim();await list();});
 $('search').onkeydown=e=>{if(e.key==='Enter')$('find').click();};
 $('previous').onclick=()=>action(async()=>{viewer.clear();offset=Math.max(0,offset-50);await list();});
 $('next').onclick=()=>action(async()=>{viewer.clear();offset+=50;await list();});
 $('customers').onclick=e=>{const b=e.target.closest('[data-customer]');if(b)choose(Number(b.dataset.customer));};
 $('files').onclick=e=>{const b=e.target.closest('[data-file]');if(b)show(Number(b.dataset.file));};
 $('lock').onclick=lock;
 document.addEventListener('visibilitychange',()=>{if(document.hidden)lock();else state();});
 window.addEventListener('pagehide',()=>{epoch++;clear();});
 client.auth.onAuthStateChange(e=>{if(e==='SIGNED_OUT'){epoch++;clear();}setTimeout(()=>state().then(list),0);});
 setInterval(()=>{if(!document.hidden&&approved)state();},30000);
 const callbackError=new URLSearchParams(location.hash.slice(1)).get('error');
 if(callbackError){history.replaceState(null,'',location.pathname+location.search);message(authError({code:callbackError}));}
 state().then(list);
})();
