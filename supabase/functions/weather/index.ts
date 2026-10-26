import { json, requireUser } from "../_shared/http.ts";

// KMA ultra-short-term observation (초단기실황) for one 5 km grid cell.
// The KMA key lives only in this function's secrets; the app sends the grid cell,
// never its exact position (PRD_step6 6-2).
const KMA_URL = "https://apis.data.go.kr/1360000/VilageFcstInfoService_2.0/getUltraSrtNcst";

const pad = (n: number) => String(n).padStart(2, "0");
const isCell = (v: unknown, max: number): v is number =>
  Number.isInteger(v) && (v as number) >= 1 && (v as number) <= max;

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);
  if (!(await requireUser(req))) return json({ error: "login_required" }, 401);

  let nx: unknown, ny: unknown;
  try {
    ({ nx, ny } = await req.json());
  } catch {
    return json({ error: "bad_request" }, 400);
  }
  // The KMA grid is 149 × 253 cells.
  if (!isCell(nx, 149) || !isCell(ny, 253)) return json({ error: "bad_grid" }, 400);

  const key = Deno.env.get("KMA_API_KEY");
  if (!key) return json({ error: "server_not_configured" }, 500);

  // Observations are hourly and published about 40 minutes later: ask for the hour 40 minutes ago (KST).
  const kst = new Date(Date.now() + 9 * 3600_000 - 40 * 60_000);
  const url = new URL(KMA_URL);
  url.search = new URLSearchParams({
    serviceKey: key, // "Decoding" key; URLSearchParams encodes it
    pageNo: "1",
    numOfRows: "20",
    dataType: "JSON",
    base_date: `${kst.getUTCFullYear()}${pad(kst.getUTCMonth() + 1)}${pad(kst.getUTCDate())}`,
    base_time: `${pad(kst.getUTCHours())}00`,
    nx: String(nx),
    ny: String(ny),
  }).toString();

  let text: string;
  try {
    const res = await fetch(url, { signal: AbortSignal.timeout(10_000) });
    if (!res.ok) return json({ error: "kma_http", status: res.status }, 502);
    text = await res.text();
  } catch (e) {
    // Fetch errors can quote the request URL, which contains the key: never echo them.
    console.error("kma fetch failed:", e instanceof Error ? e.name : "unknown");
    return json({ error: "kma_unreachable" }, 502);
  }

  let body;
  try {
    body = JSON.parse(text);
  } catch {
    // KMA answers in XML when the key is wrong or not yet activated.
    return json({ error: "kma_bad_response" }, 502);
  }
  const header = body?.response?.header;
  if (header?.resultCode !== "00") return json({ error: "kma_error", message: header?.resultMsg }, 502);

  let temp: number | undefined;
  let wind: number | undefined;
  for (const item of body.response.body?.items?.item ?? []) {
    const value = Number(item.obsrValue);
    if (item.category === "T1H" && Number.isFinite(value)) temp = value;
    if (item.category === "WSD" && Number.isFinite(value)) wind = value;
  }
  if (temp === undefined) return json({ error: "no_temperature" }, 502);

  const observedUtc = Date.UTC(kst.getUTCFullYear(), kst.getUTCMonth(), kst.getUTCDate(), kst.getUTCHours()) -
    9 * 3600_000;
  return json({ temp_c: temp, wind_ms: wind ?? 0, observed_at: new Date(observedUtc).toISOString() });
});
