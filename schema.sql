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
-- Access.
--
-- config & members (the team roster/setup): anyone with the link can
-- read, but only the admin account(s) listed below can write. This is
-- real server-side enforcement — the app's UI also hides the Setup
-- button from everyone else, but this is what actually stops writes
-- even if someone bypasses the UI.
--
-- leaves & overrides (booking your own leave / swapping a week): left
-- open to everyone, same as before — no login needed to use those.
--
-- To add more admins, add more emails to the `in (...)` list below.
-- ------------------------------------------------------------
alter table config    enable row level security;
alter table members   enable row level security;
alter table leaves    enable row level security;
alter table overrides enable row level security;

drop policy if exists "anon read/write config"  on config;
drop policy if exists "anon read/write members" on members;
drop policy if exists "config read"          on config;
drop policy if exists "config admin insert"  on config;
drop policy if exists "config admin update"  on config;
drop policy if exists "config admin delete"  on config;
drop policy if exists "members read"         on members;
drop policy if exists "members admin insert" on members;
drop policy if exists "members admin update" on members;
drop policy if exists "members admin delete" on members;

create policy "config read" on config for select using (true);
create policy "config admin insert" on config for insert
  with check ((auth.jwt() ->> 'email') in ('simone.terry@radixtrie.com'));
create policy "config admin update" on config for update
  using ((auth.jwt() ->> 'email') in ('simone.terry@radixtrie.com'))
  with check ((auth.jwt() ->> 'email') in ('simone.terry@radixtrie.com'));
create policy "config admin delete" on config for delete
  using ((auth.jwt() ->> 'email') in ('simone.terry@radixtrie.com'));

create policy "members read" on members for select using (true);
create policy "members admin insert" on members for insert
  with check ((auth.jwt() ->> 'email') in ('simone.terry@radixtrie.com'));
create policy "members admin update" on members for update
  using ((auth.jwt() ->> 'email') in ('simone.terry@radixtrie.com'))
  with check ((auth.jwt() ->> 'email') in ('simone.terry@radixtrie.com'));
create policy "members admin delete" on members for delete
  using ((auth.jwt() ->> 'email') in ('simone.terry@radixtrie.com'));

drop policy if exists "anon read/write leaves"    on leaves;
drop policy if exists "anon read/write overrides" on overrides;
create policy "anon read/write leaves"    on leaves    for all using (true) with check (true);
create policy "anon read/write overrides" on overrides for all using (true) with check (true);
