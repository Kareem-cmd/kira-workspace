create table public.kira_finance (
 id uuid primary key default gen_random_uuid(), data jsonb not null,
 version integer not null default 1, updated_at timestamptz not null default now()
);
alter table public.kira_finance enable row level security;
revoke all on public.kira_finance from public,anon,authenticated;
create function public.kira_finance_list() returns jsonb language plpgsql security definer set search_path='' as $$
declare m public.kira_members; result jsonb;
begin
 m:=public.kira_current_member();
 if m.role not in ('admin','finance') then raise exception 'مالية الشركة متاحة للمدير والحسابات فقط.' using errcode='42501'; end if;
 select coalesce(jsonb_agg(jsonb_build_object('id',id,'data',data,'version',version,'updatedAt',updated_at) order by updated_at desc),'[]') into result from public.kira_finance;
 return result;
end $$;
create function public.kira_finance_save(payload jsonb) returns uuid language plpgsql security definer set search_path='' as $$
declare m public.kira_members; d jsonb; rid uuid; old public.kira_finance; f text; a numeric;
begin
 m:=public.kira_current_member();
 if m.role not in ('admin','finance') then raise exception 'مالية الشركة متاحة للمدير والحسابات فقط.' using errcode='42501'; end if;
 d:=payload->'data'; rid:=nullif(payload->>'id','')::uuid;
 if d is null or jsonb_typeof(d)<>'object' or octet_length(d::text)>30000 then raise exception 'بيانات غير صالحة.'; end if;
 if coalesce(d->>'kind','') not in ('income','expense','salary','asset') or coalesce(d->>'currency','') not in ('EGP','SAR','USD','AED') or coalesce(d->>'status','') not in ('pending','paid','void') then raise exception 'نوع أو عملة أو حالة غير صالحة.'; end if;
 if jsonb_typeof(d->'title') is distinct from 'string' or length(trim(d->>'title')) not between 1 and 250 then raise exception 'العنوان مطلوب.'; end if;
 if jsonb_typeof(d->'amount') is distinct from 'number' then raise exception 'المبلغ مطلوب.'; end if;
 a:=(d->>'amount')::numeric; if a<=0 or a>10000000000 or round(a,2)<>a then raise exception 'أدخل مبلغًا موجبًا بمنزلتين عشريتين كحد أقصى.'; end if;
 foreach f in array array['date','due','paidDate'] loop
  if coalesce(d->>f,'')<>'' then
   if (d->>f)!~'^\d{4}-\d{2}-\d{2}$' then raise exception 'تاريخ غير صالح.'; end if;
   perform (d->>f)::date;
  end if;
 end loop;
 if nullif(d->>'date','') is null or (d->>'status'='paid' and nullif(d->>'paidDate','') is null) then raise exception 'تاريخ العملية والسداد مطلوبان.'; end if;
 foreach f in array array['employee','category','notes'] loop
  if d ? f and (jsonb_typeof(d->f)<>'string' or length(d->>f)>10000) then raise exception 'حقل نصي غير صالح.'; end if;
 end loop;
 if d->>'kind'='salary' and length(trim(coalesce(d->>'employee','')))=0 then raise exception 'اسم الموظف مطلوب.'; end if;
 if rid is null then insert into public.kira_finance(data) values(d) returning id into rid;
 else
  select * into old from public.kira_finance where id=rid for update;
  if not found or old.version is distinct from (payload->>'version')::integer then raise exception 'السجل تغير. حدث البيانات وأعد المحاولة.' using errcode='40001'; end if;
  update public.kira_finance set data=d,version=version+1,updated_at=now() where id=rid;
 end if;
 -- Do not put payroll amounts or names in the CRM activity feed visible to other roles.
 return rid;
end $$;
revoke all on function public.kira_finance_list(),public.kira_finance_save(jsonb) from public,anon;
grant execute on function public.kira_finance_list(),public.kira_finance_save(jsonb) to authenticated;
