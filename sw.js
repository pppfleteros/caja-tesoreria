var CACHE = 'caja-v13';
var ARCHIVOS = ['./', './index.html', './manifest.json', './icon-192.png', './icon-512.png'];

self.addEventListener('install', function (e) {
  e.waitUntil(caches.open(CACHE).then(function (c) { return c.addAll(ARCHIVOS); }));
  self.skipWaiting();
});

self.addEventListener('activate', function (e) {
  e.waitUntil(caches.keys().then(function (keys) {
    return Promise.all(keys.filter(function (k) { return k !== CACHE; }).map(function (k) { return caches.delete(k); }));
  }));
  self.clients.claim();
});

self.addEventListener('fetch', function (e) {
  if (e.request.method !== 'GET') return;

  // Para la página en sí pedimos SIEMPRE al servidor salteando el caché del
  // navegador. Sin esto, una actualización tarda hasta 10 minutos en llegar
  // (GitHub Pages manda la página con 10 min de caché) y los celulares siguen
  // con la versión vieja aunque uno cierre y abra la app.
  var pedido = e.request;
  if (e.request.mode === 'navigate') {
    try { pedido = new Request(e.request.url, { cache: 'reload', credentials: 'same-origin' }); }
    catch (err) { pedido = e.request; }
  }

  e.respondWith(
    fetch(pedido).then(function (r) {
      var copia = r.clone();
      caches.open(CACHE).then(function (c) { c.put(e.request, copia); });
      return r;
    }).catch(function () { return caches.match(e.request); })
  );
});
