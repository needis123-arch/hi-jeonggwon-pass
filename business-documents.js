/* Customer scans are encrypted before upload. Passwords, original filenames and
   decrypted bytes never go into database fields, browser storage or signed URLs. */
(() => {
 'use strict';
 const BUCKET='jk-ledger-documents', TABLE='jk_ledger_documents';
 const LIMIT=20*1024*1024, ITERATIONS=600000, MAGIC=new TextEncoder().encode('JKDOC001');
 const enc=new TextEncoder(), dec=new TextDecoder();
 const MIME=new Set(['image/jpeg','image/png','image/webp','application/pdf']);
 let root,ctx=null,serial=0,previewUrl=null,expiry=null,lastFocus=null;
 const el=id=>document.getElementById(id);
 const safe=s=>String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
 const current=c=>ctx===c&&c.token===serial;
 async function keyFor(password,salt,usage){
  const base=await crypto.subtle.importKey('raw',enc.encode(password),'PBKDF2',false,['deriveKey']);
  return crypto.subtle.deriveKey({name:'PBKDF2',salt,iterations:ITERATIONS,hash:'SHA-256'},base,{name:'AES-GCM',length:256},false,[usage]);
 }
 async function encrypt(file,password,ledgerId,id){
  const meta=enc.encode(JSON.stringify({name:file.name.slice(0,255),mime:file.type}));
  const bytes=new Uint8Array(await file.arrayBuffer()),plain=new Uint8Array(4+meta.length+bytes.length);
  new DataView(plain.buffer).setUint32(0,meta.length);plain.set(meta,4);plain.set(bytes,4+meta.length);
  const salt=crypto.getRandomValues(new Uint8Array(16)),iv=crypto.getRandomValues(new Uint8Array(12));
  const key=await keyFor(password,salt,'encrypt');
  const cipher=await crypto.subtle.encrypt({name:'AES-GCM',iv,additionalData:enc.encode(ledgerId+'/'+id)},key,plain);
  plain.fill(0);bytes.fill(0);
  return new Blob([MAGIC,salt,iv,cipher],{type:'application/octet-stream'});
 }
 async function decrypt(blob,password,row){
  const bytes=new Uint8Array(await blob.arrayBuffer());
  if(bytes.length<53||bytes.length>LIMIT+4096||MAGIC.some((b,i)=>bytes[i]!==b))throw new Error('지원하지 않는 서류 파일입니다.');
  const key=await keyFor(password,bytes.slice(8,24),'decrypt');
  let plain;
  try{plain=new Uint8Array(await crypto.subtle.decrypt({name:'AES-GCM',iv:bytes.slice(24,36),additionalData:enc.encode(row.ledger_id+'/'+row.id)},key,bytes.slice(36)));}
  catch{throw new Error('서류 비밀번호가 맞지 않거나 파일이 손상되었습니다.');}
  try{
   const n=new DataView(plain.buffer).getUint32(0);
   if(n<1||n>2048||n+4>=plain.length)throw new Error('서류 형식이 올바르지 않습니다.');
   const meta=JSON.parse(dec.decode(plain.slice(4,4+n)));
   if(!MIME.has(meta.mime)||typeof meta.name!=='string')throw new Error('지원하지 않는 서류 형식입니다.');
   return {name:meta.name,blob:new Blob([plain.slice(4+n)],{type:meta.mime})};
  }finally{plain.fill(0);}
 }
 function lock(){
  clearTimeout(expiry);expiry=null;
  const view=el('docPreview');if(view)view.replaceChildren();
  if(previewUrl){URL.revokeObjectURL(previewUrl);previewUrl=null;}
  for(const id of ['docPassword','docConfirm'])if(el(id))el(id).value='';
  if(el('docViewTitle'))el('docViewTitle').textContent='비밀번호를 입력하고 서류를 선택하세요.';
 }
 function close(){
  serial++;ctx=null;lock();if(root){root.hidden=true;root.querySelectorAll('input').forEach(x=>x.value='');}
  document.body.classList.remove('doc-open');const app=document.querySelector('.app');if(app)app.inert=false;lastFocus?.focus();
 }
 function status(text){if(el('docStatus'))el('docStatus').textContent=text;}
 function busy(c,value){
  if(!current(c))return;c.busy=value;
  root.querySelectorAll('[data-doc-action],#docUpload,#docFiles,#docKind,#docPassword,#docConfirm,#docLock').forEach(x=>x.disabled=value);
 }
 async function authenticated(){
  const {data,error}=await sb.auth.getSession();
  if(error||!data?.session)throw new Error('로그인 후 이용해 주세요.');
 }
 function init(){
  if(root)return;
  const style=document.createElement('style');style.textContent=`
   .doc-open{overflow:hidden}.doc-overlay[hidden]{display:none!important}.doc-overlay{position:fixed;inset:0;z-index:1500;background:#16203399;display:flex;align-items:center;justify-content:center;padding:18px}
   .doc-dialog{background:#fff;color:#15243b;border-radius:16px;width:min(1100px,100%);max-height:94dvh;overflow:auto;box-shadow:0 20px 80px #0004;padding:20px;box-sizing:border-box}
   .doc-head{display:flex;align-items:start;justify-content:space-between;gap:12px}.doc-head h2{margin:0 0 6px;font-size:20px}.doc-sub{color:#66758c;font-size:13px;overflow-wrap:anywhere}
   .doc-note{padding:12px;background:#f5f8fb;border:1px solid #dce5ed;border-radius:10px;font-size:13px;line-height:1.65;margin:14px 0}.doc-layout{display:grid;grid-template-columns:320px minmax(0,1fr);gap:18px}
   .doc-layout>div{min-width:0}.doc-controls label{display:block;margin:12px 0 5px;font-size:13px;font-weight:700}.doc-controls input,.doc-controls select{width:100%;min-width:0;box-sizing:border-box;min-height:40px;padding:8px;border:1px solid #d6dfeb;border-radius:8px;font:inherit}
   .doc-file{border:1px solid #dce5ed;padding:10px;border-radius:9px;margin-bottom:8px}.doc-file small{display:block;color:#65758a;margin:5px 0}.doc-buttons{display:flex;gap:6px;flex-wrap:wrap;margin-top:8px}.doc-controls .btn{white-space:normal}.doc-status{min-height:22px;font-size:13px;color:#a53737;margin:10px 0;overflow-wrap:anywhere}
   .doc-preview{min-height:240px;max-height:65dvh;overflow:auto;background:#f2f5f9;border-radius:10px;text-align:center}.doc-preview img{max-width:100%;height:auto;display:block;margin:auto}.doc-preview iframe{border:0;width:100%;height:60dvh}.doc-preview-title{font-size:13px;overflow-wrap:anywhere;margin:8px 0}.doc-list{max-height:34dvh;overflow:auto}
   @media(max-width:700px){.doc-overlay{padding:6px}.doc-dialog{padding:14px;max-height:98dvh}.doc-layout{grid-template-columns:1fr}.doc-preview{min-height:180px;max-height:55dvh}.doc-preview iframe{height:50dvh}.doc-list{max-height:24dvh}}
  `;document.head.append(style);
  root=document.createElement('div');root.className='doc-overlay';root.hidden=true;
  root.innerHTML=`<section class="doc-dialog" role="dialog" aria-modal="true" aria-labelledby="docTitle"><div class="doc-head"><div><h2 id="docTitle">고객 서류</h2><div id="docCustomer" class="doc-sub"></div></div><button class="btn" id="docClose" aria-label="서류 닫기">닫기</button></div>
   <div class="doc-note">SSD에서 이 고객의 폴더를 열고 사진을 여러 장 선택하세요. 선택한 파일만 암호화해 비공개 저장하며 SSD 원본은 유지됩니다.<br><b>서류 비밀번호는 로그인 비밀번호와 별도입니다.</b> 잊으면 복구할 수 없으니 SSD 원본을 보관하세요. 열람 후 5분, 다른 화면으로 전환하거나 닫으면 다시 잠깁니다.</div>
   <div class="doc-layout"><div class="doc-controls"><label for="docPassword">서류 비밀번호</label><input id="docPassword" type="password" autocomplete="off" placeholder="서류를 저장할 때 사용한 비밀번호">
   <div id="docNewPassword"><label for="docConfirm">새 서류 저장 시 비밀번호 확인</label><input id="docConfirm" type="password" autocomplete="off" placeholder="같은 비밀번호를 다시 입력"></div>
   <label for="docKind">추가할 서류 구분</label><select id="docKind"><option>가입 서류</option><option>신분증 사본</option><option>기타 서류</option></select>
   <label for="docFiles">사진 / PDF 선택 (여러 장 가능)</label><input id="docFiles" type="file" multiple accept="image/jpeg,image/png,image/webp,application/pdf"><small class="doc-sub">JPG · PNG · WEBP · PDF / 파일당 20MB, 한 번에 20개</small>
   <div class="doc-buttons"><button class="btn primary" id="docUpload">암호화해서 저장</button><button class="btn" id="docLock">다시 잠그기</button></div><div id="docStatus" class="doc-status" role="status" aria-live="polite"></div><div id="docList" class="doc-list"></div></div>
   <div><div id="docViewTitle" class="doc-preview-title"></div><div id="docPreview" class="doc-preview"></div></div></div></section>`;
  document.body.append(root);el('docClose').onclick=close;el('docLock').onclick=()=>{lock();status('서류를 잠갔습니다.');};el('docUpload').onclick=upload;
  root.addEventListener('click',e=>{if(e.target===root)close();const b=e.target.closest('[data-doc-action]');if(b&&ctx&&!ctx.busy){const row=ctx.rows.find(x=>x.id===b.dataset.id);if(row)b.dataset.docAction==='view'?view(row):remove(row);}});
  root.addEventListener('keydown',e=>{
   if(e.key==='Escape'){e.preventDefault();close();}
   if(e.key==='Tab'){const a=[...root.querySelectorAll('button,input,select,iframe')].filter(x=>!x.disabled&&x.getClientRects().length);if(!a.length)return;const first=a[0],last=a[a.length-1];if(e.shiftKey&&document.activeElement===first){e.preventDefault();last.focus();}else if(!e.shiftKey&&document.activeElement===last){e.preventDefault();first.focus();}}
  });
  document.addEventListener('visibilitychange',()=>{if(document.hidden&&ctx)close();});
  window.addEventListener('pagehide',close);
  sb.auth.onAuthStateChange(event=>{if(event==='SIGNED_OUT')close();});
 }
 function renderList(c){
  if(!current(c))return;
  el('docList').innerHTML=c.rows.map((r,i)=>`<div class="doc-file"><b>${safe(r.doc_kind)} ${i+1}</b><small>${safe(new Date(r.created_at).toLocaleString('ko-KR'))} · ${(r.byte_size/1024/1024).toFixed(1)}MB</small><div class="doc-buttons"><button class="btn" data-doc-action="view" data-id="${safe(r.id)}">비밀번호로 보기</button><button class="btn danger" data-doc-action="remove" data-id="${safe(r.id)}">삭제</button></div></div>`).join('')||'<div class="doc-sub">연결된 서류가 없습니다. 이 고객의 사진을 선택해 추가하세요.</div>';
  el('docNewPassword').hidden=c.rows.length>0;
 }
 async function refresh(c){
  const {data,error}=await sb.from(TABLE).select('id,ledger_id,storage_path,doc_kind,byte_size,created_at').eq('ledger_id',c.ledger.id).order('created_at');
  if(error)throw new Error('서류 목록을 불러오지 못했습니다. 로그인·권한을 확인하고 다시 열어 주세요.');
  if(!current(c))return;c.rows=data||[];renderList(c);
 }
 async function open(id){
  init();close();const ledger=state.ledger.find(r=>r.id===id);if(!ledger){toast('장부에서 고객을 다시 선택하세요.');return;}
  if(!crypto?.subtle){toast('서류 기능은 최신 브라우저의 보안 연결에서 이용해 주세요.');return;}
  lastFocus=document.activeElement;const c=ctx={ledger,rows:[],token:++serial,busy:false,ready:false};root.hidden=false;document.body.classList.add('doc-open');const app=document.querySelector('.app');if(app)app.inert=true;
  el('docCustomer').textContent=[ledger.customer_name_snapshot,formatPhone(ledger.customer_phone_snapshot),ledger.activation_date,ledger.vendor].filter(Boolean).join(' · ');
  el('docList').textContent='목록을 불러오는 중...';lock();status('');busy(c,true);el('docClose').focus();
  try{await authenticated();await refresh(c);if(current(c))c.ready=true;}catch(e){if(current(c))status(e.message);}finally{busy(c,false);if(current(c)&&c.ready)el('docPassword').focus();}
 }
 async function download(row){
  const {data,error}=await sb.storage.from(BUCKET).download(row.storage_path);
  if(error||!data)throw new Error('서류 파일을 불러오지 못했습니다. 로그인·권한과 인터넷 연결을 확인해 주세요.');return data;
 }
 async function view(row){
  const c=ctx;if(!c?.ready||c.busy)return;
  const password=el('docPassword').value;lock();if(!password){status('서류 비밀번호를 입력하세요.');el('docPassword').focus();return;}
  busy(c,true);status('비밀번호 확인 중...');
  try{
   await authenticated();const file=await decrypt(await download(row),password,row);if(!current(c))return;
   previewUrl=URL.createObjectURL(file.blob);el('docViewTitle').textContent=file.name;
   const media=document.createElement(file.blob.type==='application/pdf'?'iframe':'img');media.src=previewUrl;
   if(media.tagName==='IMG')media.alt='선택한 고객 서류';else{media.title='고객 서류 PDF';media.setAttribute('sandbox','allow-same-origin');}
   el('docPreview').replaceChildren(media);status('열람 중입니다. 5분 뒤 다시 잠깁니다.');expiry=setTimeout(()=>{lock();status('열람 시간이 지나 서류를 잠갔습니다.');},5*60*1000);
  }catch(e){if(current(c))status(e.message);}finally{busy(c,false);}
 }
 async function upload(){
  const c=ctx;if(!c?.ready||c.busy)return;
  const files=[...el('docFiles').files],password=el('docPassword').value,confirmPassword=el('docConfirm').value,kind=el('docKind').value;
  if(!files.length){status('이 고객의 사진 또는 PDF를 선택하세요.');return;}
  if(files.length>20||files.reduce((s,f)=>s+f.size,0)>100*1024*1024){status('한 번에 20개, 전체 100MB 이하로 선택하세요.');return;}
  if(files.some(f=>!MIME.has(f.type)||!f.size||f.size>LIMIT)){status('JPG·PNG·WEBP·PDF만 가능하며 파일당 20MB 이하여야 합니다. 다른 사진 형식은 JPG로 변환해 주세요.');return;}
  if(password.length<10){status('서류 비밀번호를 10자 이상 입력하세요.');return;}
  if(!c.rows.length&&password!==confirmPassword){status('비밀번호 확인이 일치하지 않습니다.');return;}
  if(!window.confirm(`${c.ledger.customer_name_snapshot} · ${formatPhone(c.ledger.customer_phone_snapshot)} 고객의 ${files.length}개 파일이 맞나요? 이 고객 장부에 암호화해서 저장합니다.`))return;
  lock();busy(c,true);let completed=0;
  try{
   await authenticated();
   // Verify the existing customer password before adding more files.
   if(c.rows.length)await decrypt(await download(c.rows[0]),password,c.rows[0]);
   for(const file of files){
    if(!current(c))break;
    status(`${completed+1} / ${files.length} 암호화해서 저장 중...`);
    const id=crypto.randomUUID(),storagePath=c.ledger.id+'/'+id+'.jkdoc';
    const blob=await encrypt(file,password,c.ledger.id,id);if(!current(c))break;
    const {error}=await sb.storage.from(BUCKET).upload(storagePath,blob,{contentType:'application/octet-stream',cacheControl:'0',upsert:false});
    if(error)throw new Error('암호화 서류 업로드에 실패했습니다. 다시 시도해 주세요.');
    let linked=false;
    try{
     if(!current(c))throw new Error('저장을 중단했습니다.');
     const result=await sb.from(TABLE).insert({id,ledger_id:c.ledger.id,storage_path:storagePath,doc_kind:kind,byte_size:file.size});
     if(result.error)throw new Error('장부에 서류를 연결하지 못했습니다.');linked=true;completed++;
    }finally{if(!linked)await sb.storage.from(BUCKET).remove([storagePath]);}
   }
   if(current(c)){el('docFiles').value='';await refresh(c);status(`${completed}개 서류를 저장했습니다. SSD 원본은 유지됩니다.`);}
  }catch(e){if(current(c)){await refresh(c).catch(()=>{});status(`${completed?completed+'개 저장 완료. ':''}${e.message}`);}}
  finally{busy(c,false);}
 }
 async function remove(row){
  const c=ctx;if(!c?.ready||c.busy)return;
  if(!window.confirm('이 서류의 온라인 복사본을 삭제할까요? SSD 원본은 유지됩니다.'))return;
  lock();busy(c,true);status('삭제 중...');
  try{
   await authenticated();const storage=await sb.storage.from(BUCKET).remove([row.storage_path]);if(storage.error)throw new Error('서류 파일을 삭제하지 못했습니다.');
   const record=await sb.from(TABLE).delete().eq('id',row.id).eq('ledger_id',c.ledger.id);if(record.error)throw new Error('파일은 삭제됐지만 장부 연결 정리가 필요합니다. 삭제를 다시 눌러 주세요.');
   await refresh(c);if(current(c))status('온라인 복사본을 삭제했습니다.');
  }catch(e){if(current(c))status(e.message);}finally{busy(c,false);}
 }
 window.openLedgerDocuments=open;
 window.closeLedgerDocuments=close;
 document.addEventListener('DOMContentLoaded',init,{once:true});
})();
