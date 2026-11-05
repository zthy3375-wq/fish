import { defineConfig } from 'vite';
import vue from '@vitejs/plugin-vue';
export default defineConfig({ plugins: [vue()], server: { allowedHosts: true }, build: { target: 'es2020' } });
