# KR Makers Order Management

A private order-management workspace for KR Makers, using Supabase Auth + Postgres and a static Vercel frontend.

## Features
- Admin sign-in (no public sign-up form)
- Dashboard with total orders, paid revenue, outstanding amount, and preparation counts
- Order creation/editing with per-item quantities, editable rates per kg, and automatic line and order totals
- Customer directory and customer-level order totals
- Editable product rates; old orders keep their saved rate snapshots
- Preparation statuses: Pending, Preparing, Ready, Delivered, Cancelled
- Payment status: Pending or Paid; revenue includes only orders marked Paid
- Direct invoice PDF downloads with KR Makers logo, UPI QR, and the original invoice styling

## Backend setup
1. Create a dedicated Supabase project.
2. Run `schema.sql` in the Supabase SQL Editor.
3. In Supabase Authentication, create the owner's email/password account. Keep public sign-ups disabled.
4. Add the owner's Auth UUID to the staff allow-list:
   ```sql
   insert into public.staff_profiles (user_id, display_name, is_active)
   values ('AUTH_USER_UUID', 'KR Makers Admin', true);
   ```
5. Copy `config.example.js` to `config.js` and set the Supabase project URL and publishable key.

## Deploy
Deploy the repository root as a static Vercel site (no build command). `index.html` loads the app from `app.payload`; the app reads settings from `config.js`.

The frontend uses only the Supabase **publishable key**. Never commit a service-role or secret key. RLS is enabled on every business table; only authenticated users with an active `staff_profiles` row can access the business data.

## Payment behavior
The UPI QR is printed on invoices. The app does not itself process UPI payments. After confirming receipt, the owner marks an order as Paid; the revenue page updates from paid order records. Unpaid orders are excluded from revenue.
