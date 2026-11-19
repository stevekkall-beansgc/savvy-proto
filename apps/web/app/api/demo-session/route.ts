import { NextRequest, NextResponse } from "next/server";
import { DEMO_COOKIE, demoEnabled, loopbackApi } from "../../../lib/demo-session";

export const runtime = "nodejs";
const headers = { "Cache-Control": "private, no-store" };

export function GET(request: NextRequest) {
  return NextResponse.json({ enabled: demoEnabled(), active: demoEnabled() && request.cookies.has(DEMO_COOKIE) }, { headers });
}

async function update(request: NextRequest) {
  if (!demoEnabled()) return NextResponse.json({ error: "Demo workspaces are unavailable." }, { status: 404, headers });
  const origin = request.headers.get("origin");
  const permitted = [process.env.SAVVY_PUBLIC_ORIGIN, ...[3100, 3104, 3106].flatMap(port => [`http://127.0.0.1:${port}`, `http://localhost:${port}`])];
  if (!origin || !permitted.includes(origin)) return NextResponse.json({ error: "This origin is not allowed." }, { status: 403, headers });

  try {
    const upstream = await fetch(new URL("/demo-session", loopbackApi()), {
      method: request.method,
      headers: {
        "X-Savvy-Public-Demo": "1",
        "X-Savvy-Demo-Token": request.cookies.get(DEMO_COOKIE)?.value || "",
      },
      cache: "no-store",
      signal: AbortSignal.timeout(25000),
    });
    if (!upstream.ok) {
      const data = await upstream.json();
      return NextResponse.json({ error: data.error || "The workspace could not be opened." }, { status: upstream.status, headers });
    }
    const starting = request.method === "POST";
    const token = starting ? (await upstream.json()).token : "";
    if (starting && !/^[a-f0-9]{64}$/.test(token)) throw new Error("Invalid workspace token");
    const response = NextResponse.json({ active: starting }, { headers });
    response.cookies.set(DEMO_COOKIE, token, { httpOnly: true, secure: origin.startsWith("https:"), sameSite: "strict", path: "/", maxAge: starting ? 86400 : 0 });
    return response;
  } catch {
    return NextResponse.json({ error: "The workspace could not be opened. Try again." }, { status: 503, headers });
  }
}

export const POST = update;
export const DELETE = update;
