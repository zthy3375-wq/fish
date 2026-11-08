import type {PangguaiTicket} from '../services/pangguai-client';

// This merchant's minor-unit balance is verified against its official recharge page.
// Preserve native/cache units and do not guess conversions for unrelated merchants.
export function drinkingWaterTicket(tickets:PangguaiTicket[]):PangguaiTicket|undefined {
 const matches=tickets.filter(ticket=>ticket.name.replace(/\s/g,'')==='邯郸学院直饮水机');
 return matches.length===1?matches[0]:undefined;
}
export function drinkingWaterAmount(value?:string|null):string|null {
 if(value==null||!/^\d{1,10}(\.\d{1,4})?$/.test(value))return null;
 return (Number(value)/100).toLocaleString('zh-CN',{minimumFractionDigits:2,maximumFractionDigits:2,useGrouping:false});
}
