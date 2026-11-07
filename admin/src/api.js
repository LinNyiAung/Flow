// Shared API helper for the admin panel.
// All requests go through `apiRequest` so that error handling and
// session expiry (401) behave the same everywhere.

export const API_BASE_URL = import.meta.env.VITE_API_BASE_URL ?? 'https://toepwar-t9vc.onrender.com';

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

// ─── AI providers ─────────────────────────────────────────────────────────────
const enc = encodeURIComponent;

/** Providers (with `configured`) and every feature's effective setting and `known_models` ({provider: [models]}). */
export const getAISettings = (token) => apiRequest('/api/admin/ai/settings', { token });

/** body: { main: {provider, model}, backups: [{provider, model}] | null }  (null = default backups, [] = none) */
export const updateAISetting = (token, feature, body) =>
  apiRequest(`/api/admin/ai/settings/${enc(feature)}`, { token, method: 'PUT', body });

/** Remove the admin-panel setting ("use server setting"). */
export const resetAISetting = (token, feature) =>
  apiRequest(`/api/admin/ai/settings/${enc(feature)}`, { token, method: 'DELETE' });

export const getAIStatus = (token) => apiRequest('/api/admin/ai/status', { token });

/** Sends one tiny request to the provider. Resolves to { ok: true } or { ok: false, error }. */
export const testAIProvider = (token, provider, model = null) =>
  apiRequest(`/api/admin/ai/test/${enc(provider)}`, { token, method: 'POST', body: { model } });

// ─── Plans ────────────────────────────────────────────────────────────────────
/**
 * { plans: {plan: {limits: {feature: {mode, quota, period}}, cost_cap_usd, price_monthly_mmk, price_yearly_mmk}},
 *   upgrade_contact: {en, my}, owner_contact: {email, viber} }. A price is whole kyat, or null when not set (Free: always null).
 */
export const getPlans = (token) => apiRequest('/api/admin/plans', { token });

/** Same shape as getPlans. Replaces every plan's limits, cost caps, prices and the contact texts. 422 detail: a string or a list. */
export const updatePlans = (token, body) => apiRequest('/api/admin/plans', { token, method: 'PUT', body });

/** { plan, features: {feature: {mode, used, limit, period}}, month_spend_usd, cost_cap_usd, cost_cap_reached } */
export const getUserUsage = (token, userId) => apiRequest(`/api/admin/users/${enc(userId)}/usage`, { token });

/** Clears this period's counts and the cost-cap flag for the user (admins only). */
export const resetUserUsage = (token, userId) =>
  apiRequest(`/api/admin/users/${enc(userId)}/reset-usage`, { token, method: 'POST' });

// ─── Upgrade requests ─────────────────────────────────────────────────────────
/**
 * status: 'pending' (default) | 'done' | 'dismissed'. Resolves to
 * [{ id, user_id, name, email, current_plan, is_trial, trial_ends_at, requested_plan, is_renewal, note, viber_number,
 *    billing ('month' | 'year' | null), created_at, status, handled_at }].
 * is_renewal: a pending request for the paid plan the user has now (they ask to extend it); false once handled.
 */
export const getUpgradeRequests = (token, params = {}) =>
  apiRequest('/api/admin/upgrade-requests', { token, params });

/** Admins only. 409 when the request is not pending any more. */
export const markUpgradeRequestDone = (token, id) =>
  apiRequest(`/api/admin/upgrade-requests/${enc(id)}/done`, { token, method: 'POST' });

export const dismissUpgradeRequest = (token, id) =>
  apiRequest(`/api/admin/upgrade-requests/${enc(id)}/dismiss`, { token, method: 'POST' });

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
