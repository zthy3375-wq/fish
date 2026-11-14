/** Display-only helpers; original API timestamps and anonymous author names remain intact. */
export function treeholeTimestamp(value:string, now=Date.now()):string {
 const date=new Date(value);if(!Number.isFinite(date.getTime()))return '时间未知';
 const elapsed=now-date.getTime();
 if(elapsed>=0&&elapsed<60_000)return '刚刚';
 if(elapsed>=0&&elapsed<3_600_000)return Math.floor(elapsed/60_000)+' 分钟前';
 if(elapsed>=0&&elapsed<86_400_000)return Math.floor(elapsed/3_600_000)+' 小时前';
 return date.toLocaleString('zh-CN',{timeZone:'Asia/Shanghai',month:'numeric',day:'numeric',hour:'2-digit',minute:'2-digit'});
}
