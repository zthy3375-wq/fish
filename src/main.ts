// Older Android WebViews load these modules before the app and its dependencies.
import 'core-js/actual/global-this';
import 'core-js/actual/object/from-entries';
import 'core-js/actual/promise/all-settled';
import 'core-js/actual/array/at';
import 'core-js/actual/string/at';
import 'core-js/actual/string/replace-all';
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

import './interface.css';

import './campus-home.css';

import './profile.css';

// Shared product primitives load after legacy page layouts.
import './product.css';
import './home-dashboard.css';
