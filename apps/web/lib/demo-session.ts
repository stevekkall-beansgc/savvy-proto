export const DEMO_COOKIE = "savvy_demo_session";

export function demoEnabled() {
  return process.env.SAVVY_DEMO_SESSIONS === "1";
}

export function loopbackApi() {
  const api = new URL(process.env.SAVVY_API_URL || "http://127.0.0.1:3101");
  if (api.protocol !== "http:" ||
      !["3101", "3102", "3108", "3109"].includes(api.port) ||
      !["127.0.0.1", "localhost", "[::1]"].includes(api.hostname) ||
      api.username || api.password || api.pathname !== "/" || api.search || api.hash) {
    throw new Error("INVALID_LOCAL_API");
  }
  return api;
}
