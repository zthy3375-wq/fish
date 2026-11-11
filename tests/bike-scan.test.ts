import {expect,it} from 'vitest';
import {validateBike,bikeErrorMessage,bikeStatusMessage} from '../src/services/bike-scan';
it('public scan projection excludes URLs and accepts only the two known brands and a complete number',()=>{
 const v={provider:'hello',number:'9150978196',ticket:'11111111-1111-4111-8111-111111111111'};
 expect(validateBike({...v,url:'https://evil.test'})).toEqual(v);
 for(const x of [{...v,provider:'other'},{...v,number:'915'},{...v,ticket:'https://evil.test'}])expect(()=>validateBike(x)).toThrow();
});
it('transport details never become user-facing error text',()=>{
 expect(bikeErrorMessage({code:'PRIVATE',message:'secret token'})).not.toContain('secret');
 expect(bikeErrorMessage({code:'STALE'})).toContain('重新扫码');
 expect(bikeStatusMessage('link_requested')).toContain('可能进入官方网页或下载页');
});
