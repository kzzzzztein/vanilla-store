# Jade Steam — Supabase backend foundation

Static HTML/CSS/JS, compatible with GitHub Pages. **Not ready for real customer payments or orders.** The existing storefront still uses demonstration cart/checkout/order tracking; admin dashboard reads real Supabase data once connected.

## Setup (no npm or VS Code)
1. Create a Supabase project at https://supabase.com/dashboard.
2. Open **SQL Editor**, paste `supabase/schema.sql`, and run it. This creates tables, RLS policies, a secure admin-only payment-review function, and sample products.
3. Go to **Authentication → Users** and create an admin user (email/password). In SQL Editor, promote ONLY your own user, using their actual ID from Auth Users:

   ```sql
   insert into public.profiles(id,role,full_name)
   values ('REPLACE-WITH-AUTH-USER-UUID','admin','Store Administrator')
   on conflict (id) do update set role='admin';
   ```

4. In **Project Settings → API** (or Connect → API keys), copy the **Project URL** and **publishable / anon key** into `supabase-config.js`. These are public client credentials, protected by RLS. **Never put a service_role / secret key into GitHub files.**
5. Upload the whole folder's contents to the root of your GitHub `vanilla-store` repository, including `admin.html`, `admin.js`, `admin.css`, `supabase-config.js`, and `supabase/schema.sql` (SQL file is setup only). Open `/admin.html` and sign in.

## Working in this release
- Admin authentication via Supabase Auth and admin role check
- Database tables for products, orders, items, payment submissions, promos, affiliates, clicks, commissions, settings
- Row Level Security for sensitive data; guest browsers cannot list orders or payments
- Admin order status changes and product price/stock editing
- Admin payment verification/rejection with a database function
- Admin overview and read-only promo/affiliate views

## Not yet live
- Guest checkout server-side order creation, distance-based shipping (the requirements omit 26–29 km and need an origin address and distance provider), secure proof uploads, order lookup, transactional email/SMS, full product editing, affiliate sign-up/tracking/commission payouts, promo redemption and reporting/date filters.
- Admin cannot securely approve a payment until a submission is received through a future checkout backend; the review interface is in place, but payment collection is not.
- The current store's sample products and voucher `SAVE50` remain frontend demonstrations and **must not be treated as production prices, discounts, or payments**.

## Security notes
- Do not publish actual bank/GCash credentials or personal payout information in repository files.
- Never use `service_role` in client JavaScript. RLS is enabled on all private tables.
- Store payment proofs in a **private Supabase Storage bucket** with signed URLs after secure upload implementation.
- Create order placement through a validated server-side RPC/Edge Function that computes product prices, shipping, discounts, stock, and commissions transactionally.
- Protect public order tracking with an unguessable token and rate limits, not just sequential order numbers.

## Design polish v2
Includes `polish.css` and `polish.js` for accessible microinteractions, animated steam, scroll reveals, mobile refinements and unclipped product availability labels. Upload these files alongside all existing files. Supabase setup remains optional and deferred; checkout is still demo-only.


## Design V3 repairs
- Mobile menu stacking fixed: previously the backdrop was above the entire sticky header, blocking menu clicks. The header and menu now sit above the backdrop.
- Accessible menu toggle, Escape/backdrop closing, and keyboard navigation.
- Availability badges are constrained **inside** each product art card on narrow screens.
- New `refinement.css` adds responsive cards and visual refinements. Upload this file too.
- No Supabase account is required for the frontend preview; checkout remains a demo.
