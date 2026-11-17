import { createRequire } from 'node:module';
import { readFileSync, appendFileSync } from 'node:fs';
import { spawn, spawnSync } from 'node:child_process';
const require = createRequire('/home/zhanxp/projects/tg-agent-gateway/package.json');
const fetch = require('node-fetch');
const { HttpsProxyAgent } = require('https-proxy-agent');
require('dotenv').config({path:'/home/zhanxp/projects/tg-agent-gateway/.env'});
const logfile='/tmp/tg-app-localhostrun-20261112.log';
const existingSession='tg-app-localhostrun-20261112';
const sleep=ms=>new Promise(r=>setTimeout(r,ms));
const log=s=>console.log(new Date().toISOString(),s);
const agent=()=>new HttpsProxyAgent(process.env.HTTPS_PROXY||process.env.https_proxy);
let child=null,published='',failed=0;
function sessionAlive(){return spawnSync('tmux',['has-session','-t',existingSession],{stdio:'ignore'}).status===0;}
function startTunnel(){
 const args=['-o','ProxyCommand=nc -X connect -x 172.31.112.1:4077 %h %p','-o','StrictHostKeyChecking=accept-new','-o','ServerAliveInterval=15','-o','ServerAliveCountMax=3','-o','ExitOnForwardFailure=yes','-T','-R','80:127.0.0.1:3007','nokey@localhost.run'];
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
 if(!health.ok||(await health.json()).status!=='ok')throw Error('health failed');
 const r=await fetch(base+'/',{agent:agent(),timeout:60000});const html=await r.text();
 const assets=[...html.matchAll(/(?:src|href)="(\/assets\/[^\"]+)"/g)].map(m=>m[1]);
 if(!r.ok||!assets.some(s=>s.endsWith('.js'))||html.includes('@vite/client'))throw Error('production HTML failed');
 for(const path of assets){const a=await fetch(base+path,{agent:agent(),timeout:60000});if(!a.ok)throw Error('asset failed');await a.arrayBuffer();}
}
async function publish(base){
 const url=base+'/?v='+Date.now();
 const menu={type:'web_app',text:'打开控制台',web_app:{url}};
 await telegram('setChatMenuButton',{menu_button:menu});
 await telegram('setChatMenuButton',{chat_id:Number(process.env.ADMIN_USER_ID),menu_button:menu});
 const sent=await telegram('sendMessage',{chat_id:process.env.ADMIN_USER_ID,text:'Mini App 备用入口已更新。请先关闭旧弹窗，再点击下面的新按钮。此通道已启用自动重连和菜单更新；临时域名仍可能变化。',reply_markup:{inline_keyboard:[[{text:'打开当前控制台',web_app:{url}}]]}});
 const current=await telegram('getChatMenuButton',{chat_id:Number(process.env.ADMIN_USER_ID)});
 if(current.result?.web_app?.url!==url)throw Error('menu readback mismatch');
 log('published '+base+' messageId='+sent.result.message_id);
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
