create table if not exists public.sara_push_request_nonces (
  request_id uuid primary key,
  expires_at timestamptz not null,
  created_at timestamptz not null default now()
);

create index if not exists sara_push_request_nonces_expires_at_idx
  on public.sara_push_request_nonces (expires_at);

alter table public.sara_push_request_nonces enable row level security;
revoke all on table public.sara_push_request_nonces from anon, authenticated;
grant select, insert, delete on table public.sara_push_request_nonces to service_role;
