-- Run ONCE in Supabase SQL editor after replacing placeholders with your own email and name.
-- Never allow the first anonymous visitor to become administrator.
insert into public.kira_members(email,name,role,active)
values(lower('REPLACE_WITH_OWNER_EMAIL'),'REPLACE_WITH_OWNER_NAME','admin',true)
on conflict(email) do nothing;
