// Export the exact Android product catalog. Native artwork stays in Swift.
import {build} from 'esbuild';
import {writeFileSync, readFileSync} from 'node:fs';
import {createRequire} from 'node:module';
import {resolve} from 'node:path';
const require = createRequire(import.meta.url);
const result = await build({stdin:{contents:"export {catalog} from './src/domain/globalAchievements'",resolveDir:process.cwd()}, bundle:true,write:false,format:'cjs',platform:'node',external:['vue','lucide-vue-next']});
const mod={exports:{}};
new Function('module','exports','require',result.outputFiles[0].text)(mod,mod.exports,require);
const json=JSON.stringify(mod.exports.catalog.map(({icon,...medal})=>medal),null,2)+'\n';
const target=resolve('ios-native/Hanyuantong/Resources/medals.json');
if(process.argv.includes('--check')){if(readFileSync(target,'utf8')!==json)throw new Error('Native catalog differs from Android');}
else writeFileSync(target,json);
