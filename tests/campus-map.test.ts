// @vitest-environment jsdom
import {beforeEach,expect,it} from 'vitest';
import {validPlace,readMapData,saveMapData,filterPlaces,navigationUrl,type CampusPlace} from '../src/services/campus-map';
const point:CampusPlace={id:'synthetic-1',name:'测试饮水机',campus:'east',lat:36.576,lng:114.504,category:'life',source:'personal',note:'一层'};
beforeEach(()=>localStorage.clear());
it('validates school bounds and imported types',()=>{expect(validPlace(point)).toBe(true);for(const change of [{lat:NaN},{lat:0},{lng:0},{name:''},{campus:'__proto__'},{category:'constructor'},{source:'osm'}])expect(validPlace({...point,...change})).toBe(false)});
it('preserves separate map storage and favorites',()=>{localStorage.setItem('handan.personal.tasks.v2','keep');saveMapData([point],[point.id,point.id]);expect(readMapData()).toEqual({places:[point],favorites:[point.id]});expect(localStorage.getItem('handan.personal.tasks.v2')).toBe('keep')});
it('does not replace stored points when invalid data is saved',()=>{saveMapData([point],[]);expect(()=>saveMapData([{...point,lat:0}],[])).toThrow();expect(readMapData().places).toEqual([point])});
it('tolerates corrupt persisted content',()=>{localStorage.setItem('handan-campus-map-v083','{');expect(readMapData()).toEqual({places:[],favorites:[]})});
it('filters by campus, category, favorites and notes',()=>{const all=[point,{...point,id:'second',campus:'west' as const}];expect(filterPlaces(all,'east','一层','life')).toEqual([point]);expect(filterPlaces(all,'east','','favorite',[])).toEqual([]);expect(filterPlaces(all,'east','','favorite',[point.id])).toEqual([point]);expect(filterPlaces(all,'east','教室','all')).toEqual([])});
it('keeps WGS84 route coordinates and rejects foreign points',()=>{expect(navigationUrl(point)).toContain('36.576,114.504');expect(()=>navigationUrl({lat:0,lng:0})).toThrow()});
