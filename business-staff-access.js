/* Employees use the same BUSINESS CENTER. Server RPCs check approval on every read. */
(() => {
 'use strict';
 let owner=false,approved=false,documentOwner=false,manager=false,generation=0,requestBusy=false,loadGeneration=0,identity='',lastUser='';
 const pages=['ledger','used','payback','affiliate','consultations','closing','calendar'],operationRequests={};
 const el=id=>document.getElementById(id);
 const labels={none:'장부 열람 신청',pending:'사장님 승인 대기 중',approved:'장부·업무·마감보고·서류 이용 승인 완료',rejected:'이번 신청이 거절되었습니다.',revoked:'열람 권한이 회수되었습니다.'};
 function clear(preserveDaily=false){
  if(!preserveDaily)window.jkDailyReports?.clear();
  approved=false;documentOwner=false;manager=false;loadGeneration++;identity='';document.body.dataset.staffApproved='false';
  if(typeof closeLedgerDocuments==='function')closeLedgerDocuments();
  window.jkDocumentViewer?.session.lock();
  for(const key of Object.keys(state))if(Array.isArray(state[key]))state[key]=[];
  for(const id of ['ledgerBody','ledgerMobile','ledgerMonthNav','ledgerVendorNav','usedBody','paybackBody','affiliateBody','consultList','consultDetail'])el(id)?.replaceChildren();
  if(typeof consultState!=='undefined'){consultState.request++;consultState.selectionRequest++;consultState.rows=[];consultState.selected=null;consultState.creating=false;consultState.total=0;consultState.reminders=[];consultState.dueCount=0;renderConsultReminders();}
  renderLedger();renderLedgerMonthNav();
  if(el('ledgerResultCount'))el('ledgerResultCount').textContent='0건 조회';
  if(el('modalBg'))el('modalBg').classList.remove('show');
 }
 function init(){
  if(el('page-staffaccess'))return;
  titles.staffaccess='직원 승인 요청';
  const section=document.createElement('section');section.id='page-staffaccess';section.className='page';
  section.innerHTML='<div class="card" style="max-width:650px;padding:24px"><h2>직원 로그인 · 장부 열람</h2><p id="staffIdentity"></p><h3 id="staffApprovalStatus"></h3><p>사장님 승인 후 장부·중고반납·페이백·제휴카드·영업/상담을 조회하고, 새 상담과 본인 마감보고를 작성할 수 있습니다. 고객별 서류도 열람할 수 있습니다.</p><div id="staffRequestForm"><label for="staffRequestName">직원 이름</label><input id="staffRequestName" maxlength="80" autocomplete="name" style="width:100%;padding:12px;margin:10px 0"><button class="btn primary" id="staffRequestButton">사장님에게 장부·서류 열람 요청</button></div><p id="staffRequestMessage" role="status"></p><button class="btn" id="staffApprovalRefresh">승인 상태 새로고침</button><button class="btn" onclick="logout()">로그아웃</button></div>';
  document.querySelector('.content').append(section);
  const toolbar=document.createElement('div');toolbar.className='staff-ledger-toolbar';
  toolbar.innerHTML='<span>직원 업무 화면 · 장부·중고반납·페이백·제휴카드·상담을 확인하세요.</span><button class="btn" id="staffLedgerRefresh">새로고침</button><button class="btn" onclick="logout()">로그아웃</button>';
  el('page-ledger').prepend(toolbar);el('staffLedgerRefresh').onclick=loadLedger;
  for(const page of pages.filter(p=>p!=='ledger'&&p!=='closing'&&p!=='calendar')){const bar=document.createElement('div');bar.className='staff-ledger-toolbar';bar.innerHTML='<span>직원 업무 화면</span><button class="btn" data-staff-refresh>새로고침</button><button class="btn" onclick="logout()">로그아웃</button>';bar.querySelector('[data-staff-refresh]').onclick=()=>go(page,{push:false});el('page-'+page).prepend(bar);}
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
  init();const n=++generation;owner=false;document.body.dataset.access='locked';clear(Boolean(session));
  if(!session)return 'none';
  try{
   const {data,error}=await sb.rpc('jk_document_access_state');if(n!==generation)return 'stale';if(error||!data)throw Error();
   let admin=Boolean(data.owner);
   if(!admin){const r=await sb.rpc('is_admin');if(n!==generation)return 'stale';admin=!r.error&&r.data===true;}
   documentOwner=Boolean(data.storage_owner??data.owner);manager=Boolean(data.owner)&&data.storage_owner===false;approved=data.status==='approved';
   owner=admin;if(owner){document.body.dataset.access='owner';return 'owner';}
   approved=data.status==='approved';identity=session.user.id||session.user.email;document.body.dataset.staffApproved=String(approved);
   document.body.dataset.access='staff';hideLogin();el('staffIdentity').textContent=data.email||session.user.email;
   el('staffApprovalStatus').textContent=labels[data.status]||'승인 상태 확인 필요';
   el('staffRequestForm').hidden=['pending','approved'].includes(data.status);
   el('staffRequestName').value=data.display_name||el('staffRequestName').value;
   el('staffRequestMessage').textContent=data.status==='pending'?'사장님 환경설정에서 신청을 승인하면 장부가 열립니다.':'';
   if(!approved){window.jkDailyReports?.clear();go('staffaccess',{push:false,replace:true,instant:true});return 'waiting';}
   await loadLedger();if(n!==generation)return 'stale';if(!approved)return 'waiting';const requested=new URLSearchParams(location.search).get('page')||localStorage.getItem('jk-active-page');go(pages.includes(requested)?requested:'ledger',{push:false,replace:true,instant:true});return 'staff';
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
 async function readRpc(name,args){
  if(!approved||owner)return {data:null,error:{code:'42501'}};const epoch=generation,who=identity;
  let response;try{response=await sb.rpc(name,args);}catch{response={data:null,error:{message:'연결을 확인하세요.'}};}
  if(epoch!==generation||who!==identity||!approved)return {data:null,error:{code:'STALE'}};
  if(response.error?.code==='42501'){clear();el('staffApprovalStatus').textContent='열람 권한을 다시 확인하세요.';el('staffRequestMessage').textContent='승인 상태를 새로고침하세요.';go('staffaccess',{push:false,replace:true});}
  else if(response.error)toast('조회하지 못했습니다. 새로고침해 주세요.');
  return response;
 }
 async function operations(screen,month){
  const request=operationRequests[screen]=(operationRequests[screen]||0)+1;
  const result=await readRpc('jk_staff_operations',{p_screen:screen,p_month:month+'-01'});
  return request===operationRequests[screen]?result:{data:null,error:{code:'STALE'}};
 }
 function consultationArgs(){return {p_staff:consultState.staff,p_status:el('consultStatusFilter')?.value||'active',p_search:consultFieldValue('consultSearch').slice(0,100),p_page:consultState.page};}
 async function loadConsultations(){
  if(!approved)return;const request=++consultState.request;
  const {data,error}=await readRpc('jk_staff_consultations',consultationArgs());
  if(request!==consultState.request||!approved)return;
  if(error||!data){el('consultList').innerHTML='<div class="empty">상담 목록을 불러오지 못했습니다. 새로고침해 주세요.</div>';return;}
  consultState.rows=data.rows||[];consultState.total=data.count||0;
  if(!consultState.rows.length&&consultState.page>1){consultState.page=1;return loadConsultations();}renderConsultList();
 }
 async function selectConsultation(id,push=true){
  if(!approved)return;const request=++consultState.selectionRequest;consultState.creating=false;if(push)consultPushRoute(id);
  const {data,error}=await readRpc('jk_staff_consultations',{p_id:id});
  if(request!==consultState.selectionRequest||!approved)return;
  if(error||!data?.rows?.[0]){el('consultDetail').innerHTML='<div class="empty">상담을 조회하지 못했습니다. 고객을 다시 선택하세요.</div>';return;}
  consultState.selected=data.rows[0];renderConsultDetail(consultState.selected);renderConsultList();
  el('consultHistory').innerHTML=(data.history||[]).map(h=>'<div><b>'+esc(h.action)+'</b> <small>'+esc(new Date(h.created_at).toLocaleString('ko-KR',{timeZone:'Asia/Seoul'}))+'</small><p>'+esc(h.note||'상담 정보 변경')+'</p><small>'+esc(h.snapshot?.staff_name||'미지정')+' · '+esc(h.snapshot?.status||'-')+' · 다음 연락 '+esc(h.snapshot?.next_contact_on||'종료')+'</small></div>').join('')||'<p class="consult-note">아직 처리 이력이 없습니다.</p>';
 }
 function renderConsultDetail(r){
  el('consultLayout').classList.add('detail-open');
  const info=[['담당자',r.staff_name||'미지정'],['상담 상태',r.status],['상담일',r.consulted_on],['실제 방문일',r.visited_on||'-'],['다음 연락 예정일',r.next_contact_on||'-'],['재연락 간격',(r.followup_days||3)+'일'],['필요 서비스',(r.services||[]).join(' · ')||'-'],['상담 방식',r.contact_method],['이사 예정일',r.move_date||'-'],['추천인 코드',r.referral_code||'-'],['접수 경로',r.intake_source],['접수일',r.created_at?new Date(r.created_at).toLocaleString('ko-KR',{timeZone:'Asia/Seoul'}):'-'],['고객 신청 내용',r.customer_note||'-'],['상담 내역',r.consultation_note||'-'],['최근 연락일',r.last_contacted_on||'-'],['최근 연락 결과',r.last_contact_note||'-']];
  el('consultDetail').innerHTML='<button class="btn consult-mobile-back" onclick="returnConsultList()">← 상담 목록</button><div class="consult-detail-header"><div><h3>'+esc(r.customer_name)+'</h3><a class="consult-phone" href="tel:'+esc(r.phone_digits)+'">'+esc(formatPhone(r.phone_digits))+'</a><div class="consult-note">'+esc(consultDueLabel(r))+' · 조회 전용</div></div><div class="consult-actions"><a class="btn primary" href="tel:'+esc(r.phone_digits)+'">바로 전화</a><button class="btn" onclick="copyConsultPhone()">번호 복사</button></div></div><section class="consult-detail-section"><h4>상담 상세</h4><dl class="consult-info-grid">'+info.map(([k,v])=>'<div><dt>'+esc(k)+'</dt><dd style="white-space:pre-wrap">'+esc(v??'-')+'</dd></div>').join('')+'</dl></section><section class="consult-detail-section"><h4>상담 / 재연락 이력</h4><div class="consult-history" id="consultHistory"></div></section>';
  if(matchMedia('(max-width:900px)').matches)el('consultDetail').scrollIntoView({block:'start',behavior:'smooth'});
 }
 async function loadReminders(){const {data,error}=await readRpc('jk_staff_consultations',{p_status:'due'});if(error||!approved)return;consultState.reminders=data.rows||[];consultState.dueCount=data.count||0;renderConsultReminders();}
 window.jkStaffAccess=Object.freeze({gate,loadLedger,google,operations,loadConsultations,selectConsultation,renderConsultDetail,loadReminders,get readOnly(){return !owner;},get documentReadOnly(){return !documentOwner;},get approved(){return approved;}});
 document.addEventListener('DOMContentLoaded',()=>{
  init();el('staffGoogleLogin').onclick=google;
  sb.auth.onAuthStateChange(event=>{if(event==='SIGNED_OUT'){generation++;owner=false;clear();document.body.dataset.access='locked';location.reload();return;}if(event==='SIGNED_IN')setTimeout(()=>sessionChanged(),0);});
  // Revocation also clears cached ledger rows and opened photos, without resetting filters on every poll.
  setInterval(async()=>{if(document.hidden||(owner&&!manager)||!approved)return;const n=generation;try{const r=await sb.rpc('jk_document_access_state');if(n!==generation)return;if(r.error||r.data?.status!=='approved'||(manager&&!r.data?.owner))await sessionChanged();}catch{if(n===generation)await sessionChanged();}},30000);
  document.addEventListener('visibilitychange',()=>{if(!document.hidden&&approved)sessionChanged();});
  const error=new URLSearchParams(location.hash.slice(1)).get('error');if(error){history.replaceState(null,'',location.pathname+location.search);el('loginMsg').textContent='구글 로그인이 취소되었거나 완료되지 않았습니다. 다시 로그인하세요.';}
 },{once:true});
})();
