/* Five-minute in-memory unlock; plaintext exports stay on the user's device. */
(() => {
 'use strict';
 const DURATION=300000,MAX_BATCH=100*1024*1024;
 async function limit(task,signal,ms=30000){
  const controller=new AbortController();let timer;
  const stop=()=>controller.abort(new Error('서류 요청을 중단했습니다.'));
  if(signal?.aborted)stop();else signal?.addEventListener('abort',stop,{once:true});
  try{
   if(controller.signal.aborted)throw controller.signal.reason;
   return await Promise.race([Promise.resolve().then(()=>task(controller.signal)),new Promise((_,reject)=>{
    controller.signal.addEventListener('abort',()=>reject(controller.signal.reason),{once:true});
    timer=setTimeout(()=>controller.abort(new Error('서류 응답이 늦습니다. 인터넷 연결을 확인하고 다시 눌러 주세요.')),ms);
   })]);
  }finally{clearTimeout(timer);signal?.removeEventListener('abort',stop);}
 }
 let password='',until=0,timer=null;
 function lock(){password='';until=0;clearTimeout(timer);timer=null;window.dispatchEvent(new Event('jk-document-viewer-lock'));}
 function read(){if(password&&Date.now()>=until)lock();return password;}
 function remember(value){if(read()===value)return;password=value;until=Date.now()+DURATION;clearTimeout(timer);timer=setTimeout(lock,DURATION);}
 const session=Object.freeze({read,lock,remaining:()=>read()?Math.max(0,Math.ceil((until-Date.now())/1000)):0});
 document.addEventListener('visibilitychange',()=>{if(document.hidden)lock();});window.addEventListener('pagehide',lock);
 const filename=name=>String(name||'서류.jpg').replace(/[\\/:*?"<>|\u0000-\u001f]/g,'_').replace(/^\.+/,'_').slice(0,180)||'서류.jpg';
 function save(blob,name){const url=URL.createObjectURL(blob),a=document.createElement('a');a.href=url;a.download=filename(name);a.hidden=true;document.body.append(a);a.click();a.remove();setTimeout(()=>URL.revokeObjectURL(url),1000);}
 function crc32(bytes){let crc=0xffffffff;for(const b of bytes){crc^=b;for(let i=0;i<8;i++)crc=(crc>>>1)^((crc&1)?0xedb88320:0);}return (crc^0xffffffff)>>>0;}
 async function zip(files){
  const body=[],central=[];let offset=0,total=0;const encoder=new TextEncoder();
  for(let i=0;i<files.length;i++){
   const bytes=new Uint8Array(await files[i].blob.arrayBuffer());total+=bytes.length;if(total>MAX_BATCH)throw new Error('전체 내려받기는 100MB까지 가능합니다. 사진별로 내려받아 주세요.');
   const name=encoder.encode(String(i+1).padStart(2,'0')+'_'+filename(files[i].name)),crc=crc32(bytes);
   const h=new Uint8Array(30),v=new DataView(h.buffer);v.setUint32(0,0x04034b50,true);v.setUint16(4,20,true);v.setUint16(6,0x0800,true);v.setUint16(12,33,true);v.setUint32(14,crc,true);v.setUint32(18,bytes.length,true);v.setUint32(22,bytes.length,true);v.setUint16(26,name.length,true);
   const c=new Uint8Array(46),w=new DataView(c.buffer);w.setUint32(0,0x02014b50,true);w.setUint16(4,20,true);w.setUint16(6,20,true);w.setUint16(8,0x0800,true);w.setUint16(14,33,true);w.setUint32(16,crc,true);w.setUint32(20,bytes.length,true);w.setUint32(24,bytes.length,true);w.setUint16(28,name.length,true);w.setUint32(42,offset,true);
   body.push(h,name,bytes);central.push(c,name);offset+=h.length+name.length+bytes.length;
  }
  const end=new Uint8Array(22),v=new DataView(end.buffer);v.setUint32(0,0x06054b50,true);v.setUint16(8,files.length,true);v.setUint16(10,files.length,true);v.setUint32(12,central.reduce((n,x)=>n+x.length,0),true);v.setUint32(16,offset,true);
  return new Blob([...body,...central,end],{type:'application/zip'});
 }
 async function print(files,title,valid,signal){
  const frame=document.createElement('iframe'),urls=[];frame.title='서류 인쇄';frame.style.cssText='position:fixed;left:-10000px;top:0;width:800px;height:1000px;border:0';document.body.append(frame);
  let cleaned=false,cleanupTimer;const cleanup=()=>{if(cleaned)return;cleaned=true;clearTimeout(cleanupTimer);urls.forEach(u=>URL.revokeObjectURL(u));frame.remove();window.removeEventListener('jk-document-viewer-lock',cleanup);signal?.removeEventListener('abort',cleanup);};
  signal?.addEventListener('abort',cleanup,{once:true});
  window.addEventListener('jk-document-viewer-lock',cleanup);cleanupTimer=setTimeout(cleanup,60000);
  try{
   const doc=frame.contentDocument;doc.title=title||'고객 서류';const style=doc.createElement('style');style.textContent='@page{size:A4;margin:10mm}body{margin:0}section{break-after:page;page-break-after:always}section:last-child{break-after:auto;page-break-after:auto}img{display:block;max-width:100%;max-height:270mm;object-fit:contain;margin:auto}';doc.head.append(style);
   await Promise.all(files.map(file=>new Promise((resolve,reject)=>{const section=doc.createElement('section'),img=doc.createElement('img'),u=URL.createObjectURL(file.blob);urls.push(u);img.alt=file.name;img.onload=resolve;img.onerror=()=>reject(new Error('인쇄할 사진을 불러오지 못했습니다.'));img.src=u;section.append(img);doc.body.append(section);})));if(cleaned||!valid())throw new Error('열람 시간이 지났습니다. 비밀번호를 다시 입력하세요.');
   frame.contentWindow.addEventListener('afterprint',cleanup,{once:true});frame.contentWindow.focus();frame.contentWindow.print();setTimeout(cleanup,1000);
  }catch(e){cleanup();throw e;}
 }
 function mount({preview,title,input,message,getFile,isActive,onBusy=()=>{},authorize=async()=>{}}){
  let rows=[],label='',shown=[],urls=[],selected=-1,op=0,busy=false,activeRequest=null,cacheBytes=0;
  const cache=new Map(),cacheKey=r=>[r.ledger_id,r.id,r.created_at,r.byte_size].join('/');
  const bar=document.createElement('div');bar.className='doc-viewer-tools';bar.style.cssText='display:flex;gap:6px;flex-wrap:wrap;margin:8px 0';
  bar.innerHTML='<button class="btn" data-viewer="previous">◀ 이전</button><button class="btn" data-viewer="next">다음 ▶</button><button class="btn primary" data-viewer="all">전체 보기 · 5분 열람</button><button class="btn" data-viewer="print">이 사진 인쇄</button><button class="btn" data-viewer="download">이 사진 내려받기</button><button class="btn" data-viewer="print-all">전체 인쇄</button><button class="btn" data-viewer="download-all">전체 내려받기 (ZIP)</button><span class="doc-sub" data-unlock-status style="width:100%"></span>';
  preview.before(bar);
  const cancel=document.createElement('button');cancel.className='btn';cancel.dataset.viewer='cancel';cancel.textContent='불러오기 취소';bar.append(cancel);
  function buttons(){bar.querySelectorAll('button').forEach(b=>{const a=b.dataset.viewer;if(a==='cancel'){b.hidden=!busy;b.disabled=!busy;return;}b.disabled=busy||!rows.length||(['print','download'].includes(a)&&selected<0)||(a==='previous'&&selected<=0)||(a==='next'&&selected>=rows.length-1);});bar.querySelector('[data-unlock-status]').textContent=read()?`열람 가능 ${Math.ceil(session.remaining()/60)}분 · ${rows.length}개 서류 · 비밀번호 재입력 없이 보기`:'비밀번호를 한 번 입력하면 5분 동안 다른 서류도 볼 수 있습니다.';}
  function clear(){const wasBusy=busy;op++;activeRequest?.abort();activeRequest=null;busy=false;cache.clear();cacheBytes=0;if(wasBusy)onBusy(false);urls.forEach(u=>URL.revokeObjectURL(u));urls=[];shown=[];selected=-1;preview.replaceChildren();input.value='';title.textContent='비밀번호를 입력하고 서류를 선택하세요.';buttons();}
  function retain(row,file){const key=cacheKey(row);if(cache.has(key))return;while(cacheBytes+file.blob.size>MAX_BATCH&&cache.size){const [id,old]=cache.entries().next().value;cache.delete(id);cacheBytes-=old.blob.size;}if(file.blob.size<=MAX_BATCH){cache.set(key,file);cacheBytes+=file.blob.size;}}
  function credentials(){const value=input.value||read();if(!/^[0-9]{4}$/.test(value)&&value.length<10)throw new Error('서류 비밀번호는 숫자 4자리입니다.');return value;}
  async function run(action,targets){
   if(busy||!targets.length||!isActive())return;
   let pass;try{pass=credentials();}catch(e){message(e.message);input.focus();return;}
   if(pass!==read()){cache.clear();cacheBytes=0;}
   const job=++op,controller=activeRequest=new AbortController();busy=true;onBusy(true);buttons();message('서류를 불러오는 중입니다.');const result=[];let size=0;
   try{
    await limit(()=>authorize(),controller.signal);if(job!==op||!isActive())return;
    for(const row of targets){if(job!==op||!isActive())return;if(!input.value&&!read())throw new Error('열람 시간이 지났습니다. 비밀번호를 다시 입력하세요.');message(`서류 ${result.length+1} / ${targets.length} 불러오는 중...`);const file=cache.get(cacheKey(row))||await limit(signal=>getFile(row,pass,signal),controller.signal);if(job!==op||!isActive())return;
     // A timed-out operation must never recreate an unlocked session.
     if(!input.value&&!read())throw new Error('열람 시간이 지났습니다. 비밀번호를 다시 입력하세요.');remember(pass);input.value='';size+=file.blob.size;if(size>MAX_BATCH)throw new Error('한 번에 100MB까지 가능합니다. 사진별로 보기·인쇄·내려받기를 이용하세요.');result.push(file);retain(row,file);
     if(action==='view'){
      if(result.length===1){urls.forEach(u=>URL.revokeObjectURL(u));urls=[];preview.replaceChildren();selected=rows.findIndex(r=>r.id===targets[0].id);}
      shown=[...result];title.textContent=targets.length===1?file.name:`전체 서류 ${result.length} / ${targets.length}개`;
      const figure=document.createElement('figure');figure.style.cssText='margin:0 0 16px';const img=new Image(),u=URL.createObjectURL(file.blob);urls.push(u);img.src=u;img.alt=file.name;img.style.cssText='max-width:100%;height:auto;display:block;margin:auto';img.onerror=()=>{if(job===op)message('사진을 표시하지 못했습니다. 원본 파일을 확인하세요.');};figure.append(img);if(targets.length>1){const caption=document.createElement('figcaption');caption.textContent=file.name;figure.append(caption);}preview.append(figure);
     }
    }
    if(action==='view'){
     title.textContent=targets.length===1?result[0].name:`전체 서류 ${result.length}개`;
    }else if(action.startsWith('print')){await limit(()=>authorize(),controller.signal);if(job!==op||!read()||!isActive())return;await limit(signal=>print(result,label,()=>job===op&&Boolean(read())&&isActive()&&!signal.aborted,signal),controller.signal);}
    else if(action==='download-all'){const blob=await zip(result);await limit(()=>authorize(),controller.signal);if(job!==op||!read()||!isActive())return;save(blob,(label||'고객')+'_서류.zip');}
    else {await limit(()=>authorize(),controller.signal);if(job!==op||!read()||!isActive())return;save(result[0].blob,result[0].name);}
    if(job===op)message(action.startsWith('download')?'내려받기를 시작했습니다.':action.startsWith('print')?'인쇄 화면을 열었습니다.':'열람 중입니다. 처음 비밀번호를 확인한 때부터 5분 동안 다른 서류도 바로 볼 수 있습니다.');
   }catch(e){if(job===op)message(e.message);}finally{if(job===op){busy=false;activeRequest=null;onBusy(false);buttons();}}
  }
  bar.onclick=e=>{const a=e.target.closest('[data-viewer]')?.dataset.viewer;if(!a)return;if(a==='cancel'){clear();message('불러오기를 취소했습니다. 서류를 다시 선택하세요.');return;}if(a==='previous'||a==='next'){const i=selected+(a==='previous'?-1:1);if(rows[i])run('view',[rows[i]]);}else if(a==='all')run('view',rows);else run(a,a.endsWith('-all')?rows:selected>=0?[rows[selected]]:[]);};
  input.addEventListener('keydown',e=>{if(e.key==='Enter'){e.preventDefault();run('view',rows);}});
  window.addEventListener('jk-document-viewer-lock',()=>{clear();message('5분 열람이 종료됐거나 잠겼습니다. 비밀번호를 다시 입력하세요.');});
  setInterval(()=>{if(!document.hidden)buttons();},1000);
  buttons();return Object.freeze({show:row=>run('view',[row]),clear,setRows:(value,name)=>{clear();rows=value;label=name;buttons();}});
 }
 window.jkDocumentViewer=Object.freeze({session,mount,limit});
})();
