import {createClient} from '@supabase/supabase-js';
import config from '../public-config.json';
const url=import.meta.env.VITE_SUPABASE_URL||config.url;
const key=import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY||config.publishableKey;
export const configured=!!url&&!!key;
export const supabase=configured?createClient(url,key,{auth:{persistSession:true,autoRefreshToken:true,detectSessionInUrl:true}}):null;
export async function readWorkspace(){if(!supabase)throw Error('قاعدة البيانات غير متصلة.');const {data,error}=await supabase.rpc('kira_workspace');if(error)throw Error(error.message);return data;}
export async function saveRecord(payload:unknown){if(!supabase)throw Error('قاعدة البيانات غير متصلة.');const {data,error}=await supabase.rpc('kira_save',{payload});if(error)throw Error(error.message);return data;}
export const asset=(name:string)=>import.meta.env.BASE_URL+name;
