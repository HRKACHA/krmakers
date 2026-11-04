# KR Makers Order Management

A private order-management workspace for KR Makers. The production frontend is served by Vercel and its records are stored in Supabase Postgres.

## Included features
- Private administrator sign-in; no public sign-up form
- First-time owner setup with a single-use activation code
- Dashboard for order count, paid revenue, pending payments and preparation workload
- Customer directory and order history
- Editable catalogue rates per kg for Sata Sweet and Ghughara
- Create and edit orders with multiple lines, quantities, per-order rate overrides and automatic totals
- Preparation statuses: Pending, Preparing, Ready, Delivered, Cancelled
- Payment statuses: Pending or Paid; revenue includes only orders marked Paid
- Direct PDF invoice download with the original KR Makers logo and UPI QR

## Supabase setup
1. Use the dedicated project **KR Makers Order Management**.
2. The SQL schema is in `schema.sql`. It is already applied in the production project.
3. The Edge Function source is in `supabase/functions/bootstrap-admin/index.ts`; the deployed function is named `bootstrap-admin`.
4. The website's `config.js` contains only the Supabase project URL and public publishable key. Never add a service-role or secret key to browser files.
5. Open the website and select **First-time owner setup**. Enter the one-time code supplied privately by the site owner, then create the owner's email and password.
6. Sign in with that email and password. No other account can access customer, order or revenue records unless an active staff profile is explicitly added.

## Deploy
The root `index.html` joins `app.payload` and `app.payload.part2`, decompresses the application bundle and loads it. Keep both payload parts, `config.js`, and the `assets/` directory in the deployment root. The site is deployed on Vercel.

## Business rules
- Each saved order keeps the item name, quantity and per-kg rate that were used at the time of that order.
- Changing a current product rate affects new order defaults, not previous bills.
- Revenue is calculated from orders marked Paid, using their payment-received timestamp.
- The invoice displays the payment QR. The app does not itself confirm or process UPI payment; the owner must mark an order Paid only after confirming receipt.
