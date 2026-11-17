import {createRequire} from 'node:module';
import fs from 'node:fs';
import http from 'node:http';
import {gzipSync} from 'node:zlib';
import {execFileSync} from 'node:child_process';
const require=createRequire('/home/zhanxp/projects/tg-agent-gateway/package.json');
const cfg=require('dotenv').parse(fs.readFileSync('/home/zhanxp/projects/tg-agent-gateway/.env'));
process.env.MANAGER_BOT_TOKEN=cfg.MANAGER_BOT_TOKEN;
process.env.ADMIN_USER_ID=cfg.ADMIN_USER_ID;
process.env.DOTENV_CONFIG_PATH='/dev/null';
const root='/home/zhanxp/worktrees/tg-agent-gateway/cx4';
const sha=execFileSync('git',['-C',root,'rev-parse','--short=7','HEAD'],{encoding:'utf8'}).trim();
const {startEntryProxy}=await import(root+'/dist/services/reviewPreview/entryProxy.js');
await startEntryProxy({port:43013,candidatePort:43011,pagesBaseUrl:'https://cx4-'+sha+'.tg-agent-gateway-webapp.pages.dev',proxySecret:fs.readFileSync('/home/zhanxp/.local/share/tg-gateway-reviews/cx4-auto-preview/proxy-secret','utf8')});
console.log('Isolated review entry proxy ready on 43012');

http.createServer((req,res)=>{
 const pathname=new URL(req.url||'/', 'http://127.0.0.1').pathname;
 if(/^\/assets\/[A-Za-z0-9_.-]+$/.test(pathname)){
  const file=root+'/webapp/dist'+pathname;
  if(!fs.existsSync(file)){res.writeHead(404);res.end();return;}
  const raw=fs.readFileSync(file),compress=/gzip/.test(req.headers['accept-encoding']||'');
  const body=compress?gzipSync(raw):raw;
  res.writeHead(200,{'content-type':pathname.endsWith('.js')?'application/javascript':'text/css','cache-control':'no-store','content-length':String(body.length),...(compress?{'content-encoding':'gzip',vary:'Accept-Encoding'}:{})});res.end(body);return;
 }
 const upstream=http.request({host:'127.0.0.1',port:43013,path:req.url,method:req.method,headers:req.headers},reply=>{res.writeHead(reply.statusCode||502,reply.headers);reply.pipe(res);});
 upstream.on('error',()=>{if(!res.headersSent)res.writeHead(502);res.end();});req.pipe(upstream);
}).listen(43012,'127.0.0.1');
