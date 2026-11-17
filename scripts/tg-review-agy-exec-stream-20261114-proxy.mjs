import http from 'node:http';
import fs from 'node:fs';
import { gzip } from 'node:zlib';
const server=http.createServer((req,res)=>{
 if(req.method==='GET' && /^\/assets\/[A-Za-z0-9_.-]+(?:\?.*)?$/.test(req.url||'')){
  const pathname=new URL(req.url,'http://127.0.0.1').pathname;
  const file='/home/zhanxp/worktrees/tg-agent-gateway/agy-exec-stream-20261114/webapp/dist'+pathname;
  if(!fs.existsSync(file)){res.writeHead(404);res.end();return;}
  const raw=fs.readFileSync(file),headers={'content-type':pathname.endsWith('.js')?'application/javascript':'text/css','cache-control':'no-store'};
  if(/gzip/.test(req.headers['accept-encoding']||''))gzip(raw,(error,body)=>{if(error){res.writeHead(502);res.end();return;}res.writeHead(200,{...headers,'content-encoding':'gzip','content-length':String(body.length),vary:'Accept-Encoding'});res.end(body);});
  else {res.writeHead(200,{...headers,'content-length':String(raw.length)});res.end(raw);}
  return;
 }

 const upstream=http.request({host:'127.0.0.1',port:43131,path:req.url,method:req.method,headers:{...req.headers,'accept-encoding':'identity'}},reply=>{
  const compress=req.method==='GET' && (/text\/html|application\/json/.test(String(reply.headers['content-type']||''))) && reply.statusCode===200 && /gzip/.test(req.headers['accept-encoding']||'');
  if(!compress){res.writeHead(reply.statusCode||502,reply.headers);reply.pipe(res);return;}
  const chunks=[];reply.on('data',chunk=>chunks.push(chunk));
  reply.on('end',()=>gzip(Buffer.concat(chunks),(error,body)=>{
   if(error){res.writeHead(502);res.end();return;}
   const headers={...reply.headers,'content-encoding':'gzip','content-length':String(body.length),vary:'Accept-Encoding'};delete headers['transfer-encoding'];
   res.writeHead(200,headers);res.end(body);
  }));reply.on('error',()=>res.destroy());
 });
 upstream.on('error',()=>{if(!res.headersSent)res.writeHead(502);res.end();});
 req.pipe(upstream);req.on('aborted',()=>upstream.destroy());
});
server.listen(43132,'127.0.0.1',()=>console.log('Recovery compression proxy listening on 127.0.0.1:43132'));
