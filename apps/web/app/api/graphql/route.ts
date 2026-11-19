import { NextRequest } from "next/server";
import { DEMO_COOKIE, demoEnabled, loopbackApi } from "../../../lib/demo-session";

export const runtime = "nodejs";
export async function POST(request: NextRequest) {
  const origin = request.headers.get("origin");
  const allowedOrigins = new Set([
    "http://127.0.0.1:3100",
    "http://localhost:3100",
    "http://127.0.0.1:3103",
    "http://localhost:3103",
    "http://127.0.0.1:3104",
    "http://localhost:3104",
    "http://127.0.0.1:3106",
    "http://localhost:3106",
  ]);
  if (process.env.SAVVY_PUBLIC_ORIGIN) {
    allowedOrigins.add(new URL(process.env.SAVVY_PUBLIC_ORIGIN).origin);
  }
  if (origin && !allowedOrigins.has(origin)) {
    return Response.json(
      { errors: [{ message: "This origin is not allowed." }] },
      { status: 403 },
    );
  }
  const body = await request.text();
  if (body.length > 1_048_576)
    return Response.json({ error: "BODY_TOO_LARGE" }, { status: 413 });
  let api: URL;
  try { api = loopbackApi(); }
  catch { return Response.json({ error: "INVALID_LOCAL_API" }, { status: 500 }); }
  try {
    const response = await fetch(new URL("/graphql", api), {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-Demo-Role": request.headers.get("X-Demo-Role") || "operator",
        ...(demoEnabled() && {
          "X-Savvy-Public-Demo": "1",
          "X-Savvy-Demo-Token": request.cookies.get(DEMO_COOKIE)?.value || "",
        }),
      },
      body,
      cache: "no-store",
      signal: AbortSignal.timeout(15000),
    });
    return new Response(await response.text(), {
      status: response.status,
      headers: { "Content-Type": "application/json", "Cache-Control": "private, no-store" },
    });
  } catch {
    return Response.json(
      {
        errors: [
          {
            message: "Unable to load data. Please try again.",
          },
        ],
      },
      { status: 503 },
    );
  }
}
