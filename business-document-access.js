/* Owner approval UI. Server decisions never grant financial or upload access. */
(() => {
 'use strict';
 let epoch=0,busy=false;
 const esc=s=>String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
 const names={pending:'승인 대기',approved:'열람 허용',rejected:'거절',revoked:'권한 회수'};
 const card=()=>document.getElementById('documentAccessCard');
 async function rpc(name,args={}){const {data,error}=await sb.rpc(name,args);if(error)throw new Error('승인 정보를 불러오지 못했습니다. 다시 로그인하거나 신청 새로고침을 눌러 주세요.');return data;}
 async function load(){
  const n=++epoch;if(!card())return;
  try{
   const state=await rpc('jk_document_access_state');if(n!==epoch)return;
   card().hidden=!state?.owner;if(!state?.owner)return;
   document.getElementById('documentConnectionStatus').textContent=state.drive_connected?'저장소 연결 완료 · 승인한 직원이 자기 계정으로 열람할 수 있습니다.':'저장소 연결 전 · 사장님이 서류 저장소 연결을 먼저 완료하세요.';
   const rows=await rpc('jk_document_access_requests');if(n!==epoch)return;
   document.getElementById('documentAccessRequests').innerHTML=rows?.length?rows.map(r=>`<div style="padding:14px 0;border-top:1px solid #e0e5ef"><b>${esc(r.display_name)}</b> · ${esc(r.email)}<p>${names[r.status]||'확인 필요'} · ${esc(new Date(r.requested_at).toLocaleString('ko-KR'))}</p>${(r.status==='pending'?['approved','rejected']:r.status==='approved'?['revoked']:[]).map(a=>`<button class="btn" data-document-user="${esc(r.user_id)}" data-document-action="${a}" data-version="${Number(r.version)}" data-label="${esc(r.display_name+' · '+r.email)}">${{approved:'열람 승인',rejected:'거절',revoked:'권한 회수'}[a]}</button>`).join(' ')}</div>`).join(''):'<p>직원이 제출한 열람 신청이 없습니다.</p>';
  }catch{if(n===epoch&&card())card().hidden=true;}
 }
 window.loadDocumentAccessRequests=load;
 window.copyDocumentStaffLink=async()=>{
  const link=new URL('business-documents-staff.html',location.href).href;
  try{await navigator.clipboard.writeText(link);alert('직원 신청 링크를 복사했습니다. 직원에게 전달하세요.');}catch{prompt('직원에게 아래 링크를 전달하세요.',link);}
 };
 window.connectDocumentOwnerDrive=async()=>{try{await window.jkDocumentDrive.connect();await load();}catch(e){alert(e.message);}};
 document.addEventListener('click',async e=>{
  const b=e.target.closest('[data-document-action]');if(!b||!card()?.contains(b)||busy)return;
  const action=b.dataset.documentAction,label=b.dataset.label;
  const message=action==='approved'?`${label}\n전체 고객 서류의 열람을 허용할까요? 서류 비밀번호가 추가로 필요하며 추가·삭제와 정산 수정은 허용하지 않습니다.`:action==='revoked'?`${label}\n다음 서류 열람부터 권한을 차단할까요? 이미 본 사진까지 회수할 수는 없습니다.`:`${label}\n이번 열람 신청을 거절할까요?`;
  if(!confirm(message))return;
  busy=true;b.disabled=true;
  try{await rpc('jk_document_decide_access',{p_user_id:b.dataset.documentUser,p_action:action,p_version:Number(b.dataset.version)});await load();}
  catch(e){alert(e.message+' 신청 상태가 바뀌었으면 새로고침 후 다시 처리하세요.');await load();}finally{busy=false;}
 });
 document.addEventListener('DOMContentLoaded',()=>{
  load();sb.auth.onAuthStateChange(e=>{if(e==='SIGNED_OUT'){epoch++;if(card())card().hidden=true;}else setTimeout(load,0);});
 },{once:true});
})();
