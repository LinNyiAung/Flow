import React, { useState, useEffect } from 'react';
import { Users, Shield, BarChart3, Activity, Search, LogOut, Settings, TrendingUp, UserPlus, AlertCircle, CheckCircle, Clock, Crown, Zap, Eye, Trash2, RefreshCw, Calendar, DollarSign, Target, MessageSquare, Bell } from 'lucide-react';

// API Configuration
const API_BASE_URL = 'http://localhost:8000';

// API Service
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
    <div style={{
      minHeight: '100vh',
      background: 'linear-gradient(135deg, #0F172A 0%, #1E293B 50%, #334155 100%)',
      display: 'flex',
      alignItems: 'center',
      justifyContent: 'center',
      fontFamily: '"SF Pro Display", -apple-system, BlinkMacSystemFont, sans-serif',
      position: 'relative',
      overflow: 'hidden'
    }}>
      {/* Animated background elements */}
      <div style={{
        position: 'absolute',
        top: '10%',
        left: '5%',
        width: '500px',
        height: '500px',
        background: 'radial-gradient(circle, rgba(59, 130, 246, 0.15) 0%, transparent 70%)',
        borderRadius: '50%',
        filter: 'blur(60px)',
        animation: 'float 20s ease-in-out infinite'
      }} />
      <div style={{
        position: 'absolute',
        bottom: '10%',
        right: '5%',
        width: '400px',
        height: '400px',
        background: 'radial-gradient(circle, rgba(168, 85, 247, 0.15) 0%, transparent 70%)',
        borderRadius: '50%',
        filter: 'blur(60px)',
        animation: 'float 15s ease-in-out infinite reverse'
      }} />
      
      <style>{`
        @keyframes float {
          0%, 100% { transform: translate(0, 0); }
          50% { transform: translate(30px, -30px); }
        }
        @keyframes slideUp {
          from {
            opacity: 0;
            transform: translateY(30px);
          }
          to {
            opacity: 1;
            transform: translateY(0);
          }
        }
        @keyframes shimmer {
          0% { background-position: -1000px 0; }
          100% { background-position: 1000px 0; }
        }
      `}</style>

      <div style={{
        background: 'rgba(15, 23, 42, 0.7)',
        backdropFilter: 'blur(20px)',
        borderRadius: '24px',
        padding: '48px',
        width: '100%',
        maxWidth: '440px',
        boxShadow: '0 25px 50px -12px rgba(0, 0, 0, 0.5), 0 0 0 1px rgba(255, 255, 255, 0.1)',
        border: '1px solid rgba(255, 255, 255, 0.1)',
        animation: 'slideUp 0.6s ease-out',
        position: 'relative',
        zIndex: 1
      }}>
        {/* Logo/Icon */}
        <div style={{
          width: '72px',
          height: '72px',
          background: 'linear-gradient(135deg, #3B82F6 0%, #8B5CF6 100%)',
          borderRadius: '16px',
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
          margin: '0 auto 24px',
          boxShadow: '0 10px 30px rgba(59, 130, 246, 0.3)'
        }}>
          <Shield size={36} color="white" strokeWidth={2.5} />
        </div>

        <h1 style={{
          fontSize: '32px',
          fontWeight: '700',
          textAlign: 'center',
          marginBottom: '8px',
          background: 'linear-gradient(135deg, #F1F5F9 0%, #CBD5E1 100%)',
          WebkitBackgroundClip: 'text',
          WebkitTextFillColor: 'transparent',
          letterSpacing: '-0.02em'
        }}>
          Admin Portal
        </h1>
        
        <p style={{
          textAlign: 'center',
          color: '#94A3B8',
          fontSize: '15px',
          marginBottom: '32px',
          fontWeight: '500'
        }}>
          Flow Finance Admin Dashboard
        </p>

        {error && (
          <div style={{
            background: 'rgba(239, 68, 68, 0.1)',
            border: '1px solid rgba(239, 68, 68, 0.3)',
            borderRadius: '12px',
            padding: '12px 16px',
            marginBottom: '24px',
            display: 'flex',
            alignItems: 'center',
            gap: '12px',
            animation: 'slideUp 0.3s ease-out'
          }}>
            <AlertCircle size={18} color="#EF4444" />
            <span style={{ color: '#FCA5A5', fontSize: '14px' }}>{error}</span>
          </div>
        )}

        <form onSubmit={handleSubmit}>
          <div style={{ marginBottom: '20px' }}>
            <label style={{
              display: 'block',
              color: '#CBD5E1',
              fontSize: '14px',
              fontWeight: '600',
              marginBottom: '8px',
              letterSpacing: '0.01em'
            }}>
              Email Address
            </label>
            <input
              type="email"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              required
              style={{
                width: '100%',
                padding: '14px 16px',
                background: 'rgba(30, 41, 59, 0.5)',
                border: '1px solid rgba(148, 163, 184, 0.2)',
                borderRadius: '12px',
                color: '#F1F5F9',
                fontSize: '15px',
                outline: 'none',
                transition: 'all 0.2s',
                fontFamily: 'inherit'
              }}
              onFocus={(e) => {
                e.target.style.borderColor = '#3B82F6';
                e.target.style.background = 'rgba(30, 41, 59, 0.8)';
              }}
              onBlur={(e) => {
                e.target.style.borderColor = 'rgba(148, 163, 184, 0.2)';
                e.target.style.background = 'rgba(30, 41, 59, 0.5)';
              }}
            />
          </div>

          <div style={{ marginBottom: '28px' }}>
            <label style={{
              display: 'block',
              color: '#CBD5E1',
              fontSize: '14px',
              fontWeight: '600',
              marginBottom: '8px',
              letterSpacing: '0.01em'
            }}>
              Password
            </label>
            <input
              type="password"
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              required
              style={{
                width: '100%',
                padding: '14px 16px',
                background: 'rgba(30, 41, 59, 0.5)',
                border: '1px solid rgba(148, 163, 184, 0.2)',
                borderRadius: '12px',
                color: '#F1F5F9',
                fontSize: '15px',
                outline: 'none',
                transition: 'all 0.2s',
                fontFamily: 'inherit'
              }}
              onFocus={(e) => {
                e.target.style.borderColor = '#3B82F6';
                e.target.style.background = 'rgba(30, 41, 59, 0.8)';
              }}
              onBlur={(e) => {
                e.target.style.borderColor = 'rgba(148, 163, 184, 0.2)';
                e.target.style.background = 'rgba(30, 41, 59, 0.5)';
              }}
            />
          </div>

          <button
            type="submit"
            disabled={loading}
            style={{
              width: '100%',
              padding: '16px',
              background: loading ? '#475569' : 'linear-gradient(135deg, #3B82F6 0%, #8B5CF6 100%)',
              border: 'none',
              borderRadius: '12px',
              color: 'white',
              fontSize: '16px',
              fontWeight: '600',
              cursor: loading ? 'not-allowed' : 'pointer',
              transition: 'all 0.3s',
              boxShadow: loading ? 'none' : '0 10px 25px rgba(59, 130, 246, 0.3)',
              letterSpacing: '0.01em',
              fontFamily: 'inherit'
            }}
            onMouseEnter={(e) => {
              if (!loading) {
                e.target.style.transform = 'translateY(-2px)';
                e.target.style.boxShadow = '0 15px 35px rgba(59, 130, 246, 0.4)';
              }
            }}
            onMouseLeave={(e) => {
              if (!loading) {
                e.target.style.transform = 'translateY(0)';
                e.target.style.boxShadow = '0 10px 25px rgba(59, 130, 246, 0.3)';
              }
            }}
          >
            {loading ? 'Signing in...' : 'Sign In'}
          </button>
        </form>

        <p style={{
          textAlign: 'center',
          color: '#64748B',
          fontSize: '13px',
          marginTop: '24px'
        }}>
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
    <div style={{
      minHeight: '100vh',
      background: '#0A0F1E',
      fontFamily: '"SF Pro Display", -apple-system, BlinkMacSystemFont, sans-serif',
      color: '#E2E8F0'
    }}>
      <style>{`
        @keyframes slideIn {
          from {
            opacity: 0;
            transform: translateY(20px);
          }
          to {
            opacity: 1;
            transform: translateY(0);
          }
        }
        @keyframes fadeIn {
          from { opacity: 0; }
          to { opacity: 1; }
        }
        @keyframes pulse {
          0%, 100% { opacity: 1; }
          50% { opacity: 0.7; }
        }
        .stat-card {
          transition: all 0.3s ease;
        }
        .stat-card:hover {
          transform: translateY(-4px);
          box-shadow: 0 20px 40px rgba(59, 130, 246, 0.2);
        }
        .tab-button {
          transition: all 0.2s ease;
        }
        .tab-button:hover {
          background: rgba(59, 130, 246, 0.1);
        }
        .user-row {
          transition: all 0.2s ease;
        }
        .user-row:hover {
          background: rgba(30, 41, 59, 0.5);
          transform: translateX(4px);
        }
      `}</style>

      {/* Sidebar */}
      <div style={{
        position: 'fixed',
        left: 0,
        top: 0,
        bottom: 0,
        width: '280px',
        background: 'linear-gradient(180deg, #0F172A 0%, #1E293B 100%)',
        borderRight: '1px solid rgba(255, 255, 255, 0.05)',
        padding: '32px 24px',
        display: 'flex',
        flexDirection: 'column',
        zIndex: 10
      }}>
        {/* Logo */}
        <div style={{
          display: 'flex',
          alignItems: 'center',
          gap: '12px',
          marginBottom: '40px',
          paddingBottom: '24px',
          borderBottom: '1px solid rgba(255, 255, 255, 0.1)'
        }}>
          <div style={{
            width: '48px',
            height: '48px',
            background: 'linear-gradient(135deg, #3B82F6 0%, #8B5CF6 100%)',
            borderRadius: '12px',
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center'
          }}>
            <Shield size={24} color="white" strokeWidth={2.5} />
          </div>
          <div>
            <div style={{ fontSize: '18px', fontWeight: '700', color: '#F1F5F9' }}>Flow Finance</div>
            <div style={{ fontSize: '13px', color: '#64748B', fontWeight: '500' }}>Admin Portal</div>
          </div>
        </div>

        {/* Navigation */}
        <nav style={{ flex: 1 }}>
          {[
            { id: 'overview', icon: BarChart3, label: 'Overview' },
            { id: 'users', icon: Users, label: 'Users' },
            ...(admin.role === 'super_admin' ? [
              { id: 'admins', icon: Shield, label: 'Admins' },
              { id: 'logs', icon: Activity, label: 'Activity Logs' }
            ] : [])
          ].map(tab => (
            <button
              key={tab.id}
              onClick={() => setActiveTab(tab.id)}
              className="tab-button"
              style={{
                width: '100%',
                padding: '14px 16px',
                marginBottom: '8px',
                background: activeTab === tab.id ? 'rgba(59, 130, 246, 0.15)' : 'transparent',
                border: activeTab === tab.id ? '1px solid rgba(59, 130, 246, 0.3)' : '1px solid transparent',
                borderRadius: '12px',
                color: activeTab === tab.id ? '#60A5FA' : '#94A3B8',
                fontSize: '15px',
                fontWeight: '600',
                cursor: 'pointer',
                display: 'flex',
                alignItems: 'center',
                gap: '12px',
                textAlign: 'left',
                fontFamily: 'inherit'
              }}
            >
              <tab.icon size={20} />
              {tab.label}
            </button>
          ))}
        </nav>

        {/* Admin Info */}
        <div style={{
          padding: '16px',
          background: 'rgba(30, 41, 59, 0.5)',
          borderRadius: '12px',
          border: '1px solid rgba(255, 255, 255, 0.05)'
        }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: '12px', marginBottom: '12px' }}>
            <div style={{
              width: '40px',
              height: '40px',
              background: 'linear-gradient(135deg, #8B5CF6 0%, #EC4899 100%)',
              borderRadius: '10px',
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
              fontSize: '16px',
              fontWeight: '700',
              color: 'white'
            }}>
              {admin.name.charAt(0)}
            </div>
            <div style={{ flex: 1, minWidth: 0 }}>
              <div style={{ fontSize: '14px', fontWeight: '600', color: '#F1F5F9', marginBottom: '2px' }}>
                {admin.name}
              </div>
              <div style={{
                fontSize: '12px',
                color: '#64748B',
                textTransform: 'capitalize',
                display: 'flex',
                alignItems: 'center',
                gap: '4px'
              }}>
                {admin.role === 'super_admin' && <Crown size={12} color="#F59E0B" />}
                {admin.role.replace('_', ' ')}
              </div>
            </div>
          </div>
          <button
            onClick={onLogout}
            style={{
              width: '100%',
              padding: '10px',
              background: 'rgba(239, 68, 68, 0.1)',
              border: '1px solid rgba(239, 68, 68, 0.3)',
              borderRadius: '8px',
              color: '#F87171',
              fontSize: '14px',
              fontWeight: '600',
              cursor: 'pointer',
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
              gap: '8px',
              transition: 'all 0.2s',
              fontFamily: 'inherit'
            }}
            onMouseEnter={(e) => {
              e.target.style.background = 'rgba(239, 68, 68, 0.2)';
            }}
            onMouseLeave={(e) => {
              e.target.style.background = 'rgba(239, 68, 68, 0.1)';
            }}
          >
            <LogOut size={16} />
            Sign Out
          </button>
        </div>
      </div>

      {/* Main Content */}
      <div style={{ marginLeft: '280px', padding: '40px' }}>
        {/* Overview Tab */}
        {activeTab === 'overview' && stats && systemStats && (
          <div style={{ animation: 'slideIn 0.5s ease-out' }}>
            <div style={{ marginBottom: '32px' }}>
              <h1 style={{
                fontSize: '36px',
                fontWeight: '700',
                marginBottom: '8px',
                background: 'linear-gradient(135deg, #F1F5F9 0%, #94A3B8 100%)',
                WebkitBackgroundClip: 'text',
                WebkitTextFillColor: 'transparent'
              }}>
                Dashboard Overview
              </h1>
              <p style={{ color: '#64748B', fontSize: '15px' }}>
                Welcome back, {admin.name}. Here's what's happening today.
              </p>
            </div>

            {/* Stats Grid */}
            <div style={{
              display: 'grid',
              gridTemplateColumns: 'repeat(auto-fit, minmax(280px, 1fr))',
              gap: '24px',
              marginBottom: '40px'
            }}>
              {[
                { label: 'Total Users', value: stats.total_users, icon: Users, color: '#3B82F6', bg: 'rgba(59, 130, 246, 0.1)' },
                { label: 'Premium Users', value: stats.premium_users, icon: Crown, color: '#F59E0B', bg: 'rgba(245, 158, 11, 0.1)' },
                { label: 'Free Users', value: stats.free_users, icon: Users, color: '#10B981', bg: 'rgba(16, 185, 129, 0.1)' },
                { label: 'Active (7 days)', value: stats.active_users_last_7_days, icon: Activity, color: '#8B5CF6', bg: 'rgba(139, 92, 246, 0.1)' },
                { label: 'New Users (30d)', value: stats.new_users_last_30_days, icon: TrendingUp, color: '#EC4899', bg: 'rgba(236, 72, 153, 0.1)' },
                { label: 'Total Transactions', value: stats.total_transactions, icon: DollarSign, color: '#06B6D4', bg: 'rgba(6, 182, 212, 0.1)' },
                { label: 'Total Goals', value: stats.total_goals, icon: Target, color: '#F97316', bg: 'rgba(249, 115, 22, 0.1)' },
                { label: 'Active Today', value: systemStats.active_users_today, icon: Zap, color: '#EAB308', bg: 'rgba(234, 179, 8, 0.1)' }
              ].map((stat, index) => (
                <div
                  key={index}
                  className="stat-card"
                  style={{
                    background: 'linear-gradient(135deg, rgba(30, 41, 59, 0.6) 0%, rgba(51, 65, 85, 0.3) 100%)',
                    padding: '28px',
                    borderRadius: '20px',
                    border: '1px solid rgba(255, 255, 255, 0.05)',
                    boxShadow: '0 10px 30px rgba(0, 0, 0, 0.3)',
                    animation: `slideIn 0.5s ease-out ${index * 0.1}s backwards`
                  }}
                >
                  <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', marginBottom: '20px' }}>
                    <div style={{
                      width: '56px',
                      height: '56px',
                      background: stat.bg,
                      borderRadius: '14px',
                      display: 'flex',
                      alignItems: 'center',
                      justifyContent: 'center'
                    }}>
                      <stat.icon size={28} color={stat.color} strokeWidth={2} />
                    </div>
                  </div>
                  <div style={{ fontSize: '36px', fontWeight: '700', color: '#F1F5F9', marginBottom: '8px' }}>
                    {stat.value.toLocaleString()}
                  </div>
                  <div style={{ fontSize: '14px', color: '#94A3B8', fontWeight: '500' }}>
                    {stat.label}
                  </div>
                </div>
              ))}
            </div>

            {/* Activity Summary */}
            <div style={{
              background: 'linear-gradient(135deg, rgba(30, 41, 59, 0.6) 0%, rgba(51, 65, 85, 0.3) 100%)',
              padding: '32px',
              borderRadius: '20px',
              border: '1px solid rgba(255, 255, 255, 0.05)'
            }}>
              <h2 style={{ fontSize: '24px', fontWeight: '700', marginBottom: '24px', color: '#F1F5F9' }}>
                Recent Activity
              </h2>
              <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(200px, 1fr))', gap: '20px' }}>
                <div>
                  <div style={{ fontSize: '14px', color: '#94A3B8', marginBottom: '8px' }}>New Today</div>
                  <div style={{ fontSize: '28px', fontWeight: '700', color: '#3B82F6' }}>
                    {systemStats.new_users_today}
                  </div>
                </div>
                <div>
                  <div style={{ fontSize: '14px', color: '#94A3B8', marginBottom: '8px' }}>New This Week</div>
                  <div style={{ fontSize: '28px', fontWeight: '700', color: '#8B5CF6' }}>
                    {systemStats.new_users_this_week}
                  </div>
                </div>
                <div>
                  <div style={{ fontSize: '14px', color: '#94A3B8', marginBottom: '8px' }}>New This Month</div>
                  <div style={{ fontSize: '28px', fontWeight: '700', color: '#EC4899' }}>
                    {systemStats.new_users_this_month}
                  </div>
                </div>
                <div>
                  <div style={{ fontSize: '14px', color: '#94A3B8', marginBottom: '8px' }}>Active This Week</div>
                  <div style={{ fontSize: '28px', fontWeight: '700', color: '#10B981' }}>
                    {systemStats.active_users_this_week}
                  </div>
                </div>
              </div>
            </div>
          </div>
        )}

        {/* Users Tab */}
        {activeTab === 'users' && (
          <div style={{ animation: 'slideIn 0.5s ease-out' }}>
            <div style={{ marginBottom: '32px' }}>
              <h1 style={{
                fontSize: '36px',
                fontWeight: '700',
                marginBottom: '8px',
                background: 'linear-gradient(135deg, #F1F5F9 0%, #94A3B8 100%)',
                WebkitBackgroundClip: 'text',
                WebkitTextFillColor: 'transparent'
              }}>
                User Management
              </h1>
              <p style={{ color: '#64748B', fontSize: '15px' }}>
                Manage user accounts and subscriptions
              </p>
            </div>

            {/* Search and Filters */}
            <div style={{
              background: 'linear-gradient(135deg, rgba(30, 41, 59, 0.6) 0%, rgba(51, 65, 85, 0.3) 100%)',
              padding: '24px',
              borderRadius: '20px',
              border: '1px solid rgba(255, 255, 255, 0.05)',
              marginBottom: '24px',
              display: 'flex',
              gap: '16px',
              flexWrap: 'wrap'
            }}>
              <div style={{ flex: 1, minWidth: '250px' }}>
                <input
                  type="text"
                  placeholder="Search by name or email..."
                  value={searchQuery}
                  onChange={(e) => setSearchQuery(e.target.value)}
                  onKeyPress={(e) => e.key === 'Enter' && handleSearch()}
                  style={{
                    width: '100%',
                    padding: '14px 16px',
                    background: 'rgba(15, 23, 42, 0.5)',
                    border: '1px solid rgba(148, 163, 184, 0.2)',
                    borderRadius: '12px',
                    color: '#F1F5F9',
                    fontSize: '15px',
                    outline: 'none',
                    fontFamily: 'inherit'
                  }}
                />
              </div>
              <select
                value={subscriptionFilter}
                onChange={(e) => setSubscriptionFilter(e.target.value)}
                style={{
                  padding: '14px 16px',
                  background: 'rgba(15, 23, 42, 0.5)',
                  border: '1px solid rgba(148, 163, 184, 0.2)',
                  borderRadius: '12px',
                  color: '#F1F5F9',
                  fontSize: '15px',
                  outline: 'none',
                  cursor: 'pointer',
                  fontFamily: 'inherit'
                }}
              >
                <option value="">All Subscriptions</option>
                <option value="free">Free</option>
                <option value="premium">Premium</option>
              </select>
              <button
                onClick={handleSearch}
                style={{
                  padding: '14px 24px',
                  background: 'linear-gradient(135deg, #3B82F6 0%, #8B5CF6 100%)',
                  border: 'none',
                  borderRadius: '12px',
                  color: 'white',
                  fontSize: '15px',
                  fontWeight: '600',
                  cursor: 'pointer',
                  display: 'flex',
                  alignItems: 'center',
                  gap: '8px',
                  transition: 'transform 0.2s',
                  fontFamily: 'inherit'
                }}
                onMouseEnter={(e) => e.target.style.transform = 'translateY(-2px)'}
                onMouseLeave={(e) => e.target.style.transform = 'translateY(0)'}
              >
                <Search size={18} />
                Search
              </button>
              <button
                onClick={() => { setSearchQuery(''); setSubscriptionFilter(''); loadData(); }}
                style={{
                  padding: '14px 24px',
                  background: 'rgba(100, 116, 139, 0.2)',
                  border: '1px solid rgba(148, 163, 184, 0.2)',
                  borderRadius: '12px',
                  color: '#94A3B8',
                  fontSize: '15px',
                  fontWeight: '600',
                  cursor: 'pointer',
                  display: 'flex',
                  alignItems: 'center',
                  gap: '8px',
                  transition: 'all 0.2s',
                  fontFamily: 'inherit'
                }}
                onMouseEnter={(e) => {
                  e.target.style.background = 'rgba(100, 116, 139, 0.3)';
                }}
                onMouseLeave={(e) => {
                  e.target.style.background = 'rgba(100, 116, 139, 0.2)';
                }}
              >
                <RefreshCw size={18} />
                Reset
              </button>
            </div>

            {/* Users Table */}
            <div style={{
              background: 'linear-gradient(135deg, rgba(30, 41, 59, 0.6) 0%, rgba(51, 65, 85, 0.3) 100%)',
              borderRadius: '20px',
              border: '1px solid rgba(255, 255, 255, 0.05)',
              overflow: 'hidden'
            }}>
              <div style={{ overflowX: 'auto' }}>
                <table style={{ width: '100%', borderCollapse: 'collapse' }}>
                  <thead>
                    <tr style={{ background: 'rgba(15, 23, 42, 0.5)', borderBottom: '1px solid rgba(255, 255, 255, 0.05)' }}>
                      <th style={{ padding: '16px 24px', textAlign: 'left', color: '#94A3B8', fontSize: '13px', fontWeight: '600', letterSpacing: '0.05em', textTransform: 'uppercase' }}>User</th>
                      <th style={{ padding: '16px 24px', textAlign: 'left', color: '#94A3B8', fontSize: '13px', fontWeight: '600', letterSpacing: '0.05em', textTransform: 'uppercase' }}>Subscription</th>
                      <th style={{ padding: '16px 24px', textAlign: 'left', color: '#94A3B8', fontSize: '13px', fontWeight: '600', letterSpacing: '0.05em', textTransform: 'uppercase' }}>Activity</th>
                      <th style={{ padding: '16px 24px', textAlign: 'left', color: '#94A3B8', fontSize: '13px', fontWeight: '600', letterSpacing: '0.05em', textTransform: 'uppercase' }}>Joined</th>
                      <th style={{ padding: '16px 24px', textAlign: 'center', color: '#94A3B8', fontSize: '13px', fontWeight: '600', letterSpacing: '0.05em', textTransform: 'uppercase' }}>Actions</th>
                    </tr>
                  </thead>
                  <tbody>
                    {users.map((user, index) => (
                      <tr
                        key={user.id}
                        className="user-row"
                        style={{
                          borderBottom: '1px solid rgba(255, 255, 255, 0.03)',
                          animation: `slideIn 0.4s ease-out ${index * 0.05}s backwards`
                        }}
                      >
                        <td style={{ padding: '20px 24px' }}>
                          <div style={{ display: 'flex', alignItems: 'center', gap: '12px' }}>
                            <div style={{
                              width: '44px',
                              height: '44px',
                              background: 'linear-gradient(135deg, #3B82F6 0%, #8B5CF6 100%)',
                              borderRadius: '12px',
                              display: 'flex',
                              alignItems: 'center',
                              justifyContent: 'center',
                              fontSize: '16px',
                              fontWeight: '700',
                              color: 'white'
                            }}>
                              {user.name.charAt(0).toUpperCase()}
                            </div>
                            <div>
                              <div style={{ fontSize: '15px', fontWeight: '600', color: '#F1F5F9', marginBottom: '4px' }}>
                                {user.name}
                              </div>
                              <div style={{ fontSize: '13px', color: '#64748B' }}>
                                {user.email}
                              </div>
                            </div>
                          </div>
                        </td>
                        <td style={{ padding: '20px 24px' }}>
                          <div style={{
                            display: 'inline-flex',
                            alignItems: 'center',
                            gap: '6px',
                            padding: '6px 12px',
                            background: user.subscription_type === 'premium' ? 'rgba(245, 158, 11, 0.15)' : 'rgba(100, 116, 139, 0.15)',
                            border: `1px solid ${user.subscription_type === 'premium' ? 'rgba(245, 158, 11, 0.3)' : 'rgba(100, 116, 139, 0.3)'}`,
                            borderRadius: '8px',
                            fontSize: '13px',
                            fontWeight: '600',
                            color: user.subscription_type === 'premium' ? '#F59E0B' : '#94A3B8'
                          }}>
                            {user.subscription_type === 'premium' && <Crown size={14} />}
                            {user.subscription_type.toUpperCase()}
                          </div>
                        </td>
                        <td style={{ padding: '20px 24px' }}>
                          <div style={{ fontSize: '14px', color: '#CBD5E1', marginBottom: '4px' }}>
                            {user.total_transactions} transactions
                          </div>
                          <div style={{ fontSize: '13px', color: '#64748B' }}>
                            {user.total_goals} goals
                          </div>
                        </td>
                        <td style={{ padding: '20px 24px', fontSize: '14px', color: '#94A3B8' }}>
                          {new Date(user.created_at).toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' })}
                        </td>
                        <td style={{ padding: '20px 24px', textAlign: 'center' }}>
                          <button
                            onClick={() => setSelectedUser(user)}
                            style={{
                              padding: '8px 16px',
                              background: 'rgba(59, 130, 246, 0.15)',
                              border: '1px solid rgba(59, 130, 246, 0.3)',
                              borderRadius: '8px',
                              color: '#60A5FA',
                              fontSize: '13px',
                              fontWeight: '600',
                              cursor: 'pointer',
                              display: 'inline-flex',
                              alignItems: 'center',
                              gap: '6px',
                              transition: 'all 0.2s',
                              fontFamily: 'inherit'
                            }}
                            onMouseEnter={(e) => {
                              e.target.style.background = 'rgba(59, 130, 246, 0.25)';
                            }}
                            onMouseLeave={(e) => {
                              e.target.style.background = 'rgba(59, 130, 246, 0.15)';
                            }}
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
                <div style={{ padding: '60px', textAlign: 'center', color: '#64748B' }}>
                  No users found
                </div>
              )}
            </div>
          </div>
        )}

        {/* Admins Tab */}
        {activeTab === 'admins' && admin.role === 'super_admin' && (
          <div style={{ animation: 'slideIn 0.5s ease-out' }}>
            <div style={{ marginBottom: '32px' }}>
              <h1 style={{
                fontSize: '36px',
                fontWeight: '700',
                marginBottom: '8px',
                background: 'linear-gradient(135deg, #F1F5F9 0%, #94A3B8 100%)',
                WebkitBackgroundClip: 'text',
                WebkitTextFillColor: 'transparent'
              }}>
                Admin Management
              </h1>
              <p style={{ color: '#64748B', fontSize: '15px' }}>
                Manage administrator accounts
              </p>
            </div>

            <div style={{
              background: 'linear-gradient(135deg, rgba(30, 41, 59, 0.6) 0%, rgba(51, 65, 85, 0.3) 100%)',
              borderRadius: '20px',
              border: '1px solid rgba(255, 255, 255, 0.05)',
              padding: '32px'
            }}>
              {admins.map((adm, index) => (
                <div
                  key={adm.id}
                  style={{
                    display: 'flex',
                    alignItems: 'center',
                    justifyContent: 'space-between',
                    padding: '20px',
                    background: 'rgba(15, 23, 42, 0.4)',
                    borderRadius: '12px',
                    marginBottom: '16px',
                    border: '1px solid rgba(255, 255, 255, 0.05)',
                    animation: `slideIn 0.4s ease-out ${index * 0.1}s backwards`
                  }}
                >
                  <div style={{ display: 'flex', alignItems: 'center', gap: '16px' }}>
                    <div style={{
                      width: '48px',
                      height: '48px',
                      background: 'linear-gradient(135deg, #8B5CF6 0%, #EC4899 100%)',
                      borderRadius: '12px',
                      display: 'flex',
                      alignItems: 'center',
                      justifyContent: 'center',
                      fontSize: '18px',
                      fontWeight: '700',
                      color: 'white'
                    }}>
                      {adm.name.charAt(0)}
                    </div>
                    <div>
                      <div style={{ fontSize: '16px', fontWeight: '600', color: '#F1F5F9', marginBottom: '4px', display: 'flex', alignItems: 'center', gap: '8px' }}>
                        {adm.name}
                        {adm.role === 'super_admin' && <Crown size={16} color="#F59E0B" />}
                      </div>
                      <div style={{ fontSize: '14px', color: '#64748B' }}>
                        {adm.email}
                      </div>
                    </div>
                  </div>
                  <div style={{
                    padding: '6px 12px',
                    background: adm.role === 'super_admin' ? 'rgba(245, 158, 11, 0.15)' : 'rgba(139, 92, 246, 0.15)',
                    border: `1px solid ${adm.role === 'super_admin' ? 'rgba(245, 158, 11, 0.3)' : 'rgba(139, 92, 246, 0.3)'}`,
                    borderRadius: '8px',
                    fontSize: '13px',
                    fontWeight: '600',
                    color: adm.role === 'super_admin' ? '#F59E0B' : '#A78BFA',
                    textTransform: 'capitalize'
                  }}>
                    {adm.role.replace('_', ' ')}
                  </div>
                </div>
              ))}
            </div>
          </div>
        )}

        {/* Logs Tab */}
        {activeTab === 'logs' && admin.role === 'super_admin' && (
          <div style={{ animation: 'slideIn 0.5s ease-out' }}>
            <div style={{ marginBottom: '32px' }}>
              <h1 style={{
                fontSize: '36px',
                fontWeight: '700',
                marginBottom: '8px',
                background: 'linear-gradient(135deg, #F1F5F9 0%, #94A3B8 100%)',
                WebkitBackgroundClip: 'text',
                WebkitTextFillColor: 'transparent'
              }}>
                Activity Logs
              </h1>
              <p style={{ color: '#64748B', fontSize: '15px' }}>
                Audit trail of all admin actions
              </p>
            </div>

            <div style={{
              background: 'linear-gradient(135deg, rgba(30, 41, 59, 0.6) 0%, rgba(51, 65, 85, 0.3) 100%)',
              borderRadius: '20px',
              border: '1px solid rgba(255, 255, 255, 0.05)',
              padding: '32px'
            }}>
              {logs.map((log, index) => (
                <div
                  key={log.id}
                  style={{
                    padding: '20px',
                    background: 'rgba(15, 23, 42, 0.4)',
                    borderRadius: '12px',
                    marginBottom: '12px',
                    border: '1px solid rgba(255, 255, 255, 0.05)',
                    animation: `slideIn 0.3s ease-out ${index * 0.05}s backwards`
                  }}
                >
                  <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'start', marginBottom: '12px' }}>
                    <div style={{ display: 'flex', alignItems: 'center', gap: '12px' }}>
                      <div style={{
                        width: '36px',
                        height: '36px',
                        background: 'rgba(59, 130, 246, 0.15)',
                        borderRadius: '10px',
                        display: 'flex',
                        alignItems: 'center',
                        justifyContent: 'center'
                      }}>
                        <Activity size={18} color="#3B82F6" />
                      </div>
                      <div>
                        <div style={{ fontSize: '15px', fontWeight: '600', color: '#F1F5F9', marginBottom: '4px' }}>
                          {log.action.replace(/_/g, ' ').replace(/\b\w/g, l => l.toUpperCase())}
                        </div>
                        <div style={{ fontSize: '13px', color: '#64748B' }}>
                          by {log.admin_email}
                        </div>
                      </div>
                    </div>
                    <div style={{ fontSize: '13px', color: '#64748B' }}>
                      {new Date(log.timestamp).toLocaleString()}
                    </div>
                  </div>
                  {log.details && (
                    <div style={{
                      padding: '12px',
                      background: 'rgba(30, 41, 59, 0.5)',
                      borderRadius: '8px',
                      fontSize: '13px',
                      color: '#94A3B8',
                      fontFamily: 'monospace'
                    }}>
                      {log.details}
                    </div>
                  )}
                </div>
              ))}
              {logs.length === 0 && (
                <div style={{ padding: '60px', textAlign: 'center', color: '#64748B' }}>
                  No activity logs found
                </div>
              )}
            </div>
          </div>
        )}
      </div>

      {/* User Detail Modal */}
      {selectedUser && (
        <div style={{
          position: 'fixed',
          top: 0,
          left: 0,
          right: 0,
          bottom: 0,
          background: 'rgba(0, 0, 0, 0.7)',
          backdropFilter: 'blur(8px)',
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
          zIndex: 1000,
          animation: 'fadeIn 0.2s ease-out'
        }}
        onClick={() => setSelectedUser(null)}
        >
          <div
            style={{
              background: 'linear-gradient(135deg, #1E293B 0%, #334155 100%)',
              borderRadius: '24px',
              padding: '40px',
              maxWidth: '600px',
              width: '90%',
              maxHeight: '80vh',
              overflowY: 'auto',
              border: '1px solid rgba(255, 255, 255, 0.1)',
              boxShadow: '0 25px 50px -12px rgba(0, 0, 0, 0.5)',
              animation: 'slideIn 0.3s ease-out'
            }}
            onClick={(e) => e.stopPropagation()}
          >
            <div style={{ display: 'flex', alignItems: 'center', gap: '16px', marginBottom: '32px' }}>
              <div style={{
                width: '64px',
                height: '64px',
                background: 'linear-gradient(135deg, #3B82F6 0%, #8B5CF6 100%)',
                borderRadius: '16px',
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
                fontSize: '24px',
                fontWeight: '700',
                color: 'white'
              }}>
                {selectedUser.name.charAt(0).toUpperCase()}
              </div>
              <div style={{ flex: 1 }}>
                <h2 style={{ fontSize: '24px', fontWeight: '700', color: '#F1F5F9', marginBottom: '4px' }}>
                  {selectedUser.name}
                </h2>
                <div style={{ fontSize: '14px', color: '#64748B' }}>
                  {selectedUser.email}
                </div>
              </div>
            </div>

            <div style={{ marginBottom: '32px' }}>
              <h3 style={{ fontSize: '14px', fontWeight: '600', color: '#94A3B8', marginBottom: '16px', textTransform: 'uppercase', letterSpacing: '0.05em' }}>
                Subscription
              </h3>
              <div style={{ display: 'flex', gap: '12px', marginBottom: '16px' }}>
                <button
                  onClick={() => handleUpdateSubscription(selectedUser.id, 'premium', new Date(Date.now() + 365*24*60*60*1000).toISOString())}
                  style={{
                    flex: 1,
                    padding: '14px',
                    background: 'linear-gradient(135deg, #F59E0B 0%, #D97706 100%)',
                    border: 'none',
                    borderRadius: '12px',
                    color: 'white',
                    fontSize: '14px',
                    fontWeight: '600',
                    cursor: 'pointer',
                    display: 'flex',
                    alignItems: 'center',
                    justifyContent: 'center',
                    gap: '8px',
                    transition: 'transform 0.2s',
                    fontFamily: 'inherit'
                  }}
                  onMouseEnter={(e) => e.target.style.transform = 'translateY(-2px)'}
                  onMouseLeave={(e) => e.target.style.transform = 'translateY(0)'}
                >
                  <Crown size={16} />
                  Upgrade to Premium
                </button>
                <button
                  onClick={() => handleUpdateSubscription(selectedUser.id, 'free', null)}
                  style={{
                    flex: 1,
                    padding: '14px',
                    background: 'rgba(100, 116, 139, 0.2)',
                    border: '1px solid rgba(148, 163, 184, 0.3)',
                    borderRadius: '12px',
                    color: '#94A3B8',
                    fontSize: '14px',
                    fontWeight: '600',
                    cursor: 'pointer',
                    transition: 'all 0.2s',
                    fontFamily: 'inherit'
                  }}
                  onMouseEnter={(e) => {
                    e.target.style.background = 'rgba(100, 116, 139, 0.3)';
                  }}
                  onMouseLeave={(e) => {
                    e.target.style.background = 'rgba(100, 116, 139, 0.2)';
                  }}
                >
                  Downgrade to Free
                </button>
              </div>
              <div style={{
                display: 'inline-flex',
                alignItems: 'center',
                gap: '6px',
                padding: '8px 14px',
                background: selectedUser.subscription_type === 'premium' ? 'rgba(245, 158, 11, 0.15)' : 'rgba(100, 116, 139, 0.15)',
                border: `1px solid ${selectedUser.subscription_type === 'premium' ? 'rgba(245, 158, 11, 0.3)' : 'rgba(100, 116, 139, 0.3)'}`,
                borderRadius: '10px',
                fontSize: '14px',
                fontWeight: '600',
                color: selectedUser.subscription_type === 'premium' ? '#F59E0B' : '#94A3B8'
              }}>
                {selectedUser.subscription_type === 'premium' && <Crown size={16} />}
                Current: {selectedUser.subscription_type.toUpperCase()}
              </div>
            </div>

            <div style={{ marginBottom: '32px' }}>
              <h3 style={{ fontSize: '14px', fontWeight: '600', color: '#94A3B8', marginBottom: '16px', textTransform: 'uppercase', letterSpacing: '0.05em' }}>
                Statistics
              </h3>
              <div style={{ display: 'grid', gridTemplateColumns: 'repeat(2, 1fr)', gap: '16px' }}>
                {[
                  { label: 'Transactions', value: selectedUser.total_transactions, icon: DollarSign },
                  { label: 'Goals', value: selectedUser.total_goals, icon: Target },
                  { label: 'Currency', value: selectedUser.default_currency.toUpperCase(), icon: DollarSign },
                  { label: 'Joined', value: new Date(selectedUser.created_at).toLocaleDateString('en-US', { month: 'short', year: 'numeric' }), icon: Calendar }
                ].map((stat, index) => (
                  <div key={index} style={{
                    padding: '16px',
                    background: 'rgba(30, 41, 59, 0.5)',
                    borderRadius: '12px',
                    border: '1px solid rgba(255, 255, 255, 0.05)'
                  }}>
                    <div style={{ display: 'flex', alignItems: 'center', gap: '8px', marginBottom: '8px' }}>
                      <stat.icon size={16} color="#64748B" />
                      <div style={{ fontSize: '13px', color: '#64748B' }}>{stat.label}</div>
                    </div>
                    <div style={{ fontSize: '20px', fontWeight: '700', color: '#F1F5F9' }}>
                      {stat.value}
                    </div>
                  </div>
                ))}
              </div>
            </div>

            {admin.role === 'super_admin' && (
              <div>
                <h3 style={{ fontSize: '14px', fontWeight: '600', color: '#94A3B8', marginBottom: '16px', textTransform: 'uppercase', letterSpacing: '0.05em' }}>
                  Danger Zone
                </h3>
                <button
                  onClick={() => handleDeleteUser(selectedUser.id)}
                  style={{
                    width: '100%',
                    padding: '14px',
                    background: 'rgba(239, 68, 68, 0.1)',
                    border: '1px solid rgba(239, 68, 68, 0.3)',
                    borderRadius: '12px',
                    color: '#F87171',
                    fontSize: '14px',
                    fontWeight: '600',
                    cursor: 'pointer',
                    display: 'flex',
                    alignItems: 'center',
                    justifyContent: 'center',
                    gap: '8px',
                    transition: 'all 0.2s',
                    fontFamily: 'inherit'
                  }}
                  onMouseEnter={(e) => {
                    e.target.style.background = 'rgba(239, 68, 68, 0.2)';
                  }}
                  onMouseLeave={(e) => {
                    e.target.style.background = 'rgba(239, 68, 68, 0.1)';
                  }}
                >
                  <Trash2 size={16} />
                  Delete User Account
                </button>
              </div>
            )}

            <button
              onClick={() => setSelectedUser(null)}
              style={{
                width: '100%',
                padding: '14px',
                background: 'rgba(100, 116, 139, 0.2)',
                border: '1px solid rgba(148, 163, 184, 0.3)',
                borderRadius: '12px',
                color: '#94A3B8',
                fontSize: '14px',
                fontWeight: '600',
                cursor: 'pointer',
                marginTop: '16px',
                transition: 'all 0.2s',
                fontFamily: 'inherit'
              }}
              onMouseEnter={(e) => {
                e.target.style.background = 'rgba(100, 116, 139, 0.3)';
              }}
              onMouseLeave={(e) => {
                e.target.style.background = 'rgba(100, 116, 139, 0.2)';
              }}
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
