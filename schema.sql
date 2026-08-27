-- ============================================================
-- Standby Roster — Supabase schema (shared mode)
-- Run this once in your Supabase project: SQL Editor → paste → Run.
-- ============================================================

create table if not exists config (
  id           int primary key default 1,
  team         text not null default 'Ops Standby',
  start_date   date not null,
  cadence_days int  not null default 7
);

create table if not exists members (
  id    text primary key,
  name  text not null,
  email text,
  sort  int  not null default 0
);

-- safe to re-run if the table already existed without the email column
alter table members add column if not exists email text;

create table if not exists leaves (
  id         uuid primary key default gen_random_uuid(),
  member_id  text not null,
  start_date date not null,
  end_date   date not null,
  note       text,
  created_by text,
  created_at timestamptz default now()
);

create table if not exists overrides (
  id          uuid primary key default gen_random_uuid(),
  period_start date not null unique,   -- one covering person per rotation period
  member_id   text not null,
  note        text,
  created_by  text,
  created_at  timestamptz default now()
);

-- seed a config row if none exists
insert into config (id, team, start_date, cadence_days)
values (1, 'Ops Standby', date_trunc('week', now())::date, 7)
on conflict (id) do nothing;

-- Live updates for everyone with the tab open (safe to re-run — skips
-- tables already in the publication instead of erroring)
do $$
declare
  t text;
begin
  foreach t in array array['config','members','leaves','overrides'] loop
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = t
    ) then
      execute format('alter publication supabase_realtime add table %I', t);
    end if;
  end loop;
end $$;

-- ------------------------------------------------------------
-- Access. This tool has no login: anyone with the page (and the
-- public anon key baked into it) can read and edit. For an internal
-- team behind a Teams channel that is usually fine. The policies
-- below make that explicit.
--
-- To tighten later, replace `using (true)` / `with check (true)`
-- with rules that require an authenticated user, and add Supabase
-- Auth or Microsoft sign-in to the page.
-- ------------------------------------------------------------
alter table config    enable row level security;
alter table members   enable row level security;
alter table leaves    enable row level security;
alter table overrides enable row level security;

create policy "anon read/write config"    on config    for all using (true) with check (true);
create policy "anon read/write members"   on members   for all using (true) with check (true);
create policy "anon read/write leaves"    on leaves    for all using (true) with check (true);
create policy "anon read/write overrides" on overrides for all using (true) with check (true);
