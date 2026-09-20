const OLD_PREFIXES=['jk-business-pwa-','pass-admin-app-'];
self.addEventListener('install',event=>self.skipWaiting());
self.addEventListener('activate',event=>{
  event.waitUntil((async()=>{
    const keys=await caches.keys();
    await Promise.all(keys.filter(k=>OLD_PREFIXES.some(p=>k.startsWith(p))).map(k=>caches.delete(k)));
    await self.registration.unregister();
    const clientsList=await self.clients.matchAll({type:'window',includeUncontrolled:true});
    clientsList.forEach(c=>c.postMessage({type:'root-pwa-cleaned'}));
  })());
});
