/** Prepare a public release channel. Sign/verify the APK before running this script. */
import {readFile,mkdir,writeFile,copyFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import path from 'node:path';
const [apk,codeText,name,minimumText,output,...notes]=process.argv.slice(2);
const code=Number(codeText),minimum=Number(minimumText);
if(!apk||!output||!/^\d+\.\d+\.\d+$/.test(name??'')||!Number.isSafeInteger(code)||code<1||code>2147483647||!Number.isSafeInteger(minimum)||minimum<1||minimum>code||notes.length>20||notes.some(n=>n.length>500))throw Error('Usage: node scripts/prepare-update.mjs signed.apk versionCode versionName minimumSupportedCode /path/to/site/dist "更新说明"');
const bytes=await readFile(apk);if(bytes.length<4||bytes.length>80*1024*1024||bytes.readUInt32LE(0)!==0x04034b50)throw Error('Expected a signed APK, <=80 MiB');
const directory=path.join(output,'android'),filename=`Hanyuantong-v${name}.apk`;
await mkdir(directory,{recursive:true});
const dest=path.join(directory,filename);const sha256=createHash('sha256').update(bytes).digest('hex');
try{const old=await readFile(dest);if(createHash('sha256').update(old).digest('hex')!==sha256)throw Error('Do not overwrite an existing released version with different bytes')}catch(e){if(e.code!=='ENOENT')throw e}
await copyFile(apk,dest);
const release={schema:1,versionCode:code,versionName:name,minSupportedVersionCode:minimum,minSdk:23,apkUrl:`https://hanyuantong-updates.dewydahlia.chatgpt.site/android/${filename}`,sha256,sizeBytes:bytes.length,notes};
await writeFile(path.join(directory,'stable.json'),JSON.stringify(release,null,2)+'\n');console.log(`Prepared ${name}; versions below ${minimum} require an update. Publish the Site to make this live.`);
