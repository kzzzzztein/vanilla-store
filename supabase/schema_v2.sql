-- Jade Steam v2 migration. Run AFTER schema.sql, in Supabase SQL Editor. Safe to re-run.
alter table public.store_settings
 add column if not exists gcash_number text, add column if not exists gcash_name text, add column if not exists gcash_qr_url text,
 add column if not exists bank_name text, add column if not exists bank_account_name text, add column if not exists bank_account_number text;
alter table public.orders
 add column if not exists promo_code text, add column if not exists affiliate_code text, add column if not exists payment_method text, add column if not exists distance_tier text;
alter table public.promos add column if not exists description text;

-- ---------- storage buckets ----------
insert into storage.buckets(id,name,public) values('payment-proofs','payment-proofs',false),('product-photos','product-photos',true) on conflict(id) do nothing;
drop policy if exists "guests upload proofs" on storage.objects; drop policy if exists "admin reads proofs" on storage.objects;
drop policy if exists "photos public read" on storage.objects; drop policy if exists "admin manages photos" on storage.objects;
create policy "guests upload proofs" on storage.objects for insert to anon,authenticated with check(bucket_id='payment-proofs' and octet_length(name)<200);
create policy "admin reads proofs" on storage.objects for select to authenticated using(bucket_id='payment-proofs' and public.is_admin());
create policy "photos public read" on storage.objects for select to anon,authenticated using(bucket_id='product-photos');
create policy "admin manages photos" on storage.objects for all to authenticated using(bucket_id='product-photos' and public.is_admin()) with check(bucket_id='product-photos' and public.is_admin());

-- ---------- public config (payment details are meant to be shown to customers) ----------
create or replace function public.public_config() returns jsonb language sql stable security definer set search_path=public as $$
 select jsonb_build_object('affiliate_enabled',affiliate_enabled,'promos_enabled',promos_enabled,'referral_window_days',referral_window_days,
  'gcash_number',gcash_number,'gcash_name',gcash_name,'gcash_qr_url',gcash_qr_url,'bank_name',bank_name,'bank_account_name',bank_account_name,'bank_account_number',bank_account_number) from public.store_settings $$;

create or replace function public.public_vouchers() returns setof jsonb language sql stable security definer set search_path=public as $$
 select jsonb_build_object('code',code,'name',name,'kind',kind,'value',value,'minimum_spend',minimum_spend,'max_discount',max_discount,'ends_at',ends_at,'eligible_product_ids',eligible_product_ids)
 from public.promos where active and (select promos_enabled from public.store_settings) and (starts_at is null or starts_at<=now()) and (ends_at is null or ends_at>=now()) and (max_uses is null or used_count<max_uses) $$;

-- ---------- voucher validation: single source of truth, also used by place_order ----------
create or replace function public.check_voucher(p_code text,p_items jsonb,p_email text default '',p_ship numeric default 0) returns jsonb language plpgsql stable security definer set search_path=public as $$
declare pm public.promos; it jsonb; pr public.products; q int; qual numeric:=0; d numeric:=0;
begin
 if not (select promos_enabled from public.store_settings) then return jsonb_build_object('ok',false,'message','Promotions are currently unavailable.'); end if;
 select * into pm from public.promos where upper(code)=upper(trim(coalesce(p_code,'')));
 if pm.id is null then return jsonb_build_object('ok',false,'message','Voucher code not found.'); end if;
 if not pm.active then return jsonb_build_object('ok',false,'message','This voucher is disabled.'); end if;
 if pm.starts_at is not null and pm.starts_at>now() then return jsonb_build_object('ok',false,'message','This voucher is not active yet.'); end if;
 if pm.ends_at is not null and pm.ends_at<now() then return jsonb_build_object('ok',false,'message','This voucher has expired.'); end if;
 if pm.max_uses is not null and pm.used_count>=pm.max_uses then return jsonb_build_object('ok',false,'message','This voucher has been fully redeemed.'); end if;
 if pm.per_customer_limit is not null and coalesce(p_email,'')<>'' and (select count(*) from public.orders where promo_id=pm.id and lower(customer_email)=lower(p_email) and order_status not in('cancelled','refunded'))>=pm.per_customer_limit then
  return jsonb_build_object('ok',false,'message','You have already used this voucher the maximum number of times.'); end if;
 for it in select * from jsonb_array_elements(p_items) loop
  select * into pr from public.products where id=(it->>'id')::bigint; q:=greatest(1,coalesce((it->>'qty')::int,1));
  if pr.id is not null and (pm.eligible_product_ids is null or cardinality(pm.eligible_product_ids)=0 or pr.id=any(pm.eligible_product_ids)) then qual:=qual+pr.price*q; end if;
 end loop;
 if qual=0 then return jsonb_build_object('ok',false,'message','No products in your bag are eligible for this voucher.'); end if;
 if qual<pm.minimum_spend then return jsonb_build_object('ok',false,'message','Spend ₱'||(pm.minimum_spend-qual)||' more on eligible products to use this voucher (minimum ₱'||pm.minimum_spend||').'); end if;
 d:=case pm.kind when 'fixed' then pm.value when 'percent' then qual*pm.value/100 else least(coalesce(p_ship,0),case when pm.value>0 then pm.value else coalesce(p_ship,0) end) end;
 if pm.kind<>'shipping' then d:=least(d,qual); end if;
 if pm.max_discount is not null then d:=least(d,pm.max_discount); end if;
 return jsonb_build_object('ok',true,'promo_id',pm.id,'code',pm.code,'discount',round(d,2),'message',pm.code||' applied — ₱'||round(d,2)||' off.');
end $$;

-- ---------- guest checkout: all prices, stock, shipping and discounts computed here ----------
create or replace function public.place_order(p jsonb) returns jsonb language plpgsql security definer set search_path=public as $$
declare s public.store_settings; it jsonb; pr public.products; q int; sub numeric:=0; ship numeric; v jsonb; disc numeric:=0; tot numeric; oid uuid; ref text; aff public.affiliates; pay jsonb:=p->'payment'; pid uuid;
begin
 select * into s from public.store_settings;
 if coalesce(trim(p->>'name'),'')='' or coalesce(p->>'email','') !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' or coalesce(p->>'phone','') !~ '^09[0-9]{9}$' then raise exception 'Please enter a valid name, email and mobile number (09XXXXXXXXX).'; end if;
 if jsonb_typeof(p->'items') is distinct from 'array' or jsonb_array_length(p->'items')=0 then raise exception 'Your bag is empty.'; end if;
 ship:=case p->>'distance' when 'a' then 150 when 'b' then 350 when 'd' then 500 else null end;
 if ship is null then raise exception 'Delivery for 26–29 km must be confirmed with the store first. Please contact us.'; end if;
 if pay is null or coalesce(pay->>'reference','')='' or coalesce(pay->>'proof_path','')='' or coalesce((pay->>'amount')::numeric,0)<=0 or coalesce(pay->>'method','') not in('gcash','bank') or coalesce(pay->>'paid_at','')='' then
  raise exception 'Payment method, amount, reference number, payment date/time and a screenshot are all required.'; end if;
 for it in select * from jsonb_array_elements(p->'items') loop
  q:=(it->>'qty')::int; if q is null or q<1 or q>99 then raise exception 'Invalid quantity.'; end if;
  select * into pr from public.products where id=(it->>'id')::bigint and active for update;
  if pr.id is null then raise exception 'A product in your bag is no longer available.'; end if;
  if pr.stock<q then raise exception '% has only % left in stock.',pr.name,pr.stock; end if;
  sub:=sub+pr.price*q;
 end loop;
 if coalesce(p->>'voucher','')<>'' then
  v:=public.check_voucher(p->>'voucher',(select jsonb_agg(jsonb_build_object('id',e->>'id','qty',e->>'qty')) from jsonb_array_elements(p->'items') e),p->>'email',ship);
  if not (v->>'ok')::boolean then raise exception '%',v->>'message'; end if; disc:=(v->>'discount')::numeric;
 end if;
 tot:=greatest(0,sub+ship-disc);
 if s.affiliate_enabled and coalesce(p->>'ref','')<>'' and (p->>'ref_at')::timestamptz>now()-make_interval(days=>s.referral_window_days) then
  select * into aff from public.affiliates where upper(referral_code)=upper(p->>'ref') and status='active' and lower(email)<>lower(p->>'email');
 end if;
 insert into public.orders(customer_name,customer_email,customer_phone,delivery_address,delivery_schedule,delivery_instructions,subtotal,discount,shipping_fee,total,promo_id,promo_code,affiliate_id,affiliate_code,payment_status,payment_method,distance_tier)
 values(trim(p->>'name'),lower(trim(p->>'email')),p->>'phone',coalesce(p->'address','{}'::jsonb),p->>'schedule',p->>'instructions',sub,disc,ship,tot,nullif(v->>'promo_id','')::uuid,v->>'code',aff.id,aff.referral_code,'submitted',pay->>'method',p->>'distance')
 returning id,reference into oid,ref;
 for it in select * from jsonb_array_elements(p->'items') loop
  select * into pr from public.products where id=(it->>'id')::bigint; q:=(it->>'qty')::int;
  insert into public.order_items(order_id,product_id,product_name,variant,quantity,unit_price,pass_on_price) values(oid,pr.id,pr.name,left(it->>'variant',80),q,pr.price,pr.pass_on_price);
  update public.products set stock=stock-q where id=pr.id;
 end loop;
 if v is not null then update public.promos set used_count=used_count+1 where id=(v->>'promo_id')::uuid; end if;
 insert into public.payment_submissions(order_id,method,reference_number,amount_sent,paid_at,proof_path) values(oid,pay->>'method',left(pay->>'reference',80),(pay->>'amount')::numeric,(pay->>'paid_at')::timestamptz,pay->>'proof_path');
 return jsonb_build_object('reference',ref,'total',tot);
end $$;

-- ---------- guest tracking: needs reference AND phone number ----------
create or replace function public.track_order(p_ref text,p_phone text) returns jsonb language sql stable security definer set search_path=public as $$
 select jsonb_build_object('reference',o.reference,'customer',o.customer_name,'total',o.total,'city',o.delivery_address->>'city','payment_status',o.payment_status,'order_status',o.order_status,'courier_tracking_url',o.courier_tracking_url,'created_at',o.created_at,
  'packs',(select coalesce(sum(quantity),0) from public.order_items where order_id=o.id))
 from public.orders o where upper(o.reference)=upper(trim(p_ref)) and o.customer_phone=trim(p_phone) $$;

-- ---------- affiliates ----------
create or replace function public.track_click(p_code text) returns boolean language plpgsql security definer set search_path=public as $$
declare a uuid; begin
 if not (select affiliate_enabled from public.store_settings) then return false; end if;
 select id into a from public.affiliates where upper(referral_code)=upper(p_code) and status='active'; if a is null then return false; end if;
 insert into public.affiliate_clicks(affiliate_id) values(a); return true; end $$;
create or replace function public.affiliate_apply(p_name text,p_phone text,p_payout text) returns void language plpgsql security definer set search_path=public as $$
declare em text; begin
 if auth.uid() is null then raise exception 'Please sign in first.'; end if;
 if not (select affiliate_enabled from public.store_settings) then raise exception 'The affiliate program is currently closed.'; end if;
 if exists(select 1 from public.affiliates where user_id=auth.uid()) then raise exception 'You have already applied.'; end if;
 select email into em from auth.users where id=auth.uid();
 insert into public.affiliates(user_id,full_name,email,phone,payout_details,referral_code,status,commission_type,commission_value)
 values(auth.uid(),trim(p_name),em,trim(p_phone),trim(p_payout),upper(substr(replace(gen_random_uuid()::text,'-',''),1,8)),'pending','percent',0); end $$;
create or replace function public.my_affiliate() returns jsonb language sql stable security definer set search_path=public as $$
 select to_jsonb(a)-'payout_details'||jsonb_build_object(
  'enabled',(select affiliate_enabled from public.store_settings),
  'clicks',(select count(*) from public.affiliate_clicks where affiliate_id=a.id),
  'orders',(select count(*) from public.orders where affiliate_id=a.id),
  'sales',(select coalesce(sum(subtotal-discount),0) from public.orders where affiliate_id=a.id and payment_status='verified' and order_status='delivered'),
  'pending',(select coalesce(sum(amount),0) from public.commissions where affiliate_id=a.id and status='pending'),
  'approved',(select coalesce(sum(amount),0) from public.commissions where affiliate_id=a.id and status='approved'),
  'paid',(select coalesce(sum(amount),0) from public.commissions where affiliate_id=a.id and status='paid'))
 from public.affiliates a where a.user_id=auth.uid() $$;

-- ---------- order lifecycle: restock + void on cancel/refund, commission on verified+delivered ----------
create or replace function public.on_order_change() returns trigger language plpgsql security definer set search_path=public as $$
begin
 if new.order_status in('cancelled','refunded') and old.order_status not in('cancelled','refunded') then
  update public.products p set stock=p.stock+i.quantity from public.order_items i where i.order_id=new.id and i.product_id=p.id;
  update public.commissions set status='void' where order_id=new.id and status<>'paid';
  if new.promo_id is not null then update public.promos set used_count=greatest(0,used_count-1) where id=new.promo_id; end if;
 end if;
 if new.affiliate_id is not null and new.payment_status='verified' and new.order_status='delivered' and not exists(select 1 from public.commissions where order_id=new.id) then
  insert into public.commissions(affiliate_id,order_id,amount)
  select a.id,new.id,round(greatest(0,case a.commission_type when 'percent' then (new.subtotal-new.discount)*a.commission_value/100 else a.commission_value end),2) from public.affiliates a where a.id=new.affiliate_id;
 end if; return new; end $$;
drop trigger if exists trg_order_change on public.orders;
create trigger trg_order_change after update of order_status,payment_status on public.orders for each row execute function public.on_order_change();

revoke all on function public.public_config(),public.public_vouchers(),public.check_voucher(text,jsonb,text,numeric),public.place_order(jsonb),public.track_order(text,text),public.track_click(text),public.affiliate_apply(text,text,text),public.my_affiliate() from public;
grant execute on function public.public_config(),public.public_vouchers(),public.check_voucher(text,jsonb,text,numeric),public.place_order(jsonb),public.track_order(text,text),public.track_click(text) to anon,authenticated;
grant execute on function public.affiliate_apply(text,text,text),public.my_affiliate() to authenticated;
