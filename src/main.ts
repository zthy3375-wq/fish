import { createApp } from 'vue';
import App from './App.vue';
import './style.css';
import './home-courses.css';
createApp(App).mount('#app');

import './schedule.css';
import {prepareOffline} from './services/offline';
if(import.meta.env.PROD)window.addEventListener('load',prepareOffline);

import './grade-analysis.css';

import './agenda.css';

import './navigation.css';

import './daily-flow.css';
