const {createRequire}=require('node:module');
const requireRepo=createRequire('/home/zhanxp/projects/tg-agent-gateway/package.json');
const fs=require('node:fs');
const crypto=require('node:crypto');
const fetch=requireRepo('node-fetch');
const {HttpsProxyAgent}=requireRepo('https-proxy-agent');
requireRepo('dotenv').config({path:'/home/zhanxp/projects/tg-agent-gateway/.env',quiet:true});
const agent=new HttpsProxyAgent(process.env.HTTPS_PROXY||process.env.https_proxy||'http://172.31.112.1:4065');
const state=JSON.parse(fs.readFileSync('/tmp/tg-master-agy-20261114/release.json','utf8'));
const base=new URL(state.url).origin;
async function get(path){return fetch(base+path,{agent,timeout:30000});}
async function tg(method,body){const r=await fetch('https://api.telegram.org/bot'+process.env.MANAGER_BOT_TOKEN+'/'+method,{agent,timeout:30000,method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify(body)});const d=await r.json();if(!d.ok)throw Error(d.description);return d.result;}
(async()=>{
const health=await get('/health');if(!health.ok)throw Error('health failed');const h=await health.json();if(h.status!=='ok')throw Error('health identity failed');
const page=await get('/');const html=await page.text();if(!page.ok)throw Error('HTML failed');
const local=fs.readFileSync('/home/zhanxp/projects/tg-agent-gateway-production/webapp/dist/index.html','utf8');
const paths=[...html.matchAll(/(?:src|href)="(\/assets\/[^\"]+)"/g)].map(m=>m[1]);
if(!paths.length||!paths.every(p=>local.includes(p)))throw Error('stale HTML');
for(const p of paths){const r=await get(p);const bytes=await r.buffer();const disk=fs.readFileSync('/home/zhanxp/projects/tg-agent-gateway-production/webapp/dist'+p);const hash=b=>crypto.createHash('sha256').update(b).digest('hex');if(!r.ok||hash(bytes)!==hash(disk))throw Error('asset mismatch '+p);}
const unauth=await get('/api/webapp/tasks');if(unauth.status!==401)throw Error('unexpected unauth status '+unauth.status);
const commit=require('node:child_process').execFileSync('git',['-C','/home/zhanxp/projects/tg-agent-gateway-production','rev-parse','--short','HEAD'],{encoding:'utf8'}).trim();
const url=base+'/?commit='+commit+'&v='+Date.now();
const menu={type:'web_app',text:'打开控制台',web_app:{url}};
await tg('setChatMenuButton',{menu_button:menu});await tg('setChatMenuButton',{chat_id:Number(process.env.ADMIN_USER_ID),menu_button:menu});
const sent=await tg('sendMessage',{chat_id:process.env.ADMIN_USER_ID,text:'新版任务详情页已发布\n版本：v1.0.152\n分支：master\n提交：'+commit+'\n部署时间：'+new Date().toLocaleString('zh-CN',{timeZone:'Asia/Shanghai',hour12:false})+'\n更新内容：T3 风格对话流、折叠执行记录、底部常驻输入区，保留 Agent 选择与附件。\n请先关闭旧 Mini App，再点击下方新入口。',reply_markup:{inline_keyboard:[[{text:'打开新版任务详情',web_app:{url}}],[{text:'浏览器打开',url}]]}});
const readback=await tg('getChatMenuButton',{chat_id:Number(process.env.ADMIN_USER_ID)});if(readback.web_app?.url!==url)throw Error('menu readback mismatch');
fs.writeFileSync('/tmp/tg-master-agy-20261114/t3-release.json',JSON.stringify({url,commit,messageId:sent.message_id,assets:paths,updatedAt:new Date().toISOString()},null,2));
console.log(JSON.stringify({ok:true,commit,messageId:sent.message_id,url,assetsVerified:paths.length,unauth:unauth.status}));
})().catch(e=>{console.error(e.message);process.exitCode=1});
