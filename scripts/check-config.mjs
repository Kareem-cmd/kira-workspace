import {readFileSync} from 'node:fs';
const config=JSON.parse(readFileSync(new URL('../public-config.json',import.meta.url),'utf8'));
const url=process.env.VITE_SUPABASE_URL||config.url,key=process.env.VITE_SUPABASE_PUBLISHABLE_KEY||config.publishableKey;
if(!url||!key)throw Error('Set VITE_SUPABASE_URL and VITE_SUPABASE_PUBLISHABLE_KEY repository variables before deployment.');
if(!/^https:\/\/[^/]+\.supabase\.co\/?$/.test(url))throw Error('Invalid Supabase project URL');
if(key.startsWith('sb_secret_'))throw Error('Never publish a Supabase secret key to the browser.');
if(key.split('.').length===3){const payload=JSON.parse(Buffer.from(key.split('.')[1],'base64url'));if(payload.role!=='anon')throw Error('Only the anon/publishable key may be used in a browser.');}
console.log('Public client configuration validated.');
