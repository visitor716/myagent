import { createRequire } from 'node:module';
import { readFileSync, appendFileSync } from 'node:fs';
import { spawn, spawnSync } from 'node:child_process';
const require = createRequire('/home/zhanxp/projects/tg-agent-gateway/package.json');
const fetch = require('node-fetch');
const { HttpsProxyAgent } = require('https-proxy-agent');
require('dotenv').config({path:'/home/zhanxp/projects/tg-agent-gateway/.env'});
const logfile='/tmp/tg-master-agy-20261114/tunnel.log';
const existingSession='tg-master-agy-20261114-tunnel';
const sleep=ms=>new Promise(r=>setTimeout(r,ms));
const log=s=>console.log(new Date().toISOString(),s);
const agent=()=>new HttpsProxyAgent(process.env.HTTPS_PROXY||process.env.https_proxy);
let child=null,published='',failed=0;
function sessionAlive(){return spawnSync('tmux',['has-session','-t',existingSession],{stdio:'ignore'}).status===0;}
function startTunnel(){
 child=spawn('/home/zhanxp/.local/bin/cloudflared',['tunnel','--url','http://127.0.0.1:3007','--no-autoupdate','--protocol','http2'],{stdio:['ignore','pipe','pipe']});
 for(const stream of [child.stdout,child.stderr])stream.on('data',b=>appendFileSync(logfile,b));
 child.on('error',()=>log('ssh spawn error'));
 child.on('exit',code=>{log('ssh exit '+code);child=null;});
 log('started production Cloudflare tunnel');
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
 const identity=await health.json();if(!health.ok||identity.status!=='ok'||identity.mode!=='gateway')throw Error('health failed');
 const r=await fetch(base+'/',{agent:agent(),timeout:60000});const html=await r.text();
 const assets=[...html.matchAll(/(?:src|href)="(\/assets\/[^\"]+)"/g)].map(m=>m[1]);
 if(!r.ok||!assets.some(s=>s.endsWith('.js'))||html.includes('@vite/client'))throw Error('production HTML failed');
 for(const path of assets){const a=await fetch(base+path,{agent:agent(),timeout:60000});if(!a.ok)throw Error('asset failed');const bytes=Buffer.from(await a.arrayBuffer());const local=readFileSync('/home/zhanxp/projects/tg-agent-gateway-production/webapp/dist'+path);const hash=b=>require('node:crypto').createHash('sha256').update(b).digest('hex');if(hash(bytes)!==hash(local))throw Error('asset hash mismatch');}
}
async function publish(base){
 const url=base+'/?v='+Date.now();
 const menu={type:'web_app',text:'打开控制台',web_app:{url}};
 await telegram('setChatMenuButton',{menu_button:menu});
 await telegram('setChatMenuButton',{chat_id:Number(process.env.ADMIN_USER_ID),menu_button:menu});
 const sent=await telegram('sendMessage',{chat_id:process.env.ADMIN_USER_ID,text:'任务详情修复已合并到 master 并推送。\n版本：v1.0.152\nCommit：'+spawnSync('git',['-C','/home/zhanxp/projects/tg-agent-gateway-production','rev-parse','--short','HEAD'],{encoding:'utf8'}).stdout.trim()+'\n更新：修复浅底白字与摘要留白，保留长标题、Agent选择和键盘跟随；补修真实失败显示及风险合并。\n自动发布仍关闭。请先关闭旧弹窗，再点击此正式入口。',reply_markup:{inline_keyboard:[[{text:'打开当前控制台',web_app:{url}}]]}});
 const current=await telegram('getChatMenuButton',{chat_id:Number(process.env.ADMIN_USER_ID)});
 if(current.result?.web_app?.url!==url)throw Error('menu readback mismatch');
 require('node:fs').writeFileSync('/tmp/tg-master-agy-20261114/release.json',JSON.stringify({url,messageId:sent.result.message_id,updatedAt:new Date().toISOString()},null,2));
 log('published '+base+' messageId='+sent.result.message_id);
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
