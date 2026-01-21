import React, { useState, useEffect } from 'react';
import { Users, Shield, BarChart3, Activity, Search, LogOut, TrendingUp, AlertCircle, Crown, Zap, Eye, Trash2, RefreshCw, Calendar, DollarSign, Target, Send } from 'lucide-react';

// API Configuration
const API_BASE_URL = 'http://localhost:8000';

// API Service (Kept exactly as original)
const api = {
  async login(email, password) {
    const response = await fetch(`${API_BASE_URL}/api/admin/login`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email, password })
    });
    if (!response.ok) throw new Error('Login failed');
    return response.json();
  },
  async getMe(token) {
    const response = await fetch(`${API_BASE_URL}/api/admin/me`, {
      headers: { 'Authorization': `Bearer ${token}` }
    });
    if (!response.ok) throw new Error('Failed to fetch admin info');
    return response.json();
  },
  async getUsers(token, params = {}) {
    const queryString = new URLSearchParams(params).toString();
    const response = await fetch(`${API_BASE_URL}/api/admin/users?${queryString}`, {
      headers: { 'Authorization': `Bearer ${token}` }
    });
    if (!response.ok) throw new Error('Failed to fetch users');
    return response.json();
  },
  async getUserDetail(token, userId) {
    const response = await fetch(`${API_BASE_URL}/api/admin/users/${userId}`, {
      headers: { 'Authorization': `Bearer ${token}` }
    });
    if (!response.ok) throw new Error('Failed to fetch user details');
    return response.json();
  },
  async updateUserSubscription(token, userId, data) {
    const response = await fetch(`${API_BASE_URL}/api/admin/users/${userId}/subscription`, {
      method: 'PUT',
      headers: { 
        'Authorization': `Bearer ${token}`,
        'Content-Type': 'application/json'
      },
      body: JSON.stringify(data)
    });
    if (!response.ok) throw new Error('Failed to update subscription');
    return response.json();
  },
  async getUserStats(token) {
    const response = await fetch(`${API_BASE_URL}/api/admin/stats/users`, {
      headers: { 'Authorization': `Bearer ${token}` }
    });
    if (!response.ok) throw new Error('Failed to fetch stats');
    return response.json();
  },
  async getSystemStats(token) {
    const response = await fetch(`${API_BASE_URL}/api/admin/stats/system`, {
      headers: { 'Authorization': `Bearer ${token}` }
    });
    if (!response.ok) throw new Error('Failed to fetch system stats');
    return response.json();
  },
  async getAdmins(token) {
    const response = await fetch(`${API_BASE_URL}/api/admin/admins`, {
      headers: { 'Authorization': `Bearer ${token}` }
    });
    if (!response.ok) throw new Error('Failed to fetch admins');
    return response.json();
  },
  async createAdmin(token, data) {
    const response = await fetch(`${API_BASE_URL}/api/admin/admins`, {
      method: 'POST',
      headers: { 
        'Authorization': `Bearer ${token}`,
        'Content-Type': 'application/json'
      },
      body: JSON.stringify(data)
    });
    if (!response.ok) throw new Error('Failed to create admin');
    return response.json();
  },
  async deleteUser(token, userId) {
    const response = await fetch(`${API_BASE_URL}/api/admin/users/${userId}`, {
      method: 'DELETE',
      headers: { 'Authorization': `Bearer ${token}` }
    });
    if (!response.ok) throw new Error('Failed to delete user');
    return response.json();
  },
  async getLogs(token, params = {}) {
    const queryString = new URLSearchParams(params).toString();
    const response = await fetch(`${API_BASE_URL}/api/admin/logs?${queryString}`, {
      headers: { 'Authorization': `Bearer ${token}` }
    });
    if (!response.ok) throw new Error('Failed to fetch logs');
    return response.json();
  },

    async getBroadcastStats(token) {
    const response = await fetch(`${API_BASE_URL}/api/admin/broadcast-stats`, {
      headers: { 'Authorization': `Bearer ${token}` }
    });
    if (!response.ok) throw new Error('Failed to fetch broadcast stats');
    return response.json();
  },
  
  async sendBroadcastNotification(token, data) {
    const response = await fetch(`${API_BASE_URL}/api/admin/broadcast-notification`, {
      method: 'POST',
      headers: { 
        'Authorization': `Bearer ${token}`,
        'Content-Type': 'application/json'
      },
      body: JSON.stringify(data)
    });
    if (!response.ok) throw new Error('Failed to send broadcast notification');
    return response.json();
  }
};

// Login Component
const LoginPage = ({ onLogin }) => {
  const [email, setEmail] = useState('admin@flowfinance.com');
  const [password, setPassword] = useState('admin123');
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
      setError('Invalid credentials. Please try again.');
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="min-h-screen bg-gradient-to-br from-slate-900 via-slate-800 to-slate-700 flex items-center justify-center font-sans relative overflow-hidden text-slate-200">
      {/* Animated background elements */}
      <div className="absolute top-[10%] left-[5%] w-[500px] h-[500px] rounded-full bg-blue-500/15 blur-[60px] animate-float" />
      <div className="absolute bottom-[10%] right-[5%] w-[400px] h-[400px] rounded-full bg-purple-500/15 blur-[60px] animate-float-reverse" />

      <div className="bg-slate-900/70 backdrop-blur-xl rounded-3xl p-12 w-full max-w-md shadow-2xl border border-white/10 relative z-10 animate-slideUp">
        {/* Logo/Icon */}
        <div className="w-[72px] h-[72px] bg-gradient-to-br from-blue-500 to-violet-500 rounded-2xl flex items-center justify-center mx-auto mb-6 shadow-lg shadow-blue-500/30">
          <Shield size={36} className="text-white" strokeWidth={2.5} />
        </div>

        <h1 className="text-3xl font-bold text-center mb-2 bg-gradient-to-br from-slate-100 to-slate-300 bg-clip-text text-transparent tracking-tight">
          Admin Portal
        </h1>
        
        <p className="text-center text-slate-400 text-[15px] mb-8 font-medium">
          Flow Finance Admin Dashboard
        </p>

        {error && (
          <div className="bg-red-500/10 border border-red-500/30 rounded-xl p-3 mb-6 flex items-center gap-3 animate-slideUp">
            <AlertCircle size={18} className="text-red-500" />
            <span className="text-red-300 text-sm">{error}</span>
          </div>
        )}

        <form onSubmit={handleSubmit} className="space-y-5">
          <div>
            <label className="block text-slate-300 text-sm font-semibold mb-2 tracking-wide">
              Email Address
            </label>
            <input
              type="email"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              required
              className="w-full px-4 py-3.5 bg-slate-800/50 border border-slate-600/30 rounded-xl text-slate-100 text-[15px] outline-none transition-all duration-200 focus:border-blue-500 focus:bg-slate-800/80"
            />
          </div>

          <div>
            <label className="block text-slate-300 text-sm font-semibold mb-2 tracking-wide">
              Password
            </label>
            <input
              type="password"
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              required
              className="w-full px-4 py-3.5 bg-slate-800/50 border border-slate-600/30 rounded-xl text-slate-100 text-[15px] outline-none transition-all duration-200 focus:border-blue-500 focus:bg-slate-800/80"
            />
          </div>

          <button
            type="submit"
            disabled={loading}
            className={`w-full py-4 rounded-xl text-white text-base font-semibold transition-all duration-300 shadow-lg tracking-wide ${
              loading 
                ? 'bg-slate-600 cursor-not-allowed' 
                : 'bg-gradient-to-br from-blue-500 to-violet-500 hover:-translate-y-0.5 hover:shadow-blue-500/40 shadow-blue-500/30 cursor-pointer'
            }`}
          >
            {loading ? 'Signing in...' : 'Sign In'}
          </button>
        </form>

        <p className="text-center text-slate-500 text-xs mt-6">
          Default: admin@flowfinance.com / admin123
        </p>
      </div>
    </div>
  );
};

// Dashboard Component
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
    title: '',
    message: '',
    target_users: 'all',
    notification_type: 'system_broadcast'
  });
  const [broadcastLoading, setBroadcastLoading] = useState(false);

  useEffect(() => {
    loadData();
  }, [activeTab]);

  const loadData = async () => {
    setLoading(true);
    try {
      if (activeTab === 'overview') {
        const [userStats, sysStats] = await Promise.all([
          api.getUserStats(token),
          api.getSystemStats(token)
        ]);
        setStats(userStats);
        setSystemStats(sysStats);
      } else if (activeTab === 'users') {
        const params = {};
        if (searchQuery) params.search = searchQuery;
        if (subscriptionFilter) params.subscription_type = subscriptionFilter;
        params.limit = 100;
        const usersData = await api.getUsers(token, params);
        setUsers(usersData);
      } else if (activeTab === 'broadcast') {  // ADD THIS
        const stats = await api.getBroadcastStats(token);
        setBroadcastStats(stats);
      } else if (activeTab === 'admins' && admin.role === 'super_admin') {
        const adminsData = await api.getAdmins(token);
        setAdmins(adminsData);
      } else if (activeTab === 'logs' && admin.role === 'super_admin') {
        const logsData = await api.getLogs(token, { limit: 50 });
        setLogs(logsData);
      }
    } catch (error) {
      console.error('Error loading data:', error);
    } finally {
      setLoading(false);
    }
  };

  const handleSearch = () => {
    if (activeTab === 'users') {
      loadData();
    }
  };


  const handleSendBroadcast = async () => {
  if (!broadcastForm.title.trim() || !broadcastForm.message.trim()) {
    alert('Please fill in both title and message');
    return;
  }

  if (!window.confirm(`Send notification to ${broadcastForm.target_users} users?`)) {
    return;
  }

  setBroadcastLoading(true);
  try {
    const result = await api.sendBroadcastNotification(token, broadcastForm);
    
    alert(
      `Broadcast sent successfully!\n\n` +
      `Total Users: ${result.total_users}\n` +
      `Notifications Sent: ${result.notifications_sent}\n` +
      `Push Notifications: ${result.fcm_sent} sent, ${result.fcm_failed} failed`
    );
    
    // Reset form
    setBroadcastForm({
      title: '',
      message: '',
      target_users: 'all',
      notification_type: 'system_broadcast'
    });
    
    // Reload stats
    loadData();
  } catch (error) {
    alert('Failed to send broadcast: ' + error.message);
  } finally {
    setBroadcastLoading(false);
  }
};

  const handleUpdateSubscription = async (userId, subscriptionType, expiresAt) => {
    try {
      await api.updateUserSubscription(token, userId, {
        subscription_type: subscriptionType,
        subscription_expires_at: expiresAt
      });
      alert('Subscription updated successfully!');
      loadData();
      setSelectedUser(null);
    } catch (error) {
      alert('Failed to update subscription');
    }
  };

  const handleDeleteUser = async (userId) => {
    if (!window.confirm('Are you sure you want to delete this user? This action cannot be undone.')) {
      return;
    }
    try {
      await api.deleteUser(token, userId);
      alert('User deleted successfully');
      loadData();
      setSelectedUser(null);
    } catch (error) {
      alert('Failed to delete user');
    }
  };

  return (
    <div className="min-h-screen bg-[#0A0F1E] font-sans text-slate-200">
      
      {/* Sidebar */}
      <div className="fixed left-0 top-0 bottom-0 w-[280px] bg-gradient-to-b from-slate-900 to-slate-800 border-r border-white/5 p-8 flex flex-col z-10">
        {/* Logo */}
        <div className="flex items-center gap-3 mb-10 pb-6 border-b border-white/10">
          <div className="w-12 h-12 bg-gradient-to-br from-blue-500 to-violet-500 rounded-xl flex items-center justify-center shadow-lg shadow-blue-500/20">
            <Shield size={24} className="text-white" strokeWidth={2.5} />
          </div>
          <div>
            <div className="text-lg font-bold text-slate-100">Flow Finance</div>
            <div className="text-xs text-slate-400 font-medium">Admin Portal</div>
          </div>
        </div>

        {/* Navigation */}
        <nav className="flex-1 space-y-2">
          {[
              { id: 'overview', icon: BarChart3, label: 'Overview' },
              { id: 'users', icon: Users, label: 'Users' },
              { id: 'broadcast', icon: Send, label: 'Broadcast' }, // ADD THIS LINE
              ...(admin.role === 'super_admin' ? [
                { id: 'admins', icon: Shield, label: 'Admins' },
                { id: 'logs', icon: Activity, label: 'Activity Logs' }
              ] : [])
            ].map(tab => (
            <button
              key={tab.id}
              onClick={() => setActiveTab(tab.id)}
              className={`w-full p-3.5 flex items-center gap-3 rounded-xl text-[15px] font-semibold transition-all duration-200 text-left ${
                activeTab === tab.id 
                  ? 'bg-blue-500/15 border border-blue-500/30 text-blue-400' 
                  : 'bg-transparent border border-transparent text-slate-400 hover:bg-blue-500/10'
              }`}
            >
              <tab.icon size={20} />
              {tab.label}
            </button>
          ))}
        </nav>

        {/* Admin Info */}
        <div className="p-4 bg-slate-800/50 rounded-xl border border-white/5">
          <div className="flex items-center gap-3 mb-3">
            <div className="w-10 h-10 bg-gradient-to-br from-violet-500 to-pink-500 rounded-lg flex items-center justify-center text-white font-bold shadow-sm">
              {admin.name.charAt(0)}
            </div>
            <div className="flex-1 min-w-0">
              <div className="text-sm font-semibold text-slate-100 mb-0.5 truncate">
                {admin.name}
              </div>
              <div className="text-xs text-slate-400 capitalize flex items-center gap-1">
                {admin.role === 'super_admin' && <Crown size={12} className="text-amber-500" />}
                {admin.role.replace('_', ' ')}
              </div>
            </div>
          </div>
          <button
            onClick={onLogout}
            className="w-full p-2.5 bg-red-500/10 border border-red-500/30 rounded-lg text-red-400 text-sm font-semibold flex items-center justify-center gap-2 hover:bg-red-500/20 transition-colors"
          >
            <LogOut size={16} />
            Sign Out
          </button>
        </div>
      </div>

      {/* Main Content */}
      <div className="ml-[280px] p-10">
        {/* Overview Tab */}
        {activeTab === 'overview' && stats && systemStats && (
          <div className="animate-slideIn">
            <div className="mb-8">
              <h1 className="text-4xl font-bold mb-2 bg-gradient-to-br from-slate-100 to-slate-400 bg-clip-text text-transparent">
                Dashboard Overview
              </h1>
              <p className="text-slate-400 font-medium">
                Welcome back, {admin.name}. Here's what's happening today.
              </p>
            </div>

            {/* Stats Grid */}
            <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6 mb-10">
              {[
                { label: 'Total Users', value: stats.total_users, icon: Users, color: 'text-blue-500', bg: 'bg-blue-500/10' },
                { label: 'Premium Users', value: stats.premium_users, icon: Crown, color: 'text-amber-500', bg: 'bg-amber-500/10' },
                { label: 'Free Users', value: stats.free_users, icon: Users, color: 'text-emerald-500', bg: 'bg-emerald-500/10' },
                { label: 'Active (7 days)', value: stats.active_users_last_7_days, icon: Activity, color: 'text-violet-500', bg: 'bg-violet-500/10' },
                { label: 'New Users (30d)', value: stats.new_users_last_30_days, icon: TrendingUp, color: 'text-pink-500', bg: 'bg-pink-500/10' },
                { label: 'Total Transactions', value: stats.total_transactions, icon: DollarSign, color: 'text-cyan-500', bg: 'bg-cyan-500/10' },
                { label: 'Total Goals', value: stats.total_goals, icon: Target, color: 'text-orange-500', bg: 'bg-orange-500/10' },
                { label: 'Active Today', value: systemStats.active_users_today, icon: Zap, color: 'text-yellow-500', bg: 'bg-yellow-500/10' }
              ].map((stat, index) => (
                <div
                  key={index}
                  className="bg-gradient-to-br from-slate-800/60 to-slate-700/30 p-7 rounded-2xl border border-white/5 shadow-xl hover:-translate-y-1 hover:shadow-2xl transition-all duration-300 animate-slideIn"
                  style={{ animationDelay: `${index * 100}ms` }}
                >
                  <div className="flex justify-between items-start mb-5">
                    <div className={`w-14 h-14 ${stat.bg} rounded-2xl flex items-center justify-center`}>
                      <stat.icon size={28} className={stat.color} strokeWidth={2} />
                    </div>
                  </div>
                  <div className="text-4xl font-bold text-slate-100 mb-2">
                    {stat.value.toLocaleString()}
                  </div>
                  <div className="text-sm text-slate-400 font-medium">
                    {stat.label}
                  </div>
                </div>
              ))}
            </div>

            {/* Activity Summary */}
            <div className="bg-gradient-to-br from-slate-800/60 to-slate-700/30 p-8 rounded-2xl border border-white/5">
              <h2 className="text-2xl font-bold mb-6 text-slate-100">
                Recent Activity
              </h2>
              <div className="grid grid-cols-1 md:grid-cols-4 gap-6">
                {[
                    { label: 'New Today', value: systemStats.new_users_today, color: 'text-blue-500' },
                    { label: 'New This Week', value: systemStats.new_users_this_week, color: 'text-violet-500' },
                    { label: 'New This Month', value: systemStats.new_users_this_month, color: 'text-pink-500' },
                    { label: 'Active This Week', value: systemStats.active_users_this_week, color: 'text-emerald-500' }
                ].map((item, idx) => (
                    <div key={idx}>
                        <div className="text-sm text-slate-400 mb-2">{item.label}</div>
                        <div className={`text-3xl font-bold ${item.color}`}>
                            {item.value}
                        </div>
                    </div>
                ))}
              </div>
            </div>
          </div>
        )}

        {/* Users Tab */}
        {activeTab === 'users' && (
          <div className="animate-slideIn">
            <div className="mb-8">
              <h1 className="text-4xl font-bold mb-2 bg-gradient-to-br from-slate-100 to-slate-400 bg-clip-text text-transparent">
                User Management
              </h1>
              <p className="text-slate-400 font-medium">
                Manage user accounts and subscriptions
              </p>
            </div>

            {/* Search and Filters */}
            <div className="bg-gradient-to-br from-slate-800/60 to-slate-700/30 p-6 rounded-2xl border border-white/5 mb-6 flex gap-4 flex-wrap">
              <div className="flex-1 min-w-[250px]">
                <input
                  type="text"
                  placeholder="Search by name or email..."
                  value={searchQuery}
                  onChange={(e) => setSearchQuery(e.target.value)}
                  onKeyPress={(e) => e.key === 'Enter' && handleSearch()}
                  className="w-full px-4 py-3.5 bg-slate-900/50 border border-slate-600/20 rounded-xl text-slate-100 text-[15px] outline-none focus:border-blue-500/50"
                />
              </div>
              <select
                value={subscriptionFilter}
                onChange={(e) => setSubscriptionFilter(e.target.value)}
                className="px-4 py-3.5 bg-slate-900/50 border border-slate-600/20 rounded-xl text-slate-100 text-[15px] outline-none cursor-pointer focus:border-blue-500/50"
              >
                <option value="">All Subscriptions</option>
                <option value="free">Free</option>
                <option value="premium">Premium</option>
              </select>
              <button
                onClick={handleSearch}
                className="px-6 py-3.5 bg-gradient-to-br from-blue-500 to-violet-500 rounded-xl text-white text-[15px] font-semibold flex items-center gap-2 hover:-translate-y-0.5 transition-transform"
              >
                <Search size={18} />
                Search
              </button>
              <button
                onClick={() => { setSearchQuery(''); setSubscriptionFilter(''); loadData(); }}
                className="px-6 py-3.5 bg-slate-500/20 border border-slate-400/20 rounded-xl text-slate-400 text-[15px] font-semibold flex items-center gap-2 hover:bg-slate-500/30 transition-colors"
              >
                <RefreshCw size={18} />
                Reset
              </button>
            </div>

            {/* Users Table */}
            <div className="bg-gradient-to-br from-slate-800/60 to-slate-700/30 rounded-2xl border border-white/5 overflow-hidden">
              <div className="overflow-x-auto">
                <table className="w-full border-collapse">
                  <thead>
                    <tr className="bg-slate-900/50 border-b border-white/5">
                      {['User', 'Subscription', 'Activity', 'Joined', 'Actions'].map((header, i) => (
                          <th key={i} className={`px-6 py-4 text-left text-slate-400 text-xs font-semibold tracking-wider uppercase ${i === 4 ? 'text-center' : ''}`}>
                              {header}
                          </th>
                      ))}
                    </tr>
                  </thead>
                  <tbody>
                    {users.map((user, index) => (
                      <tr
                        key={user.id}
                        className="border-b border-white/5 hover:bg-slate-800/50 hover:translate-x-1 transition-all duration-200 animate-slideIn"
                        style={{ animationDelay: `${index * 50}ms` }}
                      >
                        <td className="px-6 py-5">
                          <div className="flex items-center gap-3">
                            <div className="w-11 h-11 bg-gradient-to-br from-blue-500 to-violet-500 rounded-xl flex items-center justify-center text-white font-bold shadow-md">
                              {user.name.charAt(0).toUpperCase()}
                            </div>
                            <div>
                              <div className="text-[15px] font-semibold text-slate-100 mb-1">
                                {user.name}
                              </div>
                              <div className="text-xs text-slate-400">
                                {user.email}
                              </div>
                            </div>
                          </div>
                        </td>
                        <td className="px-6 py-5">
                          <div className={`inline-flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-[13px] font-semibold border ${
                            user.subscription_type === 'premium' 
                            ? 'bg-amber-500/15 border-amber-500/30 text-amber-500' 
                            : 'bg-slate-500/15 border-slate-500/30 text-slate-400'
                          }`}>
                            {user.subscription_type === 'premium' && <Crown size={14} />}
                            {user.subscription_type.toUpperCase()}
                          </div>
                        </td>
                        <td className="px-6 py-5">
                          <div className="text-sm text-slate-300 mb-1">
                            {user.total_transactions} transactions
                          </div>
                          <div className="text-xs text-slate-500">
                            {user.total_goals} goals
                          </div>
                        </td>
                        <td className="px-6 py-5 text-sm text-slate-400">
                          {new Date(user.created_at).toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' })}
                        </td>
                        <td className="px-6 py-5 text-center">
                          <button
                            onClick={() => setSelectedUser(user)}
                            className="inline-flex items-center gap-1.5 px-4 py-2 bg-blue-500/15 border border-blue-500/30 rounded-lg text-blue-400 text-[13px] font-semibold hover:bg-blue-500/25 transition-colors"
                          >
                            <Eye size={14} />
                            View
                          </button>
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
              {users.length === 0 && (
                <div className="p-16 text-center text-slate-400">
                  No users found
                </div>
              )}
            </div>
          </div>
        )}

        {/* Admins Tab */}
        {activeTab === 'admins' && admin.role === 'super_admin' && (
          <div className="animate-slideIn">
            <div className="mb-8">
              <h1 className="text-4xl font-bold mb-2 bg-gradient-to-br from-slate-100 to-slate-400 bg-clip-text text-transparent">
                Admin Management
              </h1>
              <p className="text-slate-400 font-medium">
                Manage administrator accounts
              </p>
            </div>

            <div className="bg-gradient-to-br from-slate-800/60 to-slate-700/30 rounded-2xl border border-white/5 p-8">
              {admins.map((adm, index) => (
                <div
                  key={adm.id}
                  className="flex items-center justify-between p-5 bg-slate-900/40 rounded-xl mb-4 border border-white/5 animate-slideIn"
                  style={{ animationDelay: `${index * 100}ms` }}
                >
                  <div className="flex items-center gap-4">
                    <div className="w-12 h-12 bg-gradient-to-br from-violet-500 to-pink-500 rounded-xl flex items-center justify-center text-lg font-bold text-white shadow-md">
                      {adm.name.charAt(0)}
                    </div>
                    <div>
                      <div className="text-base font-semibold text-slate-100 mb-1 flex items-center gap-2">
                        {adm.name}
                        {adm.role === 'super_admin' && <Crown size={16} className="text-amber-500" />}
                      </div>
                      <div className="text-sm text-slate-500">
                        {adm.email}
                      </div>
                    </div>
                  </div>
                  <div className={`px-3 py-1.5 rounded-lg text-[13px] font-semibold border capitalize ${
                    adm.role === 'super_admin' 
                    ? 'bg-amber-500/15 border-amber-500/30 text-amber-500' 
                    : 'bg-violet-500/15 border-violet-500/30 text-violet-400'
                  }`}>
                    {adm.role.replace('_', ' ')}
                  </div>
                </div>
              ))}
            </div>
          </div>
        )}

        {/* Logs Tab */}
        {activeTab === 'logs' && admin.role === 'super_admin' && (
          <div className="animate-slideIn">
            <div className="mb-8">
              <h1 className="text-4xl font-bold mb-2 bg-gradient-to-br from-slate-100 to-slate-400 bg-clip-text text-transparent">
                Activity Logs
              </h1>
              <p className="text-slate-400 font-medium">
                Audit trail of all admin actions
              </p>
            </div>

            <div className="bg-gradient-to-br from-slate-800/60 to-slate-700/30 rounded-2xl border border-white/5 p-8">
              {logs.map((log, index) => (
                <div
                  key={log.id}
                  className="p-5 bg-slate-900/40 rounded-xl mb-3 border border-white/5 animate-slideIn"
                  style={{ animationDelay: `${index * 50}ms` }}
                >
                  <div className="flex justify-between items-start mb-3">
                    <div className="flex items-center gap-3">
                      <div className="w-9 h-9 bg-blue-500/15 rounded-lg flex items-center justify-center">
                        <Activity size={18} className="text-blue-500" />
                      </div>
                      <div>
                        <div className="text-[15px] font-semibold text-slate-100 mb-1">
                          {log.action.replace(/_/g, ' ').replace(/\b\w/g, l => l.toUpperCase())}
                        </div>
                        <div className="text-[13px] text-slate-500">
                          by {log.admin_email}
                        </div>
                      </div>
                    </div>
                    <div className="text-[13px] text-slate-500">
                      {new Date(log.timestamp).toLocaleString()}
                    </div>
                  </div>
                  {log.details && (
                    <div className="p-3 bg-slate-800/50 rounded-lg text-[13px] text-slate-400 font-mono">
                      {log.details}
                    </div>
                  )}
                </div>
              ))}
              {logs.length === 0 && (
                <div className="p-16 text-center text-slate-400">
                  No activity logs found
                </div>
              )}
            </div>
          </div>
        )}



        {/* Broadcast Tab */}
        {activeTab === 'broadcast' && (
          <div className="animate-slideIn">
            <div className="mb-8">
              <h1 className="text-4xl font-bold mb-2 bg-gradient-to-br from-slate-100 to-slate-400 bg-clip-text text-transparent">
                Broadcast Notifications
              </h1>
              <p className="text-slate-400 font-medium">
                Send notifications to all users or specific groups
              </p>
            </div>

            {/* Stats Cards */}
            {broadcastStats && (
              <div className="grid grid-cols-1 md:grid-cols-3 gap-6 mb-8">
                {[
                  { label: 'Total Users', value: broadcastStats.total_users, sublabel: `${broadcastStats.users_with_push_enabled} with push`, color: 'text-blue-500', bg: 'bg-blue-500/10' },
                  { label: 'Free Users', value: broadcastStats.free_users, sublabel: `${broadcastStats.free_with_push} with push`, color: 'text-emerald-500', bg: 'bg-emerald-500/10' },
                  { label: 'Premium Users', value: broadcastStats.premium_users, sublabel: `${broadcastStats.premium_with_push} with push`, color: 'text-amber-500', bg: 'bg-amber-500/10' }
                ].map((stat, index) => (
                  <div
                    key={index}
                    className="bg-gradient-to-br from-slate-800/60 to-slate-700/30 p-7 rounded-2xl border border-white/5 shadow-xl"
                  >
                    <div className="flex justify-between items-start mb-5">
                      <div className={`w-14 h-14 ${stat.bg} rounded-2xl flex items-center justify-center`}>
                        <Users size={28} className={stat.color} strokeWidth={2} />
                      </div>
                    </div>
                    <div className="text-4xl font-bold text-slate-100 mb-2">
                      {stat.value.toLocaleString()}
                    </div>
                    <div className="text-sm text-slate-400 font-medium mb-1">
                      {stat.label}
                    </div>
                    <div className="text-xs text-slate-500">
                      {stat.sublabel}
                    </div>
                  </div>
                ))}
              </div>
            )}

            {/* Broadcast Form */}
            <div className="bg-gradient-to-br from-slate-800/60 to-slate-700/30 rounded-2xl border border-white/5 p-8">
              <h2 className="text-2xl font-bold mb-6 text-slate-100">
                Send Broadcast Notification
              </h2>
              
              <div className="space-y-6">
                {/* Target Users */}
                <div>
                  <label className="block text-slate-300 text-sm font-semibold mb-3">
                    Target Users
                  </label>
                  <div className="grid grid-cols-3 gap-4">
                    {[
                      { value: 'all', label: 'All Users', count: broadcastStats?.total_users },
                      { value: 'free', label: 'Free Users', count: broadcastStats?.free_users },
                      { value: 'premium', label: 'Premium Users', count: broadcastStats?.premium_users }
                    ].map(option => (
                      <button
                        key={option.value}
                        onClick={() => setBroadcastForm({...broadcastForm, target_users: option.value})}
                        className={`p-4 rounded-xl border-2 transition-all ${
                          broadcastForm.target_users === option.value
                            ? 'border-blue-500 bg-blue-500/10 text-blue-400'
                            : 'border-slate-600/30 bg-slate-800/50 text-slate-400 hover:border-slate-500/50'
                        }`}
                      >
                        <div className="text-lg font-bold mb-1">{option.label}</div>
                        <div className="text-sm opacity-70">{option.count?.toLocaleString() || 0} users</div>
                      </button>
                    ))}
                  </div>
                </div>

                {/* Notification Type */}
                <div>
                  <label className="block text-slate-300 text-sm font-semibold mb-3">
                    Notification Type
                  </label>
                  <select
                    value={broadcastForm.notification_type}
                    onChange={(e) => setBroadcastForm({...broadcastForm, notification_type: e.target.value})}
                    className="w-full px-4 py-3.5 bg-slate-800/50 border border-slate-600/30 rounded-xl text-slate-100 text-[15px] outline-none cursor-pointer focus:border-blue-500"
                  >
                    <option value="system_broadcast">System Broadcast</option>
                    <option value="admin_announcement">Admin Announcement</option>
                  </select>
                </div>

                {/* Title */}
                <div>
                  <label className="block text-slate-300 text-sm font-semibold mb-3">
                    Title
                  </label>
                  <input
                    type="text"
                    value={broadcastForm.title}
                    onChange={(e) => setBroadcastForm({...broadcastForm, title: e.target.value})}
                    placeholder="Enter notification title..."
                    className="w-full px-4 py-3.5 bg-slate-800/50 border border-slate-600/30 rounded-xl text-slate-100 text-[15px] outline-none transition-all duration-200 focus:border-blue-500 focus:bg-slate-800/80"
                    maxLength={100}
                  />
                  <div className="text-xs text-slate-500 mt-2">
                    {broadcastForm.title.length}/100 characters
                  </div>
                </div>

                {/* Message */}
                <div>
                  <label className="block text-slate-300 text-sm font-semibold mb-3">
                    Message
                  </label>
                  <textarea
                    value={broadcastForm.message}
                    onChange={(e) => setBroadcastForm({...broadcastForm, message: e.target.value})}
                    placeholder="Enter notification message..."
                    rows={6}
                    className="w-full px-4 py-3.5 bg-slate-800/50 border border-slate-600/30 rounded-xl text-slate-100 text-[15px] outline-none transition-all duration-200 focus:border-blue-500 focus:bg-slate-800/80 resize-none"
                    maxLength={500}
                  />
                  <div className="text-xs text-slate-500 mt-2">
                    {broadcastForm.message.length}/500 characters
                  </div>
                </div>

                {/* Send Button */}
                <button
                  onClick={handleSendBroadcast}
                  disabled={broadcastLoading || !broadcastForm.title.trim() || !broadcastForm.message.trim()}
                  className={`w-full py-4 rounded-xl text-white text-base font-semibold transition-all duration-300 shadow-lg flex items-center justify-center gap-3 ${
                    broadcastLoading || !broadcastForm.title.trim() || !broadcastForm.message.trim()
                      ? 'bg-slate-600 cursor-not-allowed'
                      : 'bg-gradient-to-br from-blue-500 to-violet-500 hover:-translate-y-0.5 hover:shadow-blue-500/40 shadow-blue-500/30'
                  }`}
                >
                  {broadcastLoading ? (
                    <>
                      <RefreshCw size={20} className="animate-spin" />
                      Sending...
                    </>
                  ) : (
                    <>
                      <Send size={20} />
                      Send Broadcast Notification
                    </>
                  )}
                </button>

                {/* Warning */}
                <div className="bg-amber-500/10 border border-amber-500/30 rounded-xl p-4 flex items-start gap-3">
                  <AlertCircle size={20} className="text-amber-500 mt-0.5 flex-shrink-0" />
                  <div className="text-sm text-amber-300">
                    <strong>Note:</strong> This will send notifications to{' '}
                    {broadcastForm.target_users === 'all' ? 'all users' :
                    broadcastForm.target_users === 'free' ? 'all free users' : 'all premium users'}.
                    Users who have disabled this notification type in their settings will not receive it.
                  </div>
                </div>
              </div>
            </div>
          </div>
        )}
      </div>

      {/* User Detail Modal */}
      {selectedUser && (
        <div 
          className="fixed inset-0 bg-black/70 backdrop-blur-sm flex items-center justify-center z-50 animate-fadeIn"
          onClick={() => setSelectedUser(null)}
        >
          <div
            className="bg-gradient-to-br from-slate-800 to-slate-700 rounded-3xl p-10 max-w-xl w-[90%] max-h-[80vh] overflow-y-auto border border-white/10 shadow-2xl animate-slideIn"
            onClick={(e) => e.stopPropagation()}
          >
            <div className="flex items-center gap-4 mb-8">
              <div className="w-16 h-16 bg-gradient-to-br from-blue-500 to-violet-500 rounded-2xl flex items-center justify-center text-2xl font-bold text-white shadow-lg">
                {selectedUser.name.charAt(0).toUpperCase()}
              </div>
              <div className="flex-1">
                <h2 className="text-2xl font-bold text-slate-100 mb-1">
                  {selectedUser.name}
                </h2>
                <div className="text-sm text-slate-400">
                  {selectedUser.email}
                </div>
              </div>
            </div>

            <div className="mb-8">
              <h3 className="text-xs font-bold text-slate-400 mb-4 uppercase tracking-wider">
                Subscription
              </h3>
              <div className="flex gap-3 mb-4">
                <button
                  onClick={() => handleUpdateSubscription(selectedUser.id, 'premium', new Date(Date.now() + 365*24*60*60*1000).toISOString())}
                  className="flex-1 p-3.5 bg-gradient-to-br from-amber-500 to-orange-600 rounded-xl text-white text-sm font-semibold flex items-center justify-center gap-2 hover:-translate-y-0.5 transition-transform"
                >
                  <Crown size={16} />
                  Upgrade to Premium
                </button>
                <button
                  onClick={() => handleUpdateSubscription(selectedUser.id, 'free', null)}
                  className="flex-1 p-3.5 bg-slate-500/20 border border-slate-500/30 rounded-xl text-slate-400 text-sm font-semibold hover:bg-slate-500/30 transition-colors"
                >
                  Downgrade to Free
                </button>
              </div>
              <div className={`inline-flex items-center gap-1.5 px-3.5 py-2 border rounded-xl text-sm font-semibold ${
                selectedUser.subscription_type === 'premium' 
                ? 'bg-amber-500/15 border-amber-500/30 text-amber-500' 
                : 'bg-slate-500/15 border-slate-500/30 text-slate-400'
              }`}>
                {selectedUser.subscription_type === 'premium' && <Crown size={16} />}
                Current: {selectedUser.subscription_type.toUpperCase()}
              </div>
            </div>

            <div className="mb-8">
              <h3 className="text-xs font-bold text-slate-400 mb-4 uppercase tracking-wider">
                Statistics
              </h3>
              <div className="grid grid-cols-2 gap-4">
                {[
                  { label: 'Transactions', value: selectedUser.total_transactions, icon: DollarSign },
                  { label: 'Goals', value: selectedUser.total_goals, icon: Target },
                  { label: 'Currency', value: selectedUser.default_currency.toUpperCase(), icon: DollarSign },
                  { label: 'Joined', value: new Date(selectedUser.created_at).toLocaleDateString('en-US', { month: 'short', year: 'numeric' }), icon: Calendar }
                ].map((stat, index) => (
                  <div key={index} className="p-4 bg-slate-900/40 rounded-xl border border-white/5">
                    <div className="flex items-center gap-2 mb-2">
                      <stat.icon size={16} className="text-slate-500" />
                      <div className="text-[13px] text-slate-500">{stat.label}</div>
                    </div>
                    <div className="text-xl font-bold text-slate-100">
                      {stat.value}
                    </div>
                  </div>
                ))}
              </div>
            </div>

            {admin.role === 'super_admin' && (
              <div>
                <h3 className="text-xs font-bold text-slate-400 mb-4 uppercase tracking-wider">
                  Danger Zone
                </h3>
                <button
                  onClick={() => handleDeleteUser(selectedUser.id)}
                  className="w-full p-3.5 bg-red-500/10 border border-red-500/30 rounded-xl text-red-400 text-sm font-semibold flex items-center justify-center gap-2 hover:bg-red-500/20 transition-colors"
                >
                  <Trash2 size={16} />
                  Delete User Account
                </button>
              </div>
            )}

            <button
              onClick={() => setSelectedUser(null)}
              className="w-full p-3.5 bg-slate-500/20 border border-slate-500/30 rounded-xl text-slate-400 text-sm font-semibold mt-4 hover:bg-slate-500/30 transition-colors"
            >
              Close
            </button>
          </div>
        </div>
      )}
    </div>
  );
};

// Main App Component
export default function AdminApp() {
  const [token, setToken] = useState(null);
  const [admin, setAdmin] = useState(null);

  useEffect(() => {
    // Check for saved token
    const savedToken = localStorage.getItem('admin_token');
    const savedAdmin = localStorage.getItem('admin_info');
    if (savedToken && savedAdmin) {
      setToken(savedToken);
      setAdmin(JSON.parse(savedAdmin));
    }
  }, []);

  const handleLogin = (accessToken, adminInfo) => {
    setToken(accessToken);
    setAdmin(adminInfo);
    localStorage.setItem('admin_token', accessToken);
    localStorage.setItem('admin_info', JSON.stringify(adminInfo));
  };

  const handleLogout = () => {
    setToken(null);
    setAdmin(null);
    localStorage.removeItem('admin_token');
    localStorage.removeItem('admin_info');
  };

  if (!token || !admin) {
    return <LoginPage onLogin={handleLogin} />;
  }

  return <Dashboard token={token} admin={admin} onLogout={handleLogout} />;
}