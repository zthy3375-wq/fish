<script setup lang="ts">
import {onBeforeUnmount,ref} from 'vue';
import type {IScannerControls} from '@zxing/browser';
const emit=defineEmits<{scan:[value:string]}>();
const video=ref<HTMLVideoElement>(),open=ref(false),error=ref('');
let controls:IScannerControls|undefined,generation=0;
function stop(){
 generation++;controls?.stop();controls=undefined;
 const stream=video.value?.srcObject;
 if(stream instanceof MediaStream)stream.getTracks().forEach(track=>track.stop());
 open.value=false;
}
async function start(){
 if(!video.value||open.value)return;
 open.value=true;error.value='';const current=++generation;
 try{
  const {BrowserQRCodeReader}=await import('@zxing/browser');
  if(generation!==current||!video.value)return;
  const reader=new BrowserQRCodeReader();
  const started=await reader.decodeFromConstraints({video:{facingMode:{ideal:'environment'}}},video.value,result=>{
   if(generation!==current||!result)return;
   const value=result.getText();
   if(!/^HYT1:[0-9]{12}$/.test(value)){error.value='请对准邯院通优惠券二维码';return;}
   emit('scan',value.slice(5));stop();
  });
  if(generation!==current)started.stop();
  else controls=started;
 }catch{if(generation===current){stop();error.value='无法打开摄像头，请检查权限或手动输入核销码。';}}
}
onBeforeUnmount(stop);
</script>
<template>
 <button type="button" class="secondary" @click="open?stop():start()">{{open?'关闭摄像头':'扫码填入'}}</button>
 <video v-show="open" ref="video" autoplay muted playsinline class="scanner-video" aria-label="优惠券扫描相机"/>
 <p v-if="error" class="subtle" role="status">{{error}}</p>
</template>
