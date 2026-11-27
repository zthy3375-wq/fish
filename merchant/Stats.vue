<script setup lang="ts">
import {computed} from 'vue';
import {metricName,type Daily} from './types';
const props=defineProps<{days:Daily[]}>();
const labels=Object.keys(metricName) as Daily['kind'][];
const grouped=computed(()=>{
 const byDay=new Map<string,Partial<Record<Daily['kind'],number>>>();
 for(const d of props.days){const values=byDay.get(d.day)||{};values[d.kind]=d.total;byDay.set(d.day,values);}
 return [...byDay.entries()].reverse();
});
</script>
<template>
 <section>
  <h2>近 30 天推广统计</h2>
  <div class="stat-grid"><div v-for="kind in labels" :key="kind"><span>{{metricName[kind]}}</span><strong>{{days.filter(d=>d.kind===kind).reduce((sum,d)=>sum+d.total,0)}}</strong></div></div>
  <p class="subtle">曝光和访问统计登录用户，每天按广告或门店去重。领券、核销按成功记录统计。</p>
  <p v-if="!grouped.length" class="empty">这段时间暂无记录</p>
  <div v-else class="table-scroll"><table><thead><tr><th scope="col">日期</th><th v-for="kind in labels" :key="kind" scope="col">{{metricName[kind]}}</th></tr></thead>
   <tbody><tr v-for="[day,values] in grouped" :key="day"><th scope="row">{{day}}</th><td v-for="kind in labels" :key="kind">{{values[kind]||0}}</td></tr></tbody></table></div>
 </section>
</template>
