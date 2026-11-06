/** Fixed Gradle tasks; no shell interpolation or dependencies. Run via npm scripts after cap sync. */
import {spawnSync} from 'node:child_process';
import {chmodSync} from 'node:fs';
const tasks={check:[':app:testDebugUnitTest',':app:testReleaseUnitTest'],apk:[':app:testDebugUnitTest',':app:assembleDebug']};
const selected=tasks[process.argv[2]];
if(!selected){console.error('Usage: node scripts/android.mjs check|apk');process.exit(2)}
const cwd=new URL('../android/',import.meta.url);
const windows=process.platform==='win32';
if(!windows)chmodSync(new URL('gradlew',cwd),0o755);
const command=windows?'cmd.exe':'./gradlew';
const args=windows?['/d','/s','/c','gradlew.bat','--no-daemon','--console=plain',...selected]:['--no-daemon','--console=plain',...selected];
const result=spawnSync(command,args,{cwd,stdio:'inherit'});
if(result.error)console.error(result.error.message);
process.exit(result.status??1);
