import React, { useState, useEffect } from 'react';
import { 
  Users, Shield, BarChart3, Activity, Search, LogOut, TrendingUp, 
  AlertCircle, Crown, Zap, Eye, Trash2, RefreshCw, Calendar, 
  DollarSign, Target, Send, Menu, X, Settings, Lock, User, MessageSquare,
  Smartphone, Plus, Edit2, ToggleLeft, ToggleRight, Download, CheckCircle,
  AlertTriangle, Globe, Apple, ExternalLink
} from 'lucide-react';
import AIUsageStats from './AIUsageStats';
import FeedbackManagement from './FeedbackManagement';

const API_BASE_URL = 'https://flowfinance.onrender.com';

// ─── API Service ──────────────────────────────────────────────────────────────
const api = {
  async login(email, password) {
    const res = await fetch(`${API_BASE_URL}/api/admin/login`, {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email, password })
    });
    if (!res.ok) throw new Error('Login failed');
    return res.json();
  },
  async getMe(token) {
    const res = await fetch(`${API_BASE_URL}/api/admin/me`, { headers: { 'Authorization': `Bearer ${token}` } });
    if (!res.ok) throw new Error('Failed to fetch admin info');
    return res.json();
  },
  async getUsers(token, params = {}) {
    const qs = new URLSearchParams(params).toString();
    const res = await fetch(`${API_BASE_URL}/api/admin/users?${qs}`, { headers: { 'Authorization': `Bearer ${token}` } });
    if (!res.ok) throw new Error('Failed to fetch users');
    return res.json();
  },
  async getUserDetail(token, userId) {
    const res = await fetch(`${API_BASE_URL}/api/admin/users/${userId}`, { headers: { 'Authorization': `Bearer ${token}` } });
    if (!res.ok) throw new Error('Failed to fetch user details');
    return res.json();
  },
  async updateUserSubscription(token, userId, data) {
    const res = await fetch(`${API_BASE_URL}/api/admin/users/${userId}/subscription`, {
      method: 'PUT', headers: { 'Authorization': `Bearer ${token}`, 'Content-Type': 'application/json' },
      body: JSON.stringify(data)
    });
    if (!res.ok) throw new Error('Failed to update subscription');
    return res.json();
  },
  async getUserStats(token) {
    const res = await fetch(`${API_BASE_URL}/api/admin/stats/users`, { headers: { 'Authorization': `Bearer ${token}` } });
    if (!res.ok) throw new Error('Failed to fetch stats');
    return res.json();
  },
  async getSystemStats(token) {
    const res = await fetch(`${API_BASE_URL}/api/admin/stats/system`, { headers: { 'Authorization': `Bearer ${token}` } });
    if (!res.ok) throw new Error('Failed to fetch system stats');
    return res.json();
  },
  async getAdmins(token) {
    const res = await fetch(`${API_BASE_URL}/api/admin/admins`, { headers: { 'Authorization': `Bearer ${token}` } });
    if (!res.ok) throw new Error('Failed to fetch admins');
    return res.json();
  },
  async createAdmin(token, data) {
    const res = await fetch(`${API_BASE_URL}/api/admin/admins`, {
      method: 'POST', headers: { 'Authorization': `Bearer ${token}`, 'Content-Type': 'application/json' },
      body: JSON.stringify(data)
    });
    if (!res.ok) throw new Error('Failed to create admin');
    return res.json();
  },
  async deleteUser(token, userId) {
    const res = await fetch(`${API_BASE_URL}/api/admin/users/${userId}`, {
      method: 'DELETE', headers: { 'Authorization': `Bearer ${token}` }
    });
    if (!res.ok) throw new Error('Failed to delete user');
    return res.json();
  },
  async getLogs(token, params = {}) {
    const qs = new URLSearchParams(params).toString();
    const res = await fetch(`${API_BASE_URL}/api/admin/logs?${qs}`, { headers: { 'Authorization': `Bearer ${token}` } });
    if (!res.ok) throw new Error('Failed to fetch logs');
    return res.json();
  },
  async getBroadcastStats(token) {
    const res = await fetch(`${API_BASE_URL}/api/admin/broadcast-stats`, { headers: { 'Authorization': `Bearer ${token}` } });
    if (!res.ok) throw new Error('Failed to fetch broadcast stats');
    return res.json();
  },
  async sendBroadcastNotification(token, data) {
    const res = await fetch(`${API_BASE_URL}/api/admin/broadcast-notification`, {
      method: 'POST', headers: { 'Authorization': `Bearer ${token}`, 'Content-Type': 'application/json' },
      body: JSON.stringify(data)
    });
    if (!res.ok) throw new Error('Failed to send broadcast notification');
    return res.json();
  },
  async deleteAdmin(token, adminId) {
    const res = await fetch(`${API_BASE_URL}/api/admin/admins/${adminId}`, {
      method: 'DELETE', headers: { 'Authorization': `Bearer ${token}` }
    });
    if (!res.ok) throw new Error('Failed to delete admin');
    return res.json();
  },
  async updateProfile(token, data) {
    const res = await fetch(`${API_BASE_URL}/api/admin/me`, {
      method: 'PUT', headers: { 'Authorization': `Bearer ${token}`, 'Content-Type': 'application/json' },
      body: JSON.stringify(data)
    });
    if (!res.ok) { const err = await res.json(); throw new Error(err.detail || 'Failed to update profile'); }
    return res.json();
  },
  async changePassword(token, data) {
    const res = await fetch(`${API_BASE_URL}/api/admin/change-password`, {
      method: 'PUT', headers: { 'Authorization': `Bearer ${token}`, 'Content-Type': 'application/json' },
      body: JSON.stringify(data)
    });
    if (!res.ok) { const err = await res.json(); throw new Error(err.detail || 'Failed to change password'); }
    return res.json();
  },

  // ─── App Version API ──────────────────────────────────────────────────────
  async getAppVersions(token, params = {}) {
    const qs = new URLSearchParams(params).toString();
    const res = await fetch(`${API_BASE_URL}/api/admin/app-versions?${qs}`, { headers: { 'Authorization': `Bearer ${token}` } });
    if (!res.ok) throw new Error('Failed to fetch app versions');
    return res.json();
  },
  async createAppVersion(token, data) {
    const res = await fetch(`${API_BASE_URL}/api/admin/app-versions`, {
      method: 'POST', headers: { 'Authorization': `Bearer ${token}`, 'Content-Type': 'application/json' },
      body: JSON.stringify(data)
    });
    if (!res.ok) { const err = await res.json(); throw new Error(err.detail || 'Failed to create app version'); }
    return res.json();
  },
  async updateAppVersion(token, versionId, data) {
    const res = await fetch(`${API_BASE_URL}/api/admin/app-versions/${versionId}`, {
      method: 'PUT', headers: { 'Authorization': `Bearer ${token}`, 'Content-Type': 'application/json' },
      body: JSON.stringify(data)
    });
    if (!res.ok) { const err = await res.json(); throw new Error(err.detail || 'Failed to update app version'); }
    return res.json();
  },
  async deleteAppVersion(token, versionId) {
    const res = await fetch(`${API_BASE_URL}/api/admin/app-versions/${versionId}`, {
      method: 'DELETE', headers: { 'Authorization': `Bearer ${token}` }
    });
    if (!res.ok) { const err = await res.json(); throw new Error(err.detail || 'Failed to delete app version'); }
    return res.json();
  },
};


// ─── Login Page ───────────────────────────────────────────────────────────────
const LoginPage = ({ onLogin }) => {
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
    } catch {
      setError('Invalid credentials. Please try again.');
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

        {error && (
          <div className="bg-red-500/10 border border-red-500/30 rounded-xl p-3 mb-6 flex items-center gap-3 animate-slideUp">
            <AlertCircle size={18} className="text-red-500" />
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
const ProfileSettings = ({ token, admin, onUpdateAdmin, onLogout }) => {
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
        alert('Profile updated successfully');
        onUpdateAdmin(updated);
      }
    } catch (error) { alert(error.message); }
    finally { setLoading(prev => ({ ...prev, profile: false })); }
  };

  const handlePasswordChange = async (e) => {
    e.preventDefault();
    if (passwordForm.new_password !== passwordForm.confirm_password) { alert("New passwords don't match"); return; }
    setLoading(prev => ({ ...prev, password: true }));
    try {
      await api.changePassword(token, passwordForm);
      alert('Password changed successfully');
      setPasswordForm({ current_password: '', new_password: '', confirm_password: '' });
    } catch (error) { alert(error.message); }
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

const AppVersionManagement = ({ token, adminRole }) => {
  const [versions, setVersions] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  const [showForm, setShowForm] = useState(false);
  const [editingVersion, setEditingVersion] = useState(null); // null = create, object = edit
  const [form, setForm] = useState(EMPTY_VERSION_FORM);
  const [saving, setSaving] = useState(false);
  const [platformFilter, setPlatformFilter] = useState('');

  const loadVersions = async () => {
    setLoading(true);
    setError(null);
    try {
      const params = {};
      if (platformFilter) params.platform = platformFilter;
      const data = await api.getAppVersions(token, params);
      setVersions(data);
    } catch (err) {
      setError('Failed to load app versions');
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => { loadVersions(); }, [platformFilter]);

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
      const payload = {
        ...form,
        min_supported_version: form.min_supported_version.trim() || null,
        release_notes: form.release_notes.trim() || null,
      };
      if (editingVersion) {
        await api.updateAppVersion(token, editingVersion.id, payload);
      } else {
        await api.createAppVersion(token, payload);
      }
      setShowForm(false);
      loadVersions();
    } catch (err) {
      alert(err.message);
    } finally {
      setSaving(false);
    }
  };

  const handleToggleActive = async (v) => {
    try {
      await api.updateAppVersion(token, v.id, { is_active: !v.is_active });
      loadVersions();
    } catch (err) {
      alert('Failed to toggle version status');
    }
  };

  const handleToggleForce = async (v) => {
    try {
      await api.updateAppVersion(token, v.id, { is_force_update: !v.is_force_update });
      loadVersions();
    } catch (err) {
      alert('Failed to toggle force update');
    }
  };

  const handleDelete = async (id) => {
    if (!window.confirm('Delete this version record? This cannot be undone.')) return;
    try {
      await api.deleteAppVersion(token, id);
      loadVersions();
    } catch (err) {
      alert(err.message);
    }
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

  // Summary counts
  const total = versions.length;
  const active = versions.filter(v => v.is_active).length;
  const forceCount = versions.filter(v => v.is_force_update && v.is_active).length;

  return (
    <div className="animate-slideIn">
      {/* Header */}
      <div className="mb-6 md:mb-8 mt-2 md:mt-0 flex flex-col md:flex-row md:items-start justify-between gap-4">
        <div>
          <h1 className="text-3xl md:text-4xl font-bold mb-2 bg-gradient-to-br from-slate-100 to-slate-400 bg-clip-text text-transparent">
            App Version Management
          </h1>
          <p className="text-slate-400 font-medium text-sm md:text-base">
            Control app versions and force-update enforcement
          </p>
        </div>
        <button
          onClick={openCreate}
          className="w-full md:w-auto px-6 py-3.5 bg-gradient-to-br from-blue-500 to-violet-500 rounded-xl text-white text-[15px] font-semibold flex items-center justify-center gap-2 hover:-translate-y-0.5 transition-transform shadow-lg shadow-blue-500/30"
        >
          <Plus size={18} />
          Publish New Version
        </button>
      </div>

      {/* Summary Cards */}
      <div className="grid grid-cols-1 sm:grid-cols-3 gap-4 mb-6">
        {[
          { label: 'Total Versions', value: total, color: 'text-blue-400', bg: 'bg-blue-500/10', icon: Smartphone },
          { label: 'Active Versions', value: active, color: 'text-emerald-400', bg: 'bg-emerald-500/10', icon: CheckCircle },
          { label: 'Force Update Active', value: forceCount, color: 'text-red-400', bg: 'bg-red-500/10', icon: AlertTriangle },
        ].map((s) => (
          <div key={s.label} className="bg-gradient-to-br from-slate-800/60 to-slate-700/30 p-5 rounded-2xl border border-white/5">
            <div className={`w-11 h-11 ${s.bg} rounded-xl flex items-center justify-center mb-3`}>
              <s.icon size={22} className={s.color} />
            </div>
            <div className={`text-3xl font-bold mb-1 ${s.color}`}>{s.value}</div>
            <div className="text-sm text-slate-400">{s.label}</div>
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
        <button onClick={loadVersions} className="p-2.5 bg-slate-700/50 border border-white/5 rounded-xl text-slate-400 hover:text-white transition-colors">
          <RefreshCw size={18} />
        </button>
      </div>

      {/* How Force Update Works */}
      <div className="bg-blue-500/5 border border-blue-500/20 rounded-2xl p-5 mb-6 flex items-start gap-3">
        <AlertCircle size={20} className="text-blue-400 mt-0.5 flex-shrink-0" />
        <div className="text-sm text-blue-300/80 leading-relaxed">
          <strong className="text-blue-300">How it works:</strong> When a version is published and <em>active</em>, the app checks it on startup.
          If <strong>Force Update</strong> is enabled, users on older versions are blocked until they download the new version.
          Set <strong>Min Supported Version</strong> to auto-force-update anyone below that threshold regardless of the force flag.
        </div>
      </div>

      {/* Versions Table */}
      <div className="bg-gradient-to-br from-slate-800/60 to-slate-700/30 rounded-2xl border border-white/5 overflow-hidden">
        {loading ? (
          <div className="p-16 flex items-center justify-center">
            <RefreshCw size={28} className="animate-spin text-blue-500" />
          </div>
        ) : error ? (
          <div className="p-16 text-center text-red-400">{error}</div>
        ) : versions.length === 0 ? (
          <div className="p-16 text-center">
            <Smartphone size={40} className="text-slate-600 mx-auto mb-3" />
            <div className="text-slate-400 text-lg font-semibold mb-1">No versions published yet</div>
            <div className="text-slate-500 text-sm">Click "Publish New Version" to get started.</div>
          </div>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full border-collapse min-w-[900px]">
              <thead>
                <tr className="bg-slate-900/50 border-b border-white/5">
                  {['Version', 'Platform', 'Download URL', 'Force Update', 'Min Supported', 'Status', 'Published', 'Actions'].map((h, i) => (
                    <th key={i} className={`px-5 py-4 text-left text-slate-400 text-xs font-semibold tracking-wider uppercase ${i === 7 ? 'text-center' : ''}`}>
                      {h}
                    </th>
                  ))}
                </tr>
              </thead>
              <tbody>
                {versions.map((v, index) => (
                  <tr key={v.id} className="border-b border-white/5 hover:bg-slate-800/40 transition-colors animate-slideIn" style={{ animationDelay: `${index * 40}ms` }}>
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
                        {v.download_url.replace(/^https?:\/\//, '').slice(0, 30)}{v.download_url.length > 35 ? '…' : ''}
                      </a>
                    </td>

                    {/* Force Update Toggle */}
                    <td className="px-5 py-4">
                      <button
                        onClick={() => handleToggleForce(v)}
                        className={`flex items-center gap-2 px-3 py-1.5 rounded-lg text-xs font-semibold border transition-all ${
                          v.is_force_update
                            ? 'bg-red-500/15 border-red-500/30 text-red-400 hover:bg-red-500/25'
                            : 'bg-slate-700/50 border-slate-600/30 text-slate-500 hover:border-slate-500/50'
                        }`}
                      >
                        {v.is_force_update ? <AlertTriangle size={13} /> : <CheckCircle size={13} />}
                        {v.is_force_update ? 'Forced' : 'Optional'}
                      </button>
                    </td>

                    {/* Min Supported Version */}
                    <td className="px-5 py-4">
                      {v.min_supported_version ? (
                        <span className="px-2.5 py-1 bg-amber-500/10 border border-amber-500/30 text-amber-400 text-xs font-semibold rounded-lg">
                          ≥ v{v.min_supported_version}
                        </span>
                      ) : (
                        <span className="text-slate-600 text-xs">—</span>
                      )}
                    </td>

                    {/* Active Toggle */}
                    <td className="px-5 py-4">
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
                    </td>

                    {/* Published date */}
                    <td className="px-5 py-4 text-xs text-slate-500">
                      {new Date(v.created_at).toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' })}
                      <div className="text-slate-600 mt-0.5">{v.created_by_email}</div>
                    </td>

                    {/* Actions */}
                    <td className="px-5 py-4">
                      <div className="flex items-center justify-center gap-2">
                        <button
                          onClick={() => openEdit(v)}
                          className="p-2 text-slate-400 hover:text-blue-400 hover:bg-blue-500/10 rounded-lg transition-colors"
                          title="Edit"
                        >
                          <Edit2 size={15} />
                        </button>
                        {adminRole === 'super_admin' && (
                          <button
                            onClick={() => handleDelete(v.id)}
                            className="p-2 text-slate-400 hover:text-red-400 hover:bg-red-500/10 rounded-lg transition-colors"
                            title="Delete"
                          >
                            <Trash2 size={15} />
                          </button>
                        )}
                      </div>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>

      {/* Create / Edit Modal */}
      {showForm && (
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
                <p className="text-xs text-slate-500 mt-1">Users below this version will be force-updated regardless of the force flag.</p>
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
                      <div className="text-xs text-slate-500 mt-0.5">Block users from using the app until they update</div>
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
                    <strong>Warning:</strong> Force update will block all users on older versions from using the app. Use only for critical security fixes or breaking changes.
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
    </div>
  );
};


// ─── Dashboard ────────────────────────────────────────────────────────────────
const Dashboard = ({ token, admin, onLogout }) => {
  const [activeTab, setActiveTab] = useState('overview');
  const [stats, setStats] = useState(null);
  const [systemStats, setSystemStats] = useState(null);
  const [users, setUsers] = useState([]);
  const [admins, setAdmins] = useState([]);
  const [logs, setLogs] = useState([]);
  const [searchQuery, setSearchQuery] = useState('');
  const [subscriptionFilter, setSubscriptionFilter] = useState('');
  const [selectedUser, setSelectedUser] = useState(null);
  const [loading, setLoading] = useState(false);
  const [broadcastStats, setBroadcastStats] = useState(null);
  const [broadcastForm, setBroadcastForm] = useState({
    title: '', message: '', target_users: 'all', notification_type: 'system_broadcast'
  });
  const [broadcastLoading, setBroadcastLoading] = useState(false);
  const [showCreateAdmin, setShowCreateAdmin] = useState(false);
  const [createAdminForm, setCreateAdminForm] = useState({ name: '', email: '', password: '', role: 'admin' });
  const [createAdminLoading, setCreateAdminLoading] = useState(false);
  const [isSidebarOpen, setIsSidebarOpen] = useState(false);
  const [currentAdmin, setCurrentAdmin] = useState(admin);

  useEffect(() => { loadData(); }, [activeTab]);

  const loadData = async () => {
    setLoading(true);
    try {
      if (activeTab === 'overview') {
        const [userStats, sysStats] = await Promise.all([api.getUserStats(token), api.getSystemStats(token)]);
        setStats(userStats); setSystemStats(sysStats);
      } else if (activeTab === 'users') {
        const params = {};
        if (searchQuery) params.search = searchQuery;
        if (subscriptionFilter) params.subscription_type = subscriptionFilter;
        params.limit = 100;
        setUsers(await api.getUsers(token, params));
      } else if (activeTab === 'broadcast') {
        setBroadcastStats(await api.getBroadcastStats(token));
      } else if (activeTab === 'admins' && admin.role === 'super_admin') {
        setAdmins(await api.getAdmins(token));
      } else if (activeTab === 'logs' && admin.role === 'super_admin') {
        setLogs(await api.getLogs(token, { limit: 50 }));
      }
    } catch (error) { console.error('Error loading data:', error); }
    finally { setLoading(false); }
  };

  const handleSearch = () => { if (activeTab === 'users') loadData(); };
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
      loadData();
    } catch (error) { alert('Failed to create admin: ' + error.message); }
    finally { setCreateAdminLoading(false); }
  };

  const handleDeleteAdmin = async (adminId) => {
    if (!window.confirm('Delete this admin?')) return;
    try { await api.deleteAdmin(token, adminId); alert('Admin deleted'); loadData(); }
    catch (error) { alert('Failed: ' + error.message); }
  };

  const handleSendBroadcast = async () => {
    if (!broadcastForm.title.trim() || !broadcastForm.message.trim()) { alert('Fill in title and message'); return; }
    if (!window.confirm(`Send to ${broadcastForm.target_users} users?`)) return;
    setBroadcastLoading(true);
    try {
      const result = await api.sendBroadcastNotification(token, broadcastForm);
      alert(`Sent!\n\nTotal: ${result.total_users}\nNotifications: ${result.notifications_sent}\nPush: ${result.fcm_sent} sent, ${result.fcm_failed} failed`);
      setBroadcastForm({ title: '', message: '', target_users: 'all', notification_type: 'system_broadcast' });
      loadData();
    } catch (error) { alert('Failed: ' + error.message); }
    finally { setBroadcastLoading(false); }
  };

  const handleUpdateSubscription = async (userId, subscriptionType, expiresAt) => {
    try {
      await api.updateUserSubscription(token, userId, { subscription_type: subscriptionType, subscription_expires_at: expiresAt });
      alert('Subscription updated!'); loadData(); setSelectedUser(null);
    } catch { alert('Failed to update subscription'); }
  };

  const handleDeleteUser = async (userId) => {
    if (!window.confirm('Delete this user? Cannot be undone.')) return;
    try { await api.deleteUser(token, userId); alert('User deleted'); loadData(); setSelectedUser(null); }
    catch { alert('Failed to delete user'); }
  };

  const navItems = [
    { id: 'overview', icon: BarChart3, label: 'Overview' },
    { id: 'users', icon: Users, label: 'Users' },
    { id: 'broadcast', icon: Send, label: 'Broadcast' },
    { id: 'app-versions', icon: Smartphone, label: 'App Versions' },
    { id: 'ai-usage', icon: Zap, label: 'AI Usage & Costs' },
    { id: 'feedback', icon: MessageSquare, label: 'Feedback' },
    { id: 'settings', icon: Settings, label: 'Settings' },
    ...(admin.role === 'super_admin' ? [
      { id: 'admins', icon: Shield, label: 'Admins' },
      { id: 'logs', icon: Activity, label: 'Activity Logs' },
    ] : []),
  ];

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
                {admin.name.charAt(0)}
              </div>
              <div className="flex-1 min-w-0">
                <div className="text-sm font-semibold text-slate-100 mb-0.5 truncate">{admin.name}</div>
                <div className="text-xs text-slate-400 capitalize flex items-center gap-1">
                  {admin.role === 'super_admin' && <Crown size={12} className="text-amber-500" />}
                  {admin.role.replace('_', ' ')}
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

        {/* Overview Tab */}
        {activeTab === 'overview' && stats && systemStats && (
          <div className="animate-slideIn">
            <div className="mb-8 mt-2 md:mt-0">
              <h1 className="text-3xl md:text-4xl font-bold mb-2 bg-gradient-to-br from-slate-100 to-slate-400 bg-clip-text text-transparent">Dashboard Overview</h1>
              <p className="text-slate-400 font-medium text-sm md:text-base">Welcome back, {admin.name}. Here's what's happening today.</p>
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
                <div key={index} className="bg-gradient-to-br from-slate-800/60 to-slate-700/30 p-5 md:p-7 rounded-2xl border border-white/5 shadow-xl hover:-translate-y-1 hover:shadow-2xl transition-all duration-300 animate-slideIn" style={{ animationDelay: `${index * 100}ms` }}>
                  <div className="flex justify-between items-start mb-4 md:mb-5">
                    <div className={`w-12 h-12 md:w-14 md:h-14 ${stat.bg} rounded-2xl flex items-center justify-center`}>
                      <stat.icon size={24} className={`md:w-7 md:h-7 ${stat.color}`} strokeWidth={2} />
                    </div>
                  </div>
                  <div className="text-3xl md:text-4xl font-bold text-slate-100 mb-2">{stat.value.toLocaleString()}</div>
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
                ].map((item, idx) => (
                  <div key={idx}>
                    <div className="text-xs md:text-sm text-slate-400 mb-2">{item.label}</div>
                    <div className={`text-2xl md:text-3xl font-bold ${item.color}`}>{item.value}</div>
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
        {activeTab === 'feedback' && <FeedbackManagement token={token} />}

        {/* Users Tab */}
        {activeTab === 'users' && (
          <div className="animate-slideIn">
            <div className="mb-6 md:mb-8 mt-2 md:mt-0">
              <h1 className="text-3xl md:text-4xl font-bold mb-2 bg-gradient-to-br from-slate-100 to-slate-400 bg-clip-text text-transparent">User Management</h1>
              <p className="text-slate-400 font-medium text-sm md:text-base">Manage user accounts and subscriptions</p>
            </div>
            <div className="bg-gradient-to-br from-slate-800/60 to-slate-700/30 p-4 md:p-6 rounded-2xl border border-white/5 mb-6 flex flex-col md:flex-row gap-4">
              <div className="flex-1">
                <input type="text" placeholder="Search by name or email..." value={searchQuery}
                  onChange={(e) => setSearchQuery(e.target.value)} onKeyPress={(e) => e.key === 'Enter' && handleSearch()}
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
                <button onClick={() => { setSearchQuery(''); setSubscriptionFilter(''); loadData(); }}
                  className="px-4 py-3.5 bg-slate-500/20 border border-slate-400/20 rounded-xl text-slate-400 text-[15px] font-semibold flex items-center gap-2 hover:bg-slate-500/30 transition-colors">
                  <RefreshCw size={18} />
                </button>
              </div>
            </div>
            <div className="bg-gradient-to-br from-slate-800/60 to-slate-700/30 rounded-2xl border border-white/5 overflow-hidden">
              <div className="overflow-x-auto">
                <table className="w-full border-collapse min-w-[800px]">
                  <thead>
                    <tr className="bg-slate-900/50 border-b border-white/5">
                      {['User', 'Subscription', 'Activity', 'Joined', 'Actions'].map((header, i) => (
                        <th key={i} className={`px-6 py-4 text-left text-slate-400 text-xs font-semibold tracking-wider uppercase ${i === 4 ? 'text-center' : ''}`}>{header}</th>
                      ))}
                    </tr>
                  </thead>
                  <tbody>
                    {users.map((user, index) => (
                      <tr key={user.id} className="border-b border-white/5 hover:bg-slate-800/50 transition-all duration-200 animate-slideIn" style={{ animationDelay: `${index * 50}ms` }}>
                        <td className="px-6 py-5">
                          <div className="flex items-center gap-3">
                            <div className="w-11 h-11 bg-gradient-to-br from-blue-500 to-violet-500 rounded-xl flex items-center justify-center text-white font-bold shadow-md">{user.name.charAt(0).toUpperCase()}</div>
                            <div>
                              <div className="text-[15px] font-semibold text-slate-100 mb-1">{user.name}</div>
                              <div className="text-xs text-slate-400">{user.email}</div>
                            </div>
                          </div>
                        </td>
                        <td className="px-6 py-5">
                          <div className={`inline-flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-[13px] font-semibold border ${user.subscription_type === 'premium' ? 'bg-amber-500/15 border-amber-500/30 text-amber-500' : 'bg-slate-500/15 border-slate-500/30 text-slate-400'}`}>
                            {user.subscription_type === 'premium' && <Crown size={14} />}
                            {user.subscription_type.toUpperCase()}
                          </div>
                        </td>
                        <td className="px-6 py-5">
                          <div className="text-sm text-slate-300 mb-1">{user.total_transactions} transactions</div>
                          <div className="text-xs text-slate-500">{user.total_goals} goals</div>
                        </td>
                        <td className="px-6 py-5 text-sm text-slate-400">
                          {new Date(user.created_at).toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' })}
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
              {users.length === 0 && <div className="p-16 text-center text-slate-400">No users found</div>}
            </div>
          </div>
        )}

        {/* Admins Tab */}
        {activeTab === 'admins' && admin.role === 'super_admin' && (
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
                        <th key={i} className={`px-6 py-4 text-left text-slate-400 text-xs font-semibold tracking-wider uppercase ${i === 5 ? 'text-center' : ''}`}>{header}</th>
                      ))}
                    </tr>
                  </thead>
                  <tbody>
                    {admins.map((adm, index) => (
                      <tr key={adm.id} className="border-b border-white/5 hover:bg-slate-800/50 transition-colors animate-slideIn" style={{ animationDelay: `${index * 50}ms` }}>
                        <td className="px-6 py-5">
                          <div className="flex items-center gap-3">
                            <div className="w-11 h-11 bg-gradient-to-br from-violet-500 to-pink-500 rounded-xl flex items-center justify-center text-white font-bold shadow-md">{adm.name.charAt(0).toUpperCase()}</div>
                            <div className="text-[15px] font-semibold text-slate-100 flex items-center gap-2">
                              {adm.name}
                              {adm.role === 'super_admin' && <Crown size={16} className="text-amber-500" />}
                            </div>
                          </div>
                        </td>
                        <td className="px-6 py-5 text-sm text-slate-300">{adm.email}</td>
                        <td className="px-6 py-5">
                          <div className={`inline-flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-[13px] font-semibold border capitalize ${adm.role === 'super_admin' ? 'bg-amber-500/15 border-amber-500/30 text-amber-500' : adm.role === 'admin' ? 'bg-violet-500/15 border-violet-500/30 text-violet-400' : 'bg-blue-500/15 border-blue-500/30 text-blue-400'}`}>
                            {adm.role.replace('_', ' ')}
                          </div>
                        </td>
                        <td className="px-6 py-5 text-sm text-slate-400">
                          {adm.last_login ? new Date(adm.last_login).toLocaleDateString('en-US', { month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit' }) : 'Never'}
                        </td>
                        <td className="px-6 py-5 text-sm text-slate-400">
                          {new Date(adm.created_at).toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' })}
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
              {admins.length === 0 && <div className="p-16 text-center text-slate-400">No admins found</div>}
            </div>
          </div>
        )}

        {/* Settings Tab */}
        {activeTab === 'settings' && (
          <ProfileSettings token={token} admin={currentAdmin}
            onUpdateAdmin={(updated) => { setCurrentAdmin(updated); localStorage.setItem('admin_info', JSON.stringify(updated)); }}
            onLogout={onLogout} />
        )}

        {/* Logs Tab */}
        {activeTab === 'logs' && admin.role === 'super_admin' && (
          <div className="animate-slideIn">
            <div className="mb-6 md:mb-8 mt-2 md:mt-0">
              <h1 className="text-3xl md:text-4xl font-bold mb-2 bg-gradient-to-br from-slate-100 to-slate-400 bg-clip-text text-transparent">Activity Logs</h1>
              <p className="text-slate-400 font-medium text-sm md:text-base">Audit trail of all admin actions</p>
            </div>
            <div className="bg-gradient-to-br from-slate-800/60 to-slate-700/30 rounded-2xl border border-white/5 p-4 md:p-8">
              {logs.map((log, index) => (
                <div key={log.id} className="p-4 md:p-5 bg-slate-900/40 rounded-xl mb-3 border border-white/5 animate-slideIn" style={{ animationDelay: `${index * 50}ms` }}>
                  <div className="flex flex-col md:flex-row md:justify-between md:items-start mb-3 gap-2">
                    <div className="flex items-center gap-3">
                      <div className="w-9 h-9 bg-blue-500/15 rounded-lg flex items-center justify-center flex-shrink-0"><Activity size={18} className="text-blue-500" /></div>
                      <div>
                        <div className="text-[15px] font-semibold text-slate-100 mb-1">{log.action.replace(/_/g, ' ').replace(/\b\w/g, l => l.toUpperCase())}</div>
                        <div className="text-[13px] text-slate-500">by {log.admin_email}</div>
                      </div>
                    </div>
                    <div className="text-[13px] text-slate-500 pl-12 md:pl-0">{new Date(log.timestamp).toLocaleString()}</div>
                  </div>
                  {log.details && <div className="p-3 bg-slate-800/50 rounded-lg text-[13px] text-slate-400 font-mono ml-0 md:ml-12">{log.details}</div>}
                </div>
              ))}
              {logs.length === 0 && <div className="p-16 text-center text-slate-400">No activity logs found</div>}
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
                  { label: 'Total Users', value: broadcastStats.total_users, sublabel: `${broadcastStats.users_with_push_enabled} with push`, color: 'text-blue-500', bg: 'bg-blue-500/10' },
                  { label: 'Free Users', value: broadcastStats.free_users, sublabel: `${broadcastStats.free_with_push} with push`, color: 'text-emerald-500', bg: 'bg-emerald-500/10' },
                  { label: 'Premium Users', value: broadcastStats.premium_users, sublabel: `${broadcastStats.premium_with_push} with push`, color: 'text-amber-500', bg: 'bg-amber-500/10' },
                ].map((stat, index) => (
                  <div key={index} className="bg-gradient-to-br from-slate-800/60 to-slate-700/30 p-5 md:p-7 rounded-2xl border border-white/5 shadow-xl">
                    <div className={`w-12 h-12 md:w-14 md:h-14 ${stat.bg} rounded-2xl flex items-center justify-center mb-5`}>
                      <Users size={24} className={`md:w-7 md:h-7 ${stat.color}`} strokeWidth={2} />
                    </div>
                    <div className="text-3xl md:text-4xl font-bold text-slate-100 mb-2">{stat.value.toLocaleString()}</div>
                    <div className="text-sm text-slate-400 font-medium mb-1">{stat.label}</div>
                    <div className="text-xs text-slate-500">{stat.sublabel}</div>
                  </div>
                ))}
              </div>
            )}
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
                        <div className="text-sm opacity-70">{option.count?.toLocaleString() || 0} users</div>
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
          </div>
        )}
      </div>

      {/* User Detail Modal */}
      {selectedUser && (
        <div className="fixed inset-0 bg-black/70 backdrop-blur-sm flex items-center justify-center z-50 animate-fadeIn p-4" onClick={() => setSelectedUser(null)}>
          <div className="bg-gradient-to-br from-slate-800 to-slate-700 rounded-3xl p-6 md:p-10 max-w-xl w-full max-h-[90vh] overflow-y-auto border border-white/10 shadow-2xl animate-slideIn" onClick={(e) => e.stopPropagation()}>
            <div className="flex items-center gap-4 mb-8">
              <div className="w-16 h-16 bg-gradient-to-br from-blue-500 to-violet-500 rounded-2xl flex items-center justify-center text-2xl font-bold text-white shadow-lg flex-shrink-0">{selectedUser.name.charAt(0).toUpperCase()}</div>
              <div className="flex-1 min-w-0">
                <h2 className="text-2xl font-bold text-slate-100 mb-1 truncate">{selectedUser.name}</h2>
                <div className="text-sm text-slate-400 truncate">{selectedUser.email}</div>
              </div>
            </div>

            <div className="mb-8">
              <h3 className="text-xs font-bold text-slate-400 mb-4 uppercase tracking-wider">Subscription Management</h3>
              {selectedUser.subscription_type === 'free' && (
                <>
                  <div className="p-4 bg-slate-500/10 border border-slate-500/30 rounded-xl mb-4">
                    <div className="flex items-center gap-2"><User size={18} className="text-slate-500" /><span className="text-sm font-semibold text-slate-400">Free User</span></div>
                  </div>
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
                    <input type="date" id={`expire-date-${selectedUser.id}`} min={new Date().toISOString().split('T')[0]}
                      className="w-full px-4 py-3 bg-slate-800/50 border border-slate-600/30 rounded-xl text-slate-100 text-sm outline-none focus:border-blue-500 focus:bg-slate-800/80 transition-all" />
                    <button onClick={() => {
                      const di = document.getElementById(`expire-date-${selectedUser.id}`);
                      if (!di.value) { alert('Please select an expiry date'); return; }
                      const d = new Date(di.value); d.setHours(23, 59, 59, 999);
                      handleUpdateSubscription(selectedUser.id, 'premium', d.toISOString());
                    }} className="w-full p-3 bg-blue-500/15 border border-blue-500/30 rounded-xl text-blue-400 text-sm font-semibold hover:bg-blue-500/25 transition-colors flex items-center justify-center gap-2">
                      <Crown size={16} />Upgrade to Premium
                    </button>
                  </div>
                </>
              )}
              {selectedUser.subscription_type === 'premium' && (
                <>
                  <div className="p-4 bg-amber-500/10 border border-amber-500/30 rounded-xl mb-4">
                    <div className="flex items-center justify-between mb-2">
                      <div className="flex items-center gap-2"><Crown size={18} className="text-amber-500" /><span className="text-sm font-semibold text-amber-400">Premium Active</span></div>
                      {selectedUser.subscription_expires_at && <div className="text-xs text-amber-400/80">Expires: {new Date(selectedUser.subscription_expires_at).toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' })}</div>}
                    </div>
                    {selectedUser.subscription_expires_at && <div className="text-xs text-amber-400/70">{Math.ceil((new Date(selectedUser.subscription_expires_at) - new Date()) / (1000 * 60 * 60 * 24))} days remaining</div>}
                  </div>
                  <div className="mb-3">
                    <label className="block text-slate-300 text-sm font-semibold mb-2">Extend Premium Period</label>
                    <div className="grid grid-cols-2 gap-2">
                      {[{ label: '+1 Month', days: 30 }, { label: '+3 Months', days: 90 }, { label: '+6 Months', days: 180 }, { label: '+1 Year', days: 365 }].map((preset) => (
                        <button key={preset.days} onClick={() => {
                          const cur = selectedUser.subscription_expires_at ? new Date(selectedUser.subscription_expires_at) : new Date();
                          handleUpdateSubscription(selectedUser.id, 'premium', new Date(cur.getTime() + preset.days*24*60*60*1000).toISOString());
                        }} className="p-3 bg-gradient-to-br from-blue-500/20 to-violet-600/20 border border-blue-500/30 rounded-xl text-blue-400 text-sm font-semibold hover:from-blue-500/30 hover:to-violet-600/30 transition-all">{preset.label}</button>
                      ))}
                    </div>
                  </div>
                  <div className="p-4 bg-slate-900/40 rounded-xl border border-white/5 space-y-3 mb-3">
                    <label className="block text-slate-300 text-sm font-semibold">Or Set New Expiry Date</label>
                    <input type="date" id={`expire-date-${selectedUser.id}`} min={new Date().toISOString().split('T')[0]}
                      defaultValue={selectedUser.subscription_expires_at ? new Date(selectedUser.subscription_expires_at).toISOString().split('T')[0] : ''}
                      className="w-full px-4 py-3 bg-slate-800/50 border border-slate-600/30 rounded-xl text-slate-100 text-sm outline-none focus:border-blue-500 focus:bg-slate-800/80 transition-all" />
                    <button onClick={() => {
                      const di = document.getElementById(`expire-date-${selectedUser.id}`);
                      if (!di.value) { alert('Please select an expiry date'); return; }
                      const d = new Date(di.value); d.setHours(23, 59, 59, 999);
                      handleUpdateSubscription(selectedUser.id, 'premium', d.toISOString());
                    }} className="w-full p-3 bg-blue-500/15 border border-blue-500/30 rounded-xl text-blue-400 text-sm font-semibold hover:bg-blue-500/25 transition-colors">Update Expiry Date</button>
                  </div>
                  <button onClick={() => { if (window.confirm('Downgrade to Free?')) handleUpdateSubscription(selectedUser.id, 'free', null); }}
                    className="w-full p-3.5 bg-slate-500/10 border border-slate-500/30 rounded-xl text-slate-400 text-sm font-semibold hover:bg-slate-500/20 transition-colors">Downgrade to Free</button>
                </>
              )}
            </div>

            <div className="mb-8">
              <h3 className="text-xs font-bold text-slate-400 mb-4 uppercase tracking-wider">Statistics</h3>
              <div className="grid grid-cols-2 gap-4">
                {[
                  { label: 'Transactions', value: selectedUser.total_transactions, icon: DollarSign },
                  { label: 'Goals', value: selectedUser.total_goals, icon: Target },
                  { label: 'Currency', value: selectedUser.default_currency.toUpperCase(), icon: DollarSign },
                  { label: 'Joined', value: new Date(selectedUser.created_at).toLocaleDateString('en-US', { month: 'short', year: 'numeric' }), icon: Calendar },
                ].map((stat, index) => (
                  <div key={index} className="p-4 bg-slate-900/40 rounded-xl border border-white/5">
                    <div className="flex items-center gap-2 mb-2"><stat.icon size={16} className="text-slate-500" /><div className="text-[13px] text-slate-500 truncate">{stat.label}</div></div>
                    <div className="text-lg md:text-xl font-bold text-slate-100 truncate">{stat.value}</div>
                  </div>
                ))}
              </div>
            </div>

            {admin.role === 'super_admin' && (
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
      {showCreateAdmin && (
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
                  {[{ value: 'moderator', label: 'Moderator', desc: 'Basic access' }, { value: 'admin', label: 'Admin', desc: 'Full access' }, { value: 'super_admin', label: 'Super Admin', desc: 'All privileges' }].map(role => (
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
  const [token, setToken] = useState(null);
  const [admin, setAdmin] = useState(null);

  useEffect(() => {
    const savedToken = localStorage.getItem('admin_token');
    const savedAdmin = localStorage.getItem('admin_info');
    if (savedToken && savedAdmin) { setToken(savedToken); setAdmin(JSON.parse(savedAdmin)); }
  }, []);

  const handleLogin = (accessToken, adminInfo) => {
    setToken(accessToken); setAdmin(adminInfo);
    localStorage.setItem('admin_token', accessToken);
    localStorage.setItem('admin_info', JSON.stringify(adminInfo));
  };

  const handleLogout = () => {
    setToken(null); setAdmin(null);
    localStorage.removeItem('admin_token');
    localStorage.removeItem('admin_info');
  };

  if (!token || !admin) return <LoginPage onLogin={handleLogin} />;
  return <Dashboard token={token} admin={admin} onLogout={handleLogout} />;
}