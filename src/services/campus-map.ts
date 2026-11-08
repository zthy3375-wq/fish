import points from '../data/campus-places.json';
export type Campus='east'|'west';
export type PlaceCategory='study'|'life'|'sport'|'transport'|'other';
export interface CampusPlace {id:string;name:string;lat:number;lng:number;category:PlaceCategory;campus:Campus;source:'osm'|'personal';note:string}
export const campusCenters:Record<Campus,{name:string;lat:number;lng:number;note:string}>={
 east:{name:'东校区',lat:36.5767722,lng:114.5039900,note:'学院北路530号 · 地图中心为区域参考点'},
 west:{name:'西校区',lat:36.5705876,lng:114.4949897,note:'光明南大街199号 · 公开图源仍有旧校名与旧楼名'},
};
export const placeCategories:Record<PlaceCategory,string>={study:'教学',life:'生活',sport:'运动',transport:'出行',other:'其他'};
export const sourcePlaces=points as CampusPlace[];
const key='handan-campus-map-v083';
export function validPlace(value:unknown):value is CampusPlace{
 if(!value||typeof value!=='object')return false;const p=value as CampusPlace;
 return typeof p.id==='string'&&p.id.length<=100&&typeof p.name==='string'&&p.name.trim().length>0&&p.name.length<=60&&
 Number.isFinite(p.lat)&&Number.isFinite(p.lng)&&p.lat>=36.55&&p.lat<=36.60&&p.lng>=114.47&&p.lng<=114.53&&
 Object.prototype.hasOwnProperty.call(campusCenters,p.campus)&&Object.prototype.hasOwnProperty.call(placeCategories,p.category)&&p.source==='personal'&&typeof p.note==='string'&&p.note.length<=200;
}
export function readMapData():{places:CampusPlace[];favorites:string[]}{
 try{const data=JSON.parse(localStorage.getItem(key)||'{}');return {places:Array.isArray(data.places)?data.places.filter(validPlace).slice(0,100):[],favorites:Array.isArray(data.favorites)?data.favorites.filter((x:unknown)=>typeof x==='string').slice(0,200):[]}}catch{return {places:[],favorites:[]}}
}
export function saveMapData(places:CampusPlace[],favorites:string[]){
 if(places.length>100||!places.every(validPlace))throw Error('INVALID_PLACE');
 localStorage.setItem(key,JSON.stringify({places,favorites:[...new Set(favorites)].slice(0,200)}));
}
export function filterPlaces(places:CampusPlace[],campus:Campus,query:string,category:string,favorites:string[]=[]):CampusPlace[]{
 const q=query.trim().toLocaleLowerCase();return places.filter(p=>p.campus===campus&&(!q||(p.name+' '+p.note).toLocaleLowerCase().includes(q))&&(category==='all'||category==='favorite'&&favorites.includes(p.id)||category===p.category));
}
/** A WGS84 route endpoint, never incorrectly label OSM coordinates as GCJ-02. */
export function navigationUrl(place:Pick<CampusPlace,'lat'|'lng'>){
 if(!Number.isFinite(place.lat)||!Number.isFinite(place.lng)||place.lat<36.55||place.lat>36.60||place.lng<114.47||place.lng>114.53)throw Error('INVALID_COORDINATES');
 return `https://www.openstreetmap.org/directions?engine=fossgis_osrm_foot&route=;${place.lat},${place.lng}`;
}
