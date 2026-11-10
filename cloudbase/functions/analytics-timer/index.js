exports.main=async()=>{
 const r=await fetch(process.env.ANALYTICS_FLUSH_URL,{method:'POST',headers:{'X-Hyt-Batch-Token':process.env.ANALYTICS_BATCH_TOKEN},signal:AbortSignal.timeout(250000)});
 if(!r.ok)throw Error('Hourly analytics aggregation failed: '+r.status);
 const result=await r.json();console.log(JSON.stringify({ok:result.ok,processed:result.processed,limitReached:result.limitReached}));return result;
};
