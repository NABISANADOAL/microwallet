-- Safe history + withdrawal cooldown migration. Preserves existing records and emails.
begin;
create table if not exists public.asset_credit_ledger (
 id uuid primary key default gen_random_uuid(),
 user_id uuid not null references public.profiles(id) on delete cascade,
 asset_code text not null check (asset_code in ('USDT','BTC','ETH','TRX')),
 entry_type text not null check (entry_type in ('credit','debit','adjustment')),
 asset_amount numeric(30,12) not null,
 usd_amount numeric(18,2) not null default 0,
 price_usd numeric(24,8),
 description text not null,
 reference_id uuid,
 created_at timestamptz not null default now()
);
create index if not exists asset_credit_ledger_user_created_idx on public.asset_credit_ledger(user_id,created_at desc);
alter table public.asset_credit_ledger enable row level security;
revoke all on public.asset_credit_ledger from anon,authenticated;
grant select on public.asset_credit_ledger to authenticated;
drop policy if exists "Read own asset credit history or admin" on public.asset_credit_ledger;
create policy "Read own asset credit history or admin" on public.asset_credit_ledger for select to authenticated
using (user_id=(select auth.uid()) or public.is_current_user_admin());

create or replace function public.admin_review_asset_topup(p_request_id uuid,p_decision text,p_note text default null,p_price_usd numeric default null)
returns void language plpgsql security definer set search_path='' as $$
declare admin_id uuid := (select auth.uid()); req record; price numeric(24,8); qty numeric(30,12);
begin
 if admin_id is null or not exists(select 1 from public.admin_users where user_id=admin_id) then raise exception 'Administrator access required' using errcode='42501'; end if;
 if p_decision not in ('approved','rejected') then raise exception 'Decision must be approved or rejected'; end if;
 select * into req from public.topup_requests where id=p_request_id for update;
 if not found then raise exception 'Request not found'; end if;
 if req.status<>'pending' then raise exception 'Request has already been reviewed'; end if;
 if p_decision='approved' then
  price:=case when req.asset_code='USDT' then 1 else p_price_usd end;
  if price is null or price<=0 then raise exception 'Enter a valid USD market price for this asset'; end if;
  qty:=round((coalesce(req.usd_amount,req.amount)/price)::numeric,12);
  insert into public.asset_balances(user_id,asset_code,balance,updated_at) values(req.user_id,req.asset_code,qty,now())
  on conflict(user_id,asset_code) do update set balance=public.asset_balances.balance+excluded.balance,updated_at=now();
  insert into public.asset_credit_ledger(user_id,asset_code,entry_type,asset_amount,usd_amount,price_usd,description,reference_id)
  values(req.user_id,req.asset_code,'credit',qty,coalesce(req.usd_amount,req.amount),price,'Top-up approved by administrator',req.id);
  update public.topup_requests set status='approved',admin_note=p_note,price_usd=price,asset_quantity=qty,reviewed_at=now() where id=p_request_id;
 else
  update public.topup_requests set status='rejected',admin_note=p_note,reviewed_at=now() where id=p_request_id;
 end if;
end; $$;
revoke all on function public.admin_review_asset_topup(uuid,text,text,numeric) from public,anon;
grant execute on function public.admin_review_asset_topup(uuid,text,text,numeric) to authenticated;

create table if not exists public.withdrawal_requests (
 id uuid primary key default gen_random_uuid(),
 user_id uuid not null references public.profiles(id) on delete cascade,
 asset_code text not null check(asset_code in ('USDT','BTC','ETH','TRX')),
 amount numeric(30,12) not null check(amount>0),
 destination_address text not null,
 status text not null default 'pending' check(status in ('pending','approved','rejected','cancelled')),
 requested_at timestamptz not null default now(),
 available_after timestamptz generated always as (requested_at + interval '24 hours') stored,
 admin_note text
);
create index if not exists withdrawal_requests_user_created_idx on public.withdrawal_requests(user_id,requested_at desc);
alter table public.withdrawal_requests enable row level security;
revoke all on public.withdrawal_requests from anon,authenticated;
grant select on public.withdrawal_requests to authenticated;
drop policy if exists "Read own withdrawal requests or admin" on public.withdrawal_requests;
create policy "Read own withdrawal requests or admin" on public.withdrawal_requests for select to authenticated
using(user_id=(select auth.uid()) or public.is_current_user_admin());

create or replace function public.create_withdrawal_request(p_asset_code text,p_amount numeric,p_destination_address text)
returns uuid language plpgsql security definer set search_path='' as $$
declare uid uuid := (select auth.uid()); req_id uuid; asset text:=upper(btrim(p_asset_code));
begin
 if uid is null then raise exception 'Authentication required'; end if;
 if asset not in ('USDT','BTC','ETH','TRX') then raise exception 'Unsupported asset'; end if;
 if p_amount is null or p_amount<=0 then raise exception 'Amount must be positive'; end if;
 if p_destination_address is null or length(btrim(p_destination_address))<10 then raise exception 'Enter a valid destination wallet address'; end if;
 if not exists(select 1 from public.profiles where id=uid and status='approved') then raise exception 'Approved account required'; end if;
 insert into public.withdrawal_requests(user_id,asset_code,amount,destination_address,requested_at)
 values(uid,asset,p_amount,btrim(p_destination_address),now()) returning id into req_id;
 return req_id;
end; $$;
revoke all on function public.create_withdrawal_request(text,numeric,text) from public,anon;
grant execute on function public.create_withdrawal_request(text,numeric,text) to authenticated;
commit;
