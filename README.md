# Jade Steam — dim sum storefront + Supabase backend

Static HTML/CSS/JS (GitHub Pages compatible). Runs in **demo mode** until Supabase is connected.

## Setup
1. Create a Supabase project. In **SQL Editor** run, in this order: `supabase/schema.sql`, then `supabase/schema_v2.sql` (safe to re-run).
2. **Authentication → Users**: create your admin user, then promote ONLY that user:
   ```sql
   insert into public.profiles(id,role,full_name) values ('AUTH-USER-UUID','admin','Store Administrator')
   on conflict (id) do update set role='admin';
   ```
3. Put the **Project URL** and **publishable/anon key** in `supabase-config.js`. Never use the service_role key in these files.
4. Open `/admin.html` → **Settings & payment details**: enter your GCash / bank details (shown to customers at checkout).
5. Add real products (Products → Add). The seeded sample products have `pass-on price = 0`; set the real value for margin reporting.
6. Affiliate program and Promos are **OFF by default** — switch them on in their admin tabs.

## What is implemented
**Customer:** product catalog from Supabase · guest checkout (no account) · server-side price/stock/shipping/discount calculation · one voucher per order with clear invalid-voucher reasons · GCash/bank details + required reference number, amount, date/time and screenshot upload (private bucket) · thank-you pop-up · order confirmation page · tracking by reference + mobile number with 6-step timeline and a rider-tracking button once the admin adds a link · affiliate landing/sign-in/apply/dashboard (only when the program is ON) · `?ref=CODE` attribution with a configurable window, click tracking and self-referral blocking.

**Admin:** dashboard (sales, orders, pending payments, processing, delivery, completed, customers, bestsellers, recent orders) · orders (search, filter, one-click advance, cancel, details, courier link) · payment verification (never automatic; amount-mismatch warning) · products (add/edit, photo upload, pass-on price, variants, storage/cooking text) · reports (daily/weekly/monthly, by product, customers new/repeat/history, estimated margin) · affiliates (toggle, add/edit, links, commission %/₱, performance, pending→approved→paid) · promos (toggle, all fields, schedule, limits, tracking) · date-range filter across all tabs.

**Rules enforced in the database:** commission only for verified + delivered orders; cancelled/refunded orders restock, void unpaid commissions and release the voucher use; expired/inactive/exhausted/under-minimum vouchers rejected; program OFF stops new links and tracking but keeps history.

## Not yet implemented
- **Email / SMS notifications** — need a Supabase Edge Function plus a provider (e.g. Resend, Semaphore/Twilio).
- **Automatic shipping from the typed address** — needs a maps/distance API. Customers pick a distance tier instead; 26–29 km is undefined in the brief and is blocked until you define it.
- Live rider map (a link button is provided); affiliate payout automation (payouts are manual by design).
- Not tested against a live Supabase project — run through a full test order before launch.
