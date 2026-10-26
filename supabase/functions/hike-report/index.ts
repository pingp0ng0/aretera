import { json, requireUser } from "../_shared/http.ts";

// AI report (PRD_step6 6-3): the app sends numbers it already computed; the model only interprets them.
// No coordinates, place names, memos or exact dates ever reach this function.
// REPORT_MODEL: "model[,fallback…]" (OpenRouter ids). OPENROUTER_API_KEY: function secret.
const OPENROUTER_URL = "https://openrouter.ai/api/v1/chat/completions";
const MAX_INPUT_BYTES = 20_000;
const ATTEMPTS = 3;

const SYSTEM_PROMPT = `너는 백패킹·등산 기록을 읽고 조언하는 코치다.
사용자가 주는 목록은 앱이 휴대폰 GPS 기록으로 이미 계산한 통계다.
규칙:
- 한국어 한글로만 쓴다. 한자와 영어 단어는 쓰지 않는다(단위 km, m, kg 는 괜찮다).
- 모든 문장은 "~요" 로 끝나는 존댓말로, 친근하지만 과장 없이 쓴다.
- 목록에 있는 숫자만 그대로 인용한다. 새 숫자를 계산하거나 지어내지 않는다. 기록이 적으면 그렇다고 말한다.
- 아래 네 소제목을 이 순서로, 각 소제목 줄 맨 앞에 "## " 를 붙여 쓴다. 각 소제목 아래 "- " 로 시작하는 줄 2~3개:
  ## 한눈에 보기 — 전체 기록과 월별 흐름(늘었는지, 꾸준한지)
  ## 잘하고 있는 점 — 숫자로 보이는 강점 두 가지
  ## 살펴볼 점 — 배낭 무게 영향, 휴식 습관, 오르막 페이스, 체감 난이도와 상승의 관계 중 목록에 있는 것 두 가지
  ## 다음 산행 제안 — 내 페이스로 본 알맞은 상승 범위, 배낭 무게, 휴식 방식 같은 구체적인 제안 두 가지
- 같은 내용을 여러 소제목에서 되풀이하지 않는다. 전체 700자 이내.
- 의학적 진단이나 위험한 산행을 부추기는 말은 하지 않는다. 생각 과정이나 머리말 없이 본문만 쓴다.
- 말투 예시(내용은 따라 하지 말 것): "꾸준히 한 달에 한 번씩 다녀오셨어요." "다음엔 쉬는 간격을 조금 짧게 나눠 보면 좋아요."`;

type Obj = Record<string, unknown>;
const num = (v: unknown): number | undefined => (typeof v === "number" && Number.isFinite(v) ? v : undefined);
const fmt = (v: unknown, digits = 0): string | undefined => {
  const n = num(v);
  return n === undefined ? undefined : n.toLocaleString("en-US", { maximumFractionDigits: digits });
};
const obj = (v: unknown): Obj | undefined => (typeof v === "object" && v !== null && !Array.isArray(v) ? v as Obj : undefined);
const list = (v: unknown): Obj[] => (Array.isArray(v) ? v.map(obj).filter((o): o is Obj => !!o) : []);
const join = (parts: (string | undefined | false)[]) => parts.filter(Boolean).join(", ");

/** The app's summary JSON → Korean fact lines, so the model never sees field names. Unknown fields are ignored. */
function factSheet(s: Obj): string {
  const lines: string[] = [];
  const t = obj(s.totals);
  if (t) {
    lines.push(`- 전체: ${join([
      fmt(t.hikes) && `기록 ${fmt(t.hikes)}회`,
      fmt(t.distance_km, 1) && `총 거리 ${fmt(t.distance_km, 1)}km`,
      fmt(t.gain_m) && `총 상승 ${fmt(t.gain_m)}m`,
      fmt(t.hours, 1) && `총 산행 시간 ${fmt(t.hours, 1)}시간`,
    ])}`);
  }
  const months = list(s.months);
  if (months.length) {
    lines.push(`- 월별: ${months.map((m) =>
      `${m.month} ${join([`${fmt(m.hikes)}회`, `${fmt(m.distance_km, 1)}km`, `상승 ${fmt(m.gain_m)}m`])}`).join(" / ")}`);
    // Pre-computed highlights: small models misread which month a number belongs to.
    const top = (field: string) => months.reduce((a, b) => ((num(b[field]) ?? 0) > (num(a[field]) ?? 0) ? b : a));
    const gainTop = top("gain_m"), distTop = top("distance_km");
    lines.push(`- 가장 많이 오른 달: ${gainTop.month}(${fmt(gainTop.gain_m)}m), 가장 멀리 걸은 달: ${distTop.month}(${fmt(distTop.distance_km, 1)}km)`);
  }
  const pace = obj(s.pace);
  if (pace) {
    const up = obj(pace.up), down = obj(pace.down), flat = obj(pace.flat);
    lines.push(`- 구간별 속도: ${join([
      up && `오르막 시속 ${fmt(up.km_h, 1)}km(시간당 ${fmt(up.vertical_m_h)}m 오름)`,
      down && `내리막 시속 ${fmt(down.km_h, 1)}km(시간당 ${fmt(down.vertical_m_h)}m 내려감)`,
      flat && `평지 시속 ${fmt(flat.km_h, 1)}km`,
    ])}`);
  }
  const rest = obj(s.rest);
  if (rest) {
    lines.push(`- 이동과 휴식: ${join([
      fmt(rest.moving_pct) && `전체 시간 중 이동 ${fmt(rest.moving_pct)}%`,
      fmt(rest.rests_per_hike, 1) && `산행당 휴식 ${fmt(rest.rests_per_hike, 1)}회`,
      fmt(rest.avg_rest_min) && `1회 평균 휴식 ${fmt(rest.avg_rest_min)}분`,
    ])}`);
  }
  const effort = obj(s.effort);
  if (effort) {
    lines.push(`- 내 페이스(노력거리 = 거리km + 상승m÷100): ${join([
      fmt(effort.min_per_effort_km, 1) && `노력거리 1km에 ${fmt(effort.min_per_effort_km, 1)}분`,
      fmt(effort.rest_min_per_moving_hour) && `이동 1시간당 휴식 ${fmt(effort.rest_min_per_moving_hour)}분`,
      fmt(effort.based_on) && `최근 기록 ${fmt(effort.based_on)}개 기준`,
    ])}`);
  }
  const pack = obj(s.pack);
  if (pack && num(pack.pct_per_kg) !== undefined) {
    lines.push(`- 배낭 무게: 1kg 무거워질 때마다 노력 속도 ${fmt(pack.pct_per_kg, 1)}% 변화(기록 ${fmt(pack.hikes)}개 기준)`);
  }
  const difficulty = list(s.difficulty);
  if (difficulty.length) {
    lines.push(`- 체감 난이도별 평균 상승: ${difficulty.map((d) =>
      `별 ${fmt(d.stars)}개 ${fmt(d.avg_gain_m)}m(${fmt(d.hikes)}회)`).join(", ")}`);
  }
  const recent = list(s.recent);
  const packed = recent.filter((r) => num(r.pack_kg) !== undefined);
  if (packed.length >= 2) {
    const heavy = packed.reduce((a, b) => ((num(b.pack_kg) ?? 0) > (num(a.pack_kg) ?? 0) ? b : a));
    const light = packed.reduce((a, b) => ((num(b.pack_kg) ?? 0) < (num(a.pack_kg) ?? 0) ? b : a));
    lines.push(`- 가장 무거운 배낭: ${heavy.month} ${fmt(heavy.pack_kg, 1)}kg, 가장 가벼운 배낭: ${light.month} ${fmt(light.pack_kg, 1)}kg`);
  }
  if (recent.length) {
    lines.push("- 최근 기록(새것부터):");
    for (const r of recent) {
      lines.push(`  - ${r.month}: ${join([
        `${fmt(r.distance_km, 1)}km`,
        `상승 ${fmt(r.gain_m)}m`,
        fmt(r.moving_min) && `이동 ${fmt(r.moving_min)}분`,
        fmt(r.rest_min) && `휴식 ${fmt(r.rest_min)}분`,
        fmt(r.pack_kg, 1) && `배낭 ${fmt(r.pack_kg, 1)}kg`,
        fmt(r.stars) && `별 ${fmt(r.stars)}개`,
      ])}`);
    }
  }
  return lines.join("\n");
}

/** Drops reasoning blocks and any chatter before the first heading. */
function cleanReport(text: string): string {
  let t = text.replace(/<think>[\s\S]*?<\/think>/gi, "").trim();
  const first = t.indexOf("## ");
  if (first > 0) t = t.slice(first);
  return t.trim();
}

const numbersIn = (text: string) =>
  (text.match(/\d[\d,]*(?:\.\d+)?/g) ?? []).map((n) => n.replace(/,/g, "").replace(/\.0+$/, ""));

/**
 * Checks a reply. `hard`: unusable (empty, not Korean, Chinese characters, made-up totals).
 * `soft`: usable but not ideal (plain speech, a stray English word) — kept if no clean reply comes.
 */
function review(report: string, facts: string): { hard?: string; soft?: string } {
  if (report.length < 40 || !/[가-힣]/.test(report)) return { hard: "empty_or_not_korean" };
  if (/[一-鿿]/.test(report)) return { hard: "chinese_characters" };
  // In the overview (where stats are restated) big numbers must come from the facts: catches made-up
  // totals. Later sections may suggest new targets, so they aren't checked.
  const overview = report.split(/^## /m)[1] ?? "";
  const known = new Set(numbersIn(facts));
  const invented = numbersIn(overview).filter((n) => n.replace(".", "").length >= 3 && !known.has(n));
  if (invented.length) return { hard: `invented_numbers:${invented.slice(0, 3).join("/")}` };
  const english = report.match(/[A-Za-z]{4,}|\w*_[a-z]\w*/);
  if (english) return { soft: `english_words:${english[0]}` };
  // Plain speech ("올랐다.", "~이다.") instead of the polite form the app uses everywhere.
  if ((report.match(/(?<!니)다[.!]/g) ?? []).length >= 2) return { soft: "plain_speech" };
  return {};
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);
  if (!(await requireUser(req))) return json({ error: "login_required" }, 401);

  const raw = await req.text();
  if (raw.length > MAX_INPUT_BYTES) return json({ error: "too_large" }, 413);
  let summary: Obj | undefined;
  try {
    summary = obj(JSON.parse(raw));
  } catch { /* handled below */ }
  if (!summary) return json({ error: "bad_request" }, 400);
  const facts = factSheet(summary);
  if (!facts) return json({ error: "bad_request" }, 400);

  const key = Deno.env.get("OPENROUTER_API_KEY");
  const models = (Deno.env.get("REPORT_MODEL") ?? "").split(",").map((m) => m.trim()).filter(Boolean);
  if (!key || models.length === 0) return json({ error: "server_not_configured" }, 500);

  let lastProblem = "";
  let fallback: { report: string; model: string } | undefined;
  for (let attempt = 1; attempt <= ATTEMPTS; attempt++) {
    let res: Response;
    try {
      res = await fetch(OPENROUTER_URL, {
        method: "POST",
        headers: { Authorization: `Bearer ${key}`, "Content-Type": "application/json", "X-Title": "Bivi" },
        body: JSON.stringify({
          model: models[0],
          // OpenRouter tries these in order when one is down or rate-limited.
          ...(models.length > 1 ? { models } : {}),
          temperature: 0.4,
          // Reasoning models can spend the whole budget thinking and return nothing: turn it off.
          reasoning: { enabled: false, exclude: true },
          max_tokens: 3000,
          messages: [
            { role: "system", content: SYSTEM_PROMPT },
            { role: "user", content: `내 산행 통계예요.\n${facts}` },
          ],
        }),
        // Free models can be slow; all attempts must fit in the function's wall-clock limit (150 s).
        signal: AbortSignal.timeout(45_000),
      });
    } catch (e) {
      const timeout = e instanceof DOMException && e.name === "TimeoutError";
      return json({ error: timeout ? "timeout" : "model_unreachable" }, 504);
    }

    if (!res.ok) {
      const status = res.status;
      let detail = "";
      try {
        detail = (await res.json())?.error?.message ?? "";
      } catch { /* not JSON */ }
      console.error("openrouter error", status, detail.slice(0, 200));
      // e.g. a busy upstream provider vs. the account's daily free-request cap
      if (status === 429) return json({ error: "rate_limited", detail: detail.slice(0, 200) }, 429);
      if (status === 401 || status === 403) return json({ error: "model_key_rejected" }, 502);
      if (status === 404) return json({ error: "model_unavailable", detail: detail.slice(0, 200) }, 502);
      return json({ error: "model_error", status }, 502);
    }

    const body = await res.json();
    const report = cleanReport(String(body?.choices?.[0]?.message?.content ?? ""));
    const model = body?.model ?? models[0];
    const { hard, soft } = review(report, facts);
    if (!hard && !soft) return json({ report, model, generated_at: new Date().toISOString() });
    if (!hard && !fallback) fallback = { report, model };
    lastProblem = `${model}: ${hard ?? soft} (${body?.choices?.[0]?.finish_reason ?? "?"})`;
    console.error("model output not clean", attempt, lastProblem);
  }
  // No clean reply: a slightly imperfect one is still better than nothing.
  if (fallback) return json({ ...fallback, generated_at: new Date().toISOString() });
  return json({ error: "bad_model_output", detail: lastProblem }, 502);
});
