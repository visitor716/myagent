import http from 'node:http';
import { gzip } from 'node:zlib';
const server=http.createServer((req,res)=>{
 if(req.method==='GET' && /^\/assets\//.test(req.url||'')){res.writeHead(302,{location:'https://cc4-e757c34.tg-agent-gateway-webapp.pages.dev'+req.url,'access-control-allow-origin':'*','cache-control':'no-store'});res.end();return;}

 const upstream=http.request({host:'127.0.0.1',port:43009,path:req.url,method:req.method,headers:{...req.headers,'accept-encoding':'identity'}},reply=>{
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
server.listen(43010,'127.0.0.1',()=>console.log('Recovery compression proxy listening on 127.0.0.1:43010'));
