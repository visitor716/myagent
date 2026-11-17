import { createRequire } from 'node:module';
import { readFileSync, appendFileSync } from 'node:fs';
import { spawn, spawnSync } from 'node:child_process';
const require = createRequire('/home/zhanxp/projects/tg-agent-gateway/package.json');
const fetch = require('node-fetch');
const { HttpsProxyAgent } = require('https-proxy-agent');
require('dotenv').config({path:'/home/zhanxp/projects/tg-agent-gateway/.env'});
const logfile='/tmp/tg-review-agy-master-details-20261114-tunnel.log';
const existingSession='tg-review-agy-master-details-20261114-ssh';
const sleep=ms=>new Promise(r=>setTimeout(r,ms));
const log=s=>console.log(new Date().toISOString(),s);
const agent=()=>new HttpsProxyAgent(process.env.HTTPS_PROXY||process.env.https_proxy);
let child=null,published='',failed=0;
function sessionAlive(){return spawnSync('tmux',['has-session','-t',existingSession],{stdio:'ignore'}).status===0;}
function startTunnel(){
 child=spawn('/home/zhanxp/.local/bin/cloudflared',['tunnel','--url','http://127.0.0.1:43122','--no-autoupdate','--protocol','http2'],{stdio:['ignore','pipe','pipe']});
 for(const stream of [child.stdout,child.stderr])stream.on('data',b=>appendFileSync(logfile,b));
 child.on('error',()=>log('ssh spawn error'));
 child.on('exit',code=>{log('ssh exit '+code);child=null;});
 log('started dedicated Cloudflare tunnel');
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
 const healthData=await health.json();if(healthData.reviewTaskId!=='agy-master-details-20261114'||!health.ok||healthData.status!=='ok'||healthData.mode!=='review'||healthData.reviewCommit!=='0c7f194309202c4a769cf106375c4a317de5a7c1')throw Error('review identity failed');
 const r=await fetch(base+'/',{agent:agent(),timeout:60000});const html=await r.text();
 const assets=[...html.matchAll(/(?:src|href)="(\/assets\/[^\"]+)"/g)].map(m=>m[1]);
 if(!r.ok||!assets.some(s=>s.endsWith('.js'))||html.includes('@vite/client'))throw Error('production HTML failed');
 for(const path of assets){const a=await fetch(base+path,{agent:agent(),timeout:60000});if(!a.ok)throw Error('asset failed');const bytes=Buffer.from(await a.arrayBuffer());const local=readFileSync('/home/zhanxp/worktrees/tg-agent-gateway/agy-detail-master-20261114/webapp/dist'+path);const hash=b=>require('node:crypto').createHash('sha256').update(b).digest('hex');if(hash(bytes)!==hash(local))throw Error('asset hash mismatch');}
}
async function publish(base){
 const denied=await fetch(base+'/api/webapp/tasks',{method:'POST',agent:agent(),timeout:30000});if(denied.status!==403)throw Error('write guard failed');
 const noauth=await fetch(base+'/api/webapp/tasks',{agent:agent(),timeout:30000});if(noauth.status!==401)throw Error('auth guard failed');
 const url=base+'/?task=task-20261111-003&commit=0c7f194&v='+Date.now();
 const markup={inline_keyboard:[[{text:'打开 master 基线修复验收版',web_app:{url}}]]};
 const stateFile='/home/zhanxp/.local/share/tg-gateway-reviews/agy-master-details-20261114/telegram-entry.json';
 let prior;try{prior=JSON.parse(readFileSync(stateFile,'utf8'));}catch{}
 let messageId=prior?.messageId;
 if(messageId){await telegram('editMessageReplyMarkup',{chat_id:process.env.ADMIN_USER_ID,message_id:messageId,reply_markup:markup});}
 else {const sent=await telegram('sendMessage',{chat_id:process.env.ADMIN_USER_ID,text:'🧪 agy 任务详情页修复验收版\n分支：fix/agy-detail-master-20261114\nCommit：0c7f194\n基线：master 79dcb9e（已核验，本次基于最新master）\n更新：修复浅色面板白字、收敛执行摘要空白、长标题两行与展开、available不再标红、精简待验收操作。保留Agent/附件/当前Worktree续接和键盘跟随。\n类型检查、后端与前端构建、1996项单测通过。\n独立数据与只读界面验收，禁止创建/追加/验收写入。iPhone深浅色主题、滚动与键盘仍需真机验收。本次未替换正式版、未merge或push，尚未完整独立代码复审。\n请关闭旧预览后点击此新入口。',reply_markup:markup});messageId=sent.result.message_id;}
 const fs=await import('node:fs');fs.writeFileSync(stateFile,JSON.stringify({url,messageId,commit:'0c7f194',mode:'review',updatedAt:new Date().toISOString()},null,2));
 log('review published '+base+' messageId='+messageId);
}
if(!process.env.MANAGER_BOT_TOKEN||!process.env.ADMIN_USER_ID)throw Error('missing bot configuration');
while(true){
 try{
  if(!child&&!sessionAlive()){await sleep(15000);startTunnel();await sleep(10000);}
  const text=readFileSync(logfile,'utf8');
  const matches=[...text.matchAll(/https:\/\/[a-zA-Z0-9-]+\.trycloudflare\.com/g)];
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
