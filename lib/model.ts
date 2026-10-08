import {z} from 'zod';
export const stages=['جديد','مؤهل','اكتشاف الاحتياج','تجهيز العرض','العرض مُرسل','تفاوض','مكتسبة','مفقودة'] as const;
export const kinds=['client','deal','task','project','document','note','payment','service','settings'] as const;
export const docKinds={quote:'عرض سعر',proposal:'بروبوزال',contract:'عقد خدمات',invoice:'فاتورة'};
export type Kind=typeof kinds[number];
export type Row={id:string;kind:Kind;clientId:string;owner:string;data:any;version:number;updatedAt:string};
export type Member={email:string;name:string;role:'admin'|'sales'|'delivery'|'finance';active:number};
export type Activity={id:string;clientId:string;actor:string;message:string;createdAt:string};
export const roles={admin:'مدير',sales:'مبيعات',delivery:'تنفيذ',finance:'حسابات'};
const text=z.string().trim().max(10000).default('');
const name=z.string().trim().min(1,'أدخل اسمًا صحيحًا').max(250);
const num=z.number().finite().min(0).max(1e10);
const date=z.string().refine(v=>!v||(/^\d{4}-\d{2}-\d{2}$/.test(v)&&!isNaN(Date.parse(v))),'تاريخ غير صحيح').default('');
export const schemas:Record<Kind,z.ZodTypeAny>={
 client:z.object({name,contact:text,email:z.union([z.literal(''),z.string().email()]).default(''),phone:text,industry:text,source:text,notes:text,status:z.enum(['نشط','محتمل','مؤرشف']).default('محتمل')}),
 deal:z.object({title:name,value:num,currency:z.enum(['EGP','SAR','USD','AED']),stage:z.enum(stages),nextAction:text,due:date,lostReason:text,notes:text,closedAt:date,imported:z.boolean().default(false)}),
 task:z.object({title:name,due:date,status:z.enum(['مفتوحة','مكتملة']),priority:z.enum(['عادية','عاجلة']),notes:text,projectId:text}),
 project:z.object({title:name,status:z.enum(['لم يبدأ','قيد التنفيذ','بانتظار العميل','مكتمل']),due:date,notes:text,dealId:text}),
 document:z.object({title:name,docKind:z.enum(['quote','proposal','contract','invoice']),currency:z.enum(['EGP','SAR','USD','AED']),items:z.array(z.object({name,details:text,qty:z.number().positive().max(100000),price:num})).min(1).max(100),discount:num,taxRate:z.number().min(0).max(100),date:date,due:date,scope:text,terms:text,sourceId:text,dealId:text,status:z.enum(['مسودة','صادر']).default('مسودة'),number:text,clientSnapshot:z.any().optional(),studioSnapshot:z.any().optional()}),
 note:z.object({title:name,channel:z.enum(['ملاحظة','مكالمة','اجتماع','واتساب','إيميل']),body:text}),
 payment:z.object({documentId:name,amount:z.number().positive().max(1e10),date:date,method:z.enum(['تحويل بنكي','نقدي','بطاقة','أخرى']),reference:text}),
 service:z.object({name,price:num,currency:z.enum(['EGP','SAR','USD','AED']),details:text}),
 settings:z.object({name, email:z.union([z.literal(''),z.string().email()]).default(''),phone:text,address:text,bank:text,iban:text,taxId:text,terms:text})
};
export function totals(d:any){const subtotal=d.items.reduce((n:number,i:any)=>n+i.qty*i.price,0);const net=Math.max(0,subtotal-d.discount);const tax=Math.round(net*d.taxRate)/100;return {subtotal,net,tax,total:Math.round((net+tax)*100)/100}}
export function day(){return new Intl.DateTimeFormat('en-CA',{timeZone:'Africa/Cairo',year:'numeric',month:'2-digit',day:'2-digit'}).format(new Date())}
export function money(v:number,c='EGP'){return new Intl.NumberFormat('ar-EG',{style:'currency',currency:c,minimumFractionDigits:0,maximumFractionDigits:2}).format(v)}
export function canWrite(role:string,kind:Kind){return role==='admin'||(role==='sales'&&['client','deal','task','note','document'].includes(kind))||(role==='delivery'&&['task','project','note'].includes(kind))||(role==='finance'&&['document','payment','note'].includes(kind))}

