-- ============================================================
-- MIRHA COLLECTION - SECURE MIGRATION
-- File: supabase/migrations/20261121000000_mirha_secure.sql
-- ============================================================

BEGIN;

create extension if not exists "pgcrypto";

-- 1. ROLES
create table if not exists public.roles (
  id bigint generated always as identity primary key,
  role_name text unique not null check (role_name in ('admin','manager','supervisor','frontdesk')),
  can_view_orders boolean default true,
  can_edit_products boolean default false,
  can_view_cost boolean default false,
  can_manage_team boolean default false,
  can_change_whatsapp boolean default false,
  can_change_settings boolean default false,
  created_at timestamptz default now()
);
insert into public.roles (role_name, can_view_orders, can_edit_products, can_view_cost, can_manage_team, can_change_whatsapp, can_change_settings) values
('admin', true, true, true, true, true, true),
('manager', true, true, false, false, true, false),
('supervisor', true, false, false, false, false, false),
('frontdesk', true, false, false, false, false, false)
on conflict (role_name) do nothing;

-- 2. PROFILES (Staff / Admin roles)
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  username text unique not null check (username ~ '^[a-z0-9_]{3,20}$'),
  role text not null references public.roles(role_name) on update cascade,
  phone text check (phone is null or phone ~ '^03[0-9]{9}$'),
  full_name text check (full_name is null or length(full_name) between 3 and 40),
  address text check (address is null or length(address) between 10 and 120),
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);
create index if not exists idx_profiles_role on public.profiles(role);
create index if not exists idx_profiles_phone on public.profiles(phone);

-- 3. CATEGORIES
create table if not exists public.categories (
  id bigint generated always as identity primary key,
  name text unique not null check (length(name) between 3 and 30),
  emoji text default '📦',
  sort_order int default 0,
  is_active boolean default true,
  created_at timestamptz default now()
);
insert into public.categories (name, emoji, sort_order) values
('Ladies','👩',1),('Gents','👨',2),('Kids','🧒',3),('Sale','🔥',4),('Winter','🧥',5),('New Arrival','✨',6)
on conflict (name) do nothing;

-- 4. TAGS
create table if not exists public.tags (
  id bigint generated always as identity primary key,
  name text unique not null check (length(name) between 3 and 30),
  badge_color text default '#0E7C7B',
  badge_text text default '',
  is_active boolean default true,
  created_at timestamptz default now()
);
insert into public.tags (name, badge_color) values
('Best Selling','#0E7C7B'),('New','#C9A227')
on conflict (name) do nothing;

-- 5. PRODUCTS
create table if not exists public.products (
  id bigint generated always as identity primary key,
  name text not null check (length(name) between 3 and 80),
  category_id bigint not null references public.categories(id) on delete restrict,
  cat text not null,
  price int not null check (price > 0 and price < 100000),
  old_price int check (old_price is null or old_price >= price),
  stock int not null default 0 check (stock >= 0),
  rating text default '4.8',
  tag_id bigint references public.tags(id) on delete set null,
  tag text,
  img text,
  is_active boolean default true,
  deleted_at timestamptz,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);
create index if not exists idx_products_cat on public.products(cat);
create index if not exists idx_products_category_id on public.products(category_id);
create index if not exists idx_products_tag on public.products(tag);
create index if not exists idx_products_active on public.products(is_active);
create index if not exists idx_products_price on public.products(price);

-- 6. ORDER STATUSES
create table if not exists public.order_statuses (
  id bigint generated always as identity primary key,
  status_name text unique not null check (status_name in ('Pending','Confirm','Delivered','Cancelled','Shipped')),
  emoji text default '🟡',
  message text default '',
  sort_order int default 0,
  is_active boolean default true
);
insert into public.order_statuses (status_name, emoji, sort_order) values
('Pending','🟡',1),('Confirm','🔵',2),('Shipped','🚚',3),('Delivered','🟢',4),('Cancelled','🔴',5)
on conflict (status_name) do nothing;

-- 7. ORDERS
create table if not exists public.orders (
  id uuid primary key default gen_random_uuid(),
  order_code text unique not null,
  user_id uuid references auth.users(id) on delete set null,
  customer text not null check (length(customer) between 3 and 40),
  phone text not null check (phone ~ '^03[0-9]{9}$'),
  address text not null check (length(address) between 10 and 120),
  pay text not null check (pay in ('COD','JazzCash','EasyPaisa')),
  tid text check (tid is null or length(tid) between 6 and 30),
  delivery_fee int not null default 0 check (delivery_fee >= 0),
  total int not null check (total > 0),
  status text not null default 'Pending' references public.order_statuses(status_name) on update cascade,
  created_at timestamptz default now(),
  updated_at timestamptz default now(),
  constraint chk_tid_rule check ((pay='COD' and tid is null) or (pay!='COD' and tid is not null))
);
alter table public.orders add column if not exists user_id uuid references auth.users(id) on delete set null;
alter table public.orders add column if not exists delivery_fee int not null default 0;

create index if not exists idx_orders_code on public.orders(order_code);
create unique index if not exists uq_orders_tid_paid on public.orders(tid) where tid is not null and pay != 'COD';
create index if not exists idx_orders_phone on public.orders(phone);
create index if not exists idx_orders_status on public.orders(status);
create index if not exists idx_orders_user_id on public.orders(user_id);

-- 8. ORDER ITEMS
create table if not exists public.order_items (
  id bigint generated always as identity primary key,
  order_id uuid not null references public.orders(id) on delete cascade,
  product_id bigint not null references public.products(id) on delete restrict,
  product_name text not null,
  price_at_order int not null check (price_at_order > 0),
  qty int not null default 1 check (qty > 0 and qty <= 10),
  created_at timestamptz default now()
);
create index if not exists idx_order_items_order on public.order_items(order_id);
create index if not exists idx_order_items_product on public.order_items(product_id);

-- 9. SUPPLIERS
create table if not exists public.suppliers (
  id bigint generated always as identity primary key,
  name text not null check (length(name) between 2 and 80),
  phone text not null check (phone ~ '^03[0-9]{9}$'),
  product text,
  cost int check (cost is null or cost >= 0),
  bank_name text,
  bank_last4 text check (bank_last4 is null or bank_last4 ~ '^[0-9]{4}$'),
  status text check (status in ('Active','Inactive','Pending Payment')) default 'Active',
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);
alter table public.suppliers drop constraint if exists suppliers_name_check;
alter table public.suppliers add constraint suppliers_name_check check (length(name) between 2 and 80);
create index if not exists idx_suppliers_status on public.suppliers(status);
create index if not exists idx_suppliers_phone on public.suppliers(phone);

-- 10. SUPPLIER PAYMENTS
create table if not exists public.supplier_payments (
  id bigint generated always as identity primary key,
  supplier_id bigint not null references public.suppliers(id) on delete cascade,
  amt int not null check (amt > 0),
  note text check (note is null or length(note) <= 60),
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz default now()
);

-- 11. WISHLISTS
create table if not exists public.wishlists (
  id bigint generated always as identity primary key,
  phone text not null check (phone ~ '^03[0-9]{9}$'),
  product_id bigint not null references public.products(id) on delete cascade,
  created_at timestamptz default now(),
  unique (phone, product_id)
);

-- 12. OTPS (locked legacy table)
create table if not exists public.otps (
  id bigint generated always as identity primary key,
  phone text not null check (phone ~ '^03[0-9]{9}$'),
  otp_hash text not null,
  expires_at timestamptz not null default (now() + interval '5 minutes'),
  attempts int default 0 check (attempts >= 0 and attempts <= 3),
  is_used boolean default false,
  created_at timestamptz default now()
);

-- 13. SETTINGS
create table if not exists public.settings (
  key text primary key,
  value jsonb not null,
  updated_by uuid references auth.users(id) on delete set null,
  updated_at timestamptz default now()
);
insert into public.settings (key, value) values
('store','{"name":"MIRHA COLLECTION","tagline":"Premium Suits","city":"Risalpur","area":"Nowshera, KPK"}'),
('topbar','{"text":"🔥 New Products | FREE Delivery Rs.3000+ pe | COD Available"}'),
('hero','{"title":"Premium Suits, Best Selling + New Arrival.","sub":"Ladies • Gents • Kids • Sale • Winter - COD Available"}'),
('footer','{"text":"MIRHA COLLECTION - Risalpur, Nowshera, KPK","copyright":"© 2026 MIRHA COLLECTION"}'),
('delivery','{"risalpur_days":"1-2 din","other_days":"2-3 din","free_above":3000,"charge":200,"cod":true}'),
('payments','[{"name":"COD","enabled":true,"tid_required":false},{"name":"JazzCash","enabled":true,"tid_required":true},{"name":"EasyPaisa","enabled":true,"tid_required":true}]'),
('whatsapp','{"num":"03427349881","name":"Mirha Collection","time":"9am-10pm","msg":"Salam Mirha Collection!"}'),
('theme','{"name":"Black + Gold + Teal","black":"#0A0A0A","gold":"#C9A227","teal":"#0E7C7B"}'),
('announcement','{"enabled":true,"text":"Eid Offer - 20% Off","bg":"#C9A227"}'),
('hero_image','{"url":"","enabled":false}'),
('seo','{"title":"MIRHA COLLECTION - Risalpur","desc":"Ladies, Gents, Kids Suits - COD Available"}'),
('social','{"whatsapp":"03427349881","facebook":"","instagram":"","tiktok":""}')
on conflict (key) do nothing;

-- 14. AUDIT LOGS
create table if not exists public.audit_logs (
  id bigint generated always as identity primary key,
  user_id uuid references auth.users(id) on delete set null,
  action text not null,
  table_name text,
  record_id text,
  old_value jsonb,
  new_value jsonb,
  ip text,
  device text,
  created_at timestamptz default now()
);

-- 15. SESSIONS
create table if not exists public.sessions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  device_name text,
  device_fingerprint text not null,
  ip text,
  last_active timestamptz default now(),
  created_at timestamptz default now(),
  expires_at timestamptz not null,
  is_active boolean default true,
  user_type text check (user_type in ('customer','admin'))
);

-- 16. LOGIN ATTEMPTS
create table if not exists public.login_attempts (
  id bigint generated always as identity primary key,
  identifier text not null,
  ip text,
  success boolean default false,
  created_at timestamptz default now()
);

-- ============================================================
-- TRIGGERS & HELPER FUNCTIONS
-- ============================================================

create or replace function public.update_updated_at()
returns trigger language plpgsql set search_path = public as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists trg_profiles_updated on public.profiles;
create trigger trg_profiles_updated before update on public.profiles for each row execute function public.update_updated_at();
drop trigger if exists trg_products_updated on public.products;
create trigger trg_products_updated before update on public.products for each row execute function public.update_updated_at();
drop trigger if exists trg_orders_updated on public.orders;
create trigger trg_orders_updated before update on public.orders for each row execute function public.update_updated_at();
drop trigger if exists trg_suppliers_updated on public.suppliers;
create trigger trg_suppliers_updated before update on public.suppliers for each row execute function public.update_updated_at();

create or replace function public.sync_product_cache()
returns trigger language plpgsql set search_path = public as $$
begin
  if tg_table_name = 'categories' then
    update public.products set cat = new.name where category_id = new.id;
  elsif tg_table_name = 'tags' then
    update public.products set tag = new.name where tag_id = new.id;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_sync_cat on public.categories;
create trigger trg_sync_cat after update on public.categories for each row execute function public.sync_product_cache();
drop trigger if exists trg_sync_tag on public.tags;
create trigger trg_sync_tag after update on public.tags for each row execute function public.sync_product_cache();

create or replace function public.fill_product_labels()
returns trigger language plpgsql set search_path = public as $$
begin
  select name into new.cat from public.categories where id = new.category_id;
  if new.cat is null then
    raise exception 'Invalid category_id';
  end if;
  if new.tag_id is not null then
    select name into new.tag from public.tags where id = new.tag_id;
  else
    new.tag := null;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_products_fill_labels on public.products;
create trigger trg_products_fill_labels before insert or update of category_id, tag_id on public.products
for each row execute function public.fill_product_labels();

create or replace function public.has_role(p_roles text[])
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and role = any(p_roles)
  );
$$;

create or replace function public.current_user_phone_local()
returns text language sql stable security definer set search_path = public, auth as $$
  select regexp_replace(
    coalesce(
      nullif(auth.jwt() ->> 'phone', ''),
      (select u.phone from auth.users u where u.id = auth.uid()),
      ''
    ),
    '^\+?92',
    '0'
  );
$$;

-- ============================================================
-- APPLICATION RPCs
-- ============================================================

drop function if exists public.get_my_orders(text, text);
drop function if exists public.get_my_orders();

create or replace function public.get_my_orders()
returns table(
  order_code text,
  status text,
  total int,
  pay text,
  created_at timestamptz,
  items_names text
)
language plpgsql stable security definer set search_path = public as $$
declare
  v_phone text;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;
  v_phone := public.current_user_phone_local();
  if not (v_phone ~ '^03[0-9]{9}$') then
    raise exception 'Verified phone number required';
  end if;

  return query
  select
    o.order_code,
    o.status,
    o.total,
    o.pay,
    o.created_at,
    (
      select string_agg(oi.product_name || ' x' || oi.qty, ', ' order by oi.id)
      from public.order_items oi
      where oi.order_id = o.id
    ) as items_names
  from public.orders o
  where o.phone = v_phone
  order by o.created_at desc
  limit 100;
end;
$$;

drop function if exists public.track_order(text);
create or replace function public.track_order(p_code text)
returns table(
  order_code text,
  status text,
  total int,
  items_names text,
  created_at timestamptz
)
language plpgsql stable security definer set search_path = public as $$
declare
  v_code text := upper(trim(coalesce(p_code, '')));
begin
  if length(v_code) < 5 or length(v_code) > 30 then
    return;
  end if;

  return query
  select
    o.order_code,
    o.status,
    o.total,
    (
      select string_agg(oi.product_name || ' x' || oi.qty, ', ' order by oi.id)
      from public.order_items oi
      where oi.order_id = o.id
    ) as items_names,
    o.created_at
  from public.orders o
  where o.order_code = v_code
  limit 1;
end;
$$;

drop function if exists public.create_order(jsonb, text, text, text, text, text);
create or replace function public.create_order(
  p_items jsonb,
  p_customer text,
  p_phone text,
  p_address text,
  p_pay text,
  p_tid text
)
returns public.orders
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_auth_phone text;
  v_customer text := trim(coalesce(p_customer, ''));
  v_phone text := trim(coalesce(p_phone, ''));
  v_address text := trim(coalesce(p_address, ''));
  v_pay text := trim(coalesce(p_pay, ''));
  v_tid text := nullif(trim(coalesce(p_tid, '')), '');
  v_pay_cfg jsonb;
  v_tid_required boolean := false;
  v_delivery_cfg jsonb;
  v_free_above int := 3000;
  v_charge int := 200;
  v_delivery_fee int := 0;
  v_subtotal int := 0;
  v_total int := 0;
  v_item jsonb;
  v_pid bigint;
  v_qty int;
  v_price int;
  v_stock int;
  v_active boolean;
  v_code text;
  v_order public.orders;
  v_seen_ids bigint[] := '{}';
begin
  if v_uid is null then
    raise exception 'Authentication required';
  end if;

  v_auth_phone := public.current_user_phone_local();
  if not (v_phone ~ '^03[0-9]{9}$') then
    raise exception 'Phone galat hai (03xxxxxxxxx)';
  end if;
  if v_auth_phone != v_phone then
    raise exception 'Order phone must match your verified phone number';
  end if;

  if length(v_customer) < 3 or length(v_customer) > 40 then
    raise exception 'Naam 3 se 40 characters ka hona chahiye';
  end if;
  if length(v_address) < 10 or length(v_address) > 120 then
    raise exception 'Full address kam az kam 10 characters likhein';
  end if;

  select elem into v_pay_cfg
  from public.settings s,
       lateral jsonb_array_elements(s.value) elem
  where s.key = 'payments'
    and elem->>'name' = v_pay
    and coalesce((elem->>'enabled')::boolean, false) = true
  limit 1;

  if v_pay_cfg is null then
    raise exception 'Payment method invalid ya disabled hai';
  end if;

  v_tid_required := coalesce((v_pay_cfg->>'tid_required')::boolean, v_pay != 'COD');
  if v_tid_required then
    if v_tid is null or length(v_tid) < 6 or length(v_tid) > 30 then
      raise exception 'Valid TID (6-30 characters) likhein';
    end if;
    if exists (select 1 from public.orders where tid = v_tid and pay != 'COD') then
      raise exception 'Ye TID pehle use ho chuka hai';
    end if;
  else
    v_tid := null;
  end if;

  if p_items is null or jsonb_typeof(p_items) != 'array' or jsonb_array_length(p_items) < 1 or jsonb_array_length(p_items) > 20 then
    raise exception 'Cart items invalid hain';
  end if;

  for v_item in
    select value from jsonb_array_elements(p_items) order by (value->>'id')::bigint asc
  loop
    v_pid := (v_item->>'id')::bigint;
    v_qty := (v_item->>'qty')::int;

    if v_pid is null or v_pid <= 0 or v_qty is null or v_qty < 1 or v_qty > 10 then
      raise exception 'Product quantity 1 se 10 ke darmiyan honi chahiye';
    end if;
    if v_pid = any(v_seen_ids) then
      raise exception 'Duplicate product in cart';
    end if;
    v_seen_ids := array_append(v_seen_ids, v_pid);

    select price, stock, is_active
      into v_price, v_stock, v_active
    from public.products
    where id = v_pid
    for update;

    if not found or not v_active then
      raise exception 'Product available nahi hai';
    end if;
    if v_stock < v_qty then
      raise exception 'Stock kam ya khatam hai';
    end if;

    v_subtotal := v_subtotal + (v_price * v_qty);
  end loop;

  select value into v_delivery_cfg from public.settings where key = 'delivery';
  if v_delivery_cfg is not null then
    v_free_above := coalesce((v_delivery_cfg->>'free_above')::int, 3000);
    v_charge := coalesce((v_delivery_cfg->>'charge')::int, 200);
  end if;
  v_delivery_fee := case when v_subtotal >= v_free_above then 0 else v_charge end;
  v_total := v_subtotal + v_delivery_fee;

  loop
    v_code := 'MIRHA-' || upper(substr(encode(gen_random_bytes(3), 'hex'), 1, 6));
    exit when not exists (select 1 from public.orders where order_code = v_code);
  end loop;

  insert into public.orders (order_code, user_id, customer, phone, address, pay, tid, delivery_fee, total, status)
  values (v_code, v_uid, v_customer, v_phone, v_address, v_pay, v_tid, v_delivery_fee, v_total, 'Pending')
  returning * into v_order;

  for v_item in select * from jsonb_array_elements(p_items)
  loop
    v_pid := (v_item->>'id')::bigint;
    v_qty := (v_item->>'qty')::int;

    insert into public.order_items (order_id, product_id, product_name, price_at_order, qty)
    select v_order.id, p.id, p.name, p.price, v_qty
    from public.products p where p.id = v_pid;

    update public.products
    set stock = stock - v_qty
    where id = v_pid and stock >= v_qty;
  end loop;

  insert into public.audit_logs (user_id, action, table_name, record_id, new_value)
  values (v_uid, 'Order Create', 'orders', v_code, jsonb_build_object('total', v_total, 'pay', v_pay));

  return v_order;
end;
$$;

create or replace function public.get_store_stats()
returns table(
  total_products bigint,
  total_orders bigint,
  total_sale bigint,
  pending_count bigint,
  best_count bigint,
  new_count bigint
)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.has_role(array['admin','manager','supervisor','frontdesk']) then
    raise exception 'Unauthorized';
  end if;

  return query select
    (select count(*) from public.products where is_active = true),
    (select count(*) from public.orders),
    (select coalesce(sum(total), 0) from public.orders where status != 'Cancelled'),
    (select count(*) from public.orders where status = 'Pending'),
    (select count(*) from public.products where tag = 'Best Selling' and is_active = true),
    (select count(*) from public.products where tag = 'New' and is_active = true);
end;
$$;

create or replace function public.cleanup_expired_sessions()
returns void language plpgsql security definer set search_path = public as $$
begin
  update public.sessions set is_active = false where expires_at < now() and is_active = true;
  delete from public.otps where expires_at < now();
  delete from public.login_attempts where created_at < now() - interval '7 days';
end;
$$;

-- ============================================================
-- RLS & LEAST-PRIVILEGE GRANTS (MIRHA TABLES ONLY)
-- ============================================================

alter table public.roles enable row level security;
alter table public.profiles enable row level security;
alter table public.categories enable row level security;
alter table public.tags enable row level security;
alter table public.products enable row level security;
alter table public.order_statuses enable row level security;
alter table public.orders enable row level security;
alter table public.order_items enable row level security;
alter table public.suppliers enable row level security;
alter table public.supplier_payments enable row level security;
alter table public.wishlists enable row level security;
alter table public.otps enable row level security;
alter table public.settings enable row level security;
alter table public.audit_logs enable row level security;
alter table public.sessions enable row level security;
alter table public.login_attempts enable row level security;

do $$
declare
  r record;
begin
  for r in (
    select policyname, tablename
    from pg_policies
    where schemaname = 'public'
      and tablename = any(array[
        'roles','profiles','categories','tags','products','order_statuses',
        'orders','order_items','suppliers','supplier_payments','wishlists',
        'otps','settings','audit_logs','sessions','login_attempts'
      ])
  ) loop
    execute format('drop policy if exists %I on public.%I', r.policyname, r.tablename);
  end loop;
end $$;

revoke all on all tables in schema public from anon, authenticated;
revoke all on all sequences in schema public from anon, authenticated;

grant select on public.products, public.categories, public.tags, public.settings, public.order_statuses to anon, authenticated;
grant insert, update, delete on public.products, public.categories, public.tags to authenticated;
grant insert, update on public.settings to authenticated;
grant select on public.profiles, public.roles to authenticated;
grant insert, update, delete on public.profiles to authenticated;
grant select on public.orders, public.order_items to authenticated;
grant update (status) on public.orders to authenticated;
grant select (id, name, phone, product, status, created_at, updated_at) on public.suppliers to authenticated;
grant select, insert on public.supplier_payments to authenticated;
grant select, insert, delete on public.wishlists to authenticated;
grant select, update on public.sessions to authenticated;
grant select on public.audit_logs to authenticated;

revoke all on function public.create_order(jsonb,text,text,text,text,text) from public, anon;
grant execute on function public.create_order(jsonb,text,text,text,text,text) to authenticated;

revoke all on function public.get_my_orders() from public, anon;
grant execute on function public.get_my_orders() to authenticated;

revoke all on function public.track_order(text) from public;
grant execute on function public.track_order(text) to anon, authenticated;

revoke all on function public.get_store_stats() from public, anon;
grant execute on function public.get_store_stats() to authenticated;

revoke all on function public.has_role(text[]) from public;
grant execute on function public.has_role(text[]) to authenticated;

create policy "products public read" on public.products for select
  using (is_active = true or public.has_role(array['admin','manager','supervisor','frontdesk']));
create policy "products staff write" on public.products for all
  using (public.has_role(array['admin','manager']))
  with check (public.has_role(array['admin','manager']));

create policy "categories public read" on public.categories for select
  using (is_active = true or public.has_role(array['admin','manager']));
create policy "categories staff write" on public.categories for all
  using (public.has_role(array['admin','manager']))
  with check (public.has_role(array['admin','manager']));

create policy "tags public read" on public.tags for select
  using (is_active = true or public.has_role(array['admin','manager']));
create policy "tags staff write" on public.tags for all
  using (public.has_role(array['admin','manager']))
  with check (public.has_role(array['admin','manager']));

create policy "settings public read" on public.settings for select using (true);
create policy "settings admin write" on public.settings for all
  using (public.has_role(array['admin']))
  with check (public.has_role(array['admin']));

create policy "statuses public read" on public.order_statuses for select using (is_active = true);
create policy "roles staff read" on public.roles for select
  using (public.has_role(array['admin','manager','supervisor','frontdesk']));

create policy "profiles self or admin read" on public.profiles for select
  using (id = auth.uid() or public.has_role(array['admin']));
create policy "profiles admin write" on public.profiles for all
  using (public.has_role(array['admin']))
  with check (public.has_role(array['admin']));

create policy "orders staff read" on public.orders for select
  using (public.has_role(array['admin','manager','supervisor','frontdesk']));
create policy "orders staff update status" on public.orders for update
  using (public.has_role(array['admin','manager','supervisor','frontdesk']))
  with check (public.has_role(array['admin','manager','supervisor','frontdesk']));

create policy "order_items staff read" on public.order_items for select
  using (public.has_role(array['admin','manager','supervisor','frontdesk']));

create policy "suppliers staff read non_sensitive" on public.suppliers for select
  using (public.has_role(array['admin','manager','supervisor']));

create policy "supplier_payments admin all" on public.supplier_payments for all
  using (public.has_role(array['admin']))
  with check (public.has_role(array['admin']));

create policy "wishlists owner only" on public.wishlists for all
  using (phone = public.current_user_phone_local())
  with check (phone = public.current_user_phone_local());

create policy "otps block all" on public.otps for all using (false) with check (false);
create policy "login_attempts block all" on public.login_attempts for all using (false) with check (false);

create policy "audit_logs admin read" on public.audit_logs for select
  using (public.has_role(array['admin']));

create policy "sessions owner or admin" on public.sessions for select
  using (user_id = auth.uid() or public.has_role(array['admin']));
create policy "sessions owner or admin update" on public.sessions for update
  using (user_id = auth.uid() or public.has_role(array['admin']))
  with check (user_id = auth.uid() or public.has_role(array['admin']));

insert into public.products (name, category_id, cat, price, old_price, stock, rating, tag_id, tag, img)
select * from (values
  ('Ladies Premium Lawn Suit', 1::bigint, 'Ladies', 2500, 3200, 10, '4.9', 1::bigint, 'Best Selling', 'https://images.unsplash.com/photo-1595777457583-95e059d581b8?w=600'),
  ('Ladies Embroidered Suit', 1::bigint, 'Ladies', 3200, 4000, 8, '4.8', 2::bigint, 'New', 'https://images.unsplash.com/photo-1583939003579-730e3918a45a?w=600'),
  ('Gents Plain Suit - Black', 2::bigint, 'Gents', 2500, 3200, 15, '4.8', 1::bigint, 'Best Selling', 'https://images.unsplash.com/photo-1594938298603-c8148c4dae35?w=600'),
  ('Gents Cotton Suit - White', 2::bigint, 'Gents', 2800, 3500, 12, '4.7', 2::bigint, 'New', 'https://images.unsplash.com/photo-1507679799987-c73779587ccf?w=600'),
  ('Kids Fancy Suit', 3::bigint, 'Kids', 1800, 2200, 8, '4.7', 2::bigint, 'New', 'https://images.unsplash.com/photo-1622290291468-a28f7a7dc6a8?w=600'),
  ('Winter Shawl Suit', 5::bigint, 'Winter', 3500, 4200, 5, '4.9', 1::bigint, 'Best Selling', 'https://images.unsplash.com/photo-1576871337622-98d48d1cf531?w=600')
) as seed(name, category_id, cat, price, old_price, stock, rating, tag_id, tag, img)
where not exists (select 1 from public.products limit 1);

COMMIT;