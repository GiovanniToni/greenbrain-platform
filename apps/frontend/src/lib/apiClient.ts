const BASE = (import.meta.env.VITE_API_BASE_URL ?? "").replace(/\/$/, "");

const TOKEN_KEY = "gb_access_token";
const RUNTIME_BASE_KEY = "gb_runtime_base_url";

let memoryToken: string | null = null;

const RUNTIME_API_PREFIXES = [
  "/api/v1/dashboard/",
  "/api/v1/analytics/",
  "/api/v1/forecast/",
  "/api/v1/catalog/",
  "/api/v1/sales/",
  "/api/v1/planner/",
  "/api/v1/settings/",
];

export function getStoredToken(): string | null {
  try {
    return localStorage.getItem(TOKEN_KEY) || sessionStorage.getItem(TOKEN_KEY) || memoryToken;
  } catch {
    try {
      return sessionStorage.getItem(TOKEN_KEY) || memoryToken;
    } catch {
      return memoryToken;
    }
  }
}

export function setStoredToken(token: string): void {
  memoryToken = token;
  try { localStorage.setItem(TOKEN_KEY, token); } catch {}
  try { sessionStorage.setItem(TOKEN_KEY, token); } catch {}
}

export function clearStoredToken(): void {
  memoryToken = null;
  try { localStorage.removeItem(TOKEN_KEY); localStorage.removeItem(RUNTIME_BASE_KEY); } catch {}
  try { sessionStorage.removeItem(TOKEN_KEY); sessionStorage.removeItem(RUNTIME_BASE_KEY); } catch {}
}

export function getRuntimeBaseUrl(): string | null {
  return localStorage.getItem(RUNTIME_BASE_KEY);
}

export function setRuntimeBaseUrl(url: string | null | undefined): void {
  const clean = (url || "").trim().replace(/\/$/, "");
  if (clean) localStorage.setItem(RUNTIME_BASE_KEY, clean);
}

function authHeaders(): Record<string, string> {
  const token = getStoredToken();
  return token ? { Authorization: `Bearer ${token}` } : {};
}

function shouldUseRuntime(path: string): boolean {
  return RUNTIME_API_PREFIXES.some((prefix) => path.startsWith(prefix));
}

function shouldUseCentralCloud(path: string): boolean {
  return path.startsWith("/api/v1/customer-portal/");
}

function apiOrigin(path: string): string {
  if (shouldUseRuntime(path)) {
    const runtimeBase = getRuntimeBaseUrl();
    return runtimeBase || window.location.origin;
  }

  // Customer account / portal data lives in the GreenBrain cloud even when
  // the user is currently using a customer-local runtime.
  if (shouldUseCentralCloud(path)) {
    return BASE || "https://www.greenbrain.it";
  }

  // Auth and same-app APIs must follow the current host.
  // This is critical for tenant SSO exchange:
  // cliente-reale.greenbrain.it/login?sso=... must POST to cliente-reale.greenbrain.it.
  return window.location.origin || BASE;
}

export class ApiError extends Error {
  constructor(
    public status: number,
    message: string,
  ) {
    super(message);
    this.name = "ApiError";
  }
}

export async function apiGet(
  path: string,
  params?: Record<string, string | number | boolean | string[] | number[] | null | undefined>,
): Promise<any> {
  const url = new URL(path, apiOrigin(path));

  if (params) {
    for (const [k, v] of Object.entries(params)) {
      if (v == null) continue;
      if (Array.isArray(v)) {
        v.forEach((item) => url.searchParams.append(k, String(item)));
      } else {
        url.searchParams.set(k, String(v));
      }
    }
  }

  const res = await fetch(url.toString(), { headers: authHeaders() });

  if (!res.ok) {
    let detail = `HTTP ${res.status}`;
    try {
      const body = await res.json();
      detail = body?.detail ?? body?.message ?? detail;
    } catch {}
    throw new ApiError(res.status, detail);
  }

  return res.json();
}

export async function apiPost(path: string, body: unknown): Promise<any> {
  const url = new URL(path, apiOrigin(path));

  const res = await fetch(url.toString(), {
    method: "POST",
    headers: { "Content-Type": "application/json", ...authHeaders() },
    body: JSON.stringify(body),
  });

  if (!res.ok) {
    let detail = `HTTP ${res.status}`;
    try {
      const b = await res.json();
      detail = b?.detail ?? b?.message ?? detail;
    } catch {}
    throw new ApiError(res.status, detail);
  }

  return res.json();
}

export async function apiPatch(path: string, body: unknown): Promise<any> {
  const url = new URL(path, apiOrigin(path));

  const res = await fetch(url.toString(), {
    method: "PATCH",
    headers: { "Content-Type": "application/json", ...authHeaders() },
    body: JSON.stringify(body),
  });

  if (!res.ok) {
    let detail = `HTTP ${res.status}`;
    try {
      const b = await res.json();
      detail = b?.detail ?? b?.message ?? detail;
    } catch {}
    throw new ApiError(res.status, detail);
  }

  return res.json();
}
