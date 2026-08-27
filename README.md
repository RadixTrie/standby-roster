# Standby Roster

A single-file web app for an on-call / standby rotation. It shows who's on
standby now, lays out the coming weeks, and lets people book leave and swap
weeks. It's one `index.html` — no build step, no server to run.

## The two modes

**Local preview (default).** Open `index.html` and it works right away, but
edits stay in *that one browser*. Good for trying it out and shaping the setup.

**Shared (what you want for Teams).** Point it at a free Supabase database and
everyone loading the same link sees and edits the same roster, live. This is the
version you add to a Teams channel.

---

## Try it now

Double-click `index.html`. You'll see a seeded team, a live "on standby now"
card, the rotation strip, and one demo leave that triggers a **needs cover**
flag. Click **Setup** to swap in your real people and rotation.

---

## Turn on shared mode

1. **Create a project** at supabase.com (the free tier is enough for a team).
2. **Create the tables.** In the project: SQL Editor → New query → paste the
   contents of `schema.sql` → Run.
3. **Get your keys.** Project Settings → API → copy the **Project URL** and the
   **anon public** key.
4. **Paste them in.** Open `index.html` in a text editor. At the top of the
   `<script>` block you'll see:
   ```js
   const SUPABASE_URL = "";
   const SUPABASE_ANON_KEY = "";
   ```
   Fill both in and save. Reload — the top of the page now says **● shared**.
5. **Set up your team once** via the Setup button. Everyone else just opens the
   link.

The anon key is meant to live in client code — it's protected by the row-level
security policies in `schema.sql`. As written, anyone with the link can edit,
which is normal for an internal roster. `schema.sql` explains how to lock it
down with real sign-in later if you need to.

---

## Host it

The app is one static file, so almost anything works:

- **Netlify Drop** (netlify.com/drop) — drag the file in, get a URL in seconds.
- **GitHub Pages** — commit `index.html` to a repo, enable Pages.
- **Azure Static Web Apps / Storage static site** — if you'd rather stay inside
  Microsoft/Azure.

You get back a URL like `https://your-roster.example.com`. That URL is the app.

---

## Automatic reminders (shared mode only)

Once shared mode is on, `supabase/functions/standby-reminder/index.ts` can
email whoever's up next, reading directly from the same `config`/`members`/
`overrides` tables the app uses — no separate copy of the rotation to keep in
sync. It always computes the *next* period relative to whenever it runs, so
schedule it a few days before turnover (e.g. Friday, for a Monday handover).

1. **Add emails.** Open **Setup** in the app and fill in each person's email
   address under their name — that's the only new input.
2. **Sign up for [Resend](https://resend.com)** (or swap in your own email
   API — the function only touches one `fetch` call). Free tier is plenty for
   a team roster. Verify a sending domain, or use their test sender while
   trying it out. Grab an API key.
3. **Install the Supabase CLI** (`brew install supabase/tap/supabase` on
   Mac), then from this folder:
   ```
   supabase login
   supabase link --project-ref <your-project-ref>   # find it in Project Settings
   supabase secrets set RESEND_API_KEY=re_xxx \
     REMINDER_FROM_EMAIL="Standby Roster <standby@yourdomain.com>" \
     REMINDER_APP_URL="https://your-hosted-roster-url"
   supabase functions deploy standby-reminder
   ```
   (`SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` are already available to
   every deployed function automatically — no need to set those.)
4. **Schedule it to run weekly.** Two ways:
   - **Dashboard:** Project → Edge Functions → `standby-reminder` → Cron tab
     (if your project has this), add a weekly schedule.
   - **SQL (works everywhere):** in the SQL Editor, enable the `pg_cron` and
     `pg_net` extensions (Database → Extensions), then run:
     ```sql
     select cron.schedule(
       'standby-reminder-weekly',
       '0 8 * * 5',  -- every Friday 08:00 UTC — adjust for your timezone
       $$
       select net.http_post(
         url := 'https://<your-project-ref>.functions.supabase.co/standby-reminder',
         headers := jsonb_build_object(
           'Authorization', 'Bearer <your-service-role-key>',
           'Content-Type', 'application/json'
         )
       );
       $$
     );
     ```
5. **Test it manually first:**
   `supabase functions invoke standby-reminder` — check the response and your
   inbox before trusting the schedule.

If someone's missing an email, the function skips them (check the function
logs) rather than failing the whole run.

---

## Add it to a Teams channel

In the channel, use **＋ (Add a tab) → Website** and paste your hosted URL, so
the roster lives right in the channel. If your Teams setup blocks embedding a
site in a tab, add it as a **channel bookmark / link** instead — same URL, one
click away. (Teams' menus shift around between versions; if the labels differ,
look for "add a tab" or "add a website".)

---

## Customize

Everything is editable from the **Setup** button in the app: team name, who's in
the rotation and their order, when the rotation started, and how long each turn
lasts (a day, a few days, a week, or two). "I'm…" in the top corner sets who you
are, so your name is pre-filled when you book leave or take a swap, and your
weeks are marked **you**.

---

## If you can't use Supabase

Some orgs don't allow outside data services. The data layer is isolated in one
place: in `index.html` search for `class SupabaseStore`. It's a small adapter
with `load`, `subscribe`, and a handful of write methods. Swap it for Azure
(Cosmos/Table + Functions), Firebase, or your own API and nothing else in the
app changes. Tell me which backend and I'll write that adapter for you.

## What's in each file

- `index.html` — the whole app (styles + logic in one file).
- `schema.sql` — database tables for shared mode.
- `README.md` — this file.
