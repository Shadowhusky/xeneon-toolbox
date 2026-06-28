import Foundation

extension RemoteServer {
    /// The single-page web remote. Reads its access token from its own URL
    /// (?t=…), polls state, and posts control actions. Styled to match the app
    /// (dark telemetry deck) and responsive for phone + desktop.
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
    --cyan:#54d6eb; --violet:#8f7dff; --amber:#fbbd61; --red:#fb746b; --green:#76e29a; --pink:#ff73b8;
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
  header{display:flex;align-items:center;gap:10px;padding:2px 2px 4px}
  .mark{width:30px;height:30px;border-radius:9px;background:linear-gradient(160deg,var(--cyan),#2b8fa6);
    display:grid;place-items:center;color:#04222a;font-weight:800;box-shadow:0 0 16px #54d6eb55}
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
  .grid.two{grid-template-columns:repeat(3,1fr)}
  button{font:inherit;cursor:pointer;color:var(--txt);border:1px solid var(--stroke2);
    background:#ffffff0d;border-radius:14px;padding:14px 8px;min-height:60px;display:flex;
    flex-direction:column;align-items:center;justify-content:center;gap:6px;font-weight:600;
    transition:transform .08s ease, background .15s ease, border-color .15s}
  button:active{transform:scale(.95)}
  button .ico{font-size:22px;line-height:1}
  button.on{background:#54d6eb1f;border-color:#54d6eb88;color:var(--cyan);box-shadow:0 0 18px #54d6eb33}
  .seg{display:grid;grid-template-columns:repeat(3,1fr);gap:10px}
  .slider{display:flex;align-items:center;gap:12px;margin-top:12px}
  .slider input{flex:1;accent-color:var(--amber);height:28px}
  .slider .v{font-variant-numeric:tabular-nums;color:var(--amber);font-weight:700;width:46px;text-align:right}
  .chat{display:flex;flex-direction:column;gap:10px}
  .log{display:flex;flex-direction:column;gap:8px;max-height:46vh;overflow:auto;padding-right:2px}
  .msg{padding:10px 13px;border-radius:14px;max-width:88%;white-space:pre-wrap;word-wrap:break-word;font-size:15px}
  .msg.user{align-self:flex-end;background:#54d6eb24;border:1px solid #54d6eb44}
  .msg.assistant{align-self:flex-start;background:#ffffff0e;border:1px solid var(--stroke)}
  .msg.error{align-self:flex-start;background:#fb746b1f;border:1px solid #fb746b55;color:#ffd9d5}
  .empty{color:var(--faint);text-align:center;padding:18px 0;font-size:14px}
  .composer{display:flex;gap:8px;align-items:flex-end}
  .composer textarea{flex:1;resize:none;background:#ffffff0d;border:1px solid var(--stroke2);color:var(--txt);
    border-radius:14px;padding:12px 14px;font:inherit;max-height:120px}
  .iconbtn{min-height:48px;width:48px;padding:0;border-radius:14px;flex:0 0 auto}
  .iconbtn.send{background:#54d6eb;border-color:#54d6eb;color:#03222a;font-size:20px}
  .iconbtn.mic.live{background:#fb746b;border-color:#fb746b;color:#fff;animation:pulse 1s infinite}
  @keyframes pulse{0%,100%{box-shadow:0 0 0 0 #fb746b66}50%{box-shadow:0 0 0 8px #fb746b00}}
  .foot{color:var(--faint);font-size:12px;text-align:center}
  @media(max-width:380px){.grid{grid-template-columns:repeat(2,1fr)}}
</style>
</head>
<body>
<div class="wrap">
  <header>
    <div class="mark">▦</div>
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
  </section>

  <section class="card">
    <p class="label">DISPLAY</p>
    <div class="seg" id="display"></div>
    <div class="slider" id="brightwrap" style="display:none">
      <span class="ico">🔅</span>
      <input id="bright" type="range" min="0" max="100" value="90">
      <span class="v" id="brightv">90%</span>
    </div>
  </section>

  <section class="card chat">
    <p class="label">ASSISTANT</p>
    <div class="log" id="log"><div class="empty">Ask anything, or tap the mic to speak.</div></div>
    <div class="composer">
      <textarea id="text" rows="1" placeholder="Message the assistant…"></textarea>
      <button class="iconbtn mic" id="mic" title="Voice">🎙️</button>
      <button class="iconbtn send" id="send" title="Send">➤</button>
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

const PAGES=[['dashboard','📊','Dashboard'],['clock','🕐','Clock'],['tasks','✓','Tasks'],
  ['games','🎮','Games'],['chat','✨','Assistant']];
const DISPLAY=[['full','☀︎','Wake'],['minimal','🌙','Minimal'],['sleep','⏻','Rest']];

const pagesEl=document.getElementById('pages');
PAGES.forEach(([k,ic,nm])=>{const b=document.createElement('button');b.dataset.route=k;
  b.innerHTML='<span class="ico">'+ic+'</span>'+nm;b.onclick=()=>post('/api/route',{route:k});pagesEl.appendChild(b);});
const dispEl=document.getElementById('display');
DISPLAY.forEach(([k,ic,nm])=>{const b=document.createElement('button');b.dataset.mode=k;
  b.innerHTML='<span class="ico">'+ic+'</span>'+nm;b.onclick=()=>post('/api/display',{mode:k});dispEl.appendChild(b);});

const bright=document.getElementById('bright'), brightv=document.getElementById('brightv');
let brightT=null;
bright.oninput=()=>{brightv.textContent=bright.value+'%';clearTimeout(brightT);
  brightT=setTimeout(()=>post('/api/brightness',{level:+bright.value}),120);};
let brightFocused=false; bright.onpointerdown=()=>brightFocused=true; bright.onpointerup=()=>setTimeout(()=>brightFocused=false,400);

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
let lastN=-1;
function paintChat(d){
  const turns=(d&&d.turns)||[];
  if(turns.length===lastN)return; lastN=turns.length;
  if(!turns.length){logEl.innerHTML='<div class="empty">Ask anything, or tap the mic to speak.</div>';return;}
  logEl.innerHTML='';
  turns.forEach(t=>{const m=document.createElement('div');m.className='msg '+t.role;m.textContent=t.text;logEl.appendChild(m);});
  logEl.scrollTop=logEl.scrollHeight;
}

async function tick(){ paintState(await j('/api/state')); paintChat(await j('/api/agent')); }
tick(); setInterval(tick,1500);

const text=document.getElementById('text');
text.addEventListener('input',()=>{text.style.height='auto';text.style.height=Math.min(text.scrollHeight,120)+'px';});
function sendText(){const v=text.value.trim();if(!v)return;post('/api/agent',{text:v});text.value='';text.style.height='auto';setTimeout(tick,300);}
document.getElementById('send').onclick=sendText;
text.addEventListener('keydown',e=>{if(e.key==='Enter'&&!e.shiftKey){e.preventDefault();sendText();}});

// Voice via the browser's Web Speech API (works in secure contexts / localhost).
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
