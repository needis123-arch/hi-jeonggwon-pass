const CACHE_NAME='pass-admin-app-v1';
const SHELL=['./app.html','./manifest.webmanifest','./pass-admin-icon.svg'];
self.addEventListener('install',e=>{
 e.waitUntil(caches.open(CACHE_NAME).then(c=>c.addAll(SHELL)).catch(()=>{}));
 self.skipWaiting();
});
self.addEventListener('activate',e=>{
 e.waitUntil(caches.keys().then(keys=>Promise.all(keys.filter(k=>k!==CACHE_NAME).map(k=>caches.delete(k)))));
 self.clients.claim();
});
self.addEventListener('fetch',e=>{
 if(e.request.method!=='GET') return;
 const u=new URL(e.request.url);
 if(u.origin!==self.location.origin) return;
 e.respondWith(fetch(e.request).then(r=>{
   const copy=r.clone();
   caches.open(CACHE_NAME).then(c=>c.put(e.request,copy)).catch(()=>{});
   return r;
 }).catch(()=>caches.match(e.request)));
});