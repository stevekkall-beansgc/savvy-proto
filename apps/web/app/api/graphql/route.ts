export const runtime = "nodejs";
export async function POST(request: Request) {
  const origin = request.headers.get("origin");
  const allowedOrigins = new Set([
    "http://127.0.0.1:3100",
    "http://localhost:3100",
    "http://127.0.0.1:3103",
    "http://localhost:3103",
    "http://127.0.0.1:3104",
    "http://localhost:3104",
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
  try {
    const api = new URL(process.env.SAVVY_API_URL || "http://127.0.0.1:3101");
    if (
      api.protocol !== "http:" ||
      !["3101", "3102"].includes(api.port) ||
      !["127.0.0.1", "localhost", "::1", "[::1]"].includes(api.hostname) ||
      api.username ||
      api.password ||
      api.pathname !== "/" ||
      api.search ||
      api.hash
    ) {
      return Response.json({ error: "INVALID_LOCAL_API" }, { status: 500 });
    }
    const response = await fetch(new URL("/graphql", api), {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-Demo-Role": request.headers.get("X-Demo-Role") || "operator",
      },
      body,
      cache: "no-store",
      signal: AbortSignal.timeout(15000),
    });
    return new Response(await response.text(), {
      status: response.status,
      headers: { "Content-Type": "application/json" },
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
