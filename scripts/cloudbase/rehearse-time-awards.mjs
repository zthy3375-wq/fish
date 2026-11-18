import {readFile} from 'node:fs/promises';
import assert from 'node:assert/strict';
import {createCommunity} from '../../cloudbase/functions/community/core.mjs';
import {PGlite} from '@electric-sql/pglite';
import {timeAwardMigration} from './time-award-migration.mjs';
const old=await readFile(process.argv[2],'utf8'),current=await readFile('cloudbase/community-schema.sql','utf8');
const sql=timeAwardMigration(old,current),db=new PGlite();
try{
 await db.exec(old);
 const state=async()=>(await db.query("select oid,proowner,proacl from pg_proc where oid in ('hyt_community(text,jsonb,text)'::regprocedure,'hyt_hall(hyt_members,uuid)'::regprocedure) order by oid")).rows;
 const before=await state();
 const api=createCommunity({registrationEnabled:true,db:async(a,b,t)=>(await db.query('select hyt_community($1,$2,$3) as r',[a,b,t])).rows[0].r});
 const fixture=await api.execute('register',{username:'fixture123',password:'test-only-password',agreed:true},'','fixture');
 assert.ok(fixture.user.id);
 const rows=async()=>(await db.query('select to_jsonb(m) as member from hyt_members m order by id')).rows;
 const originals=await rows();
 await db.exec(sql);await db.exec(sql);
 assert.deepEqual(await state(),before);
 assert.deepEqual(await rows(),originals);
 console.log('PASS exact old schema migrates twice, with stable grants, function OIDs and member count');
}finally{await db.close();}
