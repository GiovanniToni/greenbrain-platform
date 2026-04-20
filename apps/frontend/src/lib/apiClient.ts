const BASE = (import.meta.env.VITE_API_BASE_URL ?? "").replace(/\/$/, "");

const TOKEN_KEY = "gb_access_token";

export function getStoredToken(): string | null {
  return localStorage.getItem(TOKEN_KEY);
}

export function setStoredToken(token: string): void {
  localStorage.setItem(TOKEN_KEY, token);
}

export function clearStoredToken(): void {
  localStorage.removeItem(TOKEN_KEY);
}

function authHeaders(): Record<string, string> {
  const token = getStoredToken();
  return token ? { Authorization: `Bearer ${token}` } : {};
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
  const origin = BASE || window.location.origin;
  const url = new URL(path, origin);

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
    } catch {
      // ignore parse error
    }
    throw new ApiError(res.status, detail);
  }

  return res.json();
}

export async function apiPost(path: string, body: unknown): Promise<any> {
  const origin = BASE || window.location.origin;
  const url = new URL(path, origin);

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
    } catch {
      // ignore parse error
    }
    throw new ApiError(res.status, detail);
  }

  return res.json();
}

export async function apiPatch(path: string, body: unknown): Promise<any> {
  const origin = BASE || window.location.origin;
  const url = new URL(path, origin);

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
    } catch {
      // ignore parse error
    }
    throw new ApiError(res.status, detail);
  }

  return res.json();
}
