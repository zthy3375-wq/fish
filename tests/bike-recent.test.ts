// @vitest-environment jsdom
import {beforeEach,expect,it,vi,afterEach} from 'vitest';
import {chooseBike,lastBikeChoice,saveRecentBike,loadRecentBike,forgetRecentBike,recentBikeLifetime,bikeShortcut} from '../src/services/bike-scan';
beforeEach(()=>{localStorage.clear();vi.useFakeTimers({toFake:['Date']});vi.setSystemTime(1794360000000)});afterEach(()=>vi.useRealTimers());
it('only successful official handoffs create minimal entries without ticket or URL',()=>{
 const r=saveRecentBike('hello','alipay_requested','9150978196');expect(loadRecentBike()).toEqual(r);expect(Object.keys(r!).sort()).toEqual(['number','openedAt','provider','target']);
 for(const status of ['unavailable','blocked','cancelled','link_requested','copied'] as const){expect(saveRecentBike('meituan',status)).toBeUndefined();expect(loadRecentBike()).toEqual(r)}
 expect(saveRecentBike('meituan','alipay_requested')).toBeUndefined();
});
it('invalid, future and expired snapshots are discarded; arbitrary fields are not projected',()=>{
 const good={provider:'hello',target:'alipay',openedAt:Date.now(),number:'9150978196'};
 for(const value of [{...good,provider:'evil'},{...good,openedAt:Date.now()+1},{...good,openedAt:Date.now()-recentBikeLifetime},{...good,number:'https://evil'},{...good,provider:'meituan'},{...good,openedAt:'123'}]){localStorage.setItem('campus-bike-recent-v1',JSON.stringify(value));expect(loadRecentBike()).toBeUndefined();expect(localStorage.getItem('campus-bike-recent-v1')).toBeNull()}
 localStorage.setItem('campus-bike-recent-v1',JSON.stringify({...good,url:'https://evil',ticket:'secret'}));expect(loadRecentBike()).toEqual(good);
});
it('choice persists independently; clear cannot be interpreted as an order action',()=>{
 chooseBike('meituan');saveRecentBike('meituan','scanner_requested');forgetRecentBike();expect(loadRecentBike()).toBeUndefined();expect(lastBikeChoice()).toBe('meituan');
 localStorage.setItem('campus-bike-choice-v1','"invalid"');expect(lastBikeChoice()).toBe('hello');
});
it('unavailable storage never blocks the official entry flow',()=>{
 const spy=vi.spyOn(Storage.prototype,'setItem').mockImplementation(()=>{throw Error('disk')});expect(()=>chooseBike('hello')).not.toThrow();expect(saveRecentBike('hello','scanner_requested')).toBeDefined();spy.mockRestore();
});
it('web cannot dispatch official shortcuts',async()=>{await expect(bikeShortcut('meituan','scanner')).rejects.toThrow('UNSUPPORTED')});
