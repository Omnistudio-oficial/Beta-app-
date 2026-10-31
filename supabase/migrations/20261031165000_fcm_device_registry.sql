-- Private registration store for Flutter FCM device tokens.
-- Only Edge Functions using the Supabase service role may read/write these rows.
create table if not exists public.fcm_device_tokens (
  id uuid primary key default gen_random_uuid(),
  uid text not null check (length(uid) between 1 and 128),
  app_id text not null check (app_id = 'com.omnistudio.omnistudioFlutterPrototype'),
  platform text not null check (platform in ('android', 'ios')),
  token_hash text not null check (token_hash ~ '^[a-f0-9]{64}$'),
  fcm_token text not null check (length(fcm_token) between 1 and 4096),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (uid, app_id, platform, token_hash)
);

alter table public.fcm_device_tokens enable row level security;
revoke all on table public.fcm_device_tokens from public, anon, authenticated;
grant select, insert, update, delete on table public.fcm_device_tokens to service_role;
