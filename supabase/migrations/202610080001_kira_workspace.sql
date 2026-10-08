-- Kira Workspace: authenticated RPC boundary, no direct browser table access.
create extension if not exists pgcrypto;
create table public.kira_members (
 email text primary key check(email=lower(email)),
 user_id uuid unique references auth.users(id),
 name text not null check(length(name) between 1 and 150),
 role text not null check(role in ('admin','sales','delivery','finance')),
 active boolean not null default true
);
create table public.kira_records (
 id uuid primary key default gen_random_uuid(),
 kind text not null check(kind in ('client','deal','task','project','document','note','payment','service','settings')),
 client_id uuid references public.kira_records(id),
 owner_email text not null references public.kira_members(email),
 data jsonb not null check(jsonb_typeof(data)='object'),
 version integer not null default 1,
 updated_at timestamptz not null default now()
);
create index kira_records_client_idx on public.kira_records(client_id);
create index kira_records_kind_idx on public.kira_records(kind);
create unique index kira_one_studio_settings on public.kira_records(kind) where kind='settings';
create index kira_payment_invoice_idx on public.kira_records((data->>'documentId')) where kind='payment';
create table public.kira_activities (
 id uuid primary key default gen_random_uuid(),client_id uuid,
 actor text not null,message text not null,created_at timestamptz not null default now()
);
create index kira_activity_time_idx on public.kira_activities(created_at desc);
alter table public.kira_members enable row level security;
alter table public.kira_records enable row level security;
alter table public.kira_activities enable row level security;
revoke all on public.kira_members,public.kira_records,public.kira_activities from anon,authenticated;

-- Identity comes from verified Supabase Auth, never from the request body.
create function public.kira_current_member() returns public.kira_members
language plpgsql security definer set search_path=pg_catalog,public as $$
declare m public.kira_members; u auth.users;
begin
 if auth.uid() is null then raise exception 'سجل الدخول أولًا.' using errcode='28000'; end if;
 select * into u from auth.users where id=auth.uid() and email_confirmed_at is not null;
 if not found then raise exception 'أكد بريدك الإلكتروني أولًا.' using errcode='28000'; end if;
 select * into m from public.kira_members where user_id=u.id and active;
 if found then return m; end if;
 -- Allowlisted email is bound to the immutable auth user ID once.
 update public.kira_members set user_id=u.id where email=lower(u.email) and user_id is null and active returning * into m;
 if not found then raise exception 'حسابك غير مضاف لفريق كيرا أو تم إيقافه. تواصل مع مدير المساحة.' using errcode='42501'; end if;
 return m;
end $$;

create function public.kira_access_client(cid uuid, m public.kira_members) returns boolean
language sql stable security definer set search_path=pg_catalog,public as $$
 select exists(select 1 from public.kira_records c where c.id=cid and c.kind='client' and
 (m.role in ('admin','finance') or c.owner_email=m.email or exists(select 1 from public.kira_records a where a.client_id=c.id and a.owner_email=m.email)))
$$;
create function public.kira_visible(r public.kira_records, m public.kira_members) returns boolean
language sql stable security definer set search_path=pg_catalog,public as $$
 select m.role in ('admin','finance') or r.kind in ('settings','service') or
 (public.kira_access_client(case when r.kind='client' then r.id else r.client_id end,m) and
 (m.role<>'delivery' or r.kind not in ('deal','document','payment')))
$$;

create function public.kira_total(d jsonb) returns numeric
language sql immutable set search_path=pg_catalog,public as $$
 select round(greatest(0,coalesce(sum((i->>'qty')::numeric*(i->>'price')::numeric),0)-(d->>'discount')::numeric)*(1+(d->>'taxRate')::numeric/100),2)
 from jsonb_array_elements(d->'items') i
$$;

create function public.kira_validate(k text,d jsonb) returns jsonb
language plpgsql set search_path=pg_catalog,public as $$
declare f text; n numeric; item jsonb; total numeric:=0; required_title text;
begin
 if d is null or jsonb_typeof(d)<>'object' or octet_length(d::text)>400000 then raise exception 'صيغة البيانات غير صالحة.'; end if;
 required_title:=case when k in ('client','service','settings') then 'name' when k in ('deal','task','project','document','note') then 'title' else null end;
 if required_title is not null and (jsonb_typeof(d->required_title) is distinct from 'string' or length(trim(d->>required_title)) not between 1 and 250) then raise exception 'الاسم أو العنوان مطلوب.'; end if;
 foreach f in array array['contact','phone','industry','source','notes','nextAction','lostReason','projectId','dealId','scope','terms','sourceId','number','body','reference','details','address','bank','iban','taxId','email'] loop
  if d ? f and (jsonb_typeof(d->f)<>'string' or length(d->>f)>10000) then raise exception 'حقل نصي غير صالح: %',f; end if;
 end loop;
 foreach f in array array['due','date','closedAt'] loop
  if d ? f and d->>f<>'' then
   if jsonb_typeof(d->f)<>'string' or (d->>f)!~'^\d{4}-\d{2}-\d{2}$' then raise exception 'تاريخ غير صالح.'; end if;
   perform (d->>f)::date;
  end if;
 end loop;
 foreach f in array array['value','price','amount','discount','taxRate'] loop
  if d ? f then
   if jsonb_typeof(d->f)<>'number' then raise exception 'قيمة رقمية غير صالحة.'; end if;
   n:=(d->>f)::numeric;if n<0 or n>10000000000 then raise exception 'المبلغ خارج الحدود المسموحة.'; end if;
  end if;
 end loop;
 if k in ('deal','service','document') and coalesce(d->>'currency','') not in ('EGP','SAR','USD','AED') then raise exception 'العملة غير صالحة.'; end if;
 if k='client' then
  if coalesce(d->>'status','') not in ('نشط','محتمل','مؤرشف') then raise exception 'حالة العميل غير صالحة.'; end if;
 elsif k='deal' then
  if not d?'value' or coalesce(d->>'stage','') not in ('جديد','مؤهل','اكتشاف الاحتياج','تجهيز العرض','العرض مُرسل','تفاوض','مكتسبة','مفقودة') then raise exception 'مرحلة الفرصة أو قيمتها غير صالحة.'; end if;
  if d->>'stage'='مفقودة' and length(trim(coalesce(d->>'lostReason','')))=0 then raise exception 'اكتب سبب خسارة الفرصة.'; end if;
 elsif k='task' then
  if coalesce(d->>'status','') not in ('مفتوحة','مكتملة') or coalesce(d->>'priority','') not in ('عادية','عاجلة') then raise exception 'حالة المتابعة غير صالحة.'; end if;
 elsif k='project' then
  if coalesce(d->>'status','') not in ('لم يبدأ','قيد التنفيذ','بانتظار العميل','مكتمل') then raise exception 'حالة المشروع غير صالحة.'; end if;
 elsif k='note' then
  if coalesce(d->>'channel','') not in ('ملاحظة','مكالمة','اجتماع','واتساب','إيميل') then raise exception 'نوع التواصل غير صالح.'; end if;
 elsif k='service' then
  if not d?'price' then raise exception 'سعر الخدمة مطلوب.'; end if;
 elsif k='payment' then
  if not d?'amount' or (d->>'amount')::numeric<=0 or nullif(d->>'date','') is null or nullif(d->>'documentId','') is null or coalesce(d->>'method','') not in ('تحويل بنكي','نقدي','بطاقة','أخرى') then raise exception 'راجع بيانات الدفعة.'; end if;
 elsif k='document' then
  if coalesce(d->>'docKind','') not in ('quote','proposal','contract','invoice') or coalesce(d->>'status','') not in ('مسودة','صادر') then raise exception 'نوع المستند أو حالته غير صالحة.'; end if;
  if jsonb_typeof(d->'items') is distinct from 'array' then raise exception 'أضف بنود المستند.'; end if;
  if jsonb_array_length(d->'items') not between 1 and 100 or not d?'discount' or not d?'taxRate' then raise exception 'راجع بنود المستند والضريبة والخصم.'; end if;
  if (d->>'taxRate')::numeric>100 then raise exception 'نسبة الضريبة غير صالحة.'; end if;
  for item in select * from jsonb_array_elements(d->'items') loop
   if jsonb_typeof(item->'name') is distinct from 'string' or length(trim(item->>'name')) not between 1 and 250 then raise exception 'اسم البند مطلوب.'; end if;
   if jsonb_typeof(item->'qty') is distinct from 'number' or jsonb_typeof(item->'price') is distinct from 'number' then raise exception 'الكمية والسعر أرقام مطلوبة.'; end if;
   if (item->>'qty')::numeric<=0 or (item->>'qty')::numeric>100000 or (item->>'price')::numeric<0 or (item->>'price')::numeric>10000000000 then raise exception 'الكمية أو السعر خارج الحدود.'; end if;
   if item?'details' and (jsonb_typeof(item->'details')<>'string' or length(item->>'details')>10000) then raise exception 'تفاصيل البند غير صالحة.'; end if;
   total:=total+(item->>'qty')::numeric*(item->>'price')::numeric;
  end loop;
  if (d->>'discount')::numeric>total then raise exception 'الخصم أكبر من قيمة البنود.'; end if;
 end if;
 return d;
end $$;

create function public.kira_workspace() returns jsonb
language plpgsql security definer set search_path=pg_catalog,public as $$
declare m public.kira_members; rr jsonb; mm jsonb; aa jsonb;
begin
 m:=public.kira_current_member();
 select coalesce(jsonb_agg(jsonb_build_object('id',r.id,'kind',r.kind,'clientId',coalesce(r.client_id::text,''),'owner',r.owner_email,'data',r.data,'version',r.version,'updatedAt',r.updated_at) order by r.updated_at desc),'[]') into rr from public.kira_records r where public.kira_visible(r,m);
 select coalesce(jsonb_agg(jsonb_build_object('email',email,'name',name,'role',role,'active',case when active then 1 else 0 end) order by name),'[]') into mm from public.kira_members;
 select coalesce(jsonb_agg(jsonb_build_object('id',a.id,'clientId',coalesce(a.client_id::text,''),'actor',a.actor,'message',a.message,'createdAt',a.created_at) order by a.created_at desc),'[]') into aa from (select * from public.kira_activities where m.role in ('admin','finance') or public.kira_access_client(client_id,m) order by created_at desc limit 500) a;
 return jsonb_build_object('rows',rr,'members',mm,'activities',aa,'me',jsonb_build_object('email',m.email,'name',m.name,'role',m.role,'active',1));
end $$;

create function public.kira_save(payload jsonb) returns jsonb
language plpgsql security definer set search_path=pg_catalog,public as $$
declare m public.kira_members; k text; d jsonb; rid uuid; cid uuid; own text; old public.kira_records; related public.kira_records; studio jsonb; client_data jsonb; n numeric; paid numeric; msg text; v jsonb; member_email text; is_new boolean;
begin
 m:=public.kira_current_member();
 if payload is null or jsonb_typeof(payload)<>'object' or octet_length(payload::text)>500000 then raise exception 'الطلب غير صالح.'; end if;
 if payload->>'action'='member' then
  if m.role<>'admin' then raise exception 'إدارة الفريق متاحة للمدير فقط.' using errcode='42501'; end if;
  v:=payload->'member';member_email:=lower(trim(v->>'email'));
  if member_email is null or member_email!~'^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' or length(member_email)>254 or length(trim(coalesce(v->>'name',''))) not between 1 and 150 or coalesce(v->>'role','') not in ('admin','sales','delivery','finance') or coalesce(v->>'active','') not in ('0','1') then raise exception 'راجع بيانات عضو الفريق.'; end if;
  if member_email=m.email and (v->>'role'<>'admin' or v->>'active'<>'1') then raise exception 'لا يمكنك إلغاء صلاحيات حسابك الحالي.'; end if;
  insert into public.kira_members(email,name,role,active) values(member_email,trim(v->>'name'),v->>'role',(v->>'active')='1') on conflict(email) do update set name=excluded.name,role=excluded.role,active=excluded.active;
  insert into public.kira_activities(actor,message) values(m.name,'تحديث عضو الفريق: '||(v->>'name'));
  return jsonb_build_object('ok',true);
 end if;
 k:=payload->>'kind';
 if k is null or k not in ('client','deal','task','project','document','note','payment','service','settings') then raise exception 'نوع السجل غير صحيح.'; end if;
 if not (m.role='admin' or (m.role='sales' and k in ('client','deal','task','note','document')) or (m.role='delivery' and k in ('task','project','note')) or (m.role='finance' and k in ('document','payment','note'))) then raise exception 'غير مسموح بهذا الإجراء.' using errcode='42501'; end if;
 rid:=nullif(payload->>'id','')::uuid;is_new:=rid is null;
 if not is_new then
  select * into old from public.kira_records where id=rid for update;
  if not found then raise exception 'السجل غير موجود.'; end if;
  if old.kind<>k then raise exception 'نوع السجل غير صحيح.'; end if;
  if not public.kira_visible(old,m) or (m.role='sales' and old.owner_email<>m.email) then raise exception 'غير مسموح بتعديل هذا السجل.' using errcode='42501'; end if;
  if old.version is distinct from (payload->>'version')::integer then raise exception 'عدّل شخص آخر هذا السجل. حدث البيانات وأعد المحاولة.' using errcode='40001'; end if;
  if k='payment' or (k='document' and old.data->>'status'='صادر') then raise exception 'السجل الصادر ثابت. أنشئ نسخة جديدة للتعديل.'; end if;
 end if;
 if m.role='admin' then own:=coalesce(nullif(payload->>'owner',''),m.email);else own:=case when is_new then m.email else old.owner_email end;end if;
 if not exists(select 1 from public.kira_members where email=own and active) then raise exception 'اختر مسؤولًا نشطًا.'; end if;
 cid:=case when k in ('client','service','settings') then null else nullif(payload->>'clientId','')::uuid end;
 if k not in ('client','service','settings') and (cid is null or not public.kira_access_client(cid,m)) then raise exception 'اختر عميلًا متاحًا لك.' using errcode='42501'; end if;
 if not is_new and cid is distinct from old.client_id then raise exception 'لا يمكن نقل السجل لعميل آخر.'; end if;
 d:=public.kira_validate(k,payload->'data');
 if k='deal' then
  d:=jsonb_set(d,'{closedAt}',to_jsonb(case when d->>'stage' in ('مكتسبة','مفقودة') then case when not is_new and old.data->>'stage'=d->>'stage' then coalesce(old.data->>'closedAt','') when is_new and d->>'imported'='true' then '' else to_char(now() at time zone 'Africa/Cairo','YYYY-MM-DD') end else '' end));
 end if;
 if k='task' and nullif(d->>'projectId','') is not null then
  if not exists(select 1 from public.kira_records where id=(d->>'projectId')::uuid and kind='project' and client_id=cid) then raise exception 'المشروع غير مرتبط بالعميل.'; end if;
 end if;
 if k in ('project','document') and nullif(d->>'dealId','') is not null then
  if not exists(select 1 from public.kira_records where id=(d->>'dealId')::uuid and kind='deal' and client_id=cid) then raise exception 'الفرصة غير مرتبطة بالعميل.'; end if;
 end if;
 if k='document' then
  if m.role='sales' and d->>'docKind'='invoice' then raise exception 'الفواتير للحسابات والمدير فقط.' using errcode='42501'; end if;
  if nullif(d->>'sourceId','') is not null and not exists(select 1 from public.kira_records where id=(d->>'sourceId')::uuid and kind='document' and client_id=cid) then raise exception 'المستند المصدر غير صحيح.'; end if;
  d:=(d-'clientSnapshot'-'studioSnapshot')||jsonb_build_object('number','');
  if d->>'status'='صادر' then
   select data into studio from public.kira_records where kind='settings';
   if studio is null then raise exception 'أكمل بيانات الاستوديو قبل إصدار المستند.'; end if;
   if nullif(d->>'date','') is null then raise exception 'تاريخ الإصدار مطلوب.'; end if;
   select data into client_data from public.kira_records where id=cid;
   d:=d||jsonb_build_object('number','KR-'||case d->>'docKind' when 'quote' then 'QT' when 'proposal' then 'PR' when 'contract' then 'CT' else 'INV' end||'-'||to_char(now(),'YYYY')||'-'||upper(substr(gen_random_uuid()::text,1,8)),'clientSnapshot',client_data,'studioSnapshot',studio);
  end if;
 end if;
 if k='payment' then
  -- Serializes all payments on the same invoice, preventing concurrent overpayment.
  select * into related from public.kira_records where id=(d->>'documentId')::uuid for update;
  if not found or related.kind<>'document' or related.client_id is distinct from cid or related.data->>'docKind'<>'invoice' or related.data->>'status'<>'صادر' then raise exception 'اختر فاتورة صادرة لنفس العميل.'; end if;
  select coalesce(sum((data->>'amount')::numeric),0) into paid from public.kira_records where kind='payment' and data->>'documentId'=related.id::text;
  if round((d->>'amount')::numeric+paid,2)>public.kira_total(related.data) then raise exception 'المبلغ أكبر من المتبقي على الفاتورة.'; end if;
 end if;
 if is_new then
  insert into public.kira_records(kind,client_id,owner_email,data) values(k,cid,own,d) returning id into rid;
 else
  update public.kira_records set data=d,owner_email=own,version=version+1,updated_at=now() where id=rid;
 end if;
 msg:=case when is_new then 'إضافة ' else 'تحديث ' end||case k when 'client' then 'عميل' when 'deal' then 'فرصة' when 'task' then 'متابعة' when 'project' then 'مشروع' when 'document' then 'مستند' when 'note' then 'تواصل' when 'payment' then 'دفعة' when 'service' then 'خدمة' else 'بيانات الاستوديو' end||': '||coalesce(d->>'title',d->>'name',d->>'reference','');
 insert into public.kira_activities(client_id,actor,message) values(case when k='client' then rid else cid end,m.name,msg);
 return jsonb_build_object('id',rid);
end $$;

-- All helper functions remain inaccessible from the browser. Only these two RPCs are exposed.
revoke all on function public.kira_current_member() from public,anon,authenticated;
revoke all on function public.kira_access_client(uuid,public.kira_members) from public,anon,authenticated;
revoke all on function public.kira_visible(public.kira_records,public.kira_members) from public,anon,authenticated;
revoke all on function public.kira_validate(text,jsonb) from public,anon,authenticated;
revoke all on function public.kira_total(jsonb) from public,anon,authenticated;
revoke all on function public.kira_workspace() from public,anon;
revoke all on function public.kira_save(jsonb) from public,anon;
grant execute on function public.kira_workspace(),public.kira_save(jsonb) to authenticated;
