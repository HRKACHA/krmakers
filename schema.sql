-- KR Makers Order Management: secure Supabase schema
create extension if not exists pgcrypto;
create table if not exists public.staff_profiles (
 user_id uuid primary key references auth.users(id) on delete cascade,
 display_name text not null default 'KR Makers Admin',
 is_active boolean not null default true, created_at timestamptz not null default now()
);
alter table public.staff_profiles enable row level security;
drop policy if exists "staff can read own profile" on public.staff_profiles;
create policy "staff can read own profile" on public.staff_profiles for select to authenticated
 using (user_id=(select auth.uid()) and is_active);
revoke all on public.staff_profiles from anon, authenticated;
grant select on public.staff_profiles to authenticated;

create table if not exists public.customers (
 id uuid primary key default gen_random_uuid(), name text not null,
 name_key text generated always as (lower(btrim(name))) stored,
 created_at timestamptz not null default now(),
 constraint customers_name_nonempty check(length(btrim(name))>0)
);
create unique index if not exists customers_name_key_uidx on public.customers(name_key);
create table if not exists public.products (
 id uuid primary key default gen_random_uuid(), name text not null unique,
 rate_per_kg numeric(12,2) not null default 0 check(rate_per_kg>=0),
 is_active boolean not null default true, sort_order integer not null default 0,
 updated_at timestamptz not null default now()
);
create sequence if not exists public.kr_order_number_seq start 1;
create table if not exists public.orders (
 id uuid primary key default gen_random_uuid(), order_no text unique,
 customer_id uuid not null references public.customers(id) on delete restrict,
 order_date date not null default current_date,
 preparation_status text not null default 'pending' check(preparation_status in ('pending','preparing','ready','delivered','cancelled')),
 payment_status text not null default 'pending' check(payment_status in ('pending','paid')),
 payment_mode text not null default 'Online' check(payment_mode='Online'),
 total_amount numeric(12,2) not null default 0 check(total_amount>=0),
 amount_received numeric(12,2) not null default 0 check(amount_received>=0),
 paid_at timestamptz, notes text, created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create table if not exists public.order_items (
 id uuid primary key default gen_random_uuid(),
 order_id uuid not null references public.orders(id) on delete cascade,
 product_id uuid references public.products(id) on delete set null,
 item_name text not null, quantity_kg numeric(12,3) not null check(quantity_kg>0),
 rate_per_kg numeric(12,2) not null check(rate_per_kg>=0),
 line_total numeric(12,2) generated always as (round(quantity_kg*rate_per_kg,2)) stored,
 created_at timestamptz not null default now(),
 constraint order_items_name_nonempty check(length(btrim(item_name))>0)
);
create index if not exists orders_order_date_idx on public.orders(order_date desc);
create index if not exists orders_payment_status_idx on public.orders(payment_status,paid_at desc);
create index if not exists orders_customer_idx on public.orders(customer_id);
create index if not exists order_items_order_id_idx on public.order_items(order_id);

alter table public.customers enable row level security;
alter table public.products enable row level security;
alter table public.orders enable row level security;
alter table public.order_items enable row level security;
do $$
declare t text;
begin
 foreach t in array array['customers','products','orders','order_items'] loop
  execute format('drop policy if exists "staff full access" on public.%I',t);
  execute format('create policy "staff full access" on public.%I for all to authenticated using (exists(select 1 from public.staff_profiles s where s.user_id=(select auth.uid()) and s.is_active)) with check (exists(select 1 from public.staff_profiles s where s.user_id=(select auth.uid()) and s.is_active))',t);
 end loop;
end $$;
revoke all on public.customers,public.products,public.orders,public.order_items from anon;
grant select,insert,update,delete on public.customers,public.products,public.orders,public.order_items to authenticated;
grant usage,select on sequence public.kr_order_number_seq to authenticated;

create or replace function public.set_order_defaults()
returns trigger language plpgsql set search_path=public,pg_temp as $$
begin
 if new.order_no is null then new.order_no:='KR-'||lpad(nextval('public.kr_order_number_seq')::text,5,'0'); end if;
 if new.payment_status='paid' then new.paid_at:=coalesce(new.paid_at,now()); new.amount_received:=new.total_amount;
 else new.paid_at:=null; new.amount_received:=0; end if;
 new.updated_at:=now(); return new;
end $$;
drop trigger if exists orders_set_defaults on public.orders;
create trigger orders_set_defaults before insert or update on public.orders for each row execute function public.set_order_defaults();

create or replace function public.recalculate_order_total()
returns trigger language plpgsql set search_path=public,pg_temp as $$
declare v_order_id uuid;
begin
 if tg_op = 'DELETE' then
    v_order_id := old.order_id;
  else
    v_order_id := new.order_id;
  end if;
 update public.orders o set
  total_amount=coalesce((select sum(i.line_total) from public.order_items i where i.order_id=v_order_id),0),
  amount_received=case when o.payment_status='paid' then coalesce((select sum(i.line_total) from public.order_items i where i.order_id=v_order_id),0) else 0 end,
  updated_at=now()
 where o.id=v_order_id;
 return null;
end $$;
drop trigger if exists order_items_recalculate_total on public.order_items;
create trigger order_items_recalculate_total after insert or update or delete on public.order_items for each row execute function public.recalculate_order_total();

create or replace function public.save_order(
 p_order_id uuid,p_customer_id uuid,p_order_date date,p_preparation_status text,
 p_payment_status text,p_notes text,p_items jsonb
) returns uuid language plpgsql security invoker set search_path=public,pg_temp as $$
declare v_order_id uuid;
begin
 if not exists(select 1 from public.staff_profiles s where s.user_id=(select auth.uid()) and s.is_active) then raise exception 'Not authorized'; end if;
 if p_items is null or jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items)=0 then raise exception 'At least one order item is required'; end if;
 if p_order_id is null then
  insert into public.orders(customer_id,order_date,preparation_status,payment_status,notes)
  values(p_customer_id,coalesce(p_order_date,current_date),p_preparation_status,p_payment_status,p_notes) returning id into v_order_id;
 else
  update public.orders set customer_id=p_customer_id,order_date=coalesce(p_order_date,current_date),
   preparation_status=p_preparation_status,payment_status=p_payment_status,notes=p_notes
   where id=p_order_id returning id into v_order_id;
  if v_order_id is null then raise exception 'Order not found or access denied'; end if;
  delete from public.order_items where order_id=v_order_id;
 end if;
 insert into public.order_items(order_id,product_id,item_name,quantity_kg,rate_per_kg)
 select v_order_id,nullif(x.product_id,'')::uuid,btrim(x.item_name),x.quantity_kg,x.rate_per_kg
 from jsonb_to_recordset(p_items) as x(product_id text,item_name text,quantity_kg numeric,rate_per_kg numeric);
 return v_order_id;
end $$;
revoke all on function public.save_order(uuid,uuid,date,text,text,text,jsonb) from public,anon;
grant execute on function public.save_order(uuid,uuid,date,text,text,text,jsonb) to authenticated;

create or replace view public.revenue_monthly with (security_invoker=true) as
select date_trunc('month',paid_at)::date as revenue_month,count(*)::integer as paid_orders,
 coalesce(sum(total_amount),0)::numeric(12,2) as revenue_received
from public.orders where payment_status='paid' and paid_at is not null group by 1;
revoke all on public.revenue_monthly from anon;
grant select on public.revenue_monthly to authenticated;

insert into public.products(name,rate_per_kg,sort_order) values
 ('Sata Sweet (Ghee)',550,1),('Sata Sweet (Oil)',500,2),
 ('Dry Fruit Ghughara (Ghee)',800,3),('Dry Fruit Ghughara (Oil)',750,4)
on conflict(name) do nothing;


-- Private one-time owner bootstrap. kr_private is not an exposed Data API schema.
create schema if not exists kr_private;
revoke all on schema kr_private from public, anon, authenticated;
create table if not exists kr_private.bootstrap_config (
  id integer primary key check (id = 1),
  code_hash text not null,
  consumed_at timestamptz
);
revoke all on kr_private.bootstrap_config from public, anon, authenticated;
insert into kr_private.bootstrap_config(id, code_hash, consumed_at)
values (1, '55dfd2d7a29006f68e5072981e34aea50e97227e0fd3ee98f9ed086a292c4530', null)
on conflict (id) do nothing;

create or replace function public.claim_bootstrap_admin(
  p_code_hash text,
  p_user_id uuid,
  p_display_name text
) returns void
language plpgsql
security definer
set search_path = public, kr_private, pg_temp
as $$
begin
  update kr_private.bootstrap_config
     set consumed_at = now()
   where id = 1 and consumed_at is null and code_hash = p_code_hash;
  if not found then raise exception 'Invalid or already-used setup code'; end if;
  insert into public.staff_profiles(user_id, display_name, is_active)
  values (p_user_id, coalesce(nullif(btrim(p_display_name), ''), 'KR Makers Admin'), true);
end
$$;
revoke all on function public.claim_bootstrap_admin(text, uuid, text) from public, anon, authenticated;
grant execute on function public.claim_bootstrap_admin(text, uuid, text) to service_role;
