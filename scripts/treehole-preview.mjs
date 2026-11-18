/** Offline review artifact built from the real Vue community components. No live service. */
import {build} from 'vite';
import vue from '@vitejs/plugin-vue';
import {readFile,writeFile,mkdir,mkdtemp,rm} from 'node:fs/promises';
import path from 'node:path';
import os from 'node:os';
import {adapter} from '../tests/fixtures/treehole/preview-adapter.mjs';
const output=path.resolve(process.argv[2]||'/tmp/hyt-community-preview.html');
const temp=await mkdtemp(path.join(os.tmpdir(),'hyt-preview-'));
const entry=path.join(process.cwd(),'node_modules/.hyt-community-preview.js');

try{
 await writeFile(entry,"import {createApp} from 'vue';import Treehole from '../src/components/Treehole.vue';import '../src/style.css';createApp(Treehole).mount('#app');");
 const result=await build({configFile:false,plugins:[vue()],define:{'process.env.NODE_ENV':'"production"'},build:{write:false,target:'es2020',lib:{entry,name:'HytCommunity',formats:['iife']},cssCodeSplit:false,rollupOptions:{output:{inlineDynamicImports:true}}}});
 const assets=Array.isArray(result)?result.flatMap(r=>r.output):result.output;
 const js=assets.filter(a=>a.type==='chunk').map(a=>a.code).join('\n');const css=assets.filter(a=>a.type==='asset'&&a.fileName.endsWith('.css')).map(a=>a.source).join('\n');
 const campus='data:image/webp;base64,'+(await readFile('public/art/campus-autumn.webp')).toString('base64');
 const html=`<!doctype html><html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover"><meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; img-src data: blob:; font-src data:; connect-src 'none'"><title>邯院通 · 社区交互预览</title><style>${css}</style><style>body{background:#edf0f4}.preview-note{max-width:430px;margin:auto;padding:9px 18px;background:#eeeaf7;color:#69548a;font:12px/1.5 sans-serif;display:flex;justify-content:space-between}.treehole,.th-readbar{max-width:430px!important}.th-fab{right:max(20px,calc((100vw - 390px)/2))!important}.th-dialog{max-width:430px!important}.th-dialog.th-gallery{max-width:none!important}@media(min-width:700px){.preview-note{margin-top:24px;border-radius:18px 18px 0 0}.treehole{box-shadow:0 12px 60px #29344414}.th-nav{border-inline:1px solid #f0f1f3}}</style></head><body><div class="preview-note"><strong>邯院通 · 交互预览</strong><span>演示内容 · 不会发布</span></div><div id="app"></div><script>(${adapter.toString()})(${JSON.stringify(campus)});</script><script>${js.replace(/<\/script/gi,'<\\/script')}</script></body></html>`;
 await mkdir(path.dirname(output),{recursive:true});await writeFile(output,html);console.log(JSON.stringify({output,bytes:Buffer.byteLength(html)}));
}finally{await rm(entry,{force:true});await rm(temp,{recursive:true,force:true});}
