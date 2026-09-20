const CACHE_NAME='jk-business-isolated-v1';
const SHELL=['/hi-jeonggwon-pass/business-app/','/hi-jeonggwon-pass/business-app/manifest.webmanifest'];
self.addEventListener('install',e=>e.waitUntil(caches.open(CACHE_NAME).then(c=>c.addAll(SHELL)).catch(()=>{}).then(()=>self.skipWaiting())));
self.addEventListener('activate',e=>e.waitUntil(caches.keys().then(keys=>Promise.all(keys.filter(k=>k.startsWith('jk-business-isolated-')&&k!==CACHE_NAME).map(k=>caches.delete(k)))).then(()=>self.clients.claim())));
self.addEventListener('fetch',e=>{
 const r=e.request,u=new URL(r.url);
 if(r.method!=='GET'||u.origin!==location.origin||!u.pathname.startsWith('/hi-jeonggwon-pass/business-app/'))return;
 e.respondWith(fetch(r).catch(()=>caches.match(r).then(x=>x||caches.match('/hi-jeonggwon-pass/business-app/'))));
});