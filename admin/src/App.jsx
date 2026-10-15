import { useState, useEffect, useCallback } from 'react';
import {
  Users, Shield, BarChart3, Activity, Search, LogOut, TrendingUp,
  AlertCircle, Crown, Zap, Eye, Trash2, RefreshCw, Calendar,
  DollarSign, Target, Send, Menu, X, Settings, Lock, User, MessageSquare,
  Smartphone, Plus, Edit2, ToggleLeft, ToggleRight, Download, CheckCircle,
  AlertTriangle, Globe, Apple, ExternalLink
} from 'lucide-react';
import AIUsageStats from './AIUsageStats';
import FeedbackManagement from './FeedbackManagement';
import ErrorBoundary from './ErrorBoundary';
import {
  apiRequest, errorMessage, onUnauthorized, loadStoredSession, storeSession, clearSession,
  canWrite, isSuperAdmin, parseLocalDate, toLocalDateInput,
} from './api';

const enc = encodeURIComponent;
const USERS_PAGE_SIZE = 50;
const VERSIONS_PAGE_SIZE = 50;
const fmtNum = (v) => (Number(v) || 0).toLocaleString();

// ─── API Service ──────────────────────────────────────────────────────────────
const api = {
  login: (email, password) =>
    apiRequest('/api/admin/login', { method: 'POST', body: { email, password }, auth: false }),
  getMe: (token) => apiRequest('/api/admin/me', { token }),
  getUsers: (token, params = {}) => apiRequest('/api/admin/users', { token, params }),
  updateUserSubscription: (token, userId, data) =>
    apiRequest(`/api/admin/users/${enc(userId)}/subscription`, { token, method: 'PUT', body: data }),
  getUserStats: (token) => apiRequest('/api/admin/stats/users', { token }),
  getSystemStats: (token) => apiRequest('/api/admin/stats/system', { token }),
  getAdmins: (token) => apiRequest('/api/admin/admins', { token }),
  createAdmin: (token, data) => apiRequest('/api/admin/admins', { token, method: 'POST', body: data }),
  deleteUser: (token, userId) => apiRequest(`/api/admin/users/${enc(userId)}`, { token, method: 'DELETE' }),
  getLogs: (token, params = {}) => apiRequest('/api/admin/logs', { token, params }),
  getBroadcastStats: (token) => apiRequest('/api/admin/broadcast-stats', { token }),
  sendBroadcastNotification: (token, data) =>
    apiRequest('/api/admin/broadcast-notification', { token, method: 'POST', body: data }),
  deleteAdmin: (token, adminId) => apiRequest(`/api/admin/admins/${enc(adminId)}`, { token, method: 'DELETE' }),
  updateProfile: (token, data) => apiRequest('/api/admin/me', { token, method: 'PUT', body: data }),
  changePassword: (token, data) => apiRequest('/api/admin/change-password', { token, method: 'PUT', body: data }),

  // ─── App Version API ──────────────────────────────────────────────────────
  getAppVersions: (token, params = {}) => apiRequest('/api/admin/app-versions', { token, params }),
  createAppVersion: (token, data) => apiRequest('/api/admin/app-versions', { token, method: 'POST', body: data }),
  updateAppVersion: (token, versionId, data) =>
    apiRequest(`/api/admin/app-versions/${enc(versionId)}`, { token, method: 'PUT', body: data }),
  deleteAppVersion: (token, versionId) =>
    apiRequest(`/api/admin/app-versions/${enc(versionId)}`, { token, method: 'DELETE' }),
};


// ─── Confirm Dialog (in-page, replaces window.confirm for risky actions) ──────
const ConfirmDialog = ({ title, message, confirmLabel = 'Confirm', tone = 'danger', busy = false, onConfirm, onCancel }) => (
  <div className="fixed inset-0 bg-black/70 backdrop-blur-sm flex items-center justify-center z-[60] animate-fadeIn p-4" onClick={busy ? undefined : onCancel}>
    <div
      role="alertdialog"
      aria-modal="true"
      className="bg-gradient-to-br from-slate-800 to-slate-700 rounded-2xl p-6 md:p-8 max-w-md w-full border border-white/10 shadow-2xl animate-slideIn"
      onClick={(e) => e.stopPropagation()}
    >
      <div className="flex items-start gap-3 mb-4">
        <div className={`w-10 h-10 rounded-xl flex items-center justify-center flex-shrink-0 ${tone === 'danger' ? 'bg-red-500/15' : 'bg-amber-500/15'}`}>
          <AlertTriangle size={20} className={tone === 'danger' ? 'text-red-400' : 'text-amber-400'} />
        </div>
        <div>
          <h2 className="text-lg font-bold text-slate-100 mb-1">{title}</h2>
          <div className="text-sm text-slate-300 leading-relaxed">{message}</div>
        </div>
      </div>
      <div className="flex gap-3 mt-6">
        <button
          onClick={onCancel}
          disabled={busy}
          className="flex-1 p-3 bg-slate-500/20 border border-slate-500/30 rounded-xl text-slate-300 text-sm font-semibold hover:bg-slate-500/30 transition-colors disabled:opacity-50"
        >
          Cancel
        </button>
        <button
          onClick={onConfirm}
          disabled={busy}
          autoFocus
          className={`flex-1 p-3 rounded-xl text-white text-sm font-semibold flex items-center justify-center gap-2 transition-colors disabled:opacity-60 ${tone === 'danger' ? 'bg-red-500 hover:bg-red-600' : 'bg-amber-500 hover:bg-amber-600'}`}
        >
          {busy && <RefreshCw size={14} className="animate-spin" />}
          {confirmLabel}
        </button>
      </div>
    </div>
  </div>
);


// ─── Login Page ───────────────────────────────────────────────────────────────
const LoginPage = ({ onLogin, notice }) => {
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');

  const handleSubmit = async (e) => {
    e.preventDefault();
    setLoading(true);
    setError('');
    try {
      const data = await api.login(email, password);
      onLogin(data.access_token, data.admin);
    } catch (err) {
      // Shows the server's message, e.g. "Incorrect email or password" or a lockout notice (429).
      setError(errorMessage(err, 'Invalid credentials. Please try again.'));
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="min-h-screen bg-gradient-to-br from-slate-900 via-slate-800 to-slate-700 flex items-center justify-center font-sans relative overflow-hidden text-slate-200 p-4">
      <div className="absolute top-[10%] left-[5%] w-[300px] md:w-[500px] h-[300px] md:h-[500px] rounded-full bg-blue-500/15 blur-[60px] animate-float" />
      <div className="absolute bottom-[10%] right-[5%] w-[250px] md:w-[400px] h-[250px] md:h-[400px] rounded-full bg-purple-500/15 blur-[60px] animate-float-reverse" />

      <div className="bg-slate-900/70 backdrop-blur-xl rounded-3xl p-8 md:p-12 w-full max-w-md shadow-2xl border border-white/10 relative z-10 animate-slideUp">
        <div className="w-[72px] h-[72px] bg-gradient-to-br from-blue-500 to-violet-500 rounded-2xl flex items-center justify-center mx-auto mb-6 shadow-lg shadow-blue-500/30">
          <Shield size={36} className="text-white" strokeWidth={2.5} />
        </div>
        <h1 className="text-3xl font-bold text-center mb-2 bg-gradient-to-br from-slate-100 to-slate-300 bg-clip-text text-transparent tracking-tight">
          Admin Portal
        </h1>
        <p className="text-center text-slate-400 text-[15px] mb-8 font-medium">Flow Finance Admin Dashboard</p>

        {notice && !error && (
          <div className="bg-amber-500/10 border border-amber-500/30 rounded-xl p-3 mb-6 flex items-center gap-3 animate-slideUp">
            <AlertCircle size={18} className="text-amber-500" />
            <span className="text-amber-300 text-sm">{notice}</span>
          </div>
        )}

        {error && (
          <div className="bg-red-500/10 border border-red-500/30 rounded-xl p-3 mb-6 flex items-center gap-3 animate-slideUp">
            <AlertCircle size={18} className="text-red-500 flex-shrink-0" />
            <span className="text-red-300 text-sm">{error}</span>
          </div>
        )}

        <form onSubmit={handleSubmit} className="space-y-5">
          <div>
            <label className="block text-slate-300 text-sm font-semibold mb-2 tracking-wide">Email Address</label>
            <input type="email" value={email} onChange={(e) => setEmail(e.target.value)} required
              className="w-full px-4 py-3.5 bg-slate-800/50 border border-slate-600/30 rounded-xl text-slate-100 text-[15px] outline-none transition-all duration-200 focus:border-blue-500 focus:bg-slate-800/80" />
          </div>
          <div>
            <label className="block text-slate-300 text-sm font-semibold mb-2 tracking-wide">Password</label>
            <input type="password" value={password} onChange={(e) => setPassword(e.target.value)} required
              className="w-full px-4 py-3.5 bg-slate-800/50 border border-slate-600/30 rounded-xl text-slate-100 text-[15px] outline-none transition-all duration-200 focus:border-blue-500 focus:bg-slate-800/80" />
          </div>
          <button type="submit" disabled={loading}
            className={`w-full py-4 rounded-xl text-white text-base font-semibold transition-all duration-300 shadow-lg tracking-wide ${loading ? 'bg-slate-600 cursor-not-allowed' : 'bg-gradient-to-br from-blue-500 to-violet-500 hover:-translate-y-0.5 hover:shadow-blue-500/40 shadow-blue-500/30 cursor-pointer'}`}>
            {loading ? 'Signing in...' : 'Sign In'}
          </button>
        </form>
      </div>
    </div>
  );
};


// ─── Profile Settings ─────────────────────────────────────────────────────────
const ProfileSettings = ({ token, admin, onUpdateAdmin, onTokenRotated, onLogout }) => {
  const [profileForm, setProfileForm] = useState({ name: admin.name, email: admin.email });
  const [passwordForm, setPasswordForm] = useState({ current_password: '', new_password: '', confirm_password: '' });
  const [loading, setLoading] = useState({ profile: false, password: false });

  const handleProfileUpdate = async (e) => {
    e.preventDefault();
    setLoading(prev => ({ ...prev, profile: true }));
    try {
      const updated = await api.updateProfile(token, profileForm);
      if (updated.email !== admin.email) {
        alert('Email updated. Please log in again.');
        onLogout();
      } else {
        onUpdateAdmin(updated);
        alert('Profile updated successfully');
      }
    } catch (error) { alert(errorMessage(error, 'Failed to update profile')); }
    finally { setLoading(prev => ({ ...prev, profile: false })); }
  };

  const handlePasswordChange = async (e) => {
    e.preventDefault();
    if (passwordForm.new_password !== passwordForm.confirm_password) { alert("New passwords don't match"); return; }
    setLoading(prev => ({ ...prev, password: true }));
    try {
      const data = await api.changePassword(token, passwordForm);
      // The server revokes the old session token and returns a fresh one.
      if (data?.access_token) onTokenRotated?.(data.access_token);
      alert('Password changed successfully');
      setPasswordForm({ current_password: '', new_password: '', confirm_password: '' });
    } catch (error) { alert(errorMessage(error, 'Failed to change password')); }
    finally { setLoading(prev => ({ ...prev, password: false })); }
  };

  return (
    <div className="animate-slideIn max-w-4xl">
      <div className="mb-8 mt-2 md:mt-0">
        <h1 className="text-3xl md:text-4xl font-bold mb-2 bg-gradient-to-br from-slate-100 to-slate-400 bg-clip-text text-transparent">Admin Settings</h1>
        <p className="text-slate-400 font-medium text-sm md:text-base">Manage your profile and security settings</p>
      </div>
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        <div className="bg-gradient-to-br from-slate-800/60 to-slate-700/30 rounded-2xl border border-white/5 p-6 md:p-8">
          <div className="flex items-center gap-3 mb-6">
            <div className="w-10 h-10 bg-blue-500/10 rounded-lg flex items-center justify-center"><Users size={20} className="text-blue-500" /></div>
            <h2 className="text-xl font-bold text-slate-100">Profile Details</h2>
          </div>
          <form onSubmit={handleProfileUpdate} className="space-y-5">
            <div>
              <label className="block text-slate-300 text-sm font-semibold mb-2">Full Name</label>
              <input type="text" value={profileForm.name} onChange={(e) => setProfileForm({...profileForm, name: e.target.value})}
                className="w-full px-4 py-3.5 bg-slate-900/50 border border-slate-600/30 rounded-xl text-slate-100 text-[15px] outline-none focus:border-blue-500 focus:bg-slate-900/80 transition-all" />
            </div>
            <div>
              <label className="block text-slate-300 text-sm font-semibold mb-2">Email Address</label>
              <input type="email" value={profileForm.email} onChange={(e) => setProfileForm({...profileForm, email: e.target.value})}
                className="w-full px-4 py-3.5 bg-slate-900/50 border border-slate-600/30 rounded-xl text-slate-100 text-[15px] outline-none focus:border-blue-500 focus:bg-slate-900/80 transition-all" />
              <p className="text-xs text-amber-500/80 mt-2">Note: Changing your email will require you to log in again.</p>
            </div>
            <button type="submit" disabled={loading.profile}
              className="w-full py-3.5 bg-blue-500 hover:bg-blue-600 text-white rounded-xl font-semibold transition-colors flex items-center justify-center gap-2 disabled:opacity-50 disabled:cursor-not-allowed">
              {loading.profile ? <RefreshCw size={18} className="animate-spin" /> : 'Update Profile'}
            </button>
          </form>
        </div>

        <div className="bg-gradient-to-br from-slate-800/60 to-slate-700/30 rounded-2xl border border-white/5 p-6 md:p-8">
          <div className="flex items-center gap-3 mb-6">
            <div className="w-10 h-10 bg-violet-500/10 rounded-lg flex items-center justify-center"><Lock size={20} className="text-violet-500" /></div>
            <h2 className="text-xl font-bold text-slate-100">Security</h2>
          </div>
          <form onSubmit={handlePasswordChange} className="space-y-5">
            {['current_password', 'new_password', 'confirm_password'].map((field) => (
              <div key={field}>
                <label className="block text-slate-300 text-sm font-semibold mb-2 capitalize">{field.replace(/_/g, ' ')}</label>
                <input type="password" value={passwordForm[field]} onChange={(e) => setPasswordForm({...passwordForm, [field]: e.target.value})}
                  className="w-full px-4 py-3.5 bg-slate-900/50 border border-slate-600/30 rounded-xl text-slate-100 text-[15px] outline-none focus:border-violet-500 focus:bg-slate-900/80 transition-all" />
              </div>
            ))}
            <button type="submit" disabled={loading.password}
              className="w-full py-3.5 bg-violet-500 hover:bg-violet-600 text-white rounded-xl font-semibold transition-colors flex items-center justify-center gap-2 disabled:opacity-50 disabled:cursor-not-allowed">
              {loading.password ? <RefreshCw size={18} className="animate-spin" /> : 'Change Password'}
            </button>
          </form>
        </div>
      </div>
    </div>
  );
};


// ─── App Version Management ───────────────────────────────────────────────────
const EMPTY_VERSION_FORM = {
  version: '',
  platform: 'all',
  download_url: '',
  release_notes: '',
  is_force_update: false,
  min_supported_version: '',
};

/** Numeric dotted-version compare (2.10.0 > 2.1.0). Non-numeric parts compare as 0. */
const compareVersions = (a, b) => {
  const pa = String(a).split('.').map((n) => parseInt(n, 10) || 0);
  const pb = String(b).split('.').map((n) => parseInt(n, 10) || 0);
  for (let i = 0; i < Math.max(pa.length, pb.length); i += 1) {
    const d = (pa[i] || 0) - (pb[i] || 0);
    if (d !== 0) return d;
  }
  return 0;
};

const AppVersionManagement = ({ token, adminRole }) => {
  const [platformFilter, setPlatformFilter] = useState('');
  const [refreshKey, setRefreshKey] = useState(0);
  const [list, setList] = useState({ key: null, items: [], hasMore: false, error: null });
  const [loadingMore, setLoadingMore] = useState(false);
  const [showForm, setShowForm] = useState(false);
  const [editingVersion, setEditingVersion] = useState(null); // null = create, object = edit
  const [form, setForm] = useState(EMPTY_VERSION_FORM);
  const [saving, setSaving] = useState(false);
  const [confirm, setConfirm] = useState(null); // { title, message, confirmLabel, tone, action }
  const [confirmBusy, setConfirmBusy] = useState(false);

  const writable = canWrite(adminRole);
  const queryKey = `${platformFilter}|${refreshKey}`;
  const loading = list.key !== queryKey;

  useEffect(() => {
    let cancelled = false;
    api.getAppVersions(token, { platform: platformFilter, skip: 0, limit: VERSIONS_PAGE_SIZE })
      .then((data) => {
        if (cancelled) return;
        const items = Array.isArray(data) ? data : [];
        setList({ key: queryKey, items, hasMore: items.length === VERSIONS_PAGE_SIZE, error: null });
      })
      .catch((err) => {
        if (cancelled) return;
        setList({ key: queryKey, items: [], hasMore: false, error: errorMessage(err, 'Failed to load app versions') });
      });
    return () => { cancelled = true; };
  }, [token, platformFilter, queryKey]);

  const reload = () => setRefreshKey((k) => k + 1);

  const loadMore = async () => {
    const keyAtStart = queryKey;
    setLoadingMore(true);
    try {
      const data = await api.getAppVersions(token, { platform: platformFilter, skip: list.items.length, limit: VERSIONS_PAGE_SIZE });
      const items = Array.isArray(data) ? data : [];
      setList((prev) => {
        if (prev.key !== keyAtStart) return prev;
        const seen = new Set(prev.items.map((v) => v.id));
        return { ...prev, items: [...prev.items, ...items.filter((v) => !seen.has(v.id))], hasMore: items.length === VERSIONS_PAGE_SIZE };
      });
    } catch (err) {
      alert(errorMessage(err, 'Failed to load more versions'));
    } finally {
      setLoadingMore(false);
    }
  };

  // Replace a row with the server's copy right away, then refetch for consistency.
  const applyUpdated = (updated) => {
    if (updated && updated.id) {
      setList((prev) => ({ ...prev, items: prev.items.map((v) => (v.id === updated.id ? updated : v)) }));
    }
    reload();
  };

  const openCreate = () => {
    setEditingVersion(null);
    setForm(EMPTY_VERSION_FORM);
    setShowForm(true);
  };

  const openEdit = (v) => {
    setEditingVersion(v);
    setForm({
      version: v.version,
      platform: v.platform,
      download_url: v.download_url,
      release_notes: v.release_notes || '',
      is_force_update: v.is_force_update,
      min_supported_version: v.min_supported_version || '',
    });
    setShowForm(true);
  };

  const handleSave = async () => {
    if (!form.version.trim() || !form.download_url.trim()) {
      alert('Version and Download URL are required.');
      return;
    }
    setSaving(true);
    try {
      // Empty fields are sent as null — the server clears them on update.
      const minSupported = form.min_supported_version.trim() || null;
      const releaseNotes = form.release_notes.trim() || null;
      if (editingVersion) {
        const updated = await api.updateAppVersion(token, editingVersion.id, {
          download_url: form.download_url.trim(),
          release_notes: releaseNotes,
          is_force_update: form.is_force_update,
          min_supported_version: minSupported,
        });
        setShowForm(false);
        applyUpdated(updated);
      } else {
        await api.createAppVersion(token, {
          ...form,
          version: form.version.trim(),
          download_url: form.download_url.trim(),
          min_supported_version: minSupported,
          release_notes: releaseNotes,
        });
        setShowForm(false);
        reload();
      }
    } catch (err) {
      alert(errorMessage(err, 'Failed to save app version'));
    } finally {
      setSaving(false);
    }
  };

  const runConfirmed = async () => {
    if (!confirm) return;
    setConfirmBusy(true);
    try {
      await confirm.action();
      setConfirm(null);
    } catch (err) {
      alert(errorMessage(err, 'Action failed'));
    } finally {
      setConfirmBusy(false);
    }
  };

  const platformName = (p) => (p === 'android' ? 'Android' : p === 'ios' ? 'iOS' : 'all platforms');

  const setActive = async (v, isActive) => {
    applyUpdated(await api.updateAppVersion(token, v.id, { is_active: isActive }));
  };

  const setForce = async (v, isForce) => {
    applyUpdated(await api.updateAppVersion(token, v.id, { is_force_update: isForce }));
  };

  const handleToggleActive = (v) => {
    if (v.is_active) {
      setConfirm({
        title: `Deactivate v${v.version}?`,
        message: (
          <>
            The update check will ignore this version: it will no longer be offered to users on {platformName(v.platform)}
            {v.is_force_update || v.min_supported_version ? ', and its force-update / minimum-version rules stop being enforced.' : '.'}
          </>
        ),
        confirmLabel: 'Deactivate',
        tone: 'warning',
        action: () => setActive(v, false),
      });
    } else {
      setActive(v, true).catch((err) => alert(errorMessage(err, 'Failed to toggle version status')));
    }
  };

  const handleToggleForce = (v) => {
    if (!v.is_force_update) {
      setConfirm({
        title: `Force update to v${v.version}?`,
        message: (
          <>
            Every user on {platformName(v.platform)} running a version <strong>older than v{v.version}</strong> will be
            blocked until they update{v.is_active ? '' : ' (once this version is active)'}. This applies even if a newer, optional version exists.
          </>
        ),
        confirmLabel: 'Force update',
        tone: 'danger',
        action: () => setForce(v, true),
      });
    } else {
      setForce(v, false).catch((err) => alert(errorMessage(err, 'Failed to toggle force update')));
    }
  };

  const handleDelete = (v) => {
    setConfirm({
      title: `Delete v${v.version}?`,
      message: 'This version record will be permanently deleted. This cannot be undone.',
      confirmLabel: 'Delete',
      tone: 'danger',
      action: async () => {
        await api.deleteAppVersion(token, v.id);
        reload();
      },
    });
  };

  const platformIcon = (p) => {
    if (p === 'android') return <Globe size={14} className="text-emerald-400" />;
    if (p === 'ios') return <Apple size={14} className="text-blue-400" />;
    return <Smartphone size={14} className="text-slate-400" />;
  };

  const platformLabel = (p) => {
    if (p === 'android') return <span className="text-emerald-400">Android</span>;
    if (p === 'ios') return <span className="text-blue-400">iOS</span>;
    return <span className="text-slate-300">All Platforms</span>;
  };

  const versions = list.items;
  // Summary counts (over loaded versions)
  const total = versions.length;
  const active = versions.filter(v => v.is_active).length;
  const forceCount = versions.filter(v => v.is_force_update && v.is_active).length;
  const effectiveMin = versions
    .filter((v) => v.is_active && v.min_supported_version)
    .map((v) => v.min_supported_version)
    .sort(compareVersions)
    .pop();

  return (
    <div className="animate-slideIn">
      {/* Header */}
      <div className="mb-6 md:mb-8 mt-2 md:mt-0 flex flex-col md:flex-row md:items-start justify-between gap-4">
        <div>
          <h1 className="text-3xl md:text-4xl font-bold mb-2 bg-gradient-to-br from-slate-100 to-slate-400 bg-clip-text text-transparent">
            App Version Management
          </h1>
          <p className="text-slate-400 font-medium text-sm md:text-base">
            Control app versions and force-update enforcement{!writable && ' (read-only)'}
          </p>
        </div>
        {writable && (
          <button
            onClick={openCreate}
            className="w-full md:w-auto px-6 py-3.5 bg-gradient-to-br from-blue-500 to-violet-500 rounded-xl text-white text-[15px] font-semibold flex items-center justify-center gap-2 hover:-translate-y-0.5 transition-transform shadow-lg shadow-blue-500/30"
          >
            <Plus size={18} />
            Publish New Version
          </button>
        )}
      </div>

      {/* Summary Cards */}
      <div className="grid grid-cols-1 sm:grid-cols-3 gap-4 mb-6">
        {[
          { label: 'Total Versions', value: `${total}${list.hasMore ? '+' : ''}`, color: 'text-blue-400', bg: 'bg-blue-500/10', icon: Smartphone },
          { label: 'Active Versions', value: active, color: 'text-emerald-400', bg: 'bg-emerald-500/10', icon: CheckCircle },
          {
            label: 'Active Forced Versions', value: forceCount, color: 'text-red-400', bg: 'bg-red-500/10', icon: AlertTriangle,
            hint: forceCount > 0
              ? 'Users below the newest of these must update.'
              : effectiveMin ? `No forced versions; min supported is v${effectiveMin}.` : 'No version is currently enforced.',
          },
        ].map((s) => (
          <div key={s.label} className="bg-gradient-to-br from-slate-800/60 to-slate-700/30 p-5 rounded-2xl border border-white/5">
            <div className={`w-11 h-11 ${s.bg} rounded-xl flex items-center justify-center mb-3`}>
              <s.icon size={22} className={s.color} />
            </div>
            <div className={`text-3xl font-bold mb-1 ${s.color}`}>{s.value}</div>
            <div className="text-sm text-slate-400">{s.label}</div>
            {s.hint && <div className="text-xs text-slate-500 mt-1">{s.hint}</div>}
          </div>
        ))}
      </div>

      {/* Filters */}
      <div className="flex items-center gap-3 mb-5">
        <select
          value={platformFilter}
          onChange={(e) => setPlatformFilter(e.target.value)}
          className="px-4 py-2.5 bg-slate-800/50 border border-slate-600/30 rounded-xl text-slate-300 text-sm outline-none focus:border-blue-500 cursor-pointer"
        >
          <option value="">All Platforms</option>
          <option value="android">Android</option>
          <option value="ios">iOS</option>
          <option value="all">All</option>
        </select>
        <button onClick={reload} className="p-2.5 bg-slate-700/50 border border-white/5 rounded-xl text-slate-400 hover:text-white transition-colors">
          <RefreshCw size={18} className={loading ? 'animate-spin' : ''} />
        </button>
      </div>

      {/* How Force Update Works */}
      <div className="bg-blue-500/5 border border-blue-500/20 rounded-2xl p-5 mb-6 flex items-start gap-3">
        <AlertCircle size={20} className="text-blue-400 mt-0.5 flex-shrink-0" />
        <div className="text-sm text-blue-300/80 leading-relaxed">
          <strong className="text-blue-300">How it works:</strong> On startup the app checks all <em>active</em> versions for its platform (plus "All Platforms").
          A user is <strong>forced</strong> to update if <em>any</em> active version newer than theirs is marked <strong>Forced</strong> — even when a newer optional version also exists —
          or if they are below the highest <strong>Min Supported Version</strong> among active versions{effectiveMin ? <> (currently <strong>v{effectiveMin}</strong>)</> : null}.
          Inactive versions are ignored entirely.
        </div>
      </div>

      {/* Versions Table */}
      <div className="bg-gradient-to-br from-slate-800/60 to-slate-700/30 rounded-2xl border border-white/5 overflow-hidden">
        {loading && versions.length === 0 ? (
          <div className="p-16 flex items-center justify-center">
            <RefreshCw size={28} className="animate-spin text-blue-500" />
          </div>
        ) : list.error && !loading ? (
          <div className="p-16 text-center text-red-400">{list.error}</div>
        ) : versions.length === 0 ? (
          <div className="p-16 text-center">
            <Smartphone size={40} className="text-slate-600 mx-auto mb-3" />
            <div className="text-slate-400 text-lg font-semibold mb-1">No versions published yet</div>
            {writable && <div className="text-slate-500 text-sm">Click "Publish New Version" to get started.</div>}
          </div>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full border-collapse min-w-[900px]">
              <thead>
                <tr className="bg-slate-900/50 border-b border-white/5">
                  {['Version', 'Platform', 'Download URL', 'Force Update', 'Min Supported', 'Status', 'Published', ...(writable ? ['Actions'] : [])].map((h, i) => (
                    <th key={h} className={`px-5 py-4 text-left text-slate-400 text-xs font-semibold tracking-wider uppercase ${i === 7 ? 'text-center' : ''}`}>
                      {h}
                    </th>
                  ))}
                </tr>
              </thead>
              <tbody>
                {versions.map((v, index) => {
                  const forceClasses = v.is_force_update
                    ? (v.is_active ? 'bg-red-500/15 border-red-500/30 text-red-400' : 'bg-red-500/5 border-red-500/20 text-red-400/60')
                    : 'bg-slate-700/50 border-slate-600/30 text-slate-500';
                  const forceLabel = v.is_force_update ? (v.is_active ? 'Forced' : 'Forced (inactive)') : 'Optional';
                  const forceTitle = v.is_force_update
                    ? (v.is_active
                      ? `Users on versions older than v${v.version} must update`
                      : 'Not enforced — this version is inactive')
                    : 'Optional update';
                  return (
                  <tr key={v.id} className="border-b border-white/5 hover:bg-slate-800/40 transition-colors animate-slideIn" style={{ animationDelay: `${Math.min(index, 20) * 40}ms` }}>
                    {/* Version */}
                    <td className="px-5 py-4">
                      <div className="text-base font-bold text-slate-100">v{v.version}</div>
                      {v.release_notes && (
                        <div className="text-xs text-slate-500 mt-0.5 max-w-[140px] truncate" title={v.release_notes}>
                          {v.release_notes}
                        </div>
                      )}
                    </td>

                    {/* Platform */}
                    <td className="px-5 py-4">
                      <div className="flex items-center gap-1.5 text-sm font-semibold">
                        {platformIcon(v.platform)}
                        {platformLabel(v.platform)}
                      </div>
                    </td>

                    {/* Download URL */}
                    <td className="px-5 py-4">
                      <a href={v.download_url} target="_blank" rel="noreferrer"
                        className="flex items-center gap-1.5 text-blue-400 hover:text-blue-300 text-xs font-medium max-w-[180px] truncate transition-colors"
                        title={v.download_url}>
                        <ExternalLink size={12} className="flex-shrink-0" />
                        {String(v.download_url ?? '').replace(/^https?:\/\//, '').slice(0, 30)}{String(v.download_url ?? '').length > 35 ? '…' : ''}
                      </a>
                    </td>

                    {/* Force Update Toggle */}
                    <td className="px-5 py-4">
                      {writable ? (
                        <button
                          onClick={() => handleToggleForce(v)}
                          title={forceTitle}
                          className={`flex items-center gap-2 px-3 py-1.5 rounded-lg text-xs font-semibold border transition-all hover:brightness-125 ${forceClasses}`}
                        >
                          {v.is_force_update ? <AlertTriangle size={13} /> : <CheckCircle size={13} />}
                          {forceLabel}
                        </button>
                      ) : (
                        <span title={forceTitle} className={`inline-flex items-center gap-2 px-3 py-1.5 rounded-lg text-xs font-semibold border ${forceClasses}`}>
                          {v.is_force_update ? <AlertTriangle size={13} /> : <CheckCircle size={13} />}
                          {forceLabel}
                        </span>
                      )}
                    </td>

                    {/* Min Supported Version */}
                    <td className="px-5 py-4">
                      {v.min_supported_version ? (
                        <span
                          title={v.is_active ? 'Users below this version must update' : 'Not enforced — this version is inactive'}
                          className={`px-2.5 py-1 border text-xs font-semibold rounded-lg ${v.is_active ? 'bg-amber-500/10 border-amber-500/30 text-amber-400' : 'bg-amber-500/5 border-amber-500/15 text-amber-400/50'}`}
                        >
                          ≥ v{v.min_supported_version}
                        </span>
                      ) : (
                        <span className="text-slate-600 text-xs">—</span>
                      )}
                    </td>

                    {/* Active Toggle */}
                    <td className="px-5 py-4">
                      {writable ? (
                        <button
                          onClick={() => handleToggleActive(v)}
                          className={`flex items-center gap-2 px-3 py-1.5 rounded-lg text-xs font-semibold border transition-all ${
                            v.is_active
                              ? 'bg-emerald-500/15 border-emerald-500/30 text-emerald-400 hover:bg-emerald-500/25'
                              : 'bg-slate-700/50 border-slate-600/30 text-slate-500 hover:border-slate-500/50'
                          }`}
                        >
                          {v.is_active ? <ToggleRight size={14} /> : <ToggleLeft size={14} />}
                          {v.is_active ? 'Active' : 'Inactive'}
                        </button>
                      ) : (
                        <span className={`inline-flex items-center gap-2 px-3 py-1.5 rounded-lg text-xs font-semibold border ${
                          v.is_active ? 'bg-emerald-500/15 border-emerald-500/30 text-emerald-400' : 'bg-slate-700/50 border-slate-600/30 text-slate-500'
                        }`}>
                          {v.is_active ? <ToggleRight size={14} /> : <ToggleLeft size={14} />}
                          {v.is_active ? 'Active' : 'Inactive'}
                        </span>
                      )}
                    </td>

                    {/* Published date */}
                    <td className="px-5 py-4 text-xs text-slate-500">
                      {v.created_at ? new Date(v.created_at).toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' }) : ''}
                      <div className="text-slate-600 mt-0.5">{v.created_by_email}</div>
                    </td>

                    {/* Actions */}
                    {writable && (
                      <td className="px-5 py-4">
                        <div className="flex items-center justify-center gap-2">
                          <button
                            onClick={() => openEdit(v)}
                            className="p-2 text-slate-400 hover:text-blue-400 hover:bg-blue-500/10 rounded-lg transition-colors"
                            title="Edit"
                          >
                            <Edit2 size={15} />
                          </button>
                          {isSuperAdmin(adminRole) && (
                            <button
                              onClick={() => handleDelete(v)}
                              className="p-2 text-slate-400 hover:text-red-400 hover:bg-red-500/10 rounded-lg transition-colors"
                              title="Delete"
                            >
                              <Trash2 size={15} />
                            </button>
                          )}
                        </div>
                      </td>
                    )}
                  </tr>
                  );
                })}
              </tbody>
            </table>
            {list.hasMore && (
              <div className="p-4 border-t border-white/5 flex justify-center">
                <button
                  onClick={loadMore}
                  disabled={loadingMore}
                  className="px-5 py-2.5 bg-slate-700/50 border border-white/10 rounded-xl text-slate-300 text-sm font-semibold hover:bg-slate-700 transition-colors flex items-center gap-2 disabled:opacity-50"
                >
                  {loadingMore && <RefreshCw size={14} className="animate-spin" />}
                  Load more
                </button>
              </div>
            )}
          </div>
        )}
      </div>

      {/* Create / Edit Modal */}
      {showForm && writable && (
        <div
          className="fixed inset-0 bg-black/70 backdrop-blur-sm flex items-center justify-center z-50 animate-fadeIn p-4"
          onClick={() => setShowForm(false)}
        >
          <div
            className="bg-gradient-to-br from-slate-800 to-slate-700 rounded-3xl p-6 md:p-10 max-w-lg w-full border border-white/10 shadow-2xl animate-slideIn max-h-[90vh] overflow-y-auto"
            onClick={(e) => e.stopPropagation()}
          >
            {/* Modal Header */}
            <div className="flex items-center gap-3 mb-7">
              <div className="w-12 h-12 bg-gradient-to-br from-blue-500 to-violet-500 rounded-xl flex items-center justify-center flex-shrink-0">
                <Smartphone size={22} className="text-white" />
              </div>
              <div>
                <h2 className="text-xl font-bold text-slate-100">
                  {editingVersion ? `Edit v${editingVersion.version}` : 'Publish New Version'}
                </h2>
                <p className="text-xs text-slate-400 mt-0.5">
                  {editingVersion ? 'Update version details below' : 'Fill in the details for the new app release'}
                </p>
              </div>
            </div>

            <div className="space-y-5">
              {/* Version & Platform row */}
              <div className="grid grid-cols-2 gap-4">
                <div>
                  <label className="block text-slate-300 text-sm font-semibold mb-2">Version <span className="text-red-400">*</span></label>
                  <input
                    type="text"
                    placeholder="e.g. 2.1.0"
                    value={form.version}
                    disabled={!!editingVersion}
                    onChange={(e) => setForm({...form, version: e.target.value})}
                    className="w-full px-4 py-3 bg-slate-800/50 border border-slate-600/30 rounded-xl text-slate-100 text-[15px] outline-none focus:border-blue-500 disabled:opacity-50 disabled:cursor-not-allowed"
                  />
                </div>
                <div>
                  <label className="block text-slate-300 text-sm font-semibold mb-2">Platform <span className="text-red-400">*</span></label>
                  <select
                    value={form.platform}
                    disabled={!!editingVersion}
                    onChange={(e) => setForm({...form, platform: e.target.value})}
                    className="w-full px-4 py-3 bg-slate-800/50 border border-slate-600/30 rounded-xl text-slate-100 text-[15px] outline-none focus:border-blue-500 cursor-pointer disabled:opacity-50 disabled:cursor-not-allowed"
                  >
                    <option value="all">All Platforms</option>
                    <option value="android">Android</option>
                    <option value="ios">iOS</option>
                  </select>
                </div>
              </div>

              {/* Download URL */}
              <div>
                <label className="block text-slate-300 text-sm font-semibold mb-2">
                  Download URL <span className="text-red-400">*</span>
                </label>
                <input
                  type="url"
                  placeholder="https://play.google.com/store/apps/..."
                  value={form.download_url}
                  onChange={(e) => setForm({...form, download_url: e.target.value})}
                  className="w-full px-4 py-3 bg-slate-800/50 border border-slate-600/30 rounded-xl text-slate-100 text-[15px] outline-none focus:border-blue-500"
                />
                <p className="text-xs text-slate-500 mt-1">Play Store link, App Store link, or direct APK URL.</p>
              </div>

              {/* Min Supported Version */}
              <div>
                <label className="block text-slate-300 text-sm font-semibold mb-2">Min Supported Version</label>
                <input
                  type="text"
                  placeholder="e.g. 1.5.0 (optional)"
                  value={form.min_supported_version}
                  onChange={(e) => setForm({...form, min_supported_version: e.target.value})}
                  className="w-full px-4 py-3 bg-slate-800/50 border border-slate-600/30 rounded-xl text-slate-100 text-[15px] outline-none focus:border-blue-500"
                />
                <p className="text-xs text-slate-500 mt-1">
                  While this version is active, users below this version are force-updated regardless of the force flag.
                  {editingVersion && ' Leave empty to clear it.'}
                </p>
              </div>

              {/* Release Notes */}
              <div>
                <label className="block text-slate-300 text-sm font-semibold mb-2">Release Notes</label>
                <textarea
                  rows={3}
                  placeholder="What's new in this version..."
                  value={form.release_notes}
                  onChange={(e) => setForm({...form, release_notes: e.target.value})}
                  className="w-full px-4 py-3 bg-slate-800/50 border border-slate-600/30 rounded-xl text-slate-100 text-[15px] outline-none focus:border-blue-500 resize-none"
                />
              </div>

              {/* Force Update Toggle */}
              <div
                className={`p-4 rounded-xl border-2 cursor-pointer transition-all select-none ${
                  form.is_force_update
                    ? 'border-red-500/50 bg-red-500/10'
                    : 'border-slate-600/30 bg-slate-800/30 hover:border-slate-500/50'
                }`}
                onClick={() => setForm({...form, is_force_update: !form.is_force_update})}
              >
                <div className="flex items-center justify-between">
                  <div className="flex items-center gap-3">
                    <AlertTriangle size={18} className={form.is_force_update ? 'text-red-400' : 'text-slate-500'} />
                    <div>
                      <div className={`text-sm font-semibold ${form.is_force_update ? 'text-red-300' : 'text-slate-300'}`}>
                        Force Update
                      </div>
                      <div className="text-xs text-slate-500 mt-0.5">Block users on older versions until they update</div>
                    </div>
                  </div>
                  <div className={`w-11 h-6 rounded-full relative transition-all ${form.is_force_update ? 'bg-red-500' : 'bg-slate-600'}`}>
                    <div className={`absolute top-0.5 w-5 h-5 bg-white rounded-full shadow transition-all ${form.is_force_update ? 'left-5' : 'left-0.5'}`} />
                  </div>
                </div>
              </div>

              {/* Force Update Warning */}
              {form.is_force_update && (
                <div className="bg-red-500/10 border border-red-500/30 rounded-xl p-3 flex items-start gap-2.5">
                  <AlertCircle size={16} className="text-red-400 mt-0.5 flex-shrink-0" />
                  <p className="text-xs text-red-300">
                    <strong>Warning:</strong> Force update will block all users on versions older than this one from using the app — even if a newer optional version exists. Use only for critical security fixes or breaking changes.
                  </p>
                </div>
              )}
            </div>

            {/* Modal Actions */}
            <div className="flex gap-3 mt-8">
              <button
                onClick={() => setShowForm(false)}
                className="flex-1 p-3.5 bg-slate-500/20 border border-slate-500/30 rounded-xl text-slate-400 text-sm font-semibold hover:bg-slate-500/30 transition-colors"
              >
                Cancel
              </button>
              <button
                onClick={handleSave}
                disabled={saving}
                className={`flex-1 p-3.5 rounded-xl text-white text-sm font-semibold flex items-center justify-center gap-2 transition-all ${
                  saving ? 'bg-slate-600 cursor-not-allowed' : 'bg-gradient-to-br from-blue-500 to-violet-500 hover:-translate-y-0.5 shadow-lg shadow-blue-500/30'
                }`}
              >
                {saving ? (
                  <><RefreshCw size={16} className="animate-spin" /> Saving...</>
                ) : (
                  <><Download size={16} /> {editingVersion ? 'Save Changes' : 'Publish Version'}</>
                )}
              </button>
            </div>
          </div>
        </div>
      )}

      {confirm && (
        <ConfirmDialog
          title={confirm.title}
          message={confirm.message}
          confirmLabel={confirm.confirmLabel}
          tone={confirm.tone}
          busy={confirmBusy}
          onConfirm={runConfirmed}
          onCancel={() => setConfirm(null)}
        />
      )}
    </div>
  );
};


// ─── Dashboard ────────────────────────────────────────────────────────────────
// Tabs whose data is loaded by the Dashboard itself (others load their own).
const DASHBOARD_DATA_TABS = ['overview', 'users', 'broadcast', 'admins', 'logs'];
const EMPTY_BROADCAST_FORM = { title: '', message: '', target_users: 'all', notification_type: 'system_broadcast' };

const Dashboard = ({ token, admin, onLogout, onUpdateAdmin, onTokenRotated }) => {
  const [activeTab, setActiveTab] = useState('overview');
  const [refreshKey, setRefreshKey] = useState(0);
  const [tabStatus, setTabStatus] = useState({ key: null, error: null });
  const [stats, setStats] = useState(null);
  const [systemStats, setSystemStats] = useState(null);
  const [usersState, setUsersState] = useState({ key: null, items: [], hasMore: false });
  const [loadingMoreUsers, setLoadingMoreUsers] = useState(false);
  const [admins, setAdmins] = useState([]);
  const [logs, setLogs] = useState([]);
  // Draft inputs vs. filters actually applied to the users query.
  const [searchQuery, setSearchQuery] = useState('');
  const [subscriptionFilter, setSubscriptionFilter] = useState('');
  const [userFilters, setUserFilters] = useState({ search: '', subscription_type: '' });
  const [selectedUser, setSelectedUser] = useState(null);
  const [broadcastStats, setBroadcastStats] = useState(null);
  const [broadcastForm, setBroadcastForm] = useState(EMPTY_BROADCAST_FORM);
  const [broadcastLoading, setBroadcastLoading] = useState(false);
  const [showCreateAdmin, setShowCreateAdmin] = useState(false);
  const [createAdminForm, setCreateAdminForm] = useState({ name: '', email: '', password: '', role: 'admin' });
  const [createAdminLoading, setCreateAdminLoading] = useState(false);
  const [isSidebarOpen, setIsSidebarOpen] = useState(false);

  const isSuper = isSuperAdmin(admin.role);
  const writable = canWrite(admin.role);

  const loadKey = `${activeTab}|${userFilters.search}|${userFilters.subscription_type}|${refreshKey}`;
  const tabLoadsData = DASHBOARD_DATA_TABS.includes(activeTab);
  const loading = tabLoadsData && tabStatus.key !== loadKey;
  const tabError = tabLoadsData && tabStatus.key === loadKey ? tabStatus.error : null;

  // Single loader keyed on tab + applied filters + refresh counter.
  // Stale (out-of-order) responses are dropped via `cancelled`.
  useEffect(() => {
    if (!DASHBOARD_DATA_TABS.includes(activeTab)) return undefined;
    let cancelled = false;
    const key = loadKey;

    const run = async () => {
      switch (activeTab) {
        case 'overview': {
          const [userStats, sysStats] = await Promise.all([api.getUserStats(token), api.getSystemStats(token)]);
          return () => { setStats(userStats); setSystemStats(sysStats); };
        }
        case 'users': {
          const data = await api.getUsers(token, {
            search: userFilters.search,
            subscription_type: userFilters.subscription_type,
            skip: 0,
            limit: USERS_PAGE_SIZE,
          });
          const items = Array.isArray(data) ? data : [];
          return () => setUsersState({ key, items, hasMore: items.length === USERS_PAGE_SIZE });
        }
        case 'broadcast': {
          const data = await api.getBroadcastStats(token);
          return () => setBroadcastStats(data);
        }
        case 'admins': {
          if (!isSuper) return null;
          const data = await api.getAdmins(token);
          return () => setAdmins(Array.isArray(data) ? data : []);
        }
        case 'logs': {
          if (!isSuper) return null;
          const data = await api.getLogs(token, { limit: 50 });
          return () => setLogs(Array.isArray(data) ? data : []);
        }
        default:
          return null;
      }
    };

    run()
      .then((apply) => {
        if (cancelled) return;
        if (apply) apply();
        setTabStatus({ key, error: null });
      })
      .catch((error) => {
        if (cancelled) return;
        console.error('Error loading data:', error);
        setTabStatus({ key, error: errorMessage(error, 'Failed to load data') });
      });

    return () => { cancelled = true; };
  }, [token, activeTab, userFilters.search, userFilters.subscription_type, isSuper, loadKey]);

  const reload = () => setRefreshKey((k) => k + 1);

  const handleSearch = () => {
    setUserFilters({ search: searchQuery.trim(), subscription_type: subscriptionFilter });
    reload(); // also re-fetch when the filters didn't change
  };

  const handleResetUsers = () => {
    // All updates batch into one render → exactly one fetch with cleared filters.
    setSearchQuery('');
    setSubscriptionFilter('');
    setUserFilters({ search: '', subscription_type: '' });
    reload();
  };

  const loadMoreUsers = async () => {
    const keyAtStart = usersState.key;
    setLoadingMoreUsers(true);
    try {
      const data = await api.getUsers(token, {
        search: userFilters.search,
        subscription_type: userFilters.subscription_type,
        skip: usersState.items.length,
        limit: USERS_PAGE_SIZE,
      });
      const items = Array.isArray(data) ? data : [];
      setUsersState((prev) => {
        if (prev.key !== keyAtStart) return prev; // filters changed meanwhile
        const seen = new Set(prev.items.map((u) => u.id));
        return { ...prev, items: [...prev.items, ...items.filter((u) => !seen.has(u.id))], hasMore: items.length === USERS_PAGE_SIZE };
      });
    } catch (error) {
      alert(errorMessage(error, 'Failed to load more users'));
    } finally {
      setLoadingMoreUsers(false);
    }
  };

  const handleNavClick = (tabId) => { setActiveTab(tabId); setIsSidebarOpen(false); };

  const handleCreateAdmin = async () => {
    if (!createAdminForm.name.trim() || !createAdminForm.email.trim() || !createAdminForm.password.trim()) { alert('Please fill in all fields'); return; }
    if (createAdminForm.password.length < 8) { alert('Password must be at least 8 characters'); return; }
    setCreateAdminLoading(true);
    try {
      await api.createAdmin(token, createAdminForm);
      alert('Admin created successfully!');
      setCreateAdminForm({ name: '', email: '', password: '', role: 'admin' });
      setShowCreateAdmin(false);
      reload();
    } catch (error) { alert('Failed to create admin: ' + errorMessage(error)); }
    finally { setCreateAdminLoading(false); }
  };

  const handleDeleteAdmin = async (adminId) => {
    if (!window.confirm('Delete this admin?')) return;
    try { await api.deleteAdmin(token, adminId); alert('Admin deleted'); reload(); }
    catch (error) { alert('Failed: ' + errorMessage(error)); }
  };

  const handleSendBroadcast = async () => {
    if (!broadcastForm.title.trim() || !broadcastForm.message.trim()) { alert('Fill in title and message'); return; }
    if (!['all', 'free', 'premium'].includes(broadcastForm.target_users)) { alert('Invalid target audience'); return; }
    if (!window.confirm(`Send to ${broadcastForm.target_users} users?`)) return;
    setBroadcastLoading(true);
    try {
      const result = await api.sendBroadcastNotification(token, {
        title: broadcastForm.title.trim(),
        message: broadcastForm.message.trim(),
        target_users: broadcastForm.target_users,
        notification_type: broadcastForm.notification_type || EMPTY_BROADCAST_FORM.notification_type,
      });
      alert(`Sent!\n\nTotal: ${result.total_users}\nNotifications: ${result.notifications_sent}\nPush: ${result.fcm_sent} sent, ${result.fcm_failed} failed`);
      setBroadcastForm(EMPTY_BROADCAST_FORM);
      reload();
    } catch (error) { alert('Failed: ' + errorMessage(error)); }
    finally { setBroadcastLoading(false); }
  };

  const handleUpdateSubscription = async (userId, subscriptionType, expiresAt) => {
    try {
      await api.updateUserSubscription(token, userId, { subscription_type: subscriptionType, subscription_expires_at: expiresAt });
      alert('Subscription updated!'); reload(); setSelectedUser(null);
    } catch (error) { alert(errorMessage(error, 'Failed to update subscription')); }
  };

  const handleCustomExpiry = (userId) => {
    const di = document.getElementById(`expire-date-${userId}`);
    if (!di || !di.value) { alert('Please select an expiry date'); return; }
    // Parse YYYY-MM-DD as a LOCAL date, end of that day.
    const d = parseLocalDate(di.value, true);
    if (!d) { alert('Invalid date'); return; }
    if (d.getTime() <= Date.now()) { alert('Expiry date must be in the future'); return; }
    handleUpdateSubscription(userId, 'premium', d.toISOString());
  };

  const handleExtend = (user, days) => {
    // Extend from whichever is later: now, or the current expiry.
    const now = Date.now();
    const cur = user.subscription_expires_at ? new Date(user.subscription_expires_at).getTime() : NaN;
    const base = Number.isFinite(cur) && cur > now ? cur : now;
    handleUpdateSubscription(user.id, 'premium', new Date(base + days * 24 * 60 * 60 * 1000).toISOString());
  };

  const handleDeleteUser = async (userId) => {
    if (!window.confirm('Delete this user? Cannot be undone.')) return;
    try { await api.deleteUser(token, userId); alert('User deleted'); reload(); setSelectedUser(null); }
    catch (error) { alert(errorMessage(error, 'Failed to delete user')); }
  };

  const navItems = [
    { id: 'overview', icon: BarChart3, label: 'Overview' },
    { id: 'users', icon: Users, label: 'Users' },
    { id: 'broadcast', icon: Send, label: 'Broadcast' },
    { id: 'app-versions', icon: Smartphone, label: 'App Versions' },
    { id: 'ai-usage', icon: Zap, label: 'AI Usage & Costs' },
    { id: 'feedback', icon: MessageSquare, label: 'Feedback' },
    { id: 'settings', icon: Settings, label: 'Settings' },
    ...(isSuper ? [
      { id: 'admins', icon: Shield, label: 'Admins' },
      { id: 'logs', icon: Activity, label: 'Activity Logs' },
    ] : []),
  ];

  const users = usersState.items;
  const usersLoading = activeTab === 'users' && loading;
  const todayInput = toLocalDateInput(new Date());
  const adminName = admin.name || admin.email || 'Admin';
  const roleLabel = String(admin.role || '').replace('_', ' ');

  return (
    <div className="min-h-screen bg-[#0A0F1E] font-sans text-slate-200">

      {/* Mobile Header */}
      <div className="md:hidden flex items-center justify-between p-4 bg-slate-900 border-b border-white/5 sticky top-0 z-30">
        <div className="flex items-center gap-3">
          <div className="w-8 h-8 bg-gradient-to-br from-blue-500 to-violet-500 rounded-lg flex items-center justify-center shadow-lg shadow-blue-500/20">
            <Shield size={18} className="text-white" strokeWidth={2.5} />
          </div>
          <div className="text-base font-bold text-slate-100">Flow Finance</div>
        </div>
        <button onClick={() => setIsSidebarOpen(true)} className="p-2 text-slate-400 hover:text-white bg-slate-800/50 rounded-lg border border-white/5">
          <Menu size={24} />
        </button>
      </div>

      {isSidebarOpen && <div className="fixed inset-0 bg-black/60 z-40 md:hidden backdrop-blur-sm animate-fadeIn" onClick={() => setIsSidebarOpen(false)} />}

      {/* Sidebar */}
      <div className={`fixed left-0 top-0 bottom-0 w-[280px] bg-gradient-to-b from-slate-900 to-slate-800 border-r border-white/5 p-8 flex flex-col z-50 transition-transform duration-300 ease-in-out ${isSidebarOpen ? 'translate-x-0' : '-translate-x-full'} md:translate-x-0`}>
        <button onClick={() => setIsSidebarOpen(false)} className="absolute top-4 right-4 p-2 text-slate-400 hover:text-white md:hidden"><X size={20} /></button>

        <div className="flex items-center gap-3 mb-10 pb-6 border-b border-white/10">
          <div className="w-12 h-12 bg-gradient-to-br from-blue-500 to-violet-500 rounded-xl flex items-center justify-center shadow-lg shadow-blue-500/20">
            <Shield size={24} className="text-white" strokeWidth={2.5} />
          </div>
          <div>
            <div className="text-lg font-bold text-slate-100">Flow Finance</div>
            <div className="text-xs text-slate-400 font-medium">Admin Portal</div>
          </div>
        </div>

        <nav className="flex-1 space-y-1.5 overflow-y-auto">
          {navItems.map(tab => (
            <button key={tab.id} onClick={() => handleNavClick(tab.id)}
              className={`w-full p-3.5 flex items-center gap-3 rounded-xl text-[15px] font-semibold transition-all duration-200 text-left ${
                activeTab === tab.id
                  ? 'bg-blue-500/15 border border-blue-500/30 text-blue-400'
                  : 'bg-transparent border border-transparent text-slate-400 hover:bg-blue-500/10'
              }`}>
              <tab.icon size={20} />
              {tab.label}
            </button>
          ))}
        </nav>

        <div className="mt-4 pt-4 border-t border-white/5">
          <div className="p-4 bg-slate-800/50 rounded-xl border border-white/5">
            <div className="flex items-center gap-3 mb-3">
              <div className="w-10 h-10 bg-gradient-to-br from-violet-500 to-pink-500 rounded-lg flex items-center justify-center text-white font-bold shadow-sm">
                {adminName.charAt(0).toUpperCase()}
              </div>
              <div className="flex-1 min-w-0">
                <div className="text-sm font-semibold text-slate-100 mb-0.5 truncate">{adminName}</div>
                <div className="text-xs text-slate-400 capitalize flex items-center gap-1">
                  {isSuper && <Crown size={12} className="text-amber-500" />}
                  {roleLabel}
                  {!writable && <span className="normal-case text-slate-500">· read-only</span>}
                </div>
              </div>
            </div>
            <button onClick={onLogout} className="w-full p-2.5 bg-red-500/10 border border-red-500/30 rounded-lg text-red-400 text-sm font-semibold flex items-center justify-center gap-2 hover:bg-red-500/20 transition-colors">
              <LogOut size={16} /> Sign Out
            </button>
          </div>
        </div>
      </div>

      {/* Main Content */}
      <div className="md:ml-[280px] p-4 md:p-10 transition-all duration-300">
        <ErrorBoundary resetKey={activeTab}>

        {tabError && (
          <div className="mb-6 p-4 bg-red-500/5 border border-red-500/20 rounded-2xl flex flex-col md:flex-row md:items-center gap-3">
            <AlertCircle size={20} className="text-red-400 flex-shrink-0" />
            <div className="flex-1 text-sm text-red-300">{tabError}</div>
            <button onClick={reload} className="px-4 py-2 bg-red-500/15 border border-red-500/30 rounded-lg text-red-300 text-sm font-semibold hover:bg-red-500/25 transition-colors flex items-center gap-2 self-start md:self-auto">
              <RefreshCw size={14} /> Retry
            </button>
          </div>
        )}

        {/* Overview Tab */}
        {activeTab === 'overview' && loading && !(stats && systemStats) && (
          <div className="p-20 flex items-center justify-center"><RefreshCw size={32} className="animate-spin text-blue-500" /></div>
        )}
        {activeTab === 'overview' && stats && systemStats && (
          <div className="animate-slideIn">
            <div className="mb-8 mt-2 md:mt-0">
              <h1 className="text-3xl md:text-4xl font-bold mb-2 bg-gradient-to-br from-slate-100 to-slate-400 bg-clip-text text-transparent">Dashboard Overview</h1>
              <p className="text-slate-400 font-medium text-sm md:text-base">Welcome back, {adminName}. Here's what's happening today.</p>
            </div>
            <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4 md:gap-6 mb-8 md:mb-10">
              {[
                { label: 'Total Users', value: stats.total_users, icon: Users, color: 'text-blue-500', bg: 'bg-blue-500/10' },
                { label: 'Premium Users', value: stats.premium_users, icon: Crown, color: 'text-amber-500', bg: 'bg-amber-500/10' },
                { label: 'Free Users', value: stats.free_users, icon: Users, color: 'text-emerald-500', bg: 'bg-emerald-500/10' },
                { label: 'Active (7 days)', value: stats.active_users_last_7_days, icon: Activity, color: 'text-violet-500', bg: 'bg-violet-500/10' },
                { label: 'New Users (30d)', value: stats.new_users_last_30_days, icon: TrendingUp, color: 'text-pink-500', bg: 'bg-pink-500/10' },
                { label: 'Total Transactions', value: stats.total_transactions, icon: DollarSign, color: 'text-cyan-500', bg: 'bg-cyan-500/10' },
                { label: 'Total Goals', value: stats.total_goals, icon: Target, color: 'text-orange-500', bg: 'bg-orange-500/10' },
                { label: 'Active Today', value: systemStats.active_users_today, icon: Zap, color: 'text-yellow-500', bg: 'bg-yellow-500/10' },
              ].map((stat, index) => (
                <div key={stat.label} className="bg-gradient-to-br from-slate-800/60 to-slate-700/30 p-5 md:p-7 rounded-2xl border border-white/5 shadow-xl hover:-translate-y-1 hover:shadow-2xl transition-all duration-300 animate-slideIn" style={{ animationDelay: `${index * 100}ms` }}>
                  <div className="flex justify-between items-start mb-4 md:mb-5">
                    <div className={`w-12 h-12 md:w-14 md:h-14 ${stat.bg} rounded-2xl flex items-center justify-center`}>
                      <stat.icon size={24} className={`md:w-7 md:h-7 ${stat.color}`} strokeWidth={2} />
                    </div>
                  </div>
                  <div className="text-3xl md:text-4xl font-bold text-slate-100 mb-2">{fmtNum(stat.value)}</div>
                  <div className="text-sm text-slate-400 font-medium">{stat.label}</div>
                </div>
              ))}
            </div>
            <div className="bg-gradient-to-br from-slate-800/60 to-slate-700/30 p-6 md:p-8 rounded-2xl border border-white/5">
              <h2 className="text-xl md:text-2xl font-bold mb-6 text-slate-100">Recent Activity</h2>
              <div className="grid grid-cols-2 md:grid-cols-4 gap-6">
                {[
                  { label: 'New Today', value: systemStats.new_users_today, color: 'text-blue-500' },
                  { label: 'New This Week', value: systemStats.new_users_this_week, color: 'text-violet-500' },
                  { label: 'New This Month', value: systemStats.new_users_this_month, color: 'text-pink-500' },
                  { label: 'Active This Week', value: systemStats.active_users_this_week, color: 'text-emerald-500' },
                ].map((item) => (
                  <div key={item.label}>
                    <div className="text-xs md:text-sm text-slate-400 mb-2">{item.label}</div>
                    <div className={`text-2xl md:text-3xl font-bold ${item.color}`}>{fmtNum(item.value)}</div>
                  </div>
                ))}
              </div>
            </div>
          </div>
        )}

        {/* App Versions Tab */}
        {activeTab === 'app-versions' && (
          <AppVersionManagement token={token} adminRole={admin.role} />
        )}

        {/* AI Usage Tab */}
        {activeTab === 'ai-usage' && <AIUsageStats token={token} />}

        {/* Feedback Tab */}
        {activeTab === 'feedback' && <FeedbackManagement token={token} adminRole={admin.role} />}

        {/* Users Tab */}
        {activeTab === 'users' && (
          <div className="animate-slideIn">
            <div className="mb-6 md:mb-8 mt-2 md:mt-0">
              <h1 className="text-3xl md:text-4xl font-bold mb-2 bg-gradient-to-br from-slate-100 to-slate-400 bg-clip-text text-transparent">User Management</h1>
              <p className="text-slate-400 font-medium text-sm md:text-base">
                {writable ? 'Manage user accounts and subscriptions' : 'View user accounts and subscriptions (read-only)'}
              </p>
            </div>
            <div className="bg-gradient-to-br from-slate-800/60 to-slate-700/30 p-4 md:p-6 rounded-2xl border border-white/5 mb-6 flex flex-col md:flex-row gap-4">
              <div className="flex-1">
                <input type="text" placeholder="Search by name or email..." value={searchQuery}
                  onChange={(e) => setSearchQuery(e.target.value)} onKeyDown={(e) => { if (e.key === 'Enter') handleSearch(); }}
                  className="w-full px-4 py-3.5 bg-slate-900/50 border border-slate-600/20 rounded-xl text-slate-100 text-[15px] outline-none focus:border-blue-500/50" />
              </div>
              <div className="flex gap-4">
                <select value={subscriptionFilter} onChange={(e) => setSubscriptionFilter(e.target.value)}
                  className="flex-1 md:flex-none px-4 py-3.5 bg-slate-900/50 border border-slate-600/20 rounded-xl text-slate-100 text-[15px] outline-none cursor-pointer focus:border-blue-500/50">
                  <option value="">All Subscriptions</option>
                  <option value="free">Free</option>
                  <option value="premium">Premium</option>
                </select>
                <button onClick={handleSearch} className="px-6 py-3.5 bg-gradient-to-br from-blue-500 to-violet-500 rounded-xl text-white text-[15px] font-semibold flex items-center gap-2 hover:-translate-y-0.5 transition-transform">
                  <Search size={18} /><span className="hidden md:inline">Search</span>
                </button>
                <button onClick={handleResetUsers} title="Clear filters and reload"
                  className="px-4 py-3.5 bg-slate-500/20 border border-slate-400/20 rounded-xl text-slate-400 text-[15px] font-semibold flex items-center gap-2 hover:bg-slate-500/30 transition-colors">
                  <RefreshCw size={18} className={usersLoading ? 'animate-spin' : ''} />
                </button>
              </div>
            </div>
            <div className="bg-gradient-to-br from-slate-800/60 to-slate-700/30 rounded-2xl border border-white/5 overflow-hidden">
              {usersLoading ? (
                <div className="p-16 flex items-center justify-center"><RefreshCw size={28} className="animate-spin text-blue-500" /></div>
              ) : (
                <>
                  <div className="overflow-x-auto">
                    <table className="w-full border-collapse min-w-[800px]">
                      <thead>
                        <tr className="bg-slate-900/50 border-b border-white/5">
                          {['User', 'Subscription', 'Activity', 'Joined', 'Actions'].map((header, i) => (
                            <th key={header} className={`px-6 py-4 text-left text-slate-400 text-xs font-semibold tracking-wider uppercase ${i === 4 ? 'text-center' : ''}`}>{header}</th>
                          ))}
                        </tr>
                      </thead>
                      <tbody>
                        {users.map((user, index) => (
                          <tr key={user.id} className="border-b border-white/5 hover:bg-slate-800/50 transition-all duration-200 animate-slideIn" style={{ animationDelay: `${Math.min(index, 20) * 50}ms` }}>
                            <td className="px-6 py-5">
                              <div className="flex items-center gap-3">
                                <div className="w-11 h-11 bg-gradient-to-br from-blue-500 to-violet-500 rounded-xl flex items-center justify-center text-white font-bold shadow-md">{(user.name || '?').charAt(0).toUpperCase()}</div>
                                <div>
                                  <div className="text-[15px] font-semibold text-slate-100 mb-1">{user.name}</div>
                                  <div className="text-xs text-slate-400">{user.email}</div>
                                </div>
                              </div>
                            </td>
                            <td className="px-6 py-5">
                              <div className={`inline-flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-[13px] font-semibold border ${user.subscription_type === 'premium' ? 'bg-amber-500/15 border-amber-500/30 text-amber-500' : 'bg-slate-500/15 border-slate-500/30 text-slate-400'}`}>
                                {user.subscription_type === 'premium' && <Crown size={14} />}
                                {String(user.subscription_type || 'free').toUpperCase()}
                              </div>
                            </td>
                            <td className="px-6 py-5">
                              <div className="text-sm text-slate-300 mb-1">{fmtNum(user.total_transactions)} transactions</div>
                              <div className="text-xs text-slate-500">{fmtNum(user.total_goals)} goals</div>
                            </td>
                            <td className="px-6 py-5 text-sm text-slate-400">
                              {user.created_at ? new Date(user.created_at).toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' }) : ''}
                            </td>
                            <td className="px-6 py-5 text-center">
                              <button onClick={() => setSelectedUser(user)} className="inline-flex items-center gap-1.5 px-4 py-2 bg-blue-500/15 border border-blue-500/30 rounded-lg text-blue-400 text-[13px] font-semibold hover:bg-blue-500/25 transition-colors">
                                <Eye size={14} /> View
                              </button>
                            </td>
                          </tr>
                        ))}
                      </tbody>
                    </table>
                  </div>
                  {users.length === 0 && !tabError && <div className="p-16 text-center text-slate-400">No users found</div>}
                  {usersState.hasMore && (
                    <div className="p-4 border-t border-white/5 flex justify-center">
                      <button onClick={loadMoreUsers} disabled={loadingMoreUsers}
                        className="px-5 py-2.5 bg-slate-700/50 border border-white/10 rounded-xl text-slate-300 text-sm font-semibold hover:bg-slate-700 transition-colors flex items-center gap-2 disabled:opacity-50">
                        {loadingMoreUsers && <RefreshCw size={14} className="animate-spin" />}
                        Load more ({users.length} shown)
                      </button>
                    </div>
                  )}
                </>
              )}
            </div>
          </div>
        )}

        {/* Admins Tab */}
        {activeTab === 'admins' && isSuper && (
          <div className="animate-slideIn">
            <div className="mb-6 md:mb-8 mt-2 md:mt-0 flex flex-col md:flex-row md:items-center justify-between gap-4">
              <div>
                <h1 className="text-3xl md:text-4xl font-bold mb-2 bg-gradient-to-br from-slate-100 to-slate-400 bg-clip-text text-transparent">Admin Management</h1>
                <p className="text-slate-400 font-medium text-sm md:text-base">Manage administrator accounts and permissions</p>
              </div>
              <button onClick={() => setShowCreateAdmin(true)} className="w-full md:w-auto px-6 py-3.5 bg-gradient-to-br from-blue-500 to-violet-500 rounded-xl text-white text-[15px] font-semibold flex items-center justify-center gap-2 hover:-translate-y-0.5 transition-transform shadow-lg shadow-blue-500/30">
                <Shield size={18} /> Create New Admin
              </button>
            </div>
            <div className="bg-gradient-to-br from-slate-800/60 to-slate-700/30 rounded-2xl border border-white/5 overflow-hidden">
              <div className="overflow-x-auto">
                <table className="w-full border-collapse min-w-[900px]">
                  <thead>
                    <tr className="bg-slate-900/50 border-b border-white/5">
                      {['Admin', 'Email', 'Role', 'Last Login', 'Created', 'Actions'].map((header, i) => (
                        <th key={header} className={`px-6 py-4 text-left text-slate-400 text-xs font-semibold tracking-wider uppercase ${i === 5 ? 'text-center' : ''}`}>{header}</th>
                      ))}
                    </tr>
                  </thead>
                  <tbody>
                    {admins.map((adm, index) => (
                      <tr key={adm.id} className="border-b border-white/5 hover:bg-slate-800/50 transition-colors animate-slideIn" style={{ animationDelay: `${index * 50}ms` }}>
                        <td className="px-6 py-5">
                          <div className="flex items-center gap-3">
                            <div className="w-11 h-11 bg-gradient-to-br from-violet-500 to-pink-500 rounded-xl flex items-center justify-center text-white font-bold shadow-md">{(adm.name || '?').charAt(0).toUpperCase()}</div>
                            <div className="text-[15px] font-semibold text-slate-100 flex items-center gap-2">
                              {adm.name}
                              {adm.role === 'super_admin' && <Crown size={16} className="text-amber-500" />}
                            </div>
                          </div>
                        </td>
                        <td className="px-6 py-5 text-sm text-slate-300">{adm.email}</td>
                        <td className="px-6 py-5">
                          <div className={`inline-flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-[13px] font-semibold border capitalize ${adm.role === 'super_admin' ? 'bg-amber-500/15 border-amber-500/30 text-amber-500' : adm.role === 'admin' ? 'bg-violet-500/15 border-violet-500/30 text-violet-400' : 'bg-blue-500/15 border-blue-500/30 text-blue-400'}`}>
                            {String(adm.role || '').replace('_', ' ')}
                          </div>
                        </td>
                        <td className="px-6 py-5 text-sm text-slate-400">
                          {adm.last_login ? new Date(adm.last_login).toLocaleDateString('en-US', { month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit' }) : 'Never'}
                        </td>
                        <td className="px-6 py-5 text-sm text-slate-400">
                          {adm.created_at ? new Date(adm.created_at).toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' }) : ''}
                        </td>
                        <td className="px-6 py-5 text-center">
                          {adm.id !== admin.id ? (
                            <button onClick={() => handleDeleteAdmin(adm.id)} className="inline-flex items-center gap-1.5 px-4 py-2 bg-red-500/15 border border-red-500/30 rounded-lg text-red-400 text-[13px] font-semibold hover:bg-red-500/25 transition-colors">
                              <Trash2 size={14} /> Delete
                            </button>
                          ) : (
                            <span className="text-[13px] text-slate-500 font-medium">Current User</span>
                          )}
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
              {admins.length === 0 && !loading && <div className="p-16 text-center text-slate-400">No admins found</div>}
            </div>
          </div>
        )}

        {/* Settings Tab */}
        {activeTab === 'settings' && (
          <ProfileSettings token={token} admin={admin} onUpdateAdmin={onUpdateAdmin} onTokenRotated={onTokenRotated} onLogout={onLogout} />
        )}

        {/* Logs Tab */}
        {activeTab === 'logs' && isSuper && (
          <div className="animate-slideIn">
            <div className="mb-6 md:mb-8 mt-2 md:mt-0">
              <h1 className="text-3xl md:text-4xl font-bold mb-2 bg-gradient-to-br from-slate-100 to-slate-400 bg-clip-text text-transparent">Activity Logs</h1>
              <p className="text-slate-400 font-medium text-sm md:text-base">Audit trail of all admin actions</p>
            </div>
            <div className="bg-gradient-to-br from-slate-800/60 to-slate-700/30 rounded-2xl border border-white/5 p-4 md:p-8">
              {logs.map((log, index) => (
                <div key={log.id} className="p-4 md:p-5 bg-slate-900/40 rounded-xl mb-3 border border-white/5 animate-slideIn" style={{ animationDelay: `${Math.min(index, 20) * 50}ms` }}>
                  <div className="flex flex-col md:flex-row md:justify-between md:items-start mb-3 gap-2">
                    <div className="flex items-center gap-3">
                      <div className="w-9 h-9 bg-blue-500/15 rounded-lg flex items-center justify-center flex-shrink-0"><Activity size={18} className="text-blue-500" /></div>
                      <div>
                        <div className="text-[15px] font-semibold text-slate-100 mb-1">{String(log.action || '').replace(/_/g, ' ').replace(/\b\w/g, l => l.toUpperCase())}</div>
                        <div className="text-[13px] text-slate-500">by {log.admin_email}</div>
                      </div>
                    </div>
                    <div className="text-[13px] text-slate-500 pl-12 md:pl-0">{log.timestamp ? new Date(log.timestamp).toLocaleString() : ''}</div>
                  </div>
                  {log.details && <div className="p-3 bg-slate-800/50 rounded-lg text-[13px] text-slate-400 font-mono ml-0 md:ml-12">{log.details}</div>}
                </div>
              ))}
              {logs.length === 0 && !loading && <div className="p-16 text-center text-slate-400">No activity logs found</div>}
            </div>
          </div>
        )}

        {/* Broadcast Tab */}
        {activeTab === 'broadcast' && (
          <div className="animate-slideIn">
            <div className="mb-6 md:mb-8 mt-2 md:mt-0">
              <h1 className="text-3xl md:text-4xl font-bold mb-2 bg-gradient-to-br from-slate-100 to-slate-400 bg-clip-text text-transparent">Broadcast Notifications</h1>
              <p className="text-slate-400 font-medium text-sm md:text-base">Send notifications to all users or specific groups</p>
            </div>
            {broadcastStats && (
              <div className="grid grid-cols-1 md:grid-cols-3 gap-4 md:gap-6 mb-8">
                {[
                  { label: 'Total Users', value: broadcastStats.total_users, sublabel: `${fmtNum(broadcastStats.users_with_push_enabled)} with push`, color: 'text-blue-500', bg: 'bg-blue-500/10' },
                  { label: 'Free Users', value: broadcastStats.free_users, sublabel: `${fmtNum(broadcastStats.free_with_push)} with push`, color: 'text-emerald-500', bg: 'bg-emerald-500/10' },
                  { label: 'Premium Users', value: broadcastStats.premium_users, sublabel: `${fmtNum(broadcastStats.premium_with_push)} with push`, color: 'text-amber-500', bg: 'bg-amber-500/10' },
                ].map((stat) => (
                  <div key={stat.label} className="bg-gradient-to-br from-slate-800/60 to-slate-700/30 p-5 md:p-7 rounded-2xl border border-white/5 shadow-xl">
                    <div className={`w-12 h-12 md:w-14 md:h-14 ${stat.bg} rounded-2xl flex items-center justify-center mb-5`}>
                      <Users size={24} className={`md:w-7 md:h-7 ${stat.color}`} strokeWidth={2} />
                    </div>
                    <div className="text-3xl md:text-4xl font-bold text-slate-100 mb-2">{fmtNum(stat.value)}</div>
                    <div className="text-sm text-slate-400 font-medium mb-1">{stat.label}</div>
                    <div className="text-xs text-slate-500">{stat.sublabel}</div>
                  </div>
                ))}
              </div>
            )}
            {!writable ? (
              <div className="bg-slate-500/10 border border-slate-500/30 rounded-2xl p-5 flex items-start gap-3">
                <Lock size={20} className="text-slate-400 mt-0.5 flex-shrink-0" />
                <div className="text-sm text-slate-300">Sending broadcast notifications requires the Admin or Super Admin role. Moderators have read-only access.</div>
              </div>
            ) : (
            <div className="bg-gradient-to-br from-slate-800/60 to-slate-700/30 rounded-2xl border border-white/5 p-6 md:p-8">
              <h2 className="text-xl md:text-2xl font-bold mb-6 text-slate-100">Send Broadcast Notification</h2>
              <div className="space-y-6">
                <div>
                  <label className="block text-slate-300 text-sm font-semibold mb-3">Target Users</label>
                  <div className="grid grid-cols-1 md:grid-cols-3 gap-3 md:gap-4">
                    {[
                      { value: 'all', label: 'All Users', count: broadcastStats?.total_users },
                      { value: 'free', label: 'Free Users', count: broadcastStats?.free_users },
                      { value: 'premium', label: 'Premium Users', count: broadcastStats?.premium_users },
                    ].map(option => (
                      <button key={option.value} onClick={() => setBroadcastForm({...broadcastForm, target_users: option.value})}
                        className={`p-4 rounded-xl border-2 transition-all ${broadcastForm.target_users === option.value ? 'border-blue-500 bg-blue-500/10 text-blue-400' : 'border-slate-600/30 bg-slate-800/50 text-slate-400 hover:border-slate-500/50'}`}>
                        <div className="text-lg font-bold mb-1">{option.label}</div>
                        <div className="text-sm opacity-70">{fmtNum(option.count)} users</div>
                      </button>
                    ))}
                  </div>
                </div>
                <div>
                  <label className="block text-slate-300 text-sm font-semibold mb-3">Notification Type</label>
                  <select value={broadcastForm.notification_type} onChange={(e) => setBroadcastForm({...broadcastForm, notification_type: e.target.value})}
                    className="w-full px-4 py-3.5 bg-slate-800/50 border border-slate-600/30 rounded-xl text-slate-100 text-[15px] outline-none cursor-pointer focus:border-blue-500">
                    <option value="system_broadcast">System Broadcast</option>
                    <option value="admin_announcement">Admin Announcement</option>
                  </select>
                </div>
                <div>
                  <label className="block text-slate-300 text-sm font-semibold mb-3">Title</label>
                  <input type="text" value={broadcastForm.title} onChange={(e) => setBroadcastForm({...broadcastForm, title: e.target.value})}
                    placeholder="Enter notification title..." maxLength={100}
                    className="w-full px-4 py-3.5 bg-slate-800/50 border border-slate-600/30 rounded-xl text-slate-100 text-[15px] outline-none transition-all focus:border-blue-500 focus:bg-slate-800/80" />
                  <div className="text-xs text-slate-500 mt-2">{broadcastForm.title.length}/100 characters</div>
                </div>
                <div>
                  <label className="block text-slate-300 text-sm font-semibold mb-3">Message</label>
                  <textarea value={broadcastForm.message} onChange={(e) => setBroadcastForm({...broadcastForm, message: e.target.value})}
                    placeholder="Enter notification message..." rows={6} maxLength={500}
                    className="w-full px-4 py-3.5 bg-slate-800/50 border border-slate-600/30 rounded-xl text-slate-100 text-[15px] outline-none transition-all focus:border-blue-500 focus:bg-slate-800/80 resize-none" />
                  <div className="text-xs text-slate-500 mt-2">{broadcastForm.message.length}/500 characters</div>
                </div>
                <button onClick={handleSendBroadcast} disabled={broadcastLoading || !broadcastForm.title.trim() || !broadcastForm.message.trim()}
                  className={`w-full py-4 rounded-xl text-white text-base font-semibold transition-all duration-300 shadow-lg flex items-center justify-center gap-3 ${broadcastLoading || !broadcastForm.title.trim() || !broadcastForm.message.trim() ? 'bg-slate-600 cursor-not-allowed' : 'bg-gradient-to-br from-blue-500 to-violet-500 hover:-translate-y-0.5 hover:shadow-blue-500/40 shadow-blue-500/30'}`}>
                  {broadcastLoading ? <><RefreshCw size={20} className="animate-spin" />Sending...</> : <><Send size={20} />Send Broadcast Notification</>}
                </button>
                <div className="bg-amber-500/10 border border-amber-500/30 rounded-xl p-4 flex items-start gap-3">
                  <AlertCircle size={20} className="text-amber-500 mt-0.5 flex-shrink-0" />
                  <div className="text-sm text-amber-300">
                    <strong>Note:</strong> This will send notifications to {broadcastForm.target_users === 'all' ? 'all users' : broadcastForm.target_users === 'free' ? 'all free users' : 'all premium users'}.
                    Users who have disabled this notification type will not receive it.
                  </div>
                </div>
              </div>
            </div>
            )}
          </div>
        )}
        </ErrorBoundary>
      </div>

      {/* User Detail Modal */}
      {selectedUser && (
        <div className="fixed inset-0 bg-black/70 backdrop-blur-sm flex items-center justify-center z-50 animate-fadeIn p-4" onClick={() => setSelectedUser(null)}>
          <div className="bg-gradient-to-br from-slate-800 to-slate-700 rounded-3xl p-6 md:p-10 max-w-xl w-full max-h-[90vh] overflow-y-auto border border-white/10 shadow-2xl animate-slideIn" onClick={(e) => e.stopPropagation()}>
            <div className="flex items-center gap-4 mb-8">
              <div className="w-16 h-16 bg-gradient-to-br from-blue-500 to-violet-500 rounded-2xl flex items-center justify-center text-2xl font-bold text-white shadow-lg flex-shrink-0">{(selectedUser.name || '?').charAt(0).toUpperCase()}</div>
              <div className="flex-1 min-w-0">
                <h2 className="text-2xl font-bold text-slate-100 mb-1 truncate">{selectedUser.name}</h2>
                <div className="text-sm text-slate-400 truncate">{selectedUser.email}</div>
              </div>
            </div>

            <div className="mb-8">
              <h3 className="text-xs font-bold text-slate-400 mb-4 uppercase tracking-wider">Subscription{writable ? ' Management' : ''}</h3>
              {selectedUser.subscription_type === 'free' && (
                <>
                  <div className="p-4 bg-slate-500/10 border border-slate-500/30 rounded-xl mb-4">
                    <div className="flex items-center gap-2"><User size={18} className="text-slate-500" /><span className="text-sm font-semibold text-slate-400">Free User</span></div>
                  </div>
                  {writable && (
                    <>
                      <div className="grid grid-cols-2 gap-2 mb-3">
                        {[{ label: '1 Month', days: 30 }, { label: '3 Months', days: 90 }, { label: '6 Months', days: 180 }, { label: '1 Year', days: 365 }].map((preset) => (
                          <button key={preset.days} onClick={() => handleUpdateSubscription(selectedUser.id, 'premium', new Date(Date.now() + preset.days*24*60*60*1000).toISOString())}
                            className="p-3 bg-gradient-to-br from-amber-500/20 to-orange-600/20 border border-amber-500/30 rounded-xl text-amber-400 text-sm font-semibold hover:from-amber-500/30 hover:to-orange-600/30 transition-all flex items-center justify-center gap-2">
                            <Crown size={14} />{preset.label}
                          </button>
                        ))}
                      </div>
                      <div className="p-4 bg-slate-900/40 rounded-xl border border-white/5 space-y-3">
                        <label className="block text-slate-300 text-sm font-semibold">Or Set Custom Premium Period</label>
                        <input type="date" id={`expire-date-${selectedUser.id}`} min={todayInput}
                          className="w-full px-4 py-3 bg-slate-800/50 border border-slate-600/30 rounded-xl text-slate-100 text-sm outline-none focus:border-blue-500 focus:bg-slate-800/80 transition-all" />
                        <button onClick={() => handleCustomExpiry(selectedUser.id)} className="w-full p-3 bg-blue-500/15 border border-blue-500/30 rounded-xl text-blue-400 text-sm font-semibold hover:bg-blue-500/25 transition-colors flex items-center justify-center gap-2">
                          <Crown size={16} />Upgrade to Premium
                        </button>
                      </div>
                    </>
                  )}
                </>
              )}
              {selectedUser.subscription_type === 'premium' && (
                <>
                  <div className="p-4 bg-amber-500/10 border border-amber-500/30 rounded-xl mb-4">
                    <div className="flex items-center justify-between mb-2">
                      <div className="flex items-center gap-2"><Crown size={18} className="text-amber-500" /><span className="text-sm font-semibold text-amber-400">Premium Active</span></div>
                      {selectedUser.subscription_expires_at && <div className="text-xs text-amber-400/80">Expires: {new Date(selectedUser.subscription_expires_at).toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' })}</div>}
                    </div>
                    {selectedUser.subscription_expires_at && <div className="text-xs text-amber-400/70">{Math.max(0, Math.ceil((new Date(selectedUser.subscription_expires_at) - new Date()) / (1000 * 60 * 60 * 24)))} days remaining</div>}
                  </div>
                  {writable && (
                    <>
                      <div className="mb-3">
                        <label className="block text-slate-300 text-sm font-semibold mb-2">Extend Premium Period</label>
                        <div className="grid grid-cols-2 gap-2">
                          {[{ label: '+1 Month', days: 30 }, { label: '+3 Months', days: 90 }, { label: '+6 Months', days: 180 }, { label: '+1 Year', days: 365 }].map((preset) => (
                            <button key={preset.days} onClick={() => handleExtend(selectedUser, preset.days)}
                              className="p-3 bg-gradient-to-br from-blue-500/20 to-violet-600/20 border border-blue-500/30 rounded-xl text-blue-400 text-sm font-semibold hover:from-blue-500/30 hover:to-violet-600/30 transition-all">{preset.label}</button>
                          ))}
                        </div>
                      </div>
                      <div className="p-4 bg-slate-900/40 rounded-xl border border-white/5 space-y-3 mb-3">
                        <label className="block text-slate-300 text-sm font-semibold">Or Set New Expiry Date</label>
                        <input type="date" id={`expire-date-${selectedUser.id}`} min={todayInput}
                          defaultValue={selectedUser.subscription_expires_at ? toLocalDateInput(new Date(selectedUser.subscription_expires_at)) : ''}
                          className="w-full px-4 py-3 bg-slate-800/50 border border-slate-600/30 rounded-xl text-slate-100 text-sm outline-none focus:border-blue-500 focus:bg-slate-800/80 transition-all" />
                        <button onClick={() => handleCustomExpiry(selectedUser.id)} className="w-full p-3 bg-blue-500/15 border border-blue-500/30 rounded-xl text-blue-400 text-sm font-semibold hover:bg-blue-500/25 transition-colors">Update Expiry Date</button>
                      </div>
                      <button onClick={() => { if (window.confirm('Downgrade to Free?')) handleUpdateSubscription(selectedUser.id, 'free', null); }}
                        className="w-full p-3.5 bg-slate-500/10 border border-slate-500/30 rounded-xl text-slate-400 text-sm font-semibold hover:bg-slate-500/20 transition-colors">Downgrade to Free</button>
                    </>
                  )}
                </>
              )}
            </div>

            <div className="mb-8">
              <h3 className="text-xs font-bold text-slate-400 mb-4 uppercase tracking-wider">Statistics</h3>
              <div className="grid grid-cols-2 gap-4">
                {[
                  { label: 'Transactions', value: fmtNum(selectedUser.total_transactions), icon: DollarSign },
                  { label: 'Goals', value: fmtNum(selectedUser.total_goals), icon: Target },
                  { label: 'Currency', value: String(selectedUser.default_currency || '—').toUpperCase(), icon: DollarSign },
                  { label: 'Joined', value: selectedUser.created_at ? new Date(selectedUser.created_at).toLocaleDateString('en-US', { month: 'short', year: 'numeric' }) : '—', icon: Calendar },
                ].map((stat) => (
                  <div key={stat.label} className="p-4 bg-slate-900/40 rounded-xl border border-white/5">
                    <div className="flex items-center gap-2 mb-2"><stat.icon size={16} className="text-slate-500" /><div className="text-[13px] text-slate-500 truncate">{stat.label}</div></div>
                    <div className="text-lg md:text-xl font-bold text-slate-100 truncate">{stat.value}</div>
                  </div>
                ))}
              </div>
            </div>

            {isSuper && (
              <div>
                <h3 className="text-xs font-bold text-slate-400 mb-4 uppercase tracking-wider">Danger Zone</h3>
                <button onClick={() => handleDeleteUser(selectedUser.id)} className="w-full p-3.5 bg-red-500/10 border border-red-500/30 rounded-xl text-red-400 text-sm font-semibold flex items-center justify-center gap-2 hover:bg-red-500/20 transition-colors">
                  <Trash2 size={16} />Delete User Account
                </button>
              </div>
            )}

            <button onClick={() => setSelectedUser(null)} className="w-full p-3.5 bg-slate-500/20 border border-slate-500/30 rounded-xl text-slate-400 text-sm font-semibold mt-4 hover:bg-slate-500/30 transition-colors">Close</button>
          </div>
        </div>
      )}

      {/* Create Admin Modal */}
      {showCreateAdmin && isSuper && (
        <div className="fixed inset-0 bg-black/70 backdrop-blur-sm flex items-center justify-center z-50 animate-fadeIn p-4" onClick={() => setShowCreateAdmin(false)}>
          <div className="bg-gradient-to-br from-slate-800 to-slate-700 rounded-3xl p-6 md:p-10 max-w-lg w-full border border-white/10 shadow-2xl animate-slideIn max-h-[90vh] overflow-y-auto" onClick={(e) => e.stopPropagation()}>
            <div className="flex items-center gap-3 mb-8">
              <div className="w-12 h-12 bg-gradient-to-br from-blue-500 to-violet-500 rounded-xl flex items-center justify-center flex-shrink-0"><Shield size={24} className="text-white" /></div>
              <h2 className="text-2xl font-bold text-slate-100">Create New Admin</h2>
            </div>
            <div className="space-y-5 mb-8">
              {[{ label: 'Full Name', field: 'name', type: 'text', placeholder: 'Enter admin name...' },
                { label: 'Email Address', field: 'email', type: 'email', placeholder: 'Enter admin email...' },
                { label: 'Password', field: 'password', type: 'password', placeholder: 'Minimum 8 characters...' }].map(({ label, field, type, placeholder }) => (
                <div key={field}>
                  <label className="block text-slate-300 text-sm font-semibold mb-2">{label}</label>
                  <input type={type} value={createAdminForm[field]} placeholder={placeholder}
                    onChange={(e) => setCreateAdminForm({...createAdminForm, [field]: e.target.value})}
                    className="w-full px-4 py-3.5 bg-slate-800/50 border border-slate-600/30 rounded-xl text-slate-100 text-[15px] outline-none transition-all focus:border-blue-500 focus:bg-slate-800/80" />
                </div>
              ))}
              <div>
                <label className="block text-slate-300 text-sm font-semibold mb-3">Role</label>
                <div className="grid grid-cols-1 sm:grid-cols-3 gap-3">
                  {[{ value: 'moderator', label: 'Moderator', desc: 'Read-only access' }, { value: 'admin', label: 'Admin', desc: 'Full access' }, { value: 'super_admin', label: 'Super Admin', desc: 'All privileges' }].map(role => (
                    <button key={role.value} onClick={() => setCreateAdminForm({...createAdminForm, role: role.value})}
                      className={`p-3 rounded-xl border-2 transition-all text-left ${createAdminForm.role === role.value ? 'border-blue-500 bg-blue-500/10 text-blue-400' : 'border-slate-600/30 bg-slate-800/50 text-slate-400 hover:border-slate-500/50'}`}>
                      <div className="text-sm font-bold mb-1">{role.label}</div>
                      <div className="text-xs opacity-70">{role.desc}</div>
                    </button>
                  ))}
                </div>
              </div>
            </div>
            <div className="flex gap-3">
              <button onClick={() => setShowCreateAdmin(false)} className="flex-1 p-3.5 bg-slate-500/20 border border-slate-500/30 rounded-xl text-slate-400 text-sm font-semibold hover:bg-slate-500/30 transition-colors">Cancel</button>
              <button onClick={handleCreateAdmin} disabled={createAdminLoading}
                className={`flex-1 p-3.5 rounded-xl text-white text-sm font-semibold transition-all flex items-center justify-center gap-2 ${createAdminLoading ? 'bg-slate-600 cursor-not-allowed' : 'bg-gradient-to-br from-blue-500 to-violet-500 hover:-translate-y-0.5 shadow-lg shadow-blue-500/30'}`}>
                {createAdminLoading ? <><RefreshCw size={16} className="animate-spin" />Creating...</> : <><Shield size={16} />Create Admin</>}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
};


// ─── Root App ─────────────────────────────────────────────────────────────────
export default function AdminApp() {
  // Read the stored session once, synchronously (no setState-in-effect).
  const [session, setSession] = useState(loadStoredSession);
  // Token whose validity has been confirmed with GET /api/admin/me this page load.
  const [verifiedToken, setVerifiedToken] = useState(null);
  const [notice, setNotice] = useState('');

  // Any 401 from any request → session cleared (by the api helper) → back to login.
  useEffect(() => onUnauthorized(() => {
    setSession({ token: null, admin: null });
    setVerifiedToken(null);
    setNotice('Your session has expired. Please sign in again.');
  }), []);

  // Validate a stored token on load and refresh the cached admin profile/role.
  useEffect(() => {
    const token = session.token;
    if (!token || verifiedToken === token) return undefined;
    let cancelled = false;
    api.getMe(token)
      .then((me) => {
        if (cancelled) return;
        storeSession(token, me);
        setSession((s) => (s.token === token ? { token, admin: me } : s));
        setVerifiedToken(token);
      })
      .catch((err) => {
        if (cancelled) return;
        // 401 is handled by onUnauthorized. For network/server errors keep the
        // stored session so the panel is still usable; requests will re-check.
        if (err?.status !== 401) setVerifiedToken(token);
      });
    return () => { cancelled = true; };
  }, [session.token, verifiedToken]);

  const handleLogin = (accessToken, adminInfo) => {
    storeSession(accessToken, adminInfo);
    setSession({ token: accessToken, admin: adminInfo });
    setVerifiedToken(accessToken); // fresh from login, no need to re-check
    setNotice('');
  };

  const handleLogout = useCallback(() => {
    clearSession();
    setSession({ token: null, admin: null });
    setVerifiedToken(null);
    setNotice('');
  }, []);

  // Profile edits update both the sidebar (via session state) and localStorage.
  const handleUpdateAdmin = (updated) => {
    const nextAdmin = { ...session.admin, ...updated };
    storeSession(null, nextAdmin);
    setSession((s) => ({ ...s, admin: nextAdmin }));
  };

  // Password change returns a fresh token (the old one is revoked server-side).
  const handleTokenRotated = (newToken) => {
    storeSession(newToken, null);
    setSession((s) => ({ ...s, token: newToken }));
    setVerifiedToken(newToken);
  };

  if (!session.token || !session.admin) return <LoginPage onLogin={handleLogin} notice={notice} />;

  if (verifiedToken !== session.token) {
    return (
      <div className="min-h-screen bg-[#0A0F1E] flex flex-col items-center justify-center gap-4 text-slate-400 font-sans">
        <RefreshCw size={32} className="animate-spin text-blue-500" />
        <div className="text-sm">Verifying session…</div>
      </div>
    );
  }

  return (
    <Dashboard
      token={session.token}
      admin={session.admin}
      onLogout={handleLogout}
      onUpdateAdmin={handleUpdateAdmin}
      onTokenRotated={handleTokenRotated}
    />
  );
}
