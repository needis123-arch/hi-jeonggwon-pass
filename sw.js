const CACHE_NAME='jk-business-pwa-v1';
const APP_SHELL=[
  '/hi-jeonggwon-pass/business-center.html',
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
      .then(keys=>Promise.all(keys.filter(k=>k!==CACHE_NAME).map(k=>caches.delete(k))))
      .then(()=>self.clients.claim())
  );
});

self.addEventListener('fetch',event=>{
  const req=event.request;
  if(req.method!=='GET')return;
  const url=new URL(req.url);
  if(url.origin!==self.location.origin)return;

  if(req.mode==='navigate'){
    event.respondWith(
      fetch(req)
        .then(res=>{
          const copy=res.clone();
          caches.open(CACHE_NAME).then(cache=>cache.put('/hi-jeonggwon-pass/business-center.html',copy)).catch(()=>{});
          return res;
        })
        .catch(()=>caches.match('/hi-jeonggwon-pass/business-center.html'))
    );
    return;
  }

  if(url.pathname.endsWith('/manifest.webmanifest')||url.pathname.endsWith('/app-icon.svg')){
    event.respondWith(
      caches.match(req).then(cached=>{
        const fresh=fetch(req).then(res=>{
          const copy=res.clone();
          caches.open(CACHE_NAME).then(cache=>cache.put(req,copy)).catch(()=>{});
          return res;
        }).catch(()=>cached);
        return cached||fresh;
      })
    );
  }
});