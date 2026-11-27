import {fileURLToPath,URL} from 'node:url';
import vue from '@vitejs/plugin-vue';
import {defineConfig} from 'vite';
export default defineConfig({
 root:fileURLToPath(new URL('.',import.meta.url)),
 envDir:fileURLToPath(new URL('..',import.meta.url)),
 base:'./',plugins:[vue()],
 build:{outDir:fileURLToPath(new URL('../dist-merchant',import.meta.url)),emptyOutDir:true},
});
