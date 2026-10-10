/* Shared authenticated encryption format. No passwords or plaintext are persisted. */
(() => {
 'use strict';
 const LIMIT=20*1024*1024, ITERATIONS=600000, MAGIC=new TextEncoder().encode('JKDOC001');
 const enc=new TextEncoder(),dec=new TextDecoder(),MIME=new Set(['image/jpeg','image/png','image/webp']);
 async function keyFor(password,salt,usage){
  const base=await crypto.subtle.importKey('raw',enc.encode(password),'PBKDF2',false,['deriveKey']);
  return crypto.subtle.deriveKey({name:'PBKDF2',salt,iterations:ITERATIONS,hash:'SHA-256'},base,{name:'AES-GCM',length:256},false,[usage]);
 }
 async function encrypt(file,password,ledgerId,id){
  const meta=enc.encode(JSON.stringify({name:file.name.slice(0,255),mime:file.type}));
  const bytes=new Uint8Array(await file.arrayBuffer()),plain=new Uint8Array(4+meta.length+bytes.length);
  new DataView(plain.buffer).setUint32(0,meta.length);plain.set(meta,4);plain.set(bytes,4+meta.length);
  const salt=crypto.getRandomValues(new Uint8Array(16)),iv=crypto.getRandomValues(new Uint8Array(12));
  const key=await keyFor(password,salt,'encrypt');
  const cipher=await crypto.subtle.encrypt({name:'AES-GCM',iv,additionalData:enc.encode(ledgerId+'/'+id)},key,plain);
  plain.fill(0);bytes.fill(0);
  return new Blob([MAGIC,salt,iv,cipher],{type:'application/octet-stream'});
 }
 async function decrypt(blob,password,row){
  const bytes=new Uint8Array(await blob.arrayBuffer());
  if(bytes.length<53||bytes.length>LIMIT+4096||MAGIC.some((b,i)=>bytes[i]!==b))throw new Error('지원하지 않는 서류 파일입니다.');
  const key=await keyFor(password,bytes.slice(8,24),'decrypt');
  let plain;
  try{plain=new Uint8Array(await crypto.subtle.decrypt({name:'AES-GCM',iv:bytes.slice(24,36),additionalData:enc.encode(row.ledger_id+'/'+row.id)},key,bytes.slice(36)));}
  catch{throw new Error('서류 비밀번호가 맞지 않거나 파일이 손상되었습니다.');}
  try{
   const n=new DataView(plain.buffer).getUint32(0);
   if(n<1||n>2048||n+4>=plain.length)throw new Error('서류 형식이 올바르지 않습니다.');
   const meta=JSON.parse(dec.decode(plain.slice(4,4+n)));
   if(!MIME.has(meta.mime)||typeof meta.name!=='string')throw new Error('지원하지 않는 서류 형식입니다.');
   return {name:meta.name,blob:new Blob([plain.slice(4+n)],{type:meta.mime})};
  }finally{plain.fill(0);}
 }
 window.jkDocumentCrypto=Object.freeze({encrypt,decrypt});
})();
