// Shared API helper for the admin panel.
// All requests go through `apiRequest` so that error handling and
// session expiry (401) behave the same everywhere.

export const API_BASE_URL = import.meta.env.VITE_API_BASE_URL ?? 'https://flowfinance.onrender.com';

const TOKEN_KEY = 'admin_token';
const ADMIN_KEY = 'admin_info';

// ─── Session storage ──────────────────────────────────────────────────────────
export function loadStoredSession() {
  try {
    const token = localStorage.getItem(TOKEN_KEY);
    const rawAdmin = localStorage.getItem(ADMIN_KEY);
    if (!token || !rawAdmin) return { token: null, admin: null };
    return { token, admin: JSON.parse(rawAdmin) };
  } catch {
    return { token: null, admin: null };
  }
}

export function storeSession(token, admin) {
  try {
    if (token) localStorage.setItem(TOKEN_KEY, token);
    if (admin) localStorage.setItem(ADMIN_KEY, JSON.stringify(admin));
  } catch {
    // Storage unavailable (private mode etc.) — session will just not persist.
  }
}

export function clearSession() {
  try {
    localStorage.removeItem(TOKEN_KEY);
    localStorage.removeItem(ADMIN_KEY);
  } catch {
    // ignore
  }
}

// ─── 401 handling ─────────────────────────────────────────────────────────────
const unauthorizedListeners = new Set();

/** Subscribe to "session expired / invalid token" events. Returns an unsubscribe fn. */
export function onUnauthorized(listener) {
  unauthorizedListeners.add(listener);
  return () => unauthorizedListeners.delete(listener);
}

function notifyUnauthorized() {
  clearSession();
  unauthorizedListeners.forEach((fn) => {
    try { fn(); } catch { /* ignore listener errors */ }
  });
}

// ─── Errors ───────────────────────────────────────────────────────────────────
export class ApiError extends Error {
  constructor(message, status, detail) {
    super(message);
    this.name = 'ApiError';
    this.status = status;
    this.detail = detail;
  }
}

/** Turn a FastAPI `detail` (string, list of {msg}, or object) into readable text. */
export function formatErrorDetail(detail, fallback = 'Request failed') {
  if (!detail) return fallback;
  if (typeof detail === 'string') return detail;
  if (Array.isArray(detail)) {
    const msgs = detail
      .map((d) => {
        if (typeof d === 'string') return d;
        if (d && d.msg) {
          const field = Array.isArray(d.loc) ? d.loc.filter((p) => p !== 'body' && p !== 'query').join('.') : '';
          return field ? `${field}: ${d.msg}` : d.msg;
        }
        return null;
      })
      .filter(Boolean);
    return msgs.length ? msgs.join('; ') : fallback;
  }
  if (typeof detail === 'object' && detail.msg) return detail.msg;
  return fallback;
}

/** Readable message for any thrown error. */
export function errorMessage(err, fallback = 'Something went wrong') {
  if (!err) return fallback;
  if (err instanceof ApiError) return err.message || fallback;
  if (err instanceof TypeError) return 'Network error — could not reach the server.';
  return err.message || fallback;
}

// ─── Request ──────────────────────────────────────────────────────────────────
/**
 * @param {string} path  e.g. '/api/admin/users'
 * @param {object} opts  { token, method, body, params, auth = true, signal }
 *   - params: object of query params; null/undefined/'' values are skipped
 *   - auth: when false, a 401 is NOT treated as session expiry (used for login)
 */
export async function apiRequest(path, { token, method = 'GET', body, params, auth = true, signal } = {}) {
  let url = `${API_BASE_URL}${path}`;
  if (params) {
    const qs = new URLSearchParams();
    Object.entries(params).forEach(([k, v]) => {
      if (v !== undefined && v !== null && v !== '') qs.append(k, String(v));
    });
    const s = qs.toString();
    if (s) url += `?${s}`;
  }

  const headers = {};
  if (auth && token) headers.Authorization = `Bearer ${token}`;
  if (body !== undefined) headers['Content-Type'] = 'application/json';

  const res = await fetch(url, {
    method,
    headers,
    body: body !== undefined ? JSON.stringify(body) : undefined,
    signal,
  });

  let data = null;
  const text = await res.text();
  if (text) {
    try { data = JSON.parse(text); } catch { data = text; }
  }

  if (!res.ok) {
    const detail = data && typeof data === 'object' ? data.detail : data;
    if (res.status === 401 && auth) {
      notifyUnauthorized();
      throw new ApiError('Your session has expired. Please sign in again.', 401, detail);
    }
    throw new ApiError(formatErrorDetail(detail, `Request failed (${res.status})`), res.status, detail);
  }

  return data;
}

// ─── Roles ────────────────────────────────────────────────────────────────────
/** admin and super_admin can make changes; moderators are read-only. */
export const canWrite = (role) => role === 'admin' || role === 'super_admin';
export const isSuperAdmin = (role) => role === 'super_admin';

// ─── Date helpers ─────────────────────────────────────────────────────────────
/** Parse 'YYYY-MM-DD' (from <input type="date">) as a LOCAL date at the given time. */
export function parseLocalDate(value, endOfDay = false) {
  if (!value) return null;
  const [y, m, d] = value.split('-').map(Number);
  if (!y || !m || !d) return null;
  return endOfDay ? new Date(y, m - 1, d, 23, 59, 59, 999) : new Date(y, m - 1, d, 0, 0, 0, 0);
}

/** Format a Date as local 'YYYY-MM-DD' for <input type="date">. */
export function toLocalDateInput(date) {
  if (!date || Number.isNaN(date.getTime())) return '';
  const pad = (n) => String(n).padStart(2, '0');
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`;
}
