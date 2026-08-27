// Standby Roster — reminder Edge Function.
//
// Scheduled to run once a week (see README.md "Automatic reminders" section
// for how to wire up the schedule). Reads the live config/members/overrides
// tables directly — the same data the app shows — so there's no separate
// copy of the rotation to keep in sync. Computes who's on standby for the
// *next* period (relative to whenever this runs) and emails them via Resend.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const RESEND_API_KEY = Deno.env.get("RESEND_API_KEY")!;
const FROM_EMAIL = Deno.env.get("REMINDER_FROM_EMAIL") ?? "standby@example.com";
const APP_URL = Deno.env.get("REMINDER_APP_URL") ?? "";

const DAY = 86_400_000;

function toUTC(dateStr: string) {
  const [y, m, d] = dateStr.split("-").map(Number);
  return Date.UTC(y, m - 1, d);
}
function fromUTC(ms: number) {
  const dt = new Date(ms);
  const y = dt.getUTCFullYear();
  const m = String(dt.getUTCMonth() + 1).padStart(2, "0");
  const d = String(dt.getUTCDate()).padStart(2, "0");
  return `${y}-${m}-${d}`;
}
function addDaysStr(dateStr: string, n: number) {
  return fromUTC(toUTC(dateStr) + n * DAY);
}
function daysBetween(a: string, b: string) {
  return Math.round((toUTC(b) - toUTC(a)) / DAY);
}
function periodIndex(dateStr: string, startStr: string, cadenceDays: number) {
  return Math.floor(daysBetween(startStr, dateStr) / cadenceDays);
}
function periodStartStr(index: number, startStr: string, cadenceDays: number) {
  return addDaysStr(startStr, index * cadenceDays);
}
function periodLastDayStr(index: number, startStr: string, cadenceDays: number) {
  return addDaysStr(startStr, (index + 1) * cadenceDays - 1);
}
function todayStr() {
  const now = new Date();
  return `${now.getUTCFullYear()}-${String(now.getUTCMonth() + 1).padStart(2, "0")}-${String(now.getUTCDate()).padStart(2, "0")}`;
}

Deno.serve(async (_req) => {
  try {
    const sb = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

    const [{ data: config, error: cfgErr }, { data: members, error: memErr }] = await Promise.all([
      sb.from("config").select("*").eq("id", 1).maybeSingle(),
      sb.from("members").select("*").order("sort", { ascending: true }),
    ]);
    if (cfgErr) throw cfgErr;
    if (memErr) throw memErr;
    if (!config || !members?.length) {
      return new Response(JSON.stringify({ skipped: "no config or members" }), { status: 200 });
    }

    const today = todayStr();
    const curIdx = periodIndex(today, config.start_date, config.cadence_days);
    const nextIdx = curIdx + 1;
    const nextStart = periodStartStr(nextIdx, config.start_date, config.cadence_days);
    const nextEnd = periodLastDayStr(nextIdx, config.start_date, config.cadence_days);

    const { data: override, error: ovErr } = await sb
      .from("overrides")
      .select("*")
      .eq("period_start", nextStart)
      .maybeSingle();
    if (ovErr) throw ovErr;

    const n = members.length;
    const baseMember = members[((nextIdx % n) + n) % n];
    const memberId = override?.member_id ?? baseMember.id;
    const person = members.find((m) => m.id === memberId);

    if (!person) {
      return new Response(JSON.stringify({ skipped: "resolved member not found" }), { status: 200 });
    }
    if (!person.email) {
      return new Response(
        JSON.stringify({ skipped: `no email on file for ${person.name} — add one in Setup` }),
        { status: 200 },
      );
    }

    const subject = `Standby reminder — you're on next (${nextStart} to ${nextEnd})`;
    const linkLine = APP_URL ? `\n\nRoster: ${APP_URL}` : "";
    const text =
      `Hi ${person.name},\n\n` +
      `Heads up — you're on standby duty from ${nextStart} to ${nextEnd}.${linkLine}\n\n` +
      `If you need someone to cover, arrange a swap on the roster ahead of time.`;

    const emailRes = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${RESEND_API_KEY}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ from: FROM_EMAIL, to: person.email, subject, text }),
    });

    if (!emailRes.ok) {
      const body = await emailRes.text();
      throw new Error(`Resend API error ${emailRes.status}: ${body}`);
    }

    return new Response(JSON.stringify({ sent: person.email, period: [nextStart, nextEnd] }), { status: 200 });
  } catch (err) {
    console.error(err);
    return new Response(JSON.stringify({ error: String(err) }), { status: 500 });
  }
});
