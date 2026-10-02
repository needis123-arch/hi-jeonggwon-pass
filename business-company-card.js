'use strict';
// Keep these records in the existing manual liability/payment tables. Vendor settlement and W are unchanged.
const companyCardPrefix='JK_COMPANY_CARD_V1\n';
function companyCardBilling(date){
 if(!/^\d{4}-\d{2}-\d{2}$/.test(date))return null;
 const shift=delta=>{const d=new Date(date.slice(0,7)+'-01T00:00:00Z');d.setUTCMonth(d.getUTCMonth()+delta);return d.toISOString().slice(0,7)};
 const after25=Number(date.slice(8,10))>=26;
 return {start:shift(after25?0:-1)+'-26',end:shift(after25?1:0)+'-25',due:shift(after25?2:1)+'-01'};
}
function companyCardMeta(item){
 if(!item||!String(item.item_key).startsWith('manual:company-card:')||!String(item.note||'').startsWith(companyCardPrefix))return null;
 try{const m=JSON.parse(item.note.slice(companyCardPrefix.length));if(m.version!==1||typeof m.customer_name!=='string'||typeof m.card_name!=='string'||!/^\d{4}-\d{2}-\d{2}$/.test(m.charged_on))return null;return m}catch(e){return null}
}
function companyCardSummary(items,payments,month,asOf){
 const rows=items.filter(r=>companyCardMeta(r)),byKey=Object.fromEntries(rows.map(r=>[r.item_key,r]));
 const charged=rows.filter(r=>!r.excluded&&companyCardMeta(r).charged_on.slice(0,7)===month).reduce((s,r)=>s+Number(r.amount),0);
 const actual=payments.filter(p=>!p.voided&&p.paid_on<=asOf&&p.paid_on.slice(0,7)===month&&byKey[p.item_key]);
 return {charged,paid:actual.reduce((s,p)=>s+Number(p.amount),0),pending:rows.filter(r=>!r.excluded).reduce((s,r)=>s+Number(r.remaining||0),0),rows};
}
if(typeof module!=='undefined'&&module.exports)module.exports={companyCardMeta,companyCardSummary,companyCardBilling};
const companyCardState={key:null,saving:false,request:0,ledger:[]};
function renderCompanyCards(){
 const root=$('companyCardRows');if(!root||!financeState.model)return;
 const m=financeState.model,s=companyCardSummary(m.items,financeState.data.payments||[],financeValue('financeMonth'),financeToday());
 $('companyCardSummary').textContent=financeValue('financeMonth')+' 단말기 카드결제 '+won(s.charged)+' · 이 달 실제 카드대금 납부 '+won(s.paid)+' · 전체 카드 미납 '+won(s.pending);
 root.innerHTML=s.rows.sort((a,b)=>companyCardMeta(b).charged_on.localeCompare(companyCardMeta(a).charged_on)).map(r=>{const c=companyCardMeta(r),history=(financeState.data.payments||[]).filter(p=>p.item_key===r.item_key&&!p.voided);return '<article class="finance-history"><div><b>'+esc(c.customer_name)+' · '+esc(c.card_name)+'</b><p>'+esc(c.charged_on)+' 카드결제 · '+esc(c.vendor||'거래처 미입력')+' · 담당자 '+esc(c.staff_name||'미입력')+'</p><small>'+esc(c.phone?formatPhone(c.phone):'')+' · '+(c.ledger_id?'장부 연결':'장부 미연결')+' · 고객 현금·계좌 완납 참고 '+won(c.customer_cash||0)+'</small><p>카드대금 출금 예정 '+esc(r.due_date)+' · '+(r.excluded?'예상에서 제외':r.remaining?'미납 '+won(r.remaining):'납부 완료')+'</p><small>'+esc(c.memo||'')+'</small>'+history.map(p=>'<p>실제 납부 '+esc(p.paid_on)+' · '+won(p.amount)+' · '+(p.balance_included?'현재 잔고에 이미 반영':'잔고 기준 이후 지출')+'</p>').join('')+'</div><div><b>'+won(r.amount)+'</b><div class="finance-toolbar"><button class="btn" data-company-edit="'+esc(r.item_key)+'">수정 / 취소</button>'+(r.remaining>0&&!r.excluded?'<button class="btn primary" data-company-pay="'+esc(r.item_key)+'">카드대금 납부 기록</button>':'')+'</div></div></article>'}).join('')||'<p class="finance-help">기록된 사무실 카드 단말기 대금이 없습니다.</p>';
 root.querySelectorAll('[data-company-edit]').forEach(b=>b.onclick=()=>openCompanyCard(b.dataset.companyEdit));
 root.querySelectorAll('[data-company-pay]').forEach(b=>b.onclick=()=>openCompanyCardPayment(b.dataset.companyPay));
}
async function openCompanyCard(key=null){
 const r=financeState.model?.itemMap[key],c=companyCardMeta(r)||{};companyCardState.key=key||'manual:company-card:'+crypto.randomUUID();companyCardState.ledger=[];modalMode='company-card';
 $('modalTitle').textContent='사무실 카드로 낸 단말기 대금';$('modalSave').textContent='카드 내역 저장';
 $('modalBody').innerHTML=`<div class="form"><div class="field full"><label>연결 장부 검색 (고객 / 번호)</label><div class="finance-toolbar"><input id="ccSearch" placeholder="고객명 또는 전화번호"><button class="btn" onclick="loadCompanyCardLedger()">검색</button></div><select id="ccLedger" onchange="chooseCompanyCardLedger()"><option value="">장부 연결 없이 과거 내역 기록</option>${c.ledger_id?'<option selected value="'+esc(c.ledger_id)+'">'+esc(c.customer_name)+' · 기존 연결</option>':''}</select><small id="ccLedgerNote">고객 수납과 W 마진은 이 기록으로 바뀌지 않습니다.</small></div><div class="field"><label>고객명 *</label><input id="ccName" maxlength="200" value="${esc(c.customer_name||'')}"></div><div class="field"><label>고객 전화번호</label><input id="ccPhone" type="tel" value="${esc(formatPhone(c.phone||''))}" oninput="formatPhoneInput(this)"></div><div class="field"><label>카드 *</label><input id="ccCard" maxlength="100" value="${esc(c.card_name||'현대카드')}"></div><div class="field"><label>거래처 / 결제처</label><input id="ccVendor" maxlength="200" value="${esc(c.vendor||'')}"></div><div class="field"><label>단말기 카드결제일 *</label><input id="ccCharged" type="date" max="${financeToday()}" value="${esc(c.charged_on||financeToday())}"></div><div class="field"><label>카드로 낸 단말기 금액 *</label><input id="ccAmount" inputmode="numeric" value="${r?Number(r.amount):''}" oninput="formatMoneyInput(this)"></div><div class="field"><label>카드대금 실제 출금 예정일 *</label><input id="ccDue" type="date" value="${esc(r?.due_date||'')}"></div><div class="field"><label>담당자 *</label><select id="ccStaff">${receiptStaffOptions()}</select></div><div class="field full"><label>고객에게 받은 현금·계좌 완납액 (참고)</label><input id="ccCash" inputmode="numeric" value="${Number(c.customer_cash||0)}" oninput="formatMoneyInput(this)"><small>장부 연결 시 S 중 현금·계좌 금액을 가져옵니다. 실제 수납 기록은 고객 수납 메뉴에서 관리하며, 여기서는 돈을 다시 더하지 않습니다.</small></div><div class="field full"><label>메모 / 카드 승인번호</label><textarea id="ccMemo" maxlength="1500">${esc(c.memo||'')}</textarea></div>${r?'<div class="field full"><label><input id="ccExcluded" type="checkbox" '+(r.excluded?'checked':'')+'> 취소 / 중복 내역: 예상에서 제외</label><small>이미 납부한 내역은 실제 납부 기록을 남기세요. 이미 납부한 금액보다 작게 수정할 수 없습니다.</small></div>':''}<div class="field full"><label><input id="ccPayAfter" type="checkbox"> 저장 후 이미 납부한 카드대금 기록하기</label></div></div><p class="finance-help">단말기를 카드로 결제한 날에는 통장·현금 잔고가 줄지 않습니다. 카드대금 출금일의 미납액을 예상 지출에 반영하며, 실제 납부하면 그 잔액만 줄어듭니다. 이미 쓴 현금은 현재 남은 잔고에 넣지 마세요. 거래처 정산·급여·마진과는 별도로 관리합니다. 카드 청구서 총액이나 비용원장에 같은 대금을 다시 추가하지 마세요.</p>`;
 if(c.staff_id){if(![...$('ccStaff').options].some(o=>o.value===c.staff_id))$('ccStaff').add(new Option(c.staff_name+' (기존 담당자)',c.staff_id));$('ccStaff').value=c.staff_id}
 showModal();await loadCompanyCardLedger(c.ledger_id||'');
 $('ccCharged').setAttribute('onchange','syncCompanyCardBilling()');$('ccCard').setAttribute('onchange','syncCompanyCardBilling()');
 const cycle=document.createElement('small');cycle.id='ccCycle';$('ccDue').parentElement.append(cycle);syncCompanyCardBilling(!r);
}
function syncCompanyCardBilling(apply=true){const cycle=companyCardBilling(financeValue('ccCharged')),hyundai=/현대|hyundai/i.test(financeValue('ccCard'));if(!cycle||!hyundai){if($('ccCycle'))$('ccCycle').textContent='출금 예정일을 직접 입력하세요.';return}if(apply)$('ccDue').value=cycle.due;if($('ccCycle'))$('ccCycle').textContent=cycle.start+' ~ '+cycle.end+' 사용분 → '+cycle.due+' 결제 (예정일 조정 가능)'}
async function loadCompanyCardLedger(selected=''){
 if(modalMode!=='company-card')return;const request=++companyCardState.request,old=selected||financeValue('ccLedger'),search=financeValue('ccSearch'),digits=search.replace(/\D/g,'');
 let q=sb.from('jk_sales_ledger').select('id,activation_date,vendor,customer_name_snapshot,customer_phone_snapshot,cash_received,card_received_amount,salesperson_id').order('activation_date',{ascending:false}).limit(200);
 if(search)q=digits.length>=3?q.ilike('customer_phone_snapshot','%'+digits+'%'):q.ilike('customer_name_snapshot','%'+search.replace(/[\\%_]/g,'\\$&')+'%');
 const {data,error}=await q;if(request!==companyCardState.request||modalMode!=='company-card')return;if(error){$('ccLedgerNote').textContent='장부를 불러오지 못했습니다. 장부 연결 없이 과거 내역을 기록할 수 있습니다.';return}
 companyCardState.ledger=data||[];const options=[['','장부 연결 없이 과거 내역 기록'],...companyCardState.ledger.map(l=>[l.id,l.activation_date+' · '+l.customer_name_snapshot+' · '+formatPhone(l.customer_phone_snapshot)])];
 if(old&&!companyCardState.ledger.some(l=>l.id===old))options.push([old,'기존 장부 연결 유지']);$('ccLedger').innerHTML=financeSelectOptions(options,old);
}
function chooseCompanyCardLedger(){const l=companyCardState.ledger.find(x=>x.id===financeValue('ccLedger'));if(!l)return;$('ccName').value=l.customer_name_snapshot;$('ccPhone').value=formatPhone(l.customer_phone_snapshot);$('ccVendor').value=l.vendor||'';$('ccCash').value=Math.max(Number(l.cash_received||0)-Number(l.card_received_amount||0),0);if([...$('ccStaff').options].some(o=>o.value===l.salesperson_id))$('ccStaff').value=l.salesperson_id;formatMoneyInput($('ccCash'))}
async function saveCompanyCard(){
 if(companyCardState.saving)return;const key=companyCardState.key,r=financeState.model?.itemMap[key],amount=moneyNumber(financeValue('ccAmount')),cash=moneyNumber(financeValue('ccCash')),charged=financeValue('ccCharged'),due=financeValue('ccDue'),name=financeValue('ccName'),card=financeValue('ccCard'),staffId=financeValue('ccStaff'),oldMeta=companyCardMeta(r),staff=state.staff.find(s=>s.id===staffId),payAfter=$('ccPayAfter').checked,excluded=$('ccExcluded')?.checked||false;
 if(!name||!card||!staffId||!charged||charged>financeToday()||!due||due<charged||!Number.isSafeInteger(amount)||amount<=0||!Number.isSafeInteger(cash)||cash<0||amount<Number(r?.paid||0)){alert('고객명·담당자·카드결제일·출금 예정일·금액을 확인하세요. 이미 납부한 금액보다 작게 저장할 수 없습니다.');return}
 if(payAfter&&excluded){alert('예상에서 제외한 카드 내역에는 납부를 추가할 수 없습니다.');return}
 const metadata={version:1,customer_name:name,phone:financeValue('ccPhone').replace(/\D/g,''),card_name:card,vendor:financeValue('ccVendor'),charged_on:charged,ledger_id:financeValue('ccLedger')||null,staff_id:staffId,staff_name:staff?.name||oldMeta?.staff_name||'',customer_cash:cash,memo:financeValue('ccMemo')};
 const payload={item_key:key,category:'manual',title:card+' 단말기 대금 · '+name,source_month:charged.slice(0,7)+'-01',direction:'out',amount,due_date:due,excluded,note:companyCardPrefix+JSON.stringify(metadata)};
 if(payload.title.length>200||payload.note.length>5000){alert('고객명·카드명·메모를 짧게 입력하세요.');return}
 companyCardState.saving=true;$('modalSave').disabled=true;
 try{
  let q=sb.from('jk_internal_items');q=r?q.update(payload).eq('item_key',key).eq('updated_at',r.updated_at):q.upsert(payload,{onConflict:'item_key',ignoreDuplicates:true});
  const result=await q.select('*').single();if(result.error)throw result.error;
  closeModal();await loadInternalFinance();toast('사무실 카드 단말기 대금을 기록했습니다.');if(payAfter)openCompanyCardPayment(key);
 }catch(e){alert(e.code==='PGRST116'?'기록이 이미 저장됐거나 다른 화면에서 변경됐습니다. 새로고침 후 확인해 주세요.':'카드 내역 저장 실패: '+e.message)}finally{companyCardState.saving=false;$('modalSave').disabled=false}
}
function openCompanyCardPayment(key){
 const r=financeState.model?.itemMap[key];if(!companyCardMeta(r))return;openFinancePayment(key);if(modalMode!=='finance-payment')return;
 // The user is backfilling cash already spent. Keep that outflow inside the saved current balance.
 $('fiIncluded').checked=true;$('fiPaymentNote').value='사무실 '+companyCardMeta(r).card_name+' 단말기 대금 납부';
 $('fiPaidOn').value='';$('fiPaidOn').setAttribute('onchange','syncCompanyCardPaymentDate()');
 $('modalTitle').textContent='사무실 카드대금 실제 납부 기록';const help=document.createElement('p');help.className='finance-warning';help.textContent='이미 납부해 현재 남은 잔고에 반영된 돈이면 아래 체크를 유지하세요. 저장한 잔고 이후 새로 납부한 돈만 체크를 해제하세요. 실제 출금 날짜와 이번 납부액을 확인하세요.';$('modalBody').prepend(help);
}
function syncCompanyCardPaymentDate(){syncFinancePaymentDate();$('fiIncluded').checked=true}
