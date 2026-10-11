/* Employees use the same BUSINESS CENTER. Server RPCs check approval on every read. */
(() => {
 'use strict';
 let owner=false,approved=false,generation=0,requestBusy=false,loadGeneration=0,identity='',lastUser='';
 const el=id=>document.getElementById(id);
 const labels={none:'장부 열람 신청',pending:'사장님 승인 대기 중',approved:'장부·서류 열람 승인 완료',rejected:'이번 신청이 거절되었습니다.',revoked:'열람 권한이 회수되었습니다.'};
 function clear(){
  approved=false;loadGeneration++;identity='';
  if(typeof closeLedgerDocuments==='function')closeLedgerDocuments();
  window.jkDocumentViewer?.session.lock();
  for(const key of Object.keys(state))if(Array.isArray(state[key]))state[key]=[];
  for(const id of ['ledgerBody','ledgerMobile','ledgerMonthNav','ledgerVendorNav'])el(id)?.replaceChildren();
  renderLedger();renderLedgerMonthNav();
  if(el('ledgerResultCount'))el('ledgerResultCount').textContent='0건 조회';
  if(el('modalBg'))el('modalBg').classList.remove('show');
 }
 function init(){
  if(el('page-staffaccess'))return;
  titles.staffaccess='직원 승인 요청';
  const section=document.createElement('section');section.id='page-staffaccess';section.className='page';
  section.innerHTML='<div class="card" style="max-width:650px;padding:24px"><h2>직원 로그인 · 장부 열람</h2><p id="staffIdentity"></p><h3 id="staffApprovalStatus"></h3><p>사장님 승인 후 이 BUSINESS CENTER에서 장부를 조회하고 고객별 서류를 열 수 있습니다.</p><div id="staffRequestForm"><label for="staffRequestName">직원 이름</label><input id="staffRequestName" maxlength="80" autocomplete="name" style="width:100%;padding:12px;margin:10px 0"><button class="btn primary" id="staffRequestButton">사장님에게 장부·서류 열람 요청</button></div><p id="staffRequestMessage" role="status"></p><button class="btn" id="staffApprovalRefresh">승인 상태 새로고침</button><button class="btn" onclick="logout()">로그아웃</button></div>';
  document.querySelector('.content').append(section);
  const toolbar=document.createElement('div');toolbar.className='staff-ledger-toolbar';
  toolbar.innerHTML='<span>직원 조회 화면 · 고객 상세에서 서류를 확인하세요.</span><button class="btn" id="staffLedgerRefresh">새로고침</button><button class="btn" onclick="logout()">로그아웃</button>';
  el('page-ledger').prepend(toolbar);el('staffLedgerRefresh').onclick=loadLedger;
  el('staffRequestButton').onclick=async()=>{
   if(requestBusy)return;const name=el('staffRequestName').value.trim();if(!name){el('staffRequestMessage').textContent='직원 이름을 입력하세요.';return;}
   requestBusy=true;el('staffRequestButton').disabled=true;const n=generation;
   try{const {error}=await sb.rpc('jk_document_request_access',{p_name:name});if(error)throw error;if(n===generation)await sessionChanged();}
   catch{el('staffRequestMessage').textContent='신청하지 못했습니다. 다시 로그인한 후 요청하세요.';}
   finally{requestBusy=false;el('staffRequestButton').disabled=false;}
  };
  el('staffApprovalRefresh').onclick=()=>sessionChanged();
 }
 async function gate(session){
  const nextUser=session?.user?.id||session?.user?.email||'';
  if(lastUser&&nextUser!==lastUser){location.reload();return 'stale';}lastUser=nextUser;
  init();const n=++generation;owner=false;document.body.dataset.access='locked';clear();
  if(!session)return 'none';
  try{
   const {data,error}=await sb.rpc('jk_document_access_state');if(n!==generation)return 'stale';if(error||!data)throw Error();
   let admin=Boolean(data.owner);
   if(!admin){const r=await sb.rpc('is_admin');if(n!==generation)return 'stale';admin=!r.error&&r.data===true;}
   owner=admin;if(owner){document.body.dataset.access='owner';return 'owner';}
   approved=data.status==='approved';identity=session.user.id||session.user.email;
   document.body.dataset.access='staff';hideLogin();el('staffIdentity').textContent=data.email||session.user.email;
   el('staffApprovalStatus').textContent=labels[data.status]||'승인 상태 확인 필요';
   el('staffRequestForm').hidden=['pending','approved'].includes(data.status);
   el('staffRequestName').value=data.display_name||el('staffRequestName').value;
   el('staffRequestMessage').textContent=data.status==='pending'?'사장님 환경설정에서 신청을 승인하면 장부가 열립니다.':'';
   if(!approved){go('staffaccess',{push:false,replace:true,instant:true});return 'waiting';}
   go('ledger',{push:false,replace:true,instant:true});await loadLedger();return 'staff';
  }catch{
   if(n===generation){clear();showLogin();el('loginMsg').textContent='권한을 확인하지 못했습니다. 다시 로그인하세요.';}
   return 'waiting';
  }
 }
 async function loadLedger(){
  if(!approved)return;const n=++loadGeneration,who=identity;
  const {data,error}=await sb.rpc('jk_staff_ledger',{p_month:(el('ledgerMonth').value||mk(now))+'-01'});
  if(n!==loadGeneration||!approved||who!==identity)return;
  if(error||!data){clear();el('staffRequestMessage').textContent='장부 권한을 확인하지 못했습니다. 승인 상태를 새로고침하세요.';go('staffaccess',{push:false,replace:true,instant:true});return;}
  state.ledger=data.rows||[];state.ledgerYear=data.year||[];state.staff=data.staff||[];
  renderLedgerFilters();renderLedgerMonthNav();renderLedger();
 }
 async function google(){
  const button=el('staffGoogleLogin');if(button.disabled)return;button.disabled=true;el('loginMsg').textContent='구글 계정 선택 화면으로 이동합니다.';
  try{
   const embedded=window.self!==window.top;
   const options={redirectTo:location.origin+location.pathname,scopes:'openid email profile',queryParams:{prompt:'select_account'}};
   if(embedded)options.skipBrowserRedirect=true;
   const {data,error}=await sb.auth.signInWithOAuth({provider:'google',options});if(error)throw error;
   if(embedded){if(!data?.url)throw Error();window.top.location.assign(data.url);}
  }
  catch{el('loginMsg').textContent='구글 로그인을 시작하지 못했습니다. 다시 시도하세요.';button.disabled=false;}
 }
 window.jkStaffAccess=Object.freeze({gate,loadLedger,google,get readOnly(){return !owner;},get approved(){return approved;}});
 document.addEventListener('DOMContentLoaded',()=>{
  init();el('staffGoogleLogin').onclick=google;
  sb.auth.onAuthStateChange(event=>{if(event==='SIGNED_OUT'){generation++;owner=false;clear();document.body.dataset.access='locked';location.reload();return;}if(event==='SIGNED_IN')setTimeout(()=>sessionChanged(),0);});
  // Revocation also clears cached ledger rows and opened photos, without resetting filters on every poll.
  setInterval(async()=>{if(document.hidden||owner||!approved)return;const n=generation;try{const r=await sb.rpc('jk_document_access_state');if(n!==generation)return;if(r.error||r.data?.status!=='approved')await sessionChanged();}catch{if(n===generation)await sessionChanged();}},30000);
  document.addEventListener('visibilitychange',()=>{if(!document.hidden&&approved)sessionChanged();});
  const error=new URLSearchParams(location.hash.slice(1)).get('error');if(error){history.replaceState(null,'',location.pathname+location.search);el('loginMsg').textContent='구글 로그인이 취소되었거나 완료되지 않았습니다. 다시 로그인하세요.';}
 },{once:true});
})();
