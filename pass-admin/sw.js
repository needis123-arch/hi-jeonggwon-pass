const CACHE_NAME='pass-admin-isolated-v1';
const SHELL=['/hi-jeonggwon-pass/pass-admin/','/hi-jeonggwon-pass/pass-admin/manifest.webmanifest','/hi-jeonggwon-pass/pass-admin/icon.svg'];
self.addEventListener('install',e=>e.waitUntil(caches.open(CACHE_NAME).then(c=>c.addAll(SHELL)).catch(()=>{}).then(()=>self.skipWaiting())));
self.addEventListener('activate',e=>e.waitUntil(caches.keys().then(keys=>Promise.all(keys.filter(k=>k.startsWith('pass-admin-isolated-')&&k!==CACHE_NAME).map(k=>caches.delete(k)))).then(()=>self.clients.claim())));
self.addEventListener('fetch',e=>{
 const r=e.request,u=new URL(r.url);
 if(r.method!=='GET'||u.origin!==location.origin||!u.pathname.startsWith('/hi-jeonggwon-pass/pass-admin/'))return;
 e.respondWith(fetch(r).catch(()=>caches.match(r).then(x=>x||caches.match('/hi-jeonggwon-pass/pass-admin/'))));
});