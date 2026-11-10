// SHUpitcherhub · voice-log
// Turns what a pitcher said about his day into a structured log: day type, workload numbers,
// a bulleted breakdown by section, and how it compares with the plan.
// Needs one secret: ANTHROPIC_API_KEY (Supabase → Edge Functions → Secrets). Optional: ANTHROPIC_MODEL.
import { createClient } from "jsr:@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });

const DAY_TYPES_DEFAULT = ["Rest", "Recovery", "Hybrid B", "Hybrid A", "Bullpen", "Velo", "Live/Game", "Return to throw"];

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "Use POST" }, 405);
  try {
    const key = Deno.env.get("ANTHROPIC_API_KEY");
    if (!key) return json({ error: "Voice logging isn't switched on yet: Coach needs to add the Anthropic API key in Supabase." }, 503);

    // Only signed-in people who can see this pitcher (the pitcher himself or a coach) may use it.
    const sb = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_ANON_KEY")!, {
      global: { headers: { Authorization: req.headers.get("Authorization") ?? "" } },
    });
    const { data: who } = await sb.auth.getUser();
    if (!who?.user) return json({ error: "Sign in first." }, 401);

    const body = await req.json();
    const transcript = String(body.transcript ?? "").trim();
    const athleteId = String(body.athlete_id ?? "");
    const date = String(body.date ?? "");
    if (!transcript) return json({ error: "Say or type what you did first." }, 400);
    if (transcript.length > 6000) return json({ error: "That's too long. Keep it to a few minutes of talking." }, 400);

    const { data: ath } = await sb.from("athletes").select("id,name,role").eq("id", athleteId).maybeSingle();
    if (!ath) return json({ error: "You can only log your own day." }, 403);

    const types: { name: string; load: number | string; rpe?: string }[] =
      Array.isArray(body.types) && body.types.length ? body.types : DAY_TYPES_DEFAULT.map((n) => ({ name: n, load: "" }));
    const typeNames = types.map((t) => t.name);

    const system = `You turn a college pitcher's spoken description of his throwing day into a clean log for his coach.
Day types (pick exactly one; workload points in parentheses): ${types.map((t) => `${t.name}${t.load !== "" ? ` (${t.load})` : ""}${t.rpe ? ` – ${t.rpe}` : ""}`).join("; ")}.
Rules:
- Use only what he said. Never invent drills, counts, velocities or feelings. If something is unclear, list it under "unclear" instead of guessing.
- Pick the day type from what he actually did, even if the plan said something else. A mound bullpen = Bullpen. Facing hitters / intrasquad / game = Live/Game. Max-intent pulldowns or radar work = Velo. Hard catch play / long toss with intent ≈ Hybrid A; moderate ≈ Hybrid B; light catch play / recovery throwing = Recovery; no throwing = Rest. Use "Return to throw" only if he is on a return-to-throw program.
- throws = total throws he describes (sum the parts when he gives them). pitches = pitches off the mound or in a game. innings only for live/game. intensity = his effort % if he states or clearly implies it.
- checkin = 0–10 arm/body feeling only if he says it (0 = fresh, 10 = awful pain). Otherwise null.
- sections: short bullet strings, each one drill or block with its dose, e.g. "Band series 2×10", "Long toss out to 150 ft, ~30 throws", "Scoop toss 6 lb 2×5". Put each item in the right section: prework (mobility, bands, arm care, warm-up), plyo (plyo balls & drills), throwing (catch play, long toss, flat ground), medball, focus (bullpen / live: pitch mix, counts, what he worked on). Use "other" for lifting, conditioning or anything else.
- differences: how what he did differs from the plan, in plain words (empty if it matches or there is no plan).
- notes: one or two sentences in his voice summarizing how it went, especially anything about how the arm felt.`;

    const user = `Date: ${date} (${ath.name}, ${ath.role || "pitcher"})
Coach's plan for this day: ${body.plan ? JSON.stringify(body.plan) : "none"}
What he logged earlier today (his new log replaces it): ${body.existing ? JSON.stringify(body.existing) : "nothing"}
What he said:
"""${transcript}"""`;

    const tool = {
      name: "record_day",
      description: "Record the pitcher's day.",
      input_schema: {
        type: "object",
        properties: {
          day_type: { type: "string", enum: typeNames },
          throws: { type: ["integer", "null"] },
          intensity: { type: ["integer", "null"], description: "Effort %, 0–100" },
          innings: { type: ["number", "null"] },
          pitches: { type: ["integer", "null"] },
          bullpen: { type: ["string", "null"], description: "Short bullpen description, e.g. '25 pitches: 15 FB, 10 SL'" },
          checkin: { type: ["integer", "null"], description: "0–10, only if stated" },
          sections: {
            type: "object",
            properties: {
              prework: { type: "array", items: { type: "string" } },
              plyo: { type: "array", items: { type: "string" } },
              throwing: { type: "array", items: { type: "string" } },
              medball: { type: "array", items: { type: "string" } },
              focus: { type: "array", items: { type: "string" } },
              other: { type: "array", items: { type: "string" } },
            },
            required: ["prework", "plyo", "throwing", "medball", "focus", "other"],
          },
          differences: { type: "array", items: { type: "string" } },
          unclear: { type: "array", items: { type: "string" } },
          notes: { type: "string" },
        },
        required: ["day_type", "sections", "differences", "unclear", "notes"],
      },
    };

    const r = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: { "x-api-key": key, "anthropic-version": "2023-06-01", "content-type": "application/json" },
      body: JSON.stringify({
        model: Deno.env.get("ANTHROPIC_MODEL") || "claude-haiku-5-5",
        max_tokens: 1500,
        system,
        tools: [tool],
        tool_choice: { type: "tool", name: "record_day" },
        messages: [{ role: "user", content: user }],
      }),
    });
    const out = await r.json();
    if (!r.ok) return json({ error: `The reader couldn't process that (${out?.error?.message ?? r.status}).` }, 502);
    const use = (out.content || []).find((c: { type: string }) => c.type === "tool_use");
    if (!use) return json({ error: "The reader didn't return a log. Try again." }, 502);
    const day = use.input;
    if (!typeNames.includes(day.day_type)) day.day_type = null;
    return json({ day });
  } catch (e) {
    return json({ error: String((e as Error)?.message ?? e) }, 500);
  }
});
