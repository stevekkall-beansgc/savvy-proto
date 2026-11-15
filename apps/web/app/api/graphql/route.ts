export const runtime = "nodejs";
export async function POST(request: Request) {
  const origin = request.headers.get("origin");
  const allowedOrigins = new Set(["http://127.0.0.1:3100", "http://localhost:3100"]);
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
    const response = await fetch("http://127.0.0.1:3101/graphql", {
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
            message:
              "Unable to load data. Please try again.",
          },
        ],
      },
      { status: 503 },
    );
  }
}
