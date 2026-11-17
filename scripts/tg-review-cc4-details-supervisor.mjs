import { createRequire } from 'node:module';
import { readFileSync, appendFileSync } from 'node:fs';
import { spawn, spawnSync } from 'node:child_process';
const require = createRequire('/home/zhanxp/projects/tg-agent-gateway/package.json');
const fetch = require('node-fetch');
const { HttpsProxyAgent } = require('https-proxy-agent');
require('dotenv').config({path:'/home/zhanxp/projects/tg-agent-gateway/.env'});
const logfile='/tmp/tg-review-cc4-details-tunnel.log';
const existingSession='tg-review-cc4-details-ssh';
const sleep=ms=>new Promise(r=>setTimeout(r,ms));
const log=s=>console.log(new Date().toISOString(),s);
const agent=()=>new HttpsProxyAgent(process.env.HTTPS_PROXY||process.env.https_proxy);
let child=null,published='',failed=0;
function sessionAlive(){return spawnSync('tmux',['has-session','-t',existingSession],{stdio:'ignore'}).status===0;}
function startTunnel(){
 const args=['-o','ProxyCommand=nc -X connect -x 172.31.112.1:4077 %h %p','-o','StrictHostKeyChecking=accept-new','-o','ServerAliveInterval=15','-o','ServerAliveCountMax=3','-o','ExitOnForwardFailure=yes','-T','-R','80:127.0.0.1:43010','nokey@localhost.run'];
 child=spawn('ssh',args,{stdio:['ignore','pipe','pipe']});
 for(const stream of [child.stdout,child.stderr])stream.on('data',b=>appendFileSync(logfile,b));
 child.on('error',()=>log('ssh spawn error'));
 child.on('exit',code=>{log('ssh exit '+code);child=null;});
 log('started recovery SSH');
}
async function telegram(method,body){
 for(let attempt=0;attempt<3;attempt++){
  try{
   const r=await fetch('https://api.telegram.org/bot'+process.env.MANAGER_BOT_TOKEN+'/'+method,{method:'POST',agent:agent(),timeout:60000,headers:{'content-type':'application/json'},body:JSON.stringify(body)});
   const d=await r.json();if(d.ok)return d;
  }catch{}
  await sleep(2000);
 }
 throw Error('Telegram '+method+' failed');
}
async function verify(base){
 const health=await fetch(base+'/health',{agent:agent(),timeout:60000});
 const healthData=await health.json();if(!health.ok||healthData.status!=='ok'||healthData.mode!=='review'||healthData.reviewCommit!=='e757c3476a8ab75c82ce322128a7476df025cb82')throw Error('review identity failed');
 const r=await fetch(base+'/',{agent:agent(),timeout:60000});const html=await r.text();
 const assets=[...html.matchAll(/(?:src|href)="(\/assets\/[^\"]+)"/g)].map(m=>m[1]);
 if(!r.ok||!assets.some(s=>s.endsWith('.js'))||html.includes('@vite/client'))throw Error('production HTML failed');
 for(const path of assets){const a=await fetch(base+path,{agent:agent(),timeout:60000});if(!a.ok)throw Error('asset failed');await a.arrayBuffer();}
}
async function publish(base){
 const url=base+'/?task=task-20261111-005&commit=e757c34&v='+Date.now();
 const markup={inline_keyboard:[[{text:'打开详情页与标题验收版',web_app:{url}}]]};
 const stateFile='/home/zhanxp/.local/share/tg-gateway-reviews/cc4-details/telegram-entry.json';
 let prior;try{prior=JSON.parse(readFileSync(stateFile,'utf8'));}catch{}
 let messageId=prior?.messageId;
 if(messageId){await telegram('editMessageReplyMarkup',{chat_id:process.env.ADMIN_USER_ID,message_id:messageId,reply_markup:markup});}
 else {const sent=await telegram('sendMessage',{chat_id:process.env.ADMIN_USER_ID,text:'🧪 任务一：详情页与短标题验收版\n版本：1.0.152\n分支：fix/title-negation-review-20261112\nCommit：e757c34\n更新：全文规则提炼任务短标题；标题编辑持久化；详情五区布局、折叠记录和追加任务、统一状态操作。\n修复后完整验证1929项通过，Codex已复审标题修复。未调用额外AI生成标题；历史标题保留。\n本入口为独立数据库、只读界面验收，编辑/创建/验收提交被禁用；持久化已由隔离SQLite测试覆盖。iPhone视觉和键盘待真机验收。\n请关闭旧弹窗再点击。任务二自动发布功能仍在修复，不在此版中。',reply_markup:markup});messageId=sent.result.message_id;}
 const fs=await import('node:fs');fs.writeFileSync(stateFile,JSON.stringify({url,messageId,commit:'e757c34',mode:'review',updatedAt:new Date().toISOString()},null,2));
 log('review published '+base+' messageId='+messageId);
}
if(!process.env.MANAGER_BOT_TOKEN||!process.env.ADMIN_USER_ID)throw Error('missing bot configuration');
while(true){
 try{
  if(!child&&!sessionAlive()){await sleep(15000);startTunnel();await sleep(10000);}
  const text=readFileSync(logfile,'utf8');
  const matches=[...text.matchAll(/https:\/\/[a-zA-Z0-9.-]+\.lhr\.life/g)];
  const base=matches.at(-1)?.[0];
  if(!base)throw Error('waiting for tunnel URL');
  if(base!==published)await verify(base);
  else {const h=await fetch(base+'/health',{agent:agent(),timeout:15000});if(!h.ok)throw Error('health failed');}
  failed=0;
  if(base!==published){await publish(base);published=base;}
 }catch(e){
  failed++;log('check failed '+failed+': '+(e.message?.startsWith('Telegram')?e.message:'public entry unavailable'));
  if(failed>=3){
   // Restart only this task's SSH tunnel; never stop Gateway or other tunnels.
   if(child)child.kill('SIGTERM');
   else if(sessionAlive())spawnSync('tmux',['kill-session','-t',existingSession]);
   failed=0;
  }
 }
 await sleep(30000);
}
