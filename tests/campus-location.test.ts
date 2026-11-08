import {expect,it} from 'vitest';
import {validCampusFix} from '../src/services/campus-location';
it('rejects stale, implausible and invalid location fixes',()=>{
 const now=1700000000000,fix={latitude:36.57,longitude:114.50,accuracy:25,timestamp:now};
 expect(validCampusFix(fix,now)).toBe(true);
 for(const change of [{accuracy:0},{accuracy:NaN},{latitude:91},{longitude:181},{timestamp:now-60001},{timestamp:now+6000}])expect(validCampusFix({...fix,...change},now)).toBe(false);
});
