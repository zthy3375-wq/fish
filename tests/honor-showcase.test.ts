import {expect,it} from 'vitest';
import {featuredHonor,personalDisplay,publicMedals} from '../src/domain/honorShowcase';
const stamps={welcome:'2026-10-01',profile:'2026-10-03',bath:'2026-10-02',dream:'2026-10-04'};
it('keeps manually picked medals, and otherwise shows up to three actual dated records',()=>{
 expect(personalDisplay(stamps,[],[]).medals.map(m=>m.code)).toEqual(['dream','profile','bath']);
 const pinned=personalDisplay(stamps,['welcome','not-earned'],[]);
 expect(pinned.medals.map(m=>m.code)).toEqual(['welcome']);expect(pinned.latest?.code).toBe('dream');
 expect(pinned.first).toBe(false);expect(personalDisplay({welcome:stamps.welcome},[],[]).first).toBe(true);
 expect(personalDisplay({},[],[]).medals).toEqual([]);
 const verified=personalDisplay({},[],['arrival','dream']);expect(verified.medals.map(m=>m.code)).toEqual(['arrival']);expect(verified.latest).toBeUndefined();
});
it('shows only explicitly public community medals, removes duplicates and caps the list',()=>{
 expect(publicMedals(['dream','profile','grade','arrival','firstpost','arrival','hello','liked']).map(a=>a.code)).toEqual(['arrival','firstpost','hello']);
 expect(publicMedals()).toEqual([]);
});
it('foregrounds a worn title when the official role is already next to the nickname',()=>{
 expect(featuredHonor({worn:{code:'seed',at:null},official:{code:'developer',at:null}})?.code).toBe('seed');
 expect(featuredHonor({official:{code:'moderator',at:null}})?.code).toBe('moderator');expect(featuredHonor({})).toBeUndefined();
});
