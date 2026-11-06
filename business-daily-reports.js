/* Daily shared reports. Approved staff write their own; business managers can manage all. */
(() => {
 'use strict';
 const s={date:'',data:null,selected:null,dirty:false,busy:false,epoch:0,loading:false};
 const el=id=>document.getElementById(id),statusName=x=>x==='submitted'?'작성 완료':x==='draft'?'임시저장':'미작성';
 const today=()=>new Intl.DateTimeFormat('sv-SE',{timeZone:'Asia/Seoul',year:'numeric',month:'2-digit',day:'2-digit'}).format(new Date());
 const empty=()=>({visit:0,phone:0,online:0,flyers:0,reels_filmed:0,reels_uploaded:0,completed:'',tomorrow:'',shared:'',followups:[]});
 const allowed=()=>document.body.dataset.access==='owner'||(document.body.dataset.access==='staff'&&window.jkStaffAccess?.approved);
 const report=()=>s.data?.reports.find(r=>r.author_id===s.selected);
 const editable=()=>Boolean(s.data&&(s.selected===s.data.user_id||s.data.can_manage&&document.body.dataset.access==='owner'));
 const name=()=>s.data?.roster.find(r=>r.author_id===s.selected)?.author_name||report()?.author_name||'직원';
 function message(text,type=''){el('closingMessage').textContent=text;el('closingMessage').className='closing-message '+type;}
 function proceed(){return !s.busy&&(!s.dirty||confirm('아직 저장하지 않은 마감보고가 있습니다. 이동하면 작성 내용이 사라집니다. 이동할까요?'));}
 function beforeLeave(){if(!proceed())return false;if(s.dirty){s.dirty=false;s.data=null;}return true;}
 function clear(){s.epoch++;s.data=null;s.selected=null;s.dirty=false;s.busy=false;s.loading=false;for(const id of ['closingTeam','closingEditor','closingSummary'])el(id)?.replaceChildren();if(el('closingError'))el('closingError').textContent='';}
 function init(){
  titles.closing='마감보고';const page=document.createElement('section');page.id='page-closing';page.className='page';
  page.innerHTML='<div class="section-head"><div><h2>마감보고</h2><p>매일 상담과 업무를 기록하고, 직원 모두의 보고를 함께 확인합니다.</p></div><button class="btn primary" id="closingMine">내 보고 작성</button></div><div class="closing-controls"><button class="btn" id="closingPrev" aria-label="이전 날짜">◀</button><label for="closingDate">보고 날짜</label><input id="closingDate" type="date"><button class="btn" id="closingNext" aria-label="다음 날짜">▶</button><button class="btn" id="closingToday">오늘</button><button class="btn" id="closingReload">새로고침</button></div><div id="closingError" class="closing-message error" role="status"></div><div id="closingSummary" class="closing-summary"></div><div class="closing-layout"><aside class="card closing-team"><h3>직원별 작성 현황</h3><p class="closing-help">승인된 계정 기준입니다. 근무한 직원은 오늘 보고를 작성해 주세요.</p><div id="closingTeam" class="closing-team-list"></div></aside><article id="closingEditor" class="card closing-editor"></article></div>';
  document.querySelector('.content').append(page);el('closingDate').max=today();
  el('closingDate').onchange=()=>{const next=el('closingDate').value;if(!proceed()){el('closingDate').value=s.date;return;}load(next);};
  for(const [id,days] of [['closingPrev',-1],['closingNext',1]])el(id).onclick=()=>{if(!proceed())return;const date=new Date(s.date+'T12:00:00+09:00');date.setUTCDate(date.getUTCDate()+days);load(new Intl.DateTimeFormat('sv-SE',{timeZone:'Asia/Seoul'}).format(date));};
  el('closingToday').onclick=()=>{if(proceed())load(today());};el('closingReload').onclick=()=>{if(proceed())load(s.date);};
  el('closingMine').onclick=()=>{if(!s.data||!proceed())return;s.selected=s.data.user_id;s.dirty=false;render();};
  page.addEventListener('input',e=>{if(e.target.closest('#closingEditor')&&editable()&&!s.busy){s.dirty=true;updateTotal();const stamp=el('closingStamp');if(stamp)stamp.textContent='변경사항 저장 필요';}});
  window.addEventListener('beforeunload',e=>{if(s.dirty){e.preventDefault();e.returnValue='';}});
 }
 async function load(date=today()){
  if(!allowed())return clear();
  if(!/^\d{4}-\d{2}-\d{2}$/.test(date)||date>today()||date<'2020-01-01'){el('closingError').textContent='오늘 또는 지난 날짜를 선택하세요.';el('closingDate').value=s.date||today();return;}
  const n=++s.epoch;s.loading=true;s.dirty=false;s.data=null;s.date=date;el('closingDate').value=date;el('closingDate').max=today();el('closingNext').disabled=date>=today();el('closingError').textContent='';el('closingTeam').replaceChildren();el('closingSummary').replaceChildren();el('closingEditor').innerHTML='<p class="closing-help">보고를 불러오는 중...</p>';
  try{const {data,error}=await sb.rpc('jk_daily_report_data',{p_date:date});if(n!==s.epoch||!allowed())return;if(error)throw error;
   if(!data||!Array.isArray(data.roster)||!Array.isArray(data.reports))throw Error('마감보고를 불러오지 못했습니다.');
   s.data=data;s.selected=data.roster.some(r=>r.author_id===s.selected)||data.reports.some(r=>r.author_id===s.selected)?s.selected:data.user_id;render();
  }catch(e){if(n!==s.epoch)return;el('closingEditor').replaceChildren();el('closingError').textContent=e.code==='42501'?'직원 승인 상태를 다시 확인하세요.':e.message||'보고를 불러오지 못했습니다. 새로고침해 주세요.';if(e.code==='42501')sessionChanged();}finally{if(n===s.epoch)s.loading=false;}
 }
 function render(){
  if(!s.data)return;const completed=s.data.reports.filter(r=>r.report_status==='submitted'),drafts=s.data.reports.filter(r=>r.report_status==='draft'),roster=s.data.roster;
  const missing=roster.filter(r=>!s.data.reports.some(x=>x.author_id===r.author_id)).length;
  const total=completed.reduce((n,r)=>n+Number(r.body.visit)+Number(r.body.phone)+Number(r.body.online),0);
  el('closingSummary').innerHTML=[['작성 완료',completed.length+'명'],['임시저장',drafts.length+'명'],['미작성',missing+'명'],['완료 보고 상담 합계',total+'팀']].map(([k,v])=>'<div class="card closing-stat"><small>'+esc(k)+'</small><b>'+esc(v)+'</b></div>').join('');
  const people=[...roster,...s.data.reports.filter(r=>!roster.some(x=>x.author_id===r.author_id))];
  el('closingTeam').innerHTML=people.map(p=>{const r=s.data.reports.find(x=>x.author_id===p.author_id),count=r?Number(r.body.visit)+Number(r.body.phone)+Number(r.body.online):0;return '<button class="closing-person" data-closing-author="'+esc(p.author_id)+'" aria-pressed="'+(p.author_id===s.selected)+'"><span><b>'+esc(p.author_name)+(p.author_id===s.data.user_id?' (나)':'')+'</b><small>'+(r?'상담 '+count+'팀':'보고를 작성해 주세요')+'</small></span><span class="closing-status '+esc(r?.report_status||'')+'">'+statusName(r?.report_status)+'</span></button>';}).join('');
  el('closingTeam').querySelectorAll('[data-closing-author]').forEach(b=>b.onclick=()=>{if(!proceed())return;s.selected=b.dataset.closingAuthor;s.dirty=false;render();});renderEditor();
 }
 function numeric(key,label,b){return '<div class="closing-field"><label for="closing-'+key+'">'+label+'</label><input id="closing-'+key+'" data-closing-number="'+key+'" type="number" min="0" max="10000" step="1" inputmode="numeric" value="'+Number(b[key]||0)+'"></div>';}
 function renderEditor(){
  const r=report(),b={...empty(),...(r?.body||{})},can=editable();
  if(!can&&!r){el('closingEditor').innerHTML='<h3>'+esc(name())+'</h3><p class="closing-help">이 날짜의 마감보고가 아직 없습니다. 직원별 현황에서 다른 보고를 선택하거나 내 보고를 작성하세요.</p>';return;}
  el('closingEditor').innerHTML='<div class="closing-editor-head"><div><h3>'+esc(s.date.slice(5).replace('-','월 '))+'일 / '+esc(name())+'</h3><span class="closing-status '+esc(r?.report_status||'')+'">'+statusName(r?.report_status)+'</span><p id="closingStamp" class="closing-help">'+(r?'마지막 저장 '+esc(new Date(r.updated_at).toLocaleString('ko-KR',{timeZone:'Asia/Seoul'})):'아직 저장하지 않았습니다.')+'</p></div><button class="btn" id="closingCopy">보고 복사</button></div><p class="closing-help">'+(can?(s.selected===s.data.user_id?'본인의 마감보고를 작성합니다.':'관리자 권한으로 이 직원의 보고를 작성·수정합니다.'):'다른 직원의 보고를 조회하고 있습니다.')+'</p><fieldset id="closingFields" style="border:0;padding:0;margin:0;min-width:0" '+(!can?'disabled':'')+'><h4>1. 오늘 상담</h4><div class="closing-counts">'+numeric('visit','방문 상담 (팀)',b)+numeric('phone','전화 상담 (팀)',b)+numeric('online','온라인 · DM·카톡 등 (팀)',b)+'</div><p class="closing-total" id="closingTotal"></p><h4>2. 개통 대기·재연락</h4><p class="closing-help">고객 구분 / 상담 내용 / 남은 일 / 연락 예정 시간 (한국 시간). 없으면 비워 두세요.</p><div class="closing-followups" id="closingFollowups"></div>'+(can?'<button class="btn" id="closingAddFollowup" style="margin-top:12px">+ 고객 추가</button>':'')+'<h4>3. 오늘 한 일·내일 할 일</h4><div class="closing-counts">'+numeric('flyers','전단지 배포 (장)',b)+numeric('reels_filmed','릴스 촬영 (개)',b)+numeric('reels_uploaded','릴스 업로드 (개)',b)+'</div><div class="closing-work" style="margin-top:16px">'+[['completed','오늘 완료한 업무 *'],['tomorrow','내일 우선 처리할 일 *'],['shared','재고·개통·고객 응대 중 공유할 사항']].map(([k,label])=>'<div class="closing-field"><label for="closing-'+k+'">'+label+'</label><textarea id="closing-'+k+'" maxlength="10000" rows="4" placeholder="'+(k==='shared'?'공유할 사항이 없으면 비워두세요.':'없으면 ‘없음’으로 입력하세요.')+'">'+esc(b[k])+'</textarea></div>').join('')+'</div></fieldset><div id="closingMessage" class="closing-message" role="status"></div>'+(can?'<div class="closing-savebar"><button class="btn" id="closingDraft">임시저장</button><button class="btn primary" id="closingSubmit">마감보고 완료</button><span class="closing-help">직원 모두에게 공유됩니다. 저장 후에도 수정할 수 있습니다.</span></div>':'')+'<div id="closingCopyFallback"></div>';
  for(const item of b.followups)addFollowup(item,false);if(!b.followups.length&&!can)el('closingFollowups').innerHTML='<p class="closing-help">개통 대기·재연락 고객이 없습니다.</p>';
  if(can){el('closingAddFollowup').onclick=()=>addFollowup();el('closingDraft').onclick=()=>save('draft');el('closingSubmit').onclick=()=>save('submitted');}el('closingCopy').onclick=copy;updateTotal();
 }
 function addFollowup(item={customer:'',content:'',pending:'',contact_at:''},dirty=true){
  if(dirty&&(!editable()||s.busy))return;const area=el('closingFollowups');if(area.querySelectorAll('.closing-followup').length>=50){message('재연락 고객은 50명까지 입력할 수 있습니다.','error');return;}
  const row=document.createElement('div');row.className='closing-followup';row.innerHTML=[['customer','고객 구분','예: A고객'],['content','상담 내용','예: 기기변경'],['pending','남은 일','예: 희망 색상 입고 안내'],['contact_at','연락 예정 시간','']].map(([k,label,placeholder])=>'<div class="closing-field"><label>'+label+'<input aria-label="'+label+'" data-followup="'+k+'" maxlength="1000" type="'+(k==='contact_at'?'datetime-local':'text')+'" placeholder="'+placeholder+'" value="'+esc(item[k]||'')+'"></label></div>').join('')+(editable()?'<button class="btn danger" type="button">이 고객 행 지우기</button>':'');
  const remove=row.querySelector('button');if(remove)remove.onclick=()=>{if(s.busy)return;row.remove();s.dirty=true;};area.append(row);if(dirty)s.dirty=true;
 }
 function updateTotal(){if(!el('closingTotal'))return;el('closingTotal').textContent='오늘 상담 '+['visit','phone','online'].reduce((n,k)=>n+Number(el('closing-'+k).value||0),0)+'팀';}
 function body(validate=false,status='draft'){
  const b=empty();for(const k of ['visit','phone','online','flyers','reels_filmed','reels_uploaded']){const v=el('closing-'+k).value;if(validate&&(!/^\d+$/.test(v)||Number(v)>10000))throw Error('팀 수와 업무 수량을 0 이상의 정수로 입력하세요.');b[k]=Number(v||0);}
  for(const k of ['completed','tomorrow','shared'])b[k]=el('closing-'+k).value.trim();
  b.followups=[...el('closingFollowups').querySelectorAll('.closing-followup')].map(row=>Object.fromEntries([...row.querySelectorAll('[data-followup]')].map(e=>[e.dataset.followup,e.value.trim()]))).filter(row=>Object.values(row).some(Boolean));
  if(validate&&status==='submitted'){if(!b.completed||!b.tomorrow)throw Error('오늘 완료한 업무와 내일 할 일을 적어 주세요. 없으면 없음으로 입력하세요.');if(b.followups.some(row=>Object.values(row).some(v=>!v)))throw Error('재연락 고객의 구분·상담 내용·남은 일·연락 예정 시간을 모두 입력하세요.');}
  return b;
 }
 async function save(status){
  if(s.busy||!editable()||!allowed())return;let b;try{b=body(true,status);}catch(e){message(e.message,'error');return;}
  const n=s.epoch,date=s.date,author=s.selected,version=report()?.version||0;s.busy=true;el('closingFields').disabled=true;el('closingDraft').disabled=true;el('closingSubmit').disabled=true;message('저장 중...');
  try{const {data,error}=await sb.rpc('jk_save_daily_report',{p_date:date,p_body:b,p_status:status,p_expected_version:version,p_author_id:author});if(n!==s.epoch||!allowed())return;if(error)throw error;
   s.data.reports=s.data.reports.filter(r=>r.author_id!==author);s.data.reports.push(data);s.dirty=false;render();message(status==='submitted'?'마감보고를 완료했습니다. 직원별 현황에 반영되었습니다.':'임시저장했습니다. 작성 후 마감보고 완료를 눌러 주세요.','success');
  }catch(e){if(n!==s.epoch)return;message(e.code==='42501'?'직원 승인 상태를 다시 확인하세요.':e.message||'저장하지 못했습니다. 다시 시도하세요.','error');if(e.code==='42501'){clear();sessionChanged();}}
  finally{if(n===s.epoch){s.busy=false;if(el('closingFields'))el('closingFields').disabled=!editable();for(const id of ['closingDraft','closingSubmit'])if(el(id))el(id).disabled=false;}}
 }
 function text(){const b=body(),time=x=>x?x.replace('T',' '):'미정';return '마감보고\n'+s.date+' / '+name()+'\n\n1. 오늘 상담 '+(b.visit+b.phone+b.online)+'팀\n방문 '+b.visit+'팀 / 전화 '+b.phone+'팀 / 온라인(DM·카톡 등) '+b.online+'팀\n\n2. 개통 대기·재연락\n고객 구분 / 상담 내용 / 남은 일 / 연락 예정 시간\n'+(b.followups.map(r=>[r.customer,r.content,r.pending,time(r.contact_at)].join(' / ')).join('\n')||'없음')+'\n\n3. 오늘 한 일·내일 할 일\n전단지 '+b.flyers+'장 / 릴스 촬영 '+b.reels_filmed+'개 / 업로드 '+b.reels_uploaded+'개\n오늘 완료한 업무: '+b.completed+'\n내일 우선 처리할 일: '+b.tomorrow+'\n재고·개통·고객 응대 중 공유할 사항: '+(b.shared||'없음');}
 async function copy(){try{await navigator.clipboard.writeText(text());message('보고 내용을 복사했습니다.');}catch{el('closingCopyFallback').innerHTML='<label class="closing-help">아래 내용을 선택해 복사하세요.<textarea class="closing-copy-box" rows="15" readonly>'+esc(text())+'</textarea></label>';}}
 window.jkDailyReports=Object.freeze({init,open:()=>{if(s.data)return;return load(s.date||today());},clear,beforeLeave});
})();
