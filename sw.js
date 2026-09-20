const CACHE_NAME='jk-business-pwa-v2';
const BUSINESS_PATH='/hi-jeonggwon-pass/business-center.html';
const APP_SHELL=[
  BUSINESS_PATH,
  '/hi-jeonggwon-pass/manifest.webmanifest',
  '/hi-jeonggwon-pass/app-icon.svg'
];

self.addEventListener('install',event=>{
  event.waitUntil(
    caches.open(CACHE_NAME)
      .then(cache=>cache.addAll(APP_SHELL))
      .catch(()=>{})
      .then(()=>self.skipWaiting())
  );
});

self.addEventListener('activate',event=>{
  event.waitUntil(
    caches.keys()
      .then(keys=>Promise.all(
        keys.filter(k=>k.startsWith('jk-business-pwa-')&&k!==CACHE_NAME).map(k=>caches.delete(k))
      ))
      .then(()=>self.clients.claim())
  );
});

self.addEventListener('fetch',event=>{
  const req=event.request;
  if(req.method!=='GET') return;
  const url=new URL(req.url);
  if(url.origin!==self.location.origin) return;

  const isBusinessNav=req.mode==='navigate' && url.pathname===BUSINESS_PATH;
  if(isBusinessNav){
    event.respondWith(
      fetch(req)
        .then(res=>{
          const copy=res.clone();
          caches.open(CACHE_NAME).then(cache=>cache.put(BUSINESS_PATH,copy)).catch(()=>{});
          return res;
        })
        .catch(()=>caches.match(BUSINESS_PATH))
    );
    return;
  }

  const isBusinessAsset=
    url.pathname.endsWith('/manifest.webmanifest') ||
    url.pathname.endsWith('/app-icon.svg');

  if(isBusinessAsset){
    event.respondWith(
      fetch(req)
        .then(res=>{
          const copy=res.clone();
          caches.open(CACHE_NAME).then(cache=>cache.put(req,copy)).catch(()=>{});
          return res;
        })
        .catch(()=>caches.match(req))
    );
  }
});