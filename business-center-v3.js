
(function(){
'use strict';
var v3ExpenseRows=[],v3AdRows=[];
var v3State={series:[],target:0,annualTarget:0};

function v3SetText(id,v){var e=document.getElementById(id);if(e)e.textContent=v}
function v3Esc(v){return String(v==null?'':v).replace(/[&<>"']/g,function(m){return {'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[m]})}
function localYMD(d){return d.getFullYear()+'-'+String(d.getMonth()+1).padStart(2,'0')+'-'+String(d.getDate()).padStart(2,'0')}
function monthKey(d){return d.getFullYear()+'-'+String(d.getMonth()+1).padStart(2,'0')}
function monthBoundsFromKey(k){var p=k.split('-').map(Number),s=new Date(p[0],p[1]-1,1),n=new Date(p[0],p[1],1);return [localYMD(s),localYMD(n)]}
function krw(n){return Math.round(Number(n||0)).toLocaleString('ko-KR')+'원'}
function pct(n){return (Number.isFinite(n)?n:0).toFixed(1)+'%'}

function mountV3(){
  var dashboard=document.getElementById('page-dashboard');
  if(dashboard && !document.getElementById('liveDashboard')){
    Array.from(dashboard.children).forEach(function(x){x.classList.add('v3-hidden')});
    var live=document.createElement('div');
    live.id='liveDashboard';live.className='v3-wrap';
    live.innerHTML=
      '<div class="v3-head"><div><h2>정권통신 경영 대시보드</h2><p>장부 · 광고비 · 비용원장 · 목표를 Supabase 실데이터로 자동 계산합니다.</p></div><div style="display:flex;gap:8px"><button class="btn" onclick="loadV3All()">새로고침</button><button class="btn primary" onclick="openTargetModal()">목표 설정</button></div></div>'+
      '<div class="v3-goal"><div class="v3-goal-top"><div><h3>이번 달 목표 달성률</h3><div class="big" id="v3GoalPct">0.0%</div><div style="font-size:11px;color:#697386;margin-top:6px">현재 <b id="v3Current">0원</b> / 목표 <b id="v3Target">미설정</b></div></div><div style="text-align:right"><span style="font-size:10px;color:#697386">현재 페이스 예상</span><strong id="v3Forecast" style="display:block;font-size:24px;margin-top:5px">0원</strong><small id="v3ForecastGap" style="color:#697386">목표 설정 후 계산</small></div></div><div class="v3-progress"><span id="v3GoalBar"></span></div><div class="v3-goal-meta"><span>목표까지 <b id="v3Remaining">0원</b></span><span>남은 기간 필요 일평균 <b id="v3NeedDaily">0원</b></span></div></div>'+
      '<div class="v3-kpis">'+
        '<div class="v3-kpi"><span>월 누적 최종마진</span><strong id="v3Margin">0원</strong><small id="v3Units">0건 · 평균 0원</small></div>'+
        '<div class="v3-kpi" id="v3DeltaCard"><span>전월 동일기간 대비</span><strong id="v3Delta">-</strong><small id="v3PrevSame">전월 동일기간 0원</small></div>'+
        '<div class="v3-kpi good"><span>월 순손익</span><strong id="v3Net">0원</strong><small>최종마진 - 광고비 - 비용원장</small></div>'+
        '<div class="v3-kpi"><span>월 총지출</span><strong id="v3Outflow">0원</strong><small id="v3OutflowDetail">광고 0원 · 비용 0원</small></div>'+
        '<div class="v3-kpi"><span>고정비</span><strong id="v3Fixed">0원</strong><small>급여·월세·통신비 등</small></div>'+
        '<div class="v3-kpi"><span>유동비</span><strong id="v3Variable">0원</strong><small>사은품·소모품·식비 등</small></div>'+
        '<div class="v3-kpi"><span>광고비</span><strong id="v3Ads">0원</strong><small id="v3Roas">마진 ROAS 계산 대기</small></div>'+
        '<div class="v3-kpi"><span>연간 목표 달성률</span><strong id="v3AnnualPct">0.0%</strong><small id="v3AnnualText">연 목표 미설정</small></div>'+
      '</div>'+
      '<div class="v3-grid2"><div class="v3-chart"><h3>일별 매출(최종마진) 추이</h3><p>현재 월 장부의 일별 최종마진 합계</p><canvas id="v3DailyChart"></canvas></div><div class="v3-chart"><h3>누적 실적 vs 목표 페이스</h3><p>누적 최종마진과 월 목표의 일할 기준선 비교</p><canvas id="v3GoalChart"></canvas></div></div>'+
      '<div class="v3-table-card"><div class="v3-table-title"><h3>매출 증감표</h3><span style="font-size:10px;color:#697386">일별 실적 · 전일 대비 · 누적</span></div><div class="table-wrap"><table><thead><tr><th>일자</th><th>판매건수</th><th>일 매출</th><th>전일 대비</th><th>누적 매출</th><th>누적 목표율</th></tr></thead><tbody id="v3DeltaBody"><tr><td colspan="6">데이터 없음</td></tr></tbody></table></div></div>';
    dashboard.insertBefore(live,dashboard.firstChild);
  }

  var ads=document.getElementById('page-ads');
  if(ads)ads.innerHTML=
    '<div class="section-title"><div><h2>광고비 관리</h2><p>광고비도 서버에 저장하고 순손익에 자동 반영합니다.</p></div><button class="btn primary" onclick="openAdModal()">+ 광고비 입력</button></div>'+
    '<div class="v3-summary"><div class="box"><span>이번 달 광고비</span><strong id="adSum">0원</strong></div><div class="box"><span>문의</span><strong id="adInquiries">0건</strong></div><div class="box"><span>개통</span><strong id="adActivations">0건</strong></div><div class="box"><span>마진 ROAS</span><strong id="adRoas">-</strong></div></div>'+
    '<div class="v3-table-card"><div class="v3-table-title"><h3>광고비 원장</h3><input id="adMonth" type="month" onchange="loadAdsPage()" style="padding:8px;border:1px solid #d9dee6;border-radius:9px"></div><div class="table-wrap"><table><thead><tr><th>일자</th><th>채널</th><th>캠페인</th><th>광고비</th><th>문의</th><th>방문</th><th>개통</th><th>유입마진</th><th></th></tr></thead><tbody id="adBody"></tbody></table></div></div>';

  var exp=document.getElementById('page-expenses');
  if(exp)exp.innerHTML=
    '<div class="section-title"><div><h2>비용 원장</h2><p>고정비와 유동비를 분리해 실제 서버에 기록합니다.</p></div><button class="btn primary" onclick="openExpenseModal()">+ 지출 추가</button></div>'+
    '<div class="v3-summary"><div class="box"><span>월 총비용</span><strong id="expTotal">0원</strong></div><div class="box"><span>고정비</span><strong id="expFixed">0원</strong></div><div class="box"><span>유동비</span><strong id="expVariable">0원</strong></div><div class="box"><span>등록건수</span><strong id="expCount">0건</strong></div></div>'+
    '<div class="v3-table-card"><div class="v3-table-title"><h3>비용 내역</h3><div style="display:flex;gap:8px"><input id="expenseMonth" type="month" onchange="loadExpensesPage()" style="padding:8px;border:1px solid #d9dee6;border-radius:9px"><select id="expenseTypeFilter" onchange="renderExpensesPage()" style="padding:8px;border:1px solid #d9dee6;border-radius:9px"><option value="all">전체</option><option value="fixed">고정비</option><option value="variable">유동비</option></select></div></div><div class="table-wrap"><table><thead><tr><th>일자</th><th>구분</th><th>카테고리</th><th>내용</th><th>금액</th><th>결제수단</th><th>사용처</th><th></th></tr></thead><tbody id="expenseBody"></tbody></table></div></div>';

  var targets=document.getElementById('page-targets');
  if(targets)targets.innerHTML=
    '<div class="section-title"><div><h2>목표 관리</h2><p>월·연 목표를 DB에 저장해 달성률과 예상매출을 계산합니다.</p></div><button class="btn primary" onclick="openTargetModal()">목표 설정</button></div>'+
    '<div class="v3-summary"><div class="box"><span>월 목표</span><strong id="targetMonthlyLive">미설정</strong></div><div class="box"><span>현재 월 실적</span><strong id="targetCurrentLive">0원</strong></div><div class="box"><span>월 예상매출</span><strong id="targetForecastLive">0원</strong></div><div class="box"><span>목표 달성률</span><strong id="targetPctLive">0.0%</strong></div></div>'+
    '<div class="card"><div class="card-head"><div><h3>연간 목표</h3><p>올해 누적 실적과 연간 목표를 비교합니다.</p></div></div><div class="v3-goal"><div class="v3-goal-top"><div><span style="font-size:10px;color:#697386">연간 목표</span><div class="big" id="targetAnnualLive">미설정</div></div><div style="text-align:right"><span style="font-size:10px;color:#697386">올해 누적</span><strong id="targetAnnualCurrent" style="display:block;font-size:24px;margin-top:5px">0원</strong></div></div><div class="v3-progress"><span id="targetAnnualBar"></span></div><div class="v3-goal-meta"><span>달성률 <b id="targetAnnualPct">0.0%</b></span><span>월 판매 목표 <b id="targetUnitsLive">0건</b></span></div></div></div>';

  var lp=document.getElementById('loginPanel');
  if(lp)lp.innerHTML=
    '<div class="login-card"><h2>정권통신 대표 로그인</h2><p>대표 계정으로 로그인하면 장부·고객·페이백·비용 데이터가 서버에서 불러와집니다.</p><input id="loginEmail" type="email" value="needis123@gmail.com" placeholder="이메일"><input id="loginPassword" type="password" placeholder="비밀번호" onkeydown="if(event.key===&#39;Enter&#39;)loginSupabase()"><div class="login-actions"><button class="btn primary" onclick="loginSupabase()">로그인</button><button class="btn" onclick="resetPasswordEmail()">비밀번호 재설정 메일 보내기</button><button class="btn ghost" onclick="hideLogin()">닫기</button></div><div id="loginMsg" style="font-size:11px;color:#b05a00;margin-top:10px"></div><div class="login-help">현재 대표 계정에는 비밀번호가 설정되어 있습니다. Invalid login credentials가 나오면 입력한 비밀번호가 현재 비밀번호와 다른 상태입니다. 기억이 안 나면 재설정 메일을 이용하세요.</div></div>';
  initV3Months();
}

window.loginSupabase=async function(){
  var email=(document.getElementById('loginEmail').value||'').trim(),password=document.getElementById('loginPassword').value,msg=document.getElementById('loginMsg');
  if(!email||!password){msg.textContent='이메일과 비밀번호를 입력하세요.';return}
  msg.textContent='로그인 중...';
  var r=await sb.auth.signInWithPassword({email:email,password:password});
  if(r.error){msg.textContent=r.error.message==='Invalid login credentials'?'비밀번호가 맞지 않습니다. 아래 비밀번호 재설정을 이용하세요.':r.error.message;return}
  msg.textContent='';hideLogin();await refreshSessionState();await loadV3All();
};

window.resetPasswordEmail=async function(){
  var email=(document.getElementById('loginEmail').value||'needis123@gmail.com').trim(),msg=document.getElementById('loginMsg');
  msg.textContent='재설정 메일 전송 중...';
  var redirect=location.origin+location.pathname;
  var r=await sb.auth.resetPasswordForEmail(email,{redirectTo:redirect});
  if(r.error)r=await sb.auth.resetPasswordForEmail(email);
  msg.textContent=r.error?r.error.message:'재설정 메일을 보냈습니다. 메일 링크를 눌러 새 비밀번호를 설정하세요.';
};

sb.auth.onAuthStateChange(function(event){
  if(event==='SIGNED_IN'||event==='TOKEN_REFRESHED')setTimeout(loadV3All,0);
  if(event==='PASSWORD_RECOVERY'){
    setTimeout(async function(){
      var p1=prompt('새 비밀번호를 입력하세요. (8자 이상 권장)');
      if(!p1)return;
      var p2=prompt('새 비밀번호를 한 번 더 입력하세요.');
      if(p1!==p2){alert('비밀번호가 서로 다릅니다.');return}
      var r=await sb.auth.updateUser({password:p1});
      if(r.error){alert(r.error.message);return}
      alert('비밀번호가 변경되었습니다. 앞으로 새 비밀번호로 로그인하세요.');
      hideLogin();await refreshSessionState();await loadV3All();
    },300);
  }
});

window.loadV3All=async function(){
  var gs=await sb.auth.getSession();if(!gs.data.session)return;
  var now=new Date(),mk=monthKey(now),b=monthBoundsFromKey(mk),prev=new Date(now.getFullYear(),now.getMonth()-1,1),pb=monthBoundsFromKey(monthKey(prev)),yearStart=now.getFullYear()+'-01-01',yearNext=(now.getFullYear()+1)+'-01-01';
  var qs=await Promise.all([
    sb.from('jk_sales_ledger').select('activation_date,final_margin').gte('activation_date',b[0]).lt('activation_date',b[1]).order('activation_date'),
    sb.from('jk_sales_ledger').select('activation_date,final_margin').gte('activation_date',pb[0]).lt('activation_date',pb[1]).order('activation_date'),
    sb.from('jk_expenses').select('*').gte('expense_date',b[0]).lt('expense_date',b[1]).order('expense_date',{ascending:false}),
    sb.from('jk_ad_spend').select('*').gte('spend_date',b[0]).lt('spend_date',b[1]).order('spend_date',{ascending:false}),
    sb.from('jk_targets').select('*').eq('target_month',b[0]).maybeSingle(),
    sb.from('jk_year_targets').select('*').eq('target_year',now.getFullYear()).maybeSingle(),
    sb.from('jk_sales_ledger').select('final_margin').gte('activation_date',yearStart).lt('activation_date',yearNext)
  ]);
  var bad=qs.find(function(x){return x.error});if(bad){console.warn('V3 load',bad.error);return}
  var sales=qs[0].data||[],prevSales=qs[1].data||[],exps=qs[2].data||[],ads=qs[3].data||[],target=qs[4].data||null,annual=qs[5].data||null,yearSales=qs[6].data||[];
  v3ExpenseRows=exps;v3AdRows=ads;
  var margin=sales.reduce(function(a,r){return a+Number(r.final_margin||0)},0),units=sales.length,avg=units?Math.floor(margin/units):0;
  var fixed=exps.filter(function(r){return r.is_fixed}).reduce(function(a,r){return a+Number(r.amount||0)},0),variable=exps.filter(function(r){return !r.is_fixed}).reduce(function(a,r){return a+Number(r.amount||0)},0),expTotal=fixed+variable;
  var adTotal=ads.reduce(function(a,r){return a+Number(r.amount||0)},0),attributed=ads.reduce(function(a,r){return a+Number(r.attributed_margin||0)},0),net=margin-expTotal-adTotal;
  var targetMargin=target?Number(target.target_margin||0):0,annualTarget=annual?Number(annual.target_margin||0):0,elapsed=now.getDate(),daysInMonth=new Date(now.getFullYear(),now.getMonth()+1,0).getDate(),forecast=elapsed?Math.round(margin/elapsed*daysInMonth):0,goalPct=targetMargin?margin/targetMargin*100:0,remain=Math.max(targetMargin-margin,0),needDaily=targetMargin?Math.ceil(remain/Math.max(daysInMonth-elapsed,1)):0;
  var prevMonthDays=new Date(prev.getFullYear(),prev.getMonth()+1,0).getDate(),compareDay=Math.min(elapsed,prevMonthDays),prevSame=prevSales.filter(function(r){return Number(String(r.activation_date).slice(8,10))<=compareDay}).reduce(function(a,r){return a+Number(r.final_margin||0)},0),delta=prevSame?((margin-prevSame)/Math.abs(prevSame)*100):null;
  var yearMargin=yearSales.reduce(function(a,r){return a+Number(r.final_margin||0)},0),annualPct=annualTarget?yearMargin/annualTarget*100:0;
  v3State.target=targetMargin;v3State.annualTarget=annualTarget;

  v3SetText('v3Margin',krw(margin));v3SetText('v3Units',units+'건 · 평균 '+krw(avg));v3SetText('v3Current',krw(margin));v3SetText('v3Target',targetMargin?krw(targetMargin):'미설정');v3SetText('v3GoalPct',pct(goalPct));
  var gb=document.getElementById('v3GoalBar');if(gb)gb.style.width=Math.min(goalPct,100)+'%';
  v3SetText('v3Forecast',krw(forecast));v3SetText('v3ForecastGap',targetMargin?(forecast>=targetMargin?'목표 예상 초과 '+krw(forecast-targetMargin):'목표 예상 부족 '+krw(targetMargin-forecast)):'목표 설정 후 차이 계산');v3SetText('v3Remaining',targetMargin?krw(remain):'목표 미설정');v3SetText('v3NeedDaily',targetMargin?krw(needDaily):'-');
  v3SetText('v3Net',krw(net));v3SetText('v3Outflow',krw(expTotal+adTotal));v3SetText('v3OutflowDetail','광고 '+krw(adTotal)+' · 비용 '+krw(expTotal));v3SetText('v3Fixed',krw(fixed));v3SetText('v3Variable',krw(variable));v3SetText('v3Ads',krw(adTotal));v3SetText('v3Roas',adTotal?'마진 ROAS '+pct(attributed/adTotal*100):'광고비 입력 전');
  v3SetText('v3Delta',delta===null?'-':(delta>=0?'+':'')+pct(delta));v3SetText('v3PrevSame','전월 동일기간 '+krw(prevSame));var dc=document.getElementById('v3DeltaCard');if(dc){dc.classList.remove('good','bad');if(delta!==null)dc.classList.add(delta>=0?'good':'bad')}
  v3SetText('v3AnnualPct',pct(annualPct));v3SetText('v3AnnualText',annualTarget?'올해 '+krw(yearMargin)+' / '+krw(annualTarget):'연 목표 미설정');
  v3SetText('targetMonthlyLive',targetMargin?krw(targetMargin):'미설정');v3SetText('targetCurrentLive',krw(margin));v3SetText('targetForecastLive',krw(forecast));v3SetText('targetPctLive',pct(goalPct));v3SetText('targetAnnualLive',annualTarget?krw(annualTarget):'미설정');v3SetText('targetAnnualCurrent',krw(yearMargin));v3SetText('targetAnnualPct',pct(annualPct));v3SetText('targetUnitsLive',target?Number(target.target_units||0)+'건':'0건');
  var ab=document.getElementById('targetAnnualBar');if(ab)ab.style.width=Math.min(annualPct,100)+'%';

  v3State.series=buildDailySeries(sales,elapsed,targetMargin,daysInMonth);renderV3DeltaTable(v3State.series,targetMargin);renderV3Charts();renderExpensesPage();renderAdsPage();initV3Months();
};

function buildDailySeries(rows,elapsed,target,days){var map={};rows.forEach(function(r){var d=Number(String(r.activation_date).slice(8,10));if(!map[d])map[d]={amount:0,units:0};map[d].amount+=Number(r.final_margin||0);map[d].units++});var out=[],cum=0;for(var d=1;d<=elapsed;d++){var x=map[d]||{amount:0,units:0};cum+=x.amount;out.push({day:d,amount:x.amount,units:x.units,cum:cum,targetCum:target?target/days*d:0})}return out}
function renderV3DeltaTable(s,target){var body=document.getElementById('v3DeltaBody');if(!body)return;var rows=s.slice(-12).reverse();body.innerHTML=rows.map(function(r){var prev=s[r.day-2]?s[r.day-2].amount:0,d=prev?((r.amount-prev)/Math.abs(prev)*100):null,gp=target?r.cum/target*100:0;return '<tr><td>'+String(r.day).padStart(2,'0')+'일</td><td>'+r.units+'건</td><td><strong>'+krw(r.amount)+'</strong></td><td style="color:'+(d===null?'#7a8492':d>=0?'#148a55':'#d33c49')+'">'+(d===null?'-':(d>=0?'+':'')+pct(d))+'</td><td>'+krw(r.cum)+'</td><td>'+pct(gp)+'</td></tr>'}).join('')||'<tr><td colspan="6" style="text-align:center;padding:30px;color:#7a8492">장부 데이터가 없습니다.</td></tr>'}
function prepCanvas(id){var c=document.getElementById(id);if(!c)return null;var r=c.getBoundingClientRect(),d=window.devicePixelRatio||1;c.width=Math.max(1,r.width*d);c.height=Math.max(1,r.height*d);var x=c.getContext('2d');x.setTransform(d,0,0,d,0,0);x.clearRect(0,0,r.width,r.height);return{x:x,w:r.width,h:r.height}}
function renderV3Charts(){drawDailyChart(v3State.series||[]);drawGoalChart(v3State.series||[])}
function drawDailyChart(s){var o=prepCanvas('v3DailyChart');if(!o)return;var x=o.x,W=o.w,H=o.h,p={l:58,r:18,t:16,b:32},vals=s.map(function(r){return r.amount}),max=Math.max.apply(null,[1].concat(vals));x.strokeStyle='#e8ebef';x.fillStyle='#758092';x.font='10px system-ui';for(var i=0;i<=4;i++){var y=p.t+(H-p.t-p.b)*i/4;x.beginPath();x.moveTo(p.l,y);x.lineTo(W-p.r,y);x.stroke();x.fillText(Math.round(max*(4-i)/4/10000).toLocaleString('ko-KR')+'만',5,y+3)}var bw=Math.max(3,(W-p.l-p.r)/Math.max(s.length,1)*.56);s.forEach(function(r,i){var cx=p.l+(W-p.l-p.r)*(i+.5)/Math.max(s.length,1),bh=(H-p.t-p.b)*(r.amount/max);x.fillStyle='#9be320';x.fillRect(cx-bw/2,H-p.b-bh,bw,bh);if((i+1)%Math.max(1,Math.ceil(s.length/8))===0){x.fillStyle='#758092';x.fillText(r.day+'일',cx-8,H-10)}})}
function drawGoalChart(s){var o=prepCanvas('v3GoalChart');if(!o)return;var x=o.x,W=o.w,H=o.h,p={l:58,r:18,t:16,b:32},max=Math.max.apply(null,[1,v3State.target].concat(s.map(function(r){return r.cum})));x.strokeStyle='#e8ebef';x.fillStyle='#758092';x.font='10px system-ui';for(var i=0;i<=4;i++){var y=p.t+(H-p.t-p.b)*i/4;x.beginPath();x.moveTo(p.l,y);x.lineTo(W-p.r,y);x.stroke();x.fillText(Math.round(max*(4-i)/4/10000).toLocaleString('ko-KR')+'만',5,y+3)}function line(key,color){if(!s.length)return;x.beginPath();s.forEach(function(r,i){var px=p.l+(W-p.l-p.r)*i/Math.max(s.length-1,1),py=H-p.b-(H-p.t-p.b)*(Number(r[key]||0)/max);if(i===0)x.moveTo(px,py);else x.lineTo(px,py)});x.strokeStyle=color;x.lineWidth=3;x.stroke()}line('targetCum','#b7bec8');line('cum','#73b900');x.lineWidth=1}
function initV3Months(){var mk=monthKey(new Date());['expenseMonth','adMonth'].forEach(function(id){var e=document.getElementById(id);if(e&&!e.value)e.value=mk})}

window.loadExpensesPage=async function(){var el=document.getElementById('expenseMonth');if(!el)return;var k=el.value||monthKey(new Date()),b=monthBoundsFromKey(k),q=await sb.from('jk_expenses').select('*').gte('expense_date',b[0]).lt('expense_date',b[1]).order('expense_date',{ascending:false});if(q.error){console.warn(q.error);return}v3ExpenseRows=q.data||[];renderExpensesPage()};
window.renderExpensesPage=function(){var body=document.getElementById('expenseBody');if(!body)return;var f=(document.getElementById('expenseTypeFilter')||{}).value||'all',rows=v3ExpenseRows.filter(function(r){return f==='all'||(f==='fixed'?r.is_fixed:!r.is_fixed)});body.innerHTML=rows.map(function(r){return '<tr><td>'+v3Esc(r.expense_date)+'</td><td><span class="type-badge '+(r.is_fixed?'type-fixed':'type-variable')+'">'+(r.is_fixed?'고정비':'유동비')+'</span></td><td>'+v3Esc(r.category||'-')+'</td><td>'+v3Esc(r.description||r.subcategory||'-')+'</td><td><strong>'+krw(r.amount)+'</strong></td><td>'+v3Esc(r.payment_method||'-')+'</td><td>'+v3Esc(r.vendor||'-')+'</td><td><button class="btn" onclick="deleteExpenseV3(&quot;'+r.id+'&quot;)">삭제</button></td></tr>'}).join('')||'<tr><td colspan="8" style="text-align:center;padding:30px;color:#7a8492">등록된 비용이 없습니다.</td></tr>';var fixed=v3ExpenseRows.filter(function(r){return r.is_fixed}).reduce(function(a,r){return a+Number(r.amount||0)},0),variable=v3ExpenseRows.filter(function(r){return !r.is_fixed}).reduce(function(a,r){return a+Number(r.amount||0)},0);v3SetText('expTotal',krw(fixed+variable));v3SetText('expFixed',krw(fixed));v3SetText('expVariable',krw(variable));v3SetText('expCount',v3ExpenseRows.length+'건')};
window.openExpenseModal=function(){currentModal='expenseServer';document.getElementById('modalTitle').textContent='비용원장 지출 추가';var d=localYMD(new Date());document.getElementById('modalBody').innerHTML='<div class="form-grid"><div class="field"><label>지출일</label><input id="exDate" type="date" value="'+d+'"></div><div class="field"><label>비용 구분</label><select id="exFixed"><option value="true">고정비</option><option value="false">유동비</option></select></div><div class="field"><label>카테고리</label><select id="exCat"><option>급여</option><option>임대료</option><option>통신비</option><option>관리비</option><option>프로그램</option><option>사은품</option><option>소모품</option><option>식비</option><option>차량</option><option>세무/회계</option><option>기타</option></select></div><div class="field"><label>금액</label><input id="exAmount" type="number" min="0" placeholder="원"></div><div class="field"><label>결제수단</label><select id="exPay"><option>사업자카드</option><option>계좌이체</option><option>현금</option><option>개인카드</option></select></div><div class="field"><label>사용처/거래처</label><input id="exVendor"></div><div class="field full"><label>내용</label><input id="exDesc" placeholder="예: 9월 매장 월세"></div><div class="field full"><label>메모</label><textarea id="exNote" rows="3"></textarea></div></div>';document.getElementById('modalWrap').classList.add('show')};
async function saveExpenseServer(){var amount=Number(document.getElementById('exAmount').value||0);if(amount<=0){alert('금액을 입력하세요.');return}var payload={expense_date:document.getElementById('exDate').value,is_fixed:document.getElementById('exFixed').value==='true',category:document.getElementById('exCat').value,amount:amount,payment_method:document.getElementById('exPay').value,vendor:document.getElementById('exVendor').value||null,description:document.getElementById('exDesc').value||null,note:document.getElementById('exNote').value||null};var q=await sb.from('jk_expenses').insert(payload);if(q.error){alert(q.error.message);return}closeModal();await Promise.all([loadExpensesPage(),loadV3All(),loadMonthlyClose()]);toastMsg('비용원장에 저장했습니다.')}
window.deleteExpenseV3=async function(id){if(!confirm('이 지출을 삭제할까요?'))return;var q=await sb.from('jk_expenses').delete().eq('id',id);if(q.error){alert(q.error.message);return}await Promise.all([loadExpensesPage(),loadV3All(),loadMonthlyClose()])};

window.loadAdsPage=async function(){var el=document.getElementById('adMonth');if(!el)return;var k=el.value||monthKey(new Date()),b=monthBoundsFromKey(k),q=await sb.from('jk_ad_spend').select('*').gte('spend_date',b[0]).lt('spend_date',b[1]).order('spend_date',{ascending:false});if(q.error){console.warn(q.error);return}v3AdRows=q.data||[];renderAdsPage()};
window.renderAdsPage=function(){var body=document.getElementById('adBody');if(!body)return;body.innerHTML=v3AdRows.map(function(r){return '<tr><td>'+v3Esc(r.spend_date)+'</td><td>'+v3Esc(r.channel)+'</td><td>'+v3Esc(r.campaign||'-')+'</td><td><strong>'+krw(r.amount)+'</strong></td><td>'+Number(r.inquiries||0)+'건</td><td>'+Number(r.visits||0)+'건</td><td>'+Number(r.activations||0)+'건</td><td>'+krw(r.attributed_margin||0)+'</td><td><button class="btn" onclick="deleteAdV3(&quot;'+r.id+'&quot;)">삭제</button></td></tr>'}).join('')||'<tr><td colspan="9" style="text-align:center;padding:30px;color:#7a8492">등록된 광고비가 없습니다.</td></tr>';var spend=v3AdRows.reduce(function(a,r){return a+Number(r.amount||0)},0),inq=v3AdRows.reduce(function(a,r){return a+Number(r.inquiries||0)},0),act=v3AdRows.reduce(function(a,r){return a+Number(r.activations||0)},0),margin=v3AdRows.reduce(function(a,r){return a+Number(r.attributed_margin||0)},0);v3SetText('adSum',krw(spend));v3SetText('adInquiries',inq+'건');v3SetText('adActivations',act+'건');v3SetText('adRoas',spend?pct(margin/spend*100):'-')};
window.openAdModal=function(){currentModal='adServer';document.getElementById('modalTitle').textContent='광고비 입력';var d=localYMD(new Date());document.getElementById('modalBody').innerHTML='<div class="form-grid"><div class="field"><label>집행일</label><input id="adDateV3" type="date" value="'+d+'"></div><div class="field"><label>채널</label><select id="adChannelV3"><option>당근</option><option>인스타그램</option><option>네이버</option><option>버스광고</option><option>전단/현수막</option><option>제휴</option><option>기타</option></select></div><div class="field"><label>광고비</label><input id="adAmountV3" type="number" min="0"></div><div class="field"><label>캠페인명</label><input id="adCampaignV3"></div><div class="field"><label>문의</label><input id="adInquiryV3" type="number" value="0"></div><div class="field"><label>방문</label><input id="adVisitV3" type="number" value="0"></div><div class="field"><label>개통</label><input id="adActV3" type="number" value="0"></div><div class="field"><label>광고 유입 최종마진</label><input id="adMarginV3" type="number" value="0"></div><div class="field full"><label>메모</label><textarea id="adNoteV3" rows="3"></textarea></div></div>';document.getElementById('modalWrap').classList.add('show')};
async function saveAdServer(){var amount=Number(document.getElementById('adAmountV3').value||0);if(amount<=0){alert('광고비를 입력하세요.');return}var payload={spend_date:document.getElementById('adDateV3').value,channel:document.getElementById('adChannelV3').value,campaign:document.getElementById('adCampaignV3').value||null,amount:amount,inquiries:Number(document.getElementById('adInquiryV3').value||0),visits:Number(document.getElementById('adVisitV3').value||0),activations:Number(document.getElementById('adActV3').value||0),attributed_margin:Number(document.getElementById('adMarginV3').value||0),note:document.getElementById('adNoteV3').value||null};var q=await sb.from('jk_ad_spend').insert(payload);if(q.error){alert(q.error.message);return}closeModal();await Promise.all([loadAdsPage(),loadV3All(),loadMonthlyClose()]);toastMsg('광고비를 저장했습니다.')}
window.deleteAdV3=async function(id){if(!confirm('이 광고비 내역을 삭제할까요?'))return;var q=await sb.from('jk_ad_spend').delete().eq('id',id);if(q.error){alert(q.error.message);return}await Promise.all([loadAdsPage(),loadV3All(),loadMonthlyClose()])};

window.openTargetModal=function(){currentModal='targetServer';var now=new Date();document.getElementById('modalTitle').textContent='매출 목표 설정';document.getElementById('modalBody').innerHTML='<div class="form-grid"><div class="field"><label>월</label><input id="tgMonth" type="month" value="'+monthKey(now)+'"></div><div class="field"><label>월 목표매출(최종마진)</label><input id="tgMargin" type="number" value="'+Number(v3State.target||0)+'"></div><div class="field"><label>월 판매 목표</label><input id="tgUnits" type="number" value="0"></div><div class="field"><label>월 영업일</label><input id="tgDays" type="number" min="1" max="31" value="'+new Date(now.getFullYear(),now.getMonth()+1,0).getDate()+'"></div><div class="field full"><label>'+now.getFullYear()+'년 연간 목표매출</label><input id="tgAnnual" type="number" value="'+Number(v3State.annualTarget||0)+'"></div><div class="field full"><label>메모</label><textarea id="tgNote" rows="3"></textarea></div></div>';document.getElementById('modalWrap').classList.add('show')};
async function saveTargetServer(){var k=document.getElementById('tgMonth').value,monthly=Number(document.getElementById('tgMargin').value||0),annual=Number(document.getElementById('tgAnnual').value||0),units=Number(document.getElementById('tgUnits').value||0),days=Number(document.getElementById('tgDays').value||0),note=document.getElementById('tgNote').value||null;if(!k||monthly<=0){alert('월 목표매출을 입력하세요.');return}var y=Number(k.slice(0,4)),q1=await sb.from('jk_targets').upsert({target_month:k+'-01',target_margin:monthly,target_units:units,workdays_total:days||null,note:note},{onConflict:'target_month'});if(q1.error){alert(q1.error.message);return}if(annual>0){var q2=await sb.from('jk_year_targets').upsert({target_year:y,target_margin:annual,note:note},{onConflict:'target_year'});if(q2.error){alert(q2.error.message);return}}closeModal();await loadV3All();toastMsg('목표를 서버에 저장했습니다.')}

var legacySaveModal=saveModal;
saveModal=async function(){if(currentModal==='expenseServer'){await saveExpenseServer();return}if(currentModal==='adServer'){await saveAdServer();return}if(currentModal==='targetServer'){await saveTargetServer();return}return legacySaveModal()};

window.addEventListener('resize',function(){if(v3State.series&&v3State.series.length)renderV3Charts()});
mountV3();
setTimeout(async function(){var s=await sb.auth.getSession();if(s.data.session)await loadV3All();else showLogin()},250);
})();