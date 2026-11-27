<script setup lang="ts">
import {computed,ref} from 'vue';
import {Store,ShieldCheck,LogOut,ArrowRight} from 'lucide-vue-next';
import {request,signIn,signOut} from './api';
import {commerceError,type Access} from '../src/services/commerce';
import MerchantPanel from './MerchantPanel.vue';
import BusinessPanel from './BusinessPanel.vue';

const access=ref<Access>(),busy=ref(false),error=ref(''),username=ref(''),password=ref(''),nickname=ref(''),register=ref(false),agreement=ref(false);
const route=ref<'shop'|'admin'>('shop');
const allowsAdmin=computed(()=>access.value?.role==='owner'||access.value?.role==='business');
async function submit(){
 busy.value=true;error.value='';
 try{
  await signIn(username.value,password.value,register.value?nickname.value:undefined);
  access.value=await request<Access>('access');
  route.value=allowsAdmin.value?'admin':'shop';
 }catch(cause){
  const code=(cause as Error).message;
  error.value=code==='invalid_credentials'?'账号或密码不正确':code==='username_unavailable'?'该账号已存在':commerceError(cause);
  await signOut();
 }finally{password.value='';busy.value=false;}
}
function exit(){access.value=undefined;username.value='';password.value='';error.value='';void signOut();}
</script>
<template>
 <div class="workbench">
  <header class="masthead">
   <a href="./" class="identity"><Store :size="22"/><span><b>邯院通</b><small>{{route==='admin'&&access?'商业管理':'商家工作台'}}</small></span></a>
   <div v-if="access" class="masthead-actions">
    <button v-if="allowsAdmin&&route==='admin'" @click="route='shop'"><Store :size="17"/>商家工作台</button>
    <button v-if="allowsAdmin&&route==='shop'" @click="route='admin'"><ShieldCheck :size="17"/>商业管理</button>
    <button @click="exit"><LogOut :size="16"/>退出</button>
   </div>
  </header>
  <main>
   <section v-if="!access" class="signin surface">
    <h1>{{register?'注册商家账号':'登录工作台'}}</h1>
    <p class="subtle">{{register?'创建邯院通账号后即可提交门店资质。':'使用邯院通账号登录，管理门店、优惠和到店核销。'}}</p>
    <form class="stack" @submit.prevent="submit">
     <label>账号<input v-model.trim="username" required maxlength="32" autocomplete="username"/></label>
     <label>密码<input v-model="password" required type="password" minlength="10" maxlength="128" :autocomplete="register?'new-password':'current-password'"/></label>
     <template v-if="register">
      <label>昵称<input v-model.trim="nickname" required minlength="2" maxlength="20" autocomplete="nickname"/></label>
      <label class="check"><input v-model="agreement" type="checkbox" required/>同意按规定提供真实资质，商家资料经审核后公开展示。</label>
     </template>
     <p v-if="error" class="status error" role="alert">{{error}}</p>
     <button class="primary" :disabled="busy||(register&&!agreement)">{{busy?'正在登录…':register?'创建账号':'登录'}} <ArrowRight :size="16"/></button>
    </form>
    <button class="link signup" @click="register=!register;error=''">{{register?'已有账号，返回登录':'没有账号，注册入驻'}}</button>
   </section>
   <BusinessPanel v-else-if="route==='admin'&&allowsAdmin" :owner="access.role==='owner'" @expired="exit"/>
   <MerchantPanel v-else :access="access" @expired="exit"/>
  </main>
 </div>
</template>
