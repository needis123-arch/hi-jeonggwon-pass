const CACHE_NAME='pass-admin-pwa-v2';
const APP_SHELL=[
  '/hi-jeonggwon-pass/pass-admin/',
  '/hi-jeonggwon-pass/pass-admin/manifest.webmanifest',
  '/hi-jeonggwon-pass/pass-admin/icon.svg'
];
self.addEventListener('install',event=>{
  event.waitUntil(caches.open(CACHE_NAME).then(c=>c.addAll(APP_SHELL)).catch(()=>{}).then(()=>self.skipWaiting()));
});
self.addEventListener('activate',event=>{
  event.waitUntil(
    caches.keys().then(keys=>Promise.all(
      keys.filter(k=>k.startsWith('pass-admin-pwa-')&&k!==CACHE_NAME).map(k=>caches.delete(k))
    )).then(()=>self.clients.claim())
  );
});
self.addEventListener('fetch',event=>{
  const req=event.request;
  if(req.method!=='GET')return;
  const url=new URL(req.url);
  if(url.origin!==self.location.origin)return;
  if(!url.pathname.startsWith('/hi-jeonggwon-pass/pass-admin/'))return;
  if(req.mode==='navigate'){
    event.respondWith(fetch(req).catch(()=>caches.match('/hi-jeonggwon-pass/pass-admin/')));
    return;
  }
  event.respondWith(fetch(req).then(res=>{
    const copy=res.clone();
    caches.open(CACHE_NAME).then(c=>c.put(req,copy)).catch(()=>{});
    return res;
  }).catch(()=>caches.match(req)));
});