(() => {
 'use strict';
 const URL='https://ielwjiftulcolzfmhkwl.supabase.co',KEY='sb_publishable_wSENSDMotRXyYWzy8BT7LQ_ROiOjZoh';
 const client=window.supabase.createClient(URL,KEY,{auth:{persistSession:true,autoRefreshToken:true}}),$=id=>document.getElementById(id);
 const esc=s=>String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
 let approved=false,epoch=0,viewEpoch=0,offset=0,customers=[],files=[],objectURL='',timer=null,busy=false,search='';
 function message(s=''){$('message').textContent=s;}
 function lock(){viewEpoch++;clearTimeout(timer);timer=null;if(objectURL)window.URL.revokeObjectURL(objectURL);objectURL='';$('preview').replaceChildren();$('docPassword').value='';$('lock').hidden=true;}
 function clear(){lock();approved=false;customers=[];files=[];$('directory').hidden=true;$('customers').replaceChildren();$('files').replaceChildren();$('selected').textContent='고객을 선택하세요.';$('unlock').hidden=true;}
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
  lock();files=[];$('files').replaceChildren();$('unlock').hidden=true;const r=customers[i];if(!r)return;const n=viewEpoch;
  $('selected').textContent=`${r.customer_name_snapshot||'고객'} · ${r.activation_date}`;
  document.querySelectorAll('[data-customer]').forEach(b=>b.setAttribute('aria-current',String(Number(b.dataset.customer)===i)));
  try{const rows=await rpc('jk_document_staff_files',{p_ledger_id:r.id});if(n!==viewEpoch||!approved)return;files=rows||[];
   $('files').innerHTML=files.map((d,j)=>`<button data-file="${j}">${esc(d.doc_kind)} · 비밀번호로 보기</button>`).join('');$('unlock').hidden=!files.length;
  }catch(e){clear();message(e.message);}
 }
 async function show(i){
  if(busy||!approved)return;const row=files[i],password=$('docPassword').value;if(!row)return;
  if(!/^[0-9]{4}$/.test(password)&&password.length<10){message('서류 비밀번호는 숫자 4자리입니다.');return;}
  lock();const n=viewEpoch;busy=true;message('승인 확인 후 사진을 불러오는 중입니다.');
  try{
   const {data,error}=await client.auth.getSession();if(error||!data?.session?.access_token)throw new Error('다시 로그인하세요.');
   const response=await fetch(URL+'/functions/v1/jk-document-access',{method:'POST',headers:{Authorization:'Bearer '+data.session.access_token,apikey:KEY,'Content-Type':'application/json'},body:JSON.stringify({action:'download',document_id:row.id}),cache:'no-store'});
   if(!response.ok){let text='서류를 불러오지 못했습니다.';try{text=(await response.json()).error||text;}catch{}if(response.status===401||response.status===403)clear();throw new Error(text);}
   const content=await window.jkDocumentCrypto.decrypt(await response.blob(),password,row);if(n!==viewEpoch||!approved)return;
   objectURL=window.URL.createObjectURL(content.blob);const img=new Image();img.alt='고객 서류';img.src=objectURL;$('preview').replaceChildren(img);$('lock').hidden=false;timer=setTimeout(lock,5*60*1000);message('열람 중 · 5분 후 자동으로 잠깁니다.');
  }catch(e){if(n===viewEpoch)message(e.message);else if(!approved)message(e.message);}finally{busy=false;}
 }
 async function action(f){message();try{await f();}catch(e){message(e.message||'요청을 처리하지 못했습니다.');}}
 $('login').onclick=()=>action(async()=>{const {error}=await client.auth.signInWithPassword({email:$('email').value.trim(),password:$('password').value});$('password').value='';if(error)throw new Error('이메일과 비밀번호, 가입 확인 여부를 확인하세요.');await state();await list();});
 $('signup').onclick=()=>action(async()=>{const email=$('email').value.trim(),password=$('password').value;if(!email||password.length<10)throw new Error('이메일과 10자 이상 계정 비밀번호를 입력하세요.');const {error}=await client.auth.signUp({email,password,options:{emailRedirectTo:location.href.split('#')[0]}});$('password').value='';if(error)throw new Error('계정 만들기를 완료하지 못했습니다. 이미 가입했다면 로그인하세요.');message('가입 확인 메일이 오면 확인한 후 로그인하세요.');await state();});
 $('request').onclick=()=>action(async()=>{const name=$('name').value.trim();if(!name)throw new Error('직원 이름을 입력하세요.');await rpc('jk_document_request_access',{p_name:name});await state();});
 $('refresh').onclick=()=>action(async()=>{await state();await list();});
 $('logout').onclick=()=>action(async()=>{epoch++;clear();await client.auth.signOut();await state();});
 $('find').onclick=()=>action(async()=>{lock();offset=0;search=$('search').value.trim();await list();});
 $('search').onkeydown=e=>{if(e.key==='Enter')$('find').click();};
 $('previous').onclick=()=>action(async()=>{lock();offset=Math.max(0,offset-50);await list();});
 $('next').onclick=()=>action(async()=>{lock();offset+=50;await list();});
 $('customers').onclick=e=>{const b=e.target.closest('[data-customer]');if(b)choose(Number(b.dataset.customer));};
 $('files').onclick=e=>{const b=e.target.closest('[data-file]');if(b)show(Number(b.dataset.file));};
 $('lock').onclick=lock;
 document.addEventListener('visibilitychange',()=>{if(document.hidden)lock();else state();});
 window.addEventListener('pagehide',()=>{epoch++;clear();});
 client.auth.onAuthStateChange(e=>{if(e==='SIGNED_OUT'){epoch++;clear();}setTimeout(state,0);});
 setInterval(()=>{if(!document.hidden&&approved)state();},30000);
 state().then(list);
})();
