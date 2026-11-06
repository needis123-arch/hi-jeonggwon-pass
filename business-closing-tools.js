/* In-app daily reminders and consultation snapshots; no messages or browser push sent. */
(() => {
 'use strict';
 let reminderEpoch=0,reminderBusy=false,pickerEpoch=0,target=null,pickerPage=1,pickerTotal=0,pickerRows=[],searchTimer;
 const el=id=>document.getElementById(id),allowed=()=>document.body.dataset.access==='owner'||(document.body.dataset.access==='staff'&&window.jkStaffAccess?.approved);
 const today=()=>new Intl.DateTimeFormat('sv-SE',{timeZone:'Asia/Seoul',year:'numeric',month:'2-digit',day:'2-digit'}).format(new Date());
 function clear(){reminderEpoch++;reminderBusy=false;el('closingReminder')?.replaceChildren();if(el('closingReminder'))el('closingReminder').hidden=true;document.querySelectorAll('[data-closing-badge]').forEach(x=>{x.hidden=true;x.textContent='';});closePicker();}
 function closePicker(){pickerEpoch++;clearTimeout(searchTimer);target=null;pickerRows=[];const d=el('closingConsultDialog');if(d?.open)d.close();el('closingConsultResults')?.replaceChildren();if(el('closingConsultSearch'))el('closingConsultSearch').value='';}
 function init(){
  const banner=document.createElement('div');banner.id='closingReminder';banner.className='closing-reminder';banner.hidden=true;banner.setAttribute('role','status');document.querySelector('.content').prepend(banner);
  const dialog=document.createElement('dialog');dialog.id='closingConsultDialog';dialog.className='closing-consult-dialog';dialog.innerHTML='<div class="closing-picker-head"><h3>영업 · 상담에서 고객 선택</h3><button class="btn" id="closingConsultClose" type="button">닫기</button></div><p class="closing-help">전체 상담에서 이름·번호로 검색합니다. 선택한 고객의 이름·번호·상담내역을 보고에 복사하며 원래 상담 기록은 바뀌지 않습니다.</p><label class="closing-field">고객명 또는 전화번호<input id="closingConsultSearch" type="search" maxlength="100" placeholder="고객명 또는 전화번호 검색"></label><div id="closingConsultResults" class="closing-consult-results" aria-live="polite"></div><div class="closing-picker-pager"><button class="btn" id="closingConsultPrev">◀ 이전</button><span id="closingConsultPage"></span><button class="btn" id="closingConsultNext">다음 ▶</button></div>';
  document.body.append(dialog);el('closingConsultClose').onclick=closePicker;dialog.addEventListener('cancel',closePicker);
  el('closingConsultSearch').oninput=()=>{pickerPage=1;clearTimeout(searchTimer);pickerEpoch++;searchTimer=setTimeout(loadPicker,250);};
  for(const [id,delta] of [['closingConsultPrev',-1],['closingConsultNext',1]])el(id).onclick=()=>{pickerPage+=delta;loadPicker();};
  setInterval(()=>{if(!document.hidden)refreshReminder();},60000);
 }
 async function refreshReminder(){
  if(!allowed()||document.hidden||reminderBusy)return;const n=reminderEpoch;reminderBusy=true;
  try{const {data,error}=await sb.rpc('jk_daily_report_reminder');if(n!==reminderEpoch||!allowed())return;if(error)throw error;if(!data?.report_date||!data.user_id)return;
   const box=el('closingReminder'),ownIncomplete=data.own_required!==false&&data.own_status!=='submitted',pending=Array.isArray(data.pending)?data.pending:[];if(data.report_date!==today())return;
   if(!ownIncomplete&&['오늘 마감보고를 작성해 주세요.','오늘 마감보고를 완료해 주세요. 아직 임시저장 상태입니다.'].includes(el('toast')?.textContent))el('toast').classList.remove('show');
   const count=data.can_manage?pending.length:(ownIncomplete?1:0);document.querySelectorAll('[data-page="closing"],[data-staff-daily]').forEach(b=>{let badge=b.querySelector('[data-closing-badge]');if(!badge){badge=document.createElement('span');badge.dataset.closingBadge='';badge.className='closing-reminder-badge';b.append(badge);}badge.textContent=count;badge.hidden=!count;});
   box.hidden=!ownIncomplete&&!pending.length;if(!box.hidden){box.innerHTML='<div><b>'+esc(ownIncomplete?(data.own_status==='draft'?'오늘 마감보고가 임시저장 상태입니다.':'오늘 마감보고를 아직 작성하지 않았습니다.'):'오늘 마감보고 미완료 '+pending.length+'명')+'</b><p>'+esc(data.can_manage&&pending.length?'미완료: '+pending.map(p=>p.author_name+(p.status==='draft'?'(임시저장)':'')).join(' · '):'작성 후 ‘마감보고 완료’를 눌러 주세요.')+'</p></div><button class="btn primary" type="button">'+(ownIncomplete?'오늘 내 보고 작성':'작성 현황 보기')+'</button>';box.querySelector('button').onclick=()=>jkDailyReports.openTodayMine();}
   if(ownIncomplete){const key='jk-closing-reminder:'+data.user_id+':'+data.report_date;let last=0;try{last=Number(sessionStorage.getItem(key)||0);}catch{}const now=Date.now(),hour=Number(new Intl.DateTimeFormat('en-GB',{timeZone:'Asia/Seoul',hour:'2-digit',hourCycle:'h23'}).format(new Date()));if(!last||(hour>=18&&now-last>=3600000)){toast(data.own_status==='draft'?'오늘 마감보고를 완료해 주세요. 아직 임시저장 상태입니다.':'오늘 마감보고를 작성해 주세요.');try{sessionStorage.setItem(key,String(now));}catch{}}}
  }catch(e){if(n!==reminderEpoch)return;if(e.code==='42501'){clear();sessionChanged();}}
  finally{if(n===reminderEpoch)reminderBusy=false;}
 }
 function attachPicker(row,canEdit){
  const wrap=document.createElement('div');wrap.className='closing-row-picker';wrap.innerHTML='<button class="btn" type="button">영업 · 상담에서 고객 선택</button><small class="closing-help" data-picker-note>직접 입력하거나 기존 상담 고객을 선택하세요.</small>';row.prepend(wrap);
  wrap.querySelector('button').onclick=()=>{if(!canEdit())return;closePicker();target={row,canEdit};pickerPage=1;pickerTotal=0;el('closingConsultDialog').showModal();el('closingConsultSearch').focus();loadPicker();};
 }
 async function loadPicker(){
  if(!target?.canEdit()||!allowed())return closePicker();const n=++pickerEpoch;el('closingConsultResults').textContent='상담 목록을 불러오는 중...';el('closingConsultPrev').disabled=true;el('closingConsultNext').disabled=true;
  try{const {data,error}=await sb.rpc('jk_staff_consultations',{p_staff:'all',p_status:'all',p_search:el('closingConsultSearch').value.trim(),p_page:pickerPage});if(n!==pickerEpoch||!target?.canEdit()||!allowed())return;if(error)throw error;pickerRows=data?.rows||[];pickerTotal=Number(data?.count||0);
   el('closingConsultResults').innerHTML=pickerRows.map((r,i)=>'<button class="closing-consult-choice" type="button" data-pick-index="'+i+'"><b>'+esc(r.customer_name)+' · '+esc(formatPhone(r.phone_digits))+'</b><small>'+esc(r.staff_name||'미지정')+' · '+esc(r.status)+' · 상담일 '+esc(r.consulted_on||'-')+'</small><span>'+esc((r.consultation_note||r.customer_note||'상담내역 없음').slice(0,160))+'</span></button>').join('')||'<p class="closing-help">조건에 맞는 상담 고객이 없습니다.</p>';
   el('closingConsultResults').querySelectorAll('[data-pick-index]').forEach(b=>b.onclick=()=>pick(pickerRows[Number(b.dataset.pickIndex)],b));const pages=Math.max(1,Math.ceil(pickerTotal/20));el('closingConsultPage').textContent=pickerPage+' / '+pages+'쪽 · '+pickerTotal+'명';el('closingConsultPrev').disabled=pickerPage<=1;el('closingConsultNext').disabled=pickerPage>=pages;
  }catch(e){if(n!==pickerEpoch)return;el('closingConsultResults').textContent=e.code==='42501'?'직원 승인 상태를 다시 확인하세요.':'상담을 불러오지 못했습니다. 검색하거나 다시 열어 주세요.';if(e.code==='42501'){clear();sessionChanged();}}
 }
 async function pick(row,button){
  if(!row||!target?.canEdit())return;const current=target,n=++pickerEpoch;button.disabled=true;
  try{const {data,error}=await sb.rpc('jk_staff_consultations',{p_id:row.id});if(n!==pickerEpoch||target!==current||!current.canEdit()||!allowed())return;if(error)throw error;const r=data?.rows?.[0];if(!r)throw Error('선택한 상담을 다시 확인하세요.');
   const customer=current.row.querySelector('[data-followup=customer]'),content=current.row.querySelector('[data-followup=content]');
   if((customer.value.trim()||content.value.trim())&&!confirm('이 행의 고객 구분과 상담 내용을 선택한 상담 내용으로 바꿀까요? 남은 일과 연락 시간은 유지합니다.'))return;
   customer.value=(r.customer_name+' · '+formatPhone(r.phone_digits)).slice(0,1000);content.value=[(r.services||[]).join(' · '),r.consultation_note||r.customer_note||''].filter(Boolean).join(' / ').slice(0,1000);content.dispatchEvent(new Event('input',{bubbles:true}));
   current.row.querySelector('[data-picker-note]').textContent='가져온 상담: '+(r.staff_name||'미지정')+' · '+r.status+(r.next_contact_on?' · 다음 연락일 '+r.next_contact_on:'')+' · 남은 일과 연락 시간을 확인해 주세요.';closePicker();
  }catch(e){if(n!==pickerEpoch)return;el('closingConsultResults').textContent=e.code==='42501'?'직원 승인 상태를 다시 확인하세요.':e.message||'상담 내용을 가져오지 못했습니다.';if(e.code==='42501'){clear();sessionChanged();}}
  finally{if(button.isConnected)button.disabled=false;}
 }
 window.jkClosingTools=Object.freeze({init,clear,closePicker,attachPicker,refreshReminder});
})();
