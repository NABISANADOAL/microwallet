# MicroWallet Admin — Netlify + Supabase

Independent account portal with approval-based registration, private admin user list, internal USDT-denominated credits, audit history, and server-side authorization. Not affiliated with FaucetPay. It does not transfer cryptocurrency.

## Files
- `index.html`, `styles.css`, `app.js`: responsive frontend
- `config.js`: public Supabase URL and publishable key only
- `supabase/schema.sql`: tables, RLS policies, triggers, and restricted admin RPC functions
- `netlify.toml`: static publish config and basic security headers

## Setup checklist

### 1. Create a NEW Supabase project
Use a dedicated project for MicroWallet; do not run this schema on an unrelated production database. In Supabase, open SQL Editor and run `supabase/schema.sql`.

### 2. Configure Auth
In Authentication → URL Configuration, set your local/deployed site URL and allowed redirect URLs. Enable email confirmations. Configure SMTP before public use if you need reliable email delivery.

### 3. Create the first admin
1. Sign up using the intended administrator email through the app after configuring `config.js`.
2. Confirm that email from the confirmation message.
3. In Supabase SQL Editor, find that account's UUID in `auth.users` (or Authentication → Users).
4. Run this statement with the exact UUID:
   `insert into public.admin_users(user_id) values ('YOUR_AUTH_USER_UUID');`
5. Sign in again. Admin access is determined by `admin_users`, never by editable user metadata.
6. Admins can approve pending accounts, suspend/reactivate accounts, and adjust internal credits with a required reason. Every adjustment is recorded in the ledger and audit log.

### 4. Configure the frontend
`config.js` is preconfigured for the Supabase project created for this app:
- Project URL: `https://xfppqsngrhyvszakfwig.supabase.co`
- Browser key: publishable key (safe for client use with RLS enabled)

The publishable key is intended to be public. Never put a `service_role` or secret key in `config.js`.

Never put a Supabase `service_role` or secret key in `config.js`.

### 5. Publish to Netlify
Upload the project folder (the folder containing `index.html`) through https://app.netlify.com/drop or deploy it from a Git repository. Add the deployed Netlify URL to Supabase Auth redirect allow-list. Update the Supabase Site URL to the production URL.

## Security and scope notes
- New accounts are `pending` until an admin approves them. Email confirmation should be enabled.
- Users can read only their own profile and ledger. Admin list and audit access require an `admin_users` membership.
- Admin balance changes happen through narrowly scoped PostgreSQL functions that check admin membership server-side.
- Balance is internal credit only, displayed in USDT units; it is not USDT, a token, a deposit, or a redeemable balance.
- This is a starter implementation. Before public production, configure rate limits/CAPTCHA, custom SMTP, backups, monitoring, and privacy/terms pages. Verify the schema and policies in a dedicated Supabase project before inviting users.
