export const runtime = "nodejs";
export async function GET() {
  const api = process.env.SAVVY_API_URL || "";
  if (!["http://127.0.0.1:3108", "http://127.0.0.1:3109"].includes(api)) {
    return Response.json({ error: "INVALID_CANDIDATE_API" }, { status: 400 });
  }
  try {
    const response = await fetch(`${api}/health`, { cache: "no-store", signal: AbortSignal.timeout(5000) });
    return Response.json({ api, slot: process.env.SAVVY_BUILD_DIRECTORY, health: await response.json() }, { status: response.status });
  } catch {
    return Response.json({ error: "API_UNAVAILABLE" }, { status: 503 });
  }
}
