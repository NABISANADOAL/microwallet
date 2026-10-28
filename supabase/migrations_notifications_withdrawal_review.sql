begin;
create table if not exists public.withdrawal_requests (
 id uuid primary key default gen_random_uuid(),
 user_id uuid not null references public.profiles(id) on delete cascade,
 asset_code text not null check(asset_code in ('USDT','BTC','ETH','TRX')),
 amount numeric(30,12) not null check(amount>0),
 destination_address text not null,
 status text not null default 'pending' check(status in ('pending','approved','rejected','cancelled','paid')),
 requested_at timestamptz not null default now(),
 available_after timestamptz not null default (now() + interval '24 hours'),
 admin_note text,
 reviewed_at timestamptz,
 paid_at timestamptz,
 payout_reference text
);
create index if not exists withdrawal_requests_user_created_idx on public.withdrawal_requests(user_id,requested_at desc);
alter table public.withdrawal_requests enable row level security;
revoke all on public.withdrawal_requests from anon,authenticated;
grant select on public.withdrawal_requests to authenticated;
drop policy if exists "Read own withdrawal requests or admin" on public.withdrawal_requests;
create policy "Read own withdrawal requests or admin" on public.withdrawal_requests for select to authenticated
using(user_id=(select auth.uid()) or exists(select 1 from public.admin_users a where a.user_id=(select auth.uid())));
create or replace function public.create_withdrawal_request(p_asset_code text,p_amount numeric,p_destination_address text)
returns uuid language plpgsql security definer set search_path='' as $$
declare uid uuid := (select auth.uid()); req_id uuid; asset text:=upper(btrim(p_asset_code));
begin
 if uid is null then raise exception 'Authentication required'; end if;
 if asset not in ('USDT','BTC','ETH','TRX') then raise exception 'Unsupported asset'; end if;
 if p_amount is null or p_amount<=0 then raise exception 'Amount must be positive'; end if;
 if p_destination_address is null or length(btrim(p_destination_address))<10 then raise exception 'Enter a valid destination wallet address'; end if;
 if not exists(select 1 from public.profiles where id=uid and status='approved') then raise exception 'Approved account required'; end if;
 insert into public.withdrawal_requests(user_id,asset_code,amount,destination_address,requested_at,available_after)
 values(uid,asset,p_amount,btrim(p_destination_address),now(),now()+interval '24 hours') returning id into req_id;
 return req_id;
end; $$;
revoke all on function public.create_withdrawal_request(text,numeric,text) from public,anon;
grant execute on function public.create_withdrawal_request(text,numeric,text) to authenticated;
create or replace function public.admin_review_withdrawal_request(p_request_id uuid,p_decision text,p_note text default null)
returns void language plpgsql security definer set search_path='' as $$
declare admin_id uuid := (select auth.uid()); req record;
begin
 if admin_id is null or not exists(select 1 from public.admin_users where user_id=admin_id) then raise exception 'Administrator access required' using errcode='42501'; end if;
 if p_decision not in ('approved','rejected','paid') then raise exception 'Invalid withdrawal decision'; end if;
 select * into req from public.withdrawal_requests where id=p_request_id for update;
 if not found then raise exception 'Withdrawal request not found'; end if;
 if p_decision='approved' and req.status<>'pending' then raise exception 'Only pending requests can be approved'; end if;
 if p_decision='rejected' and req.status not in ('pending','approved') then raise exception 'This request cannot be rejected in its current state'; end if;
 if p_decision='paid' and req.status<>'approved' then raise exception 'Only approved requests can be marked paid'; end if;
 update public.withdrawal_requests set status=p_decision,admin_note=coalesce(p_note,admin_note),reviewed_at=now(),
 paid_at=case when p_decision='paid' then now() else paid_at end,
 payout_reference=case when p_decision='paid' then p_note else payout_reference end where id=p_request_id;
 insert into public.admin_audit_log(admin_user_id,admin_email,target_user_id,target_email,action,details)
 select admin_id,coalesce((select email from public.profiles where id=admin_id),''),req.user_id,
 (select email from public.profiles where id=req.user_id),'withdrawal_'||p_decision,
 'Request '||p_request_id::text||'; '||req.asset_code||' '||req.amount::text||'; '||coalesce(p_note,'');
end; $$;
revoke all on function public.admin_review_withdrawal_request(uuid,text,text) from public,anon;
grant execute on function public.admin_review_withdrawal_request(uuid,text,text) to authenticated;
commit;
