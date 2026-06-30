import Foundation

extension RemoteServer {
    /// The single-page web remote. Reads its access token from its own URL
    /// (?t=…), polls state, and posts control actions. Styled to match the app
    /// (dark telemetry deck), responsive for phone + desktop. Icons are inline
    /// SVG line icons (no emoji) so they inherit the accent colour and stay crisp.
    static let html = ##"""
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no">
<meta name="apple-mobile-web-app-capable" content="yes">
<meta name="theme-color" content="#0a0b0d">
<title>Xeneon Toolbox · Remote</title>
<style>
  :root{
    --bg:#0a0b0d; --card:#15171d; --card2:#0f1117; --stroke:#ffffff14; --stroke2:#ffffff22;
    --txt:#eef2f8; --dim:#8a93a2; --faint:#586172;
    --cyan:#54d6eb; --violet:#8f7dff; --amber:#fbbd61; --red:#fb746b; --green:#76e29a;
  }
  *{box-sizing:border-box;-webkit-tap-highlight-color:transparent}
  html,body{margin:0}
  body{
    background:radial-gradient(120% 80% at 50% -10%, #15212b 0%, var(--bg) 55%);
    color:var(--txt); min-height:100vh;
    font:16px/1.45 -apple-system,BlinkMacSystemFont,"SF Pro",Segoe UI,Roboto,sans-serif;
    padding:18px; padding-bottom:40px;
  }
  .wrap{max-width:560px;margin:0 auto;display:flex;flex-direction:column;gap:14px}
  svg{display:block}
  header{display:flex;align-items:center;gap:10px;padding:2px 2px 4px}
  .mark{width:30px;height:30px;border-radius:9px;background:linear-gradient(160deg,var(--cyan),#2b8fa6);
    display:grid;place-items:center;color:#04222a;box-shadow:0 0 16px #54d6eb55}
  .mark svg{width:17px;height:17px}
  .brand{font-weight:800;letter-spacing:.14em;font-size:13px}
  .brand small{display:block;color:var(--faint);font-weight:700;letter-spacing:.28em;font-size:9px}
  .pills{display:flex;flex-wrap:wrap;gap:8px;margin-left:auto;justify-content:flex-end}
  .pill{font-size:12px;font-weight:700;color:var(--dim);background:#ffffff0c;border:1px solid var(--stroke);
    padding:5px 10px;border-radius:999px;font-variant-numeric:tabular-nums}
  .pill b{color:var(--txt)} .pill.cy b{color:var(--cyan)} .pill.vi b{color:var(--violet)}
  .card{background:linear-gradient(180deg,var(--card),var(--card2));border:1px solid var(--stroke);
    border-radius:18px;padding:16px;box-shadow:0 12px 30px #00000055}
  .label{font-size:11px;font-weight:800;letter-spacing:.16em;color:var(--dim);margin:0 0 12px}
  .grid{display:grid;grid-template-columns:repeat(3,1fr);gap:10px}
  button{font:inherit;cursor:pointer;color:var(--txt);border:1px solid var(--stroke2);
    background:#ffffff0d;border-radius:14px;padding:14px 8px;min-height:62px;display:flex;
    flex-direction:column;align-items:center;justify-content:center;gap:7px;font-weight:600;
    transition:transform .08s ease, background .15s ease, border-color .15s, color .15s}
  button:active{transform:scale(.95)}
  .ico{width:22px;height:22px;flex:0 0 auto}
  button.on{background:#54d6eb1f;border-color:#54d6eb88;color:var(--cyan);box-shadow:0 0 18px #54d6eb33}
  .seg{display:grid;grid-template-columns:repeat(3,1fr);gap:10px}
  .slider{display:flex;align-items:center;gap:12px;margin-top:12px}
  .slider .bsun{width:18px;height:18px;color:var(--faint)}
  .slider input{flex:1;accent-color:var(--amber);height:28px}
  .slider .v{font-variant-numeric:tabular-nums;color:var(--amber);font-weight:700;width:46px;text-align:right}
  .log{display:flex;flex-direction:column;gap:8px;max-height:46vh;overflow:auto;padding-right:2px}
  .msg{padding:10px 13px;border-radius:14px;max-width:88%;white-space:pre-wrap;word-wrap:break-word;font-size:15px}
  .msg.user{align-self:flex-end;background:#54d6eb24;border:1px solid #54d6eb44}
  .msg.assistant{align-self:flex-start;background:#ffffff0e;border:1px solid var(--stroke)}
  .msg.error{align-self:flex-start;background:#fb746b1f;border:1px solid #fb746b55;color:#ffd9d5}
  .empty{color:var(--faint);text-align:center;padding:18px 0;font-size:14px}
  .card2{align-self:stretch;background:#ffffff0a;border:1px solid var(--stroke);border-radius:14px;padding:12px;display:flex;flex-direction:column;gap:8px}
  .ctitle{font-size:11px;font-weight:800;letter-spacing:.1em;color:var(--cyan);text-transform:uppercase}
  .card2 table{border-collapse:collapse;width:100%;font-size:13px}
  .card2 th{text-align:left;color:var(--dim);font-weight:700;padding:4px 8px;border-bottom:1px solid var(--stroke);white-space:nowrap}
  .card2 td{padding:4px 8px;border-bottom:1px solid #ffffff0a}
  .kv{display:flex;justify-content:space-between;gap:10px;font-size:14px}
  .kv .k{color:var(--dim)} .kv .v{color:var(--txt);font-weight:600;text-align:right}
  .bar{display:flex;align-items:center;gap:8px;font-size:13px}
  .bar .blabel{width:32%;color:var(--dim);overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
  .bar .btrack{flex:1;height:8px;background:#ffffff14;border-radius:999px;overflow:hidden}
  .bar .bfill{display:block;height:100%;background:linear-gradient(90deg,#54d6eb88,var(--cyan));border-radius:999px}
  .bar .bval{width:50px;text-align:right;color:var(--txt);font-variant-numeric:tabular-nums}
  .cimg{max-width:100%;border-radius:10px}
  .typing{display:flex;gap:5px;align-items:center;width:fit-content}
  .typing .dot{width:7px;height:7px;border-radius:50%;background:var(--cyan);animation:blink 1.2s infinite}
  .typing .dot:nth-child(2){animation-delay:.2s}.typing .dot:nth-child(3){animation-delay:.4s}
  @keyframes blink{0%,60%,100%{opacity:.3;transform:translateY(0)}30%{opacity:1;transform:translateY(-3px)}}
  .chatcard{position:relative}
  .scrollbtn{position:absolute;left:50%;transform:translateX(-50%);bottom:78px;display:none;
    width:40px;height:40px;border-radius:50%;background:var(--cyan);color:#03222a;border:none;cursor:pointer;
    align-items:center;justify-content:center;box-shadow:0 8px 18px #00000077;z-index:5}
  .scrollbtn.show{display:flex} .scrollbtn svg{width:20px;height:20px}
  .composer{display:flex;gap:8px;align-items:flex-end;margin-top:10px}
  .composer textarea{flex:1;resize:none;background:#ffffff0d;border:1px solid var(--stroke2);color:var(--txt);
    border-radius:14px;padding:12px 14px;font:inherit;max-height:120px}
  .iconbtn{min-height:48px;width:48px;padding:0;border-radius:14px;flex:0 0 auto;align-items:center}
  .iconbtn svg{width:22px;height:22px}
  .iconbtn.send{background:#54d6eb;border-color:#54d6eb;color:#03222a}
  .iconbtn.mic.live{background:#fb746b;border-color:#fb746b;color:#fff;animation:pulse 1s infinite}
  @keyframes pulse{0%,100%{box-shadow:0 0 0 0 #fb746b66}50%{box-shadow:0 0 0 8px #fb746b00}}
  .foot{color:var(--faint);font-size:12px;text-align:center}
  @media(max-width:380px){.grid{grid-template-columns:repeat(2,1fr)}}
</style>
</head>
<body>
<div class="wrap">
  <header>
    <div class="mark" id="mark"></div>
    <div class="brand">XENEON<small>TOOLBOX</small></div>
    <div class="pills">
      <span class="pill cy">CPU <b id="cpu">–</b></span>
      <span class="pill vi">MEM <b id="mem">–</b></span>
      <span class="pill"><b id="clock">–</b></span>
    </div>
  </header>

  <section class="card">
    <p class="label">PAGES</p>
    <div class="grid" id="pages"></div>
    <div style="display:flex;gap:8px;margin-top:12px">
      <input id="weburl" type="text" placeholder="Open a URL on the Edge…" autocapitalize="off" autocomplete="off" spellcheck="false"
        style="flex:1;min-width:0;background:#ffffff0e;border:1px solid var(--stroke);border-radius:12px;color:var(--txt);padding:11px 14px;font-size:15px;outline:none">
      <button id="webgo" style="background:#54d6eb;color:#04222a;border:none;border-radius:12px;padding:0 18px;font-weight:800;font-size:14px">Open</button>
    </div>
  </section>

  <section class="card">
    <p class="label">DISPLAY</p>
    <div class="seg" id="display"></div>
    <div class="slider" id="brightwrap" style="display:none">
      <span class="bsun" id="bsun"></span>
      <input id="bright" type="range" min="0" max="100" value="90">
      <span class="v" id="brightv">90%</span>
    </div>
  </section>

  <section class="card chatcard">
    <p class="label">ASSISTANT</p>
    <div class="log" id="log"><div class="empty">Ask anything, or tap the mic to speak.</div></div>
    <button class="scrollbtn" id="scrollbtn" title="Scroll to latest"></button>
    <div class="composer">
      <textarea id="text" rows="1" placeholder="Message the assistant…"></textarea>
      <button class="iconbtn mic" id="mic" title="Voice"></button>
      <button class="iconbtn send" id="send" title="Send"></button>
    </div>
  </section>

  <p class="foot">Connected to your Edge over the local network</p>
</div>

<script>
const T = new URLSearchParams(location.search).get('t') || '';
const j = (p,m='GET',b)=>fetch(p+(p.indexOf('?')<0?'?':'&')+'t='+encodeURIComponent(T),
  {method:m,headers:b?{'Content-Type':'application/json'}:undefined,body:b?JSON.stringify(b):undefined})
  .then(r=>r.json()).catch(()=>({}));
const post=(p,b)=>j(p,'POST',b);

const P={
 dashboard:'<path d="m12 14 4-4"/><path d="M3.34 19a10 10 0 1 1 17.32 0"/>',
 clock:'<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/>',
 tasks:'<path d="M9 11l3 3 8-8"/><path d="M20 12v7a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2h9"/>',
 games:'<rect x="2" y="6" width="20" height="12" rx="4"/><line x1="6" y1="12" x2="10" y2="12"/><line x1="8" y1="10" x2="8" y2="14"/><circle cx="16" cy="11.5" r="1"/><circle cx="18.5" cy="13.5" r="1"/>',
 web:'<circle cx="12" cy="12" r="9"/><path d="M3 12h18"/><path d="M12 3a14 14 0 0 1 0 18a14 14 0 0 1 0-18"/>',
 assistant:'<path d="M12 3l1.7 4.6L18.5 9.5l-4.8 1.9L12 16l-1.7-4.6L5.5 9.5l4.8-1.9z"/>',
 sun:'<circle cx="12" cy="12" r="4"/><path d="M12 2v2M12 20v2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M2 12h2M20 12h2M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4"/>',
 moon:'<path d="M21 12.8A9 9 0 1 1 11.2 3 7 7 0 0 0 21 12.8z"/>',
 power:'<path d="M12 4v8"/><path d="M7.5 7.5a7 7 0 1 0 9 0"/>',
 mic:'<rect x="9" y="3" width="6" height="11" rx="3"/><path d="M5 11a7 7 0 0 0 14 0"/><path d="M12 18v3"/>',
 send:'<path d="M12 19V5"/><path d="M5 12l7-7 7 7"/>',
 down:'<path d="M12 5v14"/><path d="M19 12l-7 7-7-7"/>',
 grid:'<rect x="3" y="3" width="7" height="7" rx="1.5"/><rect x="14" y="3" width="7" height="7" rx="1.5"/><rect x="3" y="14" width="7" height="7" rx="1.5"/><rect x="14" y="14" width="7" height="7" rx="1.5"/>'
};
const svg=(n,cls='ico')=>'<svg class="'+cls+'" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">'+(P[n]||'')+'</svg>';

document.getElementById('mark').innerHTML=svg('grid');
document.getElementById('bsun').innerHTML=svg('sun','bsun');
document.getElementById('mic').innerHTML=svg('mic');
document.getElementById('send').innerHTML=svg('send');

const PAGES=[['dashboard','dashboard','Dashboard'],['clock','clock','Clock'],['tasks','tasks','Tasks'],
  ['games','games','Games'],['web','web','Web'],['chat','assistant','Assistant']];
const DISPLAY=[['full','sun','Wake'],['minimal','moon','Minimal'],['sleep','power','Rest']];

const pagesEl=document.getElementById('pages');
PAGES.forEach(([k,ic,nm])=>{const b=document.createElement('button');b.dataset.route=k;
  b.innerHTML=svg(ic)+'<span>'+nm+'</span>';b.onclick=()=>post('/api/route',{route:k});pagesEl.appendChild(b);});

const weburl=document.getElementById('weburl'),webgo=document.getElementById('webgo');
function openWeb(){const u=weburl.value.trim();if(!u)return;post('/api/web',{url:u});weburl.value='';weburl.blur();}
webgo.onclick=openWeb;
weburl.addEventListener('keydown',e=>{if(e.key==='Enter'){e.preventDefault();openWeb();}});
const dispEl=document.getElementById('display');
DISPLAY.forEach(([k,ic,nm])=>{const b=document.createElement('button');b.dataset.mode=k;
  b.innerHTML=svg(ic)+'<span>'+nm+'</span>';b.onclick=()=>post('/api/display',{mode:k});dispEl.appendChild(b);});

const bright=document.getElementById('bright'), brightv=document.getElementById('brightv');
let brightT=null, brightFocused=false;
bright.oninput=()=>{brightv.textContent=bright.value+'%';clearTimeout(brightT);
  brightT=setTimeout(()=>post('/api/brightness',{level:+bright.value}),120);};
bright.onpointerdown=()=>brightFocused=true; bright.onpointerup=()=>setTimeout(()=>brightFocused=false,400);

function paintState(s){
  if(!s||!s.route)return;
  document.getElementById('cpu').textContent=(s.cpu??0)+'%';
  document.getElementById('mem').textContent=(s.mem??0)+'%';
  document.getElementById('clock').textContent=s.time||'';
  document.querySelectorAll('#pages button').forEach(b=>b.classList.toggle('on',b.dataset.route===s.route));
  document.querySelectorAll('#display button').forEach(b=>b.classList.toggle('on',b.dataset.mode===s.display));
  document.getElementById('brightwrap').style.display=s.canBrightness?'flex':'none';
  if(s.canBrightness&&!brightFocused){bright.value=s.brightness;brightv.textContent=s.brightness+'%';}
}

const logEl=document.getElementById('log');
const scrollbtn=document.getElementById('scrollbtn');
let lastSig='', stick=true;
function nearBottom(){return logEl.scrollHeight - logEl.scrollTop - logEl.clientHeight < 48;}
function updateScrollBtn(){scrollbtn.classList.toggle('show',!stick);}
function toBottom(){logEl.scrollTop=logEl.scrollHeight;stick=true;updateScrollBtn();}
logEl.addEventListener('scroll',()=>{stick=nearBottom();updateScrollBtn();});
scrollbtn.innerHTML=svg('down'); scrollbtn.onclick=toBottom;
function cell(tag,cls,txt){const e=document.createElement(tag);if(cls)e.className=cls;if(txt!=null)e.textContent=txt;return e;}
function renderCard(c){
  const card=cell('div','card2');
  if(c.title)card.appendChild(cell('div','ctitle',c.title));
  if(c.type==='table'){
    const t=document.createElement('table');
    if(c.headers&&c.headers.length){const tr=document.createElement('tr');c.headers.forEach(h=>tr.appendChild(cell('th',null,h)));t.appendChild(tr);}
    (c.rows||[]).forEach(r=>{const tr=document.createElement('tr');r.forEach(v=>tr.appendChild(cell('td',null,v)));t.appendChild(tr);});
    card.appendChild(t);
  }else if(c.type==='generic'){
    (c.rows||[]).forEach(r=>{const row=cell('div','kv');row.appendChild(cell('span','k',r.label));row.appendChild(cell('span','v',r.value));card.appendChild(row);});
  }else if(c.type==='processes'){
    (c.rows||[]).forEach(r=>{const row=cell('div','kv');row.appendChild(cell('span','k',r.name));row.appendChild(cell('span','v','CPU '+r.cpu+'% · MEM '+r.mem+'%'));card.appendChild(row);});
  }else if(c.type==='chart'){
    const max=Math.max(1,...(c.points||[]).map(p=>p.value));
    (c.points||[]).forEach(p=>{const row=cell('div','bar');row.appendChild(cell('span','blabel',p.label));
      const track=cell('span','btrack'),fill=cell('span','bfill');fill.style.width=Math.round(p.value/max*100)+'%';track.appendChild(fill);
      row.appendChild(track);row.appendChild(cell('span','bval',String(p.value)));card.appendChild(row);});
  }else if(c.type==='image'){
    const img=document.createElement('img');img.className='cimg';
    img.src='/api/image?id='+encodeURIComponent(c.id)+'&t='+encodeURIComponent(T);card.appendChild(img);
  }
  return card;
}
function typingEl(){const w=cell('div','msg assistant typing');for(let i=0;i<3;i++)w.appendChild(cell('span','dot'));return w;}
function paintChat(d){
  const turns=(d&&d.turns)||[], busy=!!(d&&d.busy);
  const sig=JSON.stringify(turns)+'|'+busy;
  if(sig===lastSig)return; lastSig=sig;
  const prev=logEl.scrollTop;
  if(!turns.length&&!busy){logEl.innerHTML='<div class="empty">Ask anything, or tap the mic to speak.</div>';updateScrollBtn();return;}
  logEl.innerHTML='';
  turns.forEach(t=>{ if(t.role==='card'&&t.card)logEl.appendChild(renderCard(t.card));
    else logEl.appendChild(cell('div','msg '+t.role,t.text)); });
  if(busy)logEl.appendChild(typingEl());
  // Stick to the bottom only when the user is already there; otherwise keep their
  // place (and show the scroll-to-latest button).
  if(stick)logEl.scrollTop=logEl.scrollHeight; else logEl.scrollTop=prev;
  updateScrollBtn();
}

async function tick(){ paintState(await j('/api/state')); paintChat(await j('/api/agent')); }
tick(); setInterval(tick,1500);

const text=document.getElementById('text');
text.addEventListener('input',()=>{text.style.height='auto';text.style.height=Math.min(text.scrollHeight,120)+'px';});
function sendText(){const v=text.value.trim();if(!v)return;stick=true;post('/api/agent',{text:v});text.value='';text.style.height='auto';setTimeout(tick,300);}
document.getElementById('send').onclick=sendText;
text.addEventListener('keydown',e=>{if(e.key==='Enter'&&!e.shiftKey){e.preventDefault();sendText();}});

const micBtn=document.getElementById('mic');
const SR=window.SpeechRecognition||window.webkitSpeechRecognition;
if(!SR){micBtn.style.display='none';}
else{
  const rec=new SR();rec.lang='en-US';rec.interimResults=true;
  let on=false,final='';
  micBtn.onclick=()=>{if(on){rec.stop();return;}final='';try{rec.start();}catch(e){}};
  rec.onstart=()=>{on=true;micBtn.classList.add('live');};
  rec.onend=()=>{on=false;micBtn.classList.remove('live');const v=final.trim();if(v){text.value=v;sendText();}};
  rec.onresult=e=>{let interim='';for(let i=e.resultIndex;i<e.results.length;i++){const r=e.results[i];
    if(r.isFinal)final+=r[0].transcript;else interim+=r[0].transcript;}text.value=(final+interim).trim();};
  rec.onerror=()=>{on=false;micBtn.classList.remove('live');};
}
</script>
</body>
</html>
"""##
}
