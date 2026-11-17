import { createRequire } from 'node:module';
import { readFileSync, appendFileSync } from 'node:fs';
import { spawn, spawnSync } from 'node:child_process';
const require = createRequire('/home/zhanxp/projects/tg-agent-gateway/package.json');
const fetch = require('node-fetch');
const { HttpsProxyAgent } = require('https-proxy-agent');
require('dotenv').config({path:'/home/zhanxp/projects/tg-agent-gateway/.env'});
const logfile='/tmp/tg-review-agy-exec-stream-20261114-tunnel.log';
const existingSession='tg-review-agy-exec-stream-20261114-ssh';
const sleep=ms=>new Promise(r=>setTimeout(r,ms));
const log=s=>console.log(new Date().toISOString(),s);
const agent=()=>new HttpsProxyAgent(process.env.HTTPS_PROXY||process.env.https_proxy);
let child=null,published='',failed=0;
function sessionAlive(){return spawnSync('tmux',['has-session','-t',existingSession],{stdio:'ignore'}).status===0;}
function startTunnel(){
 child=spawn('/home/zhanxp/.local/bin/cloudflared',['tunnel','--url','http://127.0.0.1:43132','--no-autoupdate','--protocol','http2'],{stdio:['ignore','pipe','pipe']});
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
 const healthData=await health.json();if(healthData.reviewTaskId!=='agy-exec-stream-20261114'||!health.ok||healthData.status!=='ok'||healthData.mode!=='review'||healthData.reviewCommit!=='5103d08538e74c86d0fd345bede2327c68169e27')throw Error('review identity failed');
 const r=await fetch(base+'/',{agent:agent(),timeout:60000});const html=await r.text();
 const assets=[...html.matchAll(/(?:src|href)="(\/assets\/[^\"]+)"/g)].map(m=>m[1]);
 if(!r.ok||!assets.some(s=>s.endsWith('.js'))||html.includes('@vite/client'))throw Error('production HTML failed');
 for(const path of assets){const a=await fetch(base+path,{agent:agent(),timeout:60000});if(!a.ok)throw Error('asset failed');const bytes=Buffer.from(await a.arrayBuffer());const local=readFileSync('/home/zhanxp/worktrees/tg-agent-gateway/agy-exec-stream-20261114/webapp/dist'+path);const hash=b=>require('node:crypto').createHash('sha256').update(b).digest('hex');if(hash(bytes)!==hash(local))throw Error('asset hash mismatch');}
}
async function publish(base){
 const denied=await fetch(base+'/api/webapp/tasks',{method:'POST',agent:agent(),timeout:30000});if(denied.status!==403)throw Error('write guard failed');
 const noauth=await fetch(base+'/api/webapp/tasks',{agent:agent(),timeout:30000});if(noauth.status!==401)throw Error('auth guard failed');
 const url=base+'/?task=task-20261111-005&commit=5103d08&v='+Date.now();
 const markup={inline_keyboard:[[{text:'打开执行流验收版',web_app:{url}}]]};
 const stateFile='/home/zhanxp/.local/share/tg-gateway-reviews/agy-exec-stream-20261114/telegram-entry.json';
 let prior;try{prior=JSON.parse(readFileSync(stateFile,'utf8'));}catch{}
 let messageId=prior?.messageId;
 if(messageId){await telegram('editMessageReplyMarkup',{chat_id:process.env.ADMIN_USER_ID,message_id:messageId,reply_markup:markup});}
 else {const sent=await telegram('sendMessage',{chat_id:process.env.ADMIN_USER_ID,text:'🧪 执行流独立验收版\n分支：feat/agy-exec-stream-20261114\n基线：5103d08-dirty（包含当前未提交修改）\n更新：执行过程时间线、Agent事件与终端事件流展示、流式连接和任务详情联动。\nverify、前端构建、执行流相关18项测试通过。\n独立历史数据快照/mock/只读；创建、追加及验收写入禁用。真实执行与手机界面待验收。\n请先关闭旧弹窗，再打开此入口。',reply_markup:markup});messageId=sent.result.message_id;}
 const fs=await import('node:fs');fs.writeFileSync(stateFile,JSON.stringify({url,messageId,commit:'5103d08538e74c86d0fd345bede2327c68169e27',dirty:true,mode:'review',updatedAt:new Date().toISOString()},null,2));
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
