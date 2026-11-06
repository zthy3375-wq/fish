import {defineConfig, type Plugin} from 'vite';
import vue from '@vitejs/plugin-vue';
import {createHash} from 'node:crypto';

// GitHub Pages project sites live below /<repository>/; other static hosts use /.
const base = process.env.GITHUB_PAGES === 'true' ? '/fish/' : '/';

function offline(): Plugin {
  return {
    name: 'campus-offline',
    generateBundle(_, bundle) {
      const paths = [
        '',
        'index.html',
        'icon.svg',
        'icon-192.png',
        'icon-512.png',
        'manifest.webmanifest',
        ...Object.keys(bundle),
      ];
      const files = [...new Set(paths.map(path => base + path))];
      const version = createHash('sha256')
        .update(JSON.stringify(Object.keys(bundle)))
        .digest('hex')
        .slice(0, 12);

      const source = `
const BASE = ${JSON.stringify(base)};
const CACHE = ${JSON.stringify('handan-' + version)};
const FILES = ${JSON.stringify(files)};
self.addEventListener('install', event => {
  event.waitUntil(
    caches.open(CACHE)
      .then(cache => cache.addAll(FILES))
      .then(() => self.skipWaiting())
  );
});
self.addEventListener('activate', event => {
  event.waitUntil(
    caches.keys()
      .then(keys => Promise.all(
        keys.filter(key => key.startsWith('handan-') && key !== CACHE)
          .map(key => caches.delete(key))
      ))
      .then(() => self.clients.claim())
  );
});
self.addEventListener('fetch', event => {
  const request = event.request;
  const url = new URL(request.url);
  if (request.method !== 'GET' || url.origin !== self.location.origin) return;
  if (request.mode === 'navigate' && url.pathname.startsWith(BASE)) {
    event.respondWith(fetch(request).catch(() => caches.match(BASE + 'index.html')));
    return;
  }
  if (FILES.includes(url.pathname)) {
    event.respondWith(caches.match(request).then(cached => cached || fetch(request)));
  }
});
`;
      this.emitFile({type: 'asset', fileName: 'sw.js', source});
    },
  };
}

export default defineConfig({
  base,
  plugins: [vue(), offline()],
  server: {allowedHosts: true},
  build: {target: 'es2020'},
});
