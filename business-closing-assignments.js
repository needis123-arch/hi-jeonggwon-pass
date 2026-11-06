/* Managers configure reminder targets; report access and completion remain independent. */
(() => {
 'use strict';
 let data=null,epoch=0,busy=false;
 const el=id=>document.getElementById(id),manager=()=>document.body.dataset.access==='owner';
 const today=()=>new Intl.DateTimeFormat('sv-SE',{timeZone:'Asia/Seoul',year:'numeric',month:'2-digit',day:'2-digit'}).format(new Date());
 function clear(){epoch++;busy=false;data=null;el('closingAssignmentsRows')?.replaceChildren();if(el('closingAssignmentsMessage'))el('closingAssignmentsMessage').textContent='';if(el('closingAssignmentsCard'))el('closingAssignmentsCard').hidden=true;if(el('closingAssignmentOpen'))el('closingAssignmentOpen').hidden=true;}
 function init(){
  const card=document.createElement('div');card.id='closingAssignmentsCard';card.className='card setting-card closing-assignments-card';card.hidden=true;card.style.gridColumn='1/-1';
  card.innerHTML='<h3>마감보고 · 담당자별 알림 ON/OFF / 휴무</h3><p>대표자·비영업 담당자는 <b>기본 알림 OFF</b>로 제외합니다. 기본 ON인 직원의 <b>휴무는 선택한 날짜만</b> 제외하고 다음 날 다시 알림 대상이 됩니다. 대표 계정은 처음에 OFF입니다. 보고 조회·작성은 계속 가능합니다.</p><div class="closing-assignment-toolbar"><label for="closingAssignmentsDate">휴무 날짜</label><input type="date" id="closingAssignmentsDate"><button class="btn" id="closingAssignmentsReload" type="button">설정 새로고침</button></div><div id="closingAssignmentsMessage" class="closing-message" role="status"></div><div id="closingAssignmentsRows" class="closing-assignment-list"></div>';
  el('page-settings').querySelector('.settings-grid').prepend(card);el('closingAssignmentsDate').value=today();const max=new Date(today()+'T12:00:00Z');max.setUTCDate(max.getUTCDate()+366);el('closingAssignmentsDate').max=max.toISOString().slice(0,10);el('closingAssignmentsDate').min='2020-01-01';
  el('closingAssignmentsDate').onchange=()=>load();el('closingAssignmentsReload').onclick=()=>load();
  const shortcut=document.createElement('button');shortcut.id='closingAssignmentOpen';shortcut.className='btn';shortcut.type='button';shortcut.textContent='담당자 알림 / 휴무 설정';shortcut.hidden=true;shortcut.onclick=()=>{go('settings');setTimeout(()=>card.scrollIntoView({block:'start',behavior:'smooth'}),0);};el('page-closing').querySelector('.section-head').append(shortcut);
 }
 function accessChanged(){if(!manager())return clear();el('closingAssignmentOpen').hidden=false;}
 async function load(){
  if(!manager())return clear();if(busy)return;accessChanged();el('closingAssignmentsCard').hidden=false;const date=el('closingAssignmentsDate').value,n=++epoch;if(!date){el('closingAssignmentsMessage').textContent='휴무 날짜를 선택하세요.';return;}
  busy=true;data=null;el('closingAssignmentsDate').disabled=true;el('closingAssignmentsRows').replaceChildren();el('closingAssignmentsMessage').textContent='알림 설정을 불러오는 중...';
  try{const {data:result,error}=await sb.rpc('jk_daily_report_assignments',{p_date:date});if(n!==epoch||!manager())return;if(error)throw error;if(!Array.isArray(result?.rows))throw Error('설정을 불러오지 못했습니다.');data=result;render();el('closingAssignmentsMessage').textContent='변경한 설정은 직원의 다른 기기에도 적용됩니다. 열린 앱은 1분 이내 또는 재접속 시 반영됩니다.';}
  catch(e){if(n!==epoch)return;el('closingAssignmentsMessage').textContent=e.code==='42501'?'관리자 권한을 다시 확인하세요.':e.message||'설정을 불러오지 못했습니다.';if(e.code==='42501')clear();}
  finally{if(n===epoch){busy=false;el('closingAssignmentsDate').disabled=false;}}
 }
 function render(){
  el('closingAssignmentsRows').innerHTML=data.rows.map((r,i)=>'<div class="closing-assignment-row"><div><b>'+esc(r.author_name)+'</b><small>'+(!r.enabled?'기본 알림 OFF':r.day_off?'선택한 날짜 휴무 · 알림 제외':'선택한 날짜 알림 대상')+'</small></div><div><span>기본 알림</span><button class="btn '+(r.enabled?'primary':'')+'" type="button" role="switch" aria-checked="'+r.enabled+'" aria-label="'+esc(r.author_name)+' 기본 알림" data-assignment-index="'+i+'" data-assignment-kind="enabled">'+(r.enabled?'ON':'OFF')+'</button></div><div><span>'+esc(data.report_date)+' 근무</span><button class="btn '+(r.day_off?'closing-day-off':'')+'" type="button" role="switch" aria-checked="'+r.day_off+'" aria-label="'+esc(r.author_name)+' 선택일 휴무" data-assignment-index="'+i+'" data-assignment-kind="day_off">'+(r.day_off?'휴무 · 해제하려면 클릭':'근무 · 휴무로 변경')+'</button></div></div>').join('')||'<p>설정할 승인 직원이 없습니다.</p>';
  el('closingAssignmentsRows').querySelectorAll('[data-assignment-kind]').forEach(b=>b.onclick=()=>save(Number(b.dataset.assignmentIndex),b.dataset.assignmentKind));
 }
 async function save(index,kind){
  if(busy||!manager()||!data)return;const r=data.rows[index];if(!r)return;const n=epoch;busy=true;el('closingAssignmentsDate').disabled=true;el('closingAssignmentsRows').querySelectorAll('button').forEach(b=>b.disabled=true);el('closingAssignmentsMessage').textContent='설정을 저장하는 중...';
  try{const {data:result,error}=await sb.rpc('jk_set_daily_report_assignment',{p_author_id:r.author_id,p_kind:kind,p_value:!r[kind],p_date:data.report_date,p_expected_revision:kind==='enabled'?r.enabled_revision:r.day_off_revision});if(n!==epoch||!manager())return;if(error)throw error;data=result;render();jkDailyReports.invalidate();jkTeamCalendar.invalidate();jkClosingTools.clear();jkClosingTools.refreshReminder();el('closingAssignmentsMessage').textContent=r.author_name+' · '+(kind==='enabled'?(!r.enabled?'기본 알림 ON으로 변경했습니다.':'기본 알림 OFF로 변경했습니다.'):(!r.day_off?data.report_date+' 휴무로 지정했습니다.':data.report_date+' 휴무를 해제했습니다.'));
  }catch(e){if(n!==epoch)return;el('closingAssignmentsMessage').textContent=e.code==='42501'?'관리자 권한을 다시 확인하세요.':e.message||'저장하지 못했습니다. 다시 시도하세요.';if(e.code==='42501'){clear();sessionChanged();}}
  finally{if(n===epoch){busy=false;el('closingAssignmentsDate').disabled=false;el('closingAssignmentsRows').querySelectorAll('button').forEach(b=>b.disabled=false);}}
 }
 window.jkClosingAssignments=Object.freeze({init,load,clear,accessChanged});
})();
