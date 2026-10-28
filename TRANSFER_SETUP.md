# Transfer with email OTP

## Files
- `supabase/migrations_transfer_email_otp.sql`: database table and RPC functions.
- `supabase/functions/transfer-email-otp/index.ts`: Edge Function for requesting a code by email and verifying it.
- `index.html` and `app.js`: transfer screen and client flow.

## Required setup before it can send email
1. Apply `supabase/migrations_transfer_email_otp.sql` to the existing Supabase project.
2. Deploy the `transfer-email-otp` Edge Function.
3. Configure these Edge Function secrets in Supabase: `RESEND_API_KEY` and `TRANSFER_EMAIL_FROM`. The sender address must be verified with Resend. Supabase-provided `SUPABASE_URL` and `SUPABASE_ANON_KEY` are used by the function.
4. Test with two approved test accounts with balances. Verify invalid code, expiry, insufficient balance, same-user recipient, and duplicate submission behavior before production use.
5. Deploy the updated static files to the hosting site; changes to local files do not automatically update Cloudflare.

The challenge code is stored as a hash, expires after five minutes, and request rate limiting is applied. The final balance updates and ledger writes happen together in a database function.