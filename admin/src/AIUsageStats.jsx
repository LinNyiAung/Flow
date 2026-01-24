import React, { useState, useEffect } from 'react';
import { Zap, DollarSign, TrendingUp, Users, Calendar, Search, RefreshCw, Eye, X, ChevronDown, ChevronUp } from 'lucide-react';

// API Configuration
const API_BASE_URL = 'https://flowfinance.onrender.com';

const AIUsageStats = ({ token }) => {
  const [stats, setStats] = useState(null);
  const [userUsage, setUserUsage] = useState([]);
  const [budgetStats, setBudgetStats] = useState(null);
  const [transactionStats, setTransactionStats] = useState(null);
  const [loading, setLoading] = useState(true);
  const [selectedUser, setSelectedUser] = useState(null);
  const [userDetail, setUserDetail] = useState([]);
  const [sortBy, setSortBy] = useState('total_cost');
  const [startDate, setStartDate] = useState('');
  const [endDate, setEndDate] = useState('');
  const [featureFilter, setFeatureFilter] = useState('');
  const [expandedSections, setExpandedSections] = useState({
    overview: true,
    users: true,
    budget: false,
    transaction: false
  });

  useEffect(() => {
    loadData();
  }, [sortBy, startDate, endDate]);

  useEffect(() => {
    if (selectedUser) {
      loadUserDetail(selectedUser.user_id);
    }
  }, [featureFilter]);

  const loadData = async () => {
    setLoading(true);
    try {
      const params = new URLSearchParams();
      if (startDate) params.append('start_date', new Date(startDate).toISOString());
      if (endDate) params.append('end_date', new Date(endDate).toISOString());

      const [statsRes, usersRes, budgetRes, transactionRes] = await Promise.all([
        fetch(`${API_BASE_URL}/api/admin/ai-usage/stats?${params}`, {
          headers: { 'Authorization': `Bearer ${token}` }
        }),
        fetch(`${API_BASE_URL}/api/admin/ai-usage/users?sort_by=${sortBy}&limit=50`, {
          headers: { 'Authorization': `Bearer ${token}` }
        }),
        fetch(`${API_BASE_URL}/api/admin/ai-usage/stats/budgets?${params}`, {
          headers: { 'Authorization': `Bearer ${token}` }
        }),
        fetch(`${API_BASE_URL}/api/admin/ai-usage/stats/transactions?${params}`, {
          headers: { 'Authorization': `Bearer ${token}` }
        })
      ]);

      setStats(await statsRes.json());
      setUserUsage(await usersRes.json());
      setBudgetStats(await budgetRes.json());
      setTransactionStats(await transactionRes.json());
    } catch (error) {
      console.error('Error loading AI usage data:', error);
    } finally {
      setLoading(false);
    }
  };

  const loadUserDetail = async (userId) => {
    try {
      const params = new URLSearchParams();
      if (featureFilter) params.append('feature_type', featureFilter);
      
      const res = await fetch(
        `https://flowfinance.onrender.com/api/admin/ai-usage/user/${userId}?${params}&limit=100`,
        { headers: { 'Authorization': `Bearer ${token}` } }
      );
      setUserDetail(await res.json());
    } catch (error) {
      console.error('Error loading user detail:', error);
    }
  };

  const toggleSection = (section) => {
    setExpandedSections(prev => ({ ...prev, [section]: !prev[section] }));
  };

  if (loading) {
    return (
      <div className="flex items-center justify-center p-20">
        <RefreshCw size={32} className="animate-spin text-blue-500" />
      </div>
    );
  }

  return (
    <div className="animate-slideIn">
      <div className="mb-8 mt-2 md:mt-0">
        <h1 className="text-3xl md:text-4xl font-bold mb-2 bg-gradient-to-br from-slate-100 to-slate-400 bg-clip-text text-transparent">
          AI Usage & Token Costs
        </h1>
        <p className="text-slate-400 font-medium text-sm md:text-base">
          Monitor AI API usage and costs across all features
        </p>
      </div>

      {/* Date Range Filter */}
      <div className="bg-gradient-to-br from-slate-800/60 to-slate-700/30 rounded-2xl border border-white/5 p-6 mb-6">
        <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
          <div>
            <label className="block text-slate-300 text-sm font-semibold mb-2">
              Start Date
            </label>
            <input
              type="date"
              value={startDate}
              onChange={(e) => setStartDate(e.target.value)}
              className="w-full px-4 py-3 bg-slate-900/50 border border-slate-600/30 rounded-xl text-slate-100 outline-none focus:border-blue-500"
            />
          </div>
          <div>
            <label className="block text-slate-300 text-sm font-semibold mb-2">
              End Date
            </label>
            <input
              type="date"
              value={endDate}
              onChange={(e) => setEndDate(e.target.value)}
              className="w-full px-4 py-3 bg-slate-900/50 border border-slate-600/30 rounded-xl text-slate-100 outline-none focus:border-blue-500"
            />
          </div>
          <div className="flex items-end gap-2">
            <button
              onClick={loadData}
              className="flex-1 px-6 py-3 bg-blue-500 hover:bg-blue-600 rounded-xl text-white font-semibold flex items-center justify-center gap-2"
            >
              <Search size={18} />
              Filter
            </button>
            <button
              onClick={() => {
                setStartDate('');
                setEndDate('');
                loadData();
              }}
              className="px-4 py-3 bg-slate-500/20 border border-slate-400/20 rounded-xl text-slate-400 hover:bg-slate-500/30"
            >
              <RefreshCw size={18} />
            </button>
          </div>
        </div>
      </div>

      {/* Overall Stats */}
      <div className="mb-6">
        <button
          onClick={() => toggleSection('overview')}
          className="w-full flex items-center justify-between p-4 bg-gradient-to-br from-slate-800/60 to-slate-700/30 rounded-2xl border border-white/5 mb-4 hover:bg-slate-800/80 transition-colors"
        >
          <h2 className="text-xl font-bold text-slate-100">Overall Statistics</h2>
          {expandedSections.overview ? <ChevronUp size={20} /> : <ChevronDown size={20} />}
        </button>
        
        {expandedSections.overview && stats && (
          <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4 mb-6">
            {[
              { label: 'Total Requests', value: stats.total_requests.toLocaleString(), icon: Zap, color: 'text-blue-500', bg: 'bg-blue-500/10' },
              { label: 'Total Tokens', value: stats.total_tokens.toLocaleString(), icon: TrendingUp, color: 'text-violet-500', bg: 'bg-violet-500/10' },
              { label: 'Total Cost', value: `$${stats.total_cost_usd.toFixed(4)}`, icon: DollarSign, color: 'text-emerald-500', bg: 'bg-emerald-500/10' },
              { label: 'Active Users', value: stats.total_users.toLocaleString(), icon: Users, color: 'text-amber-500', bg: 'bg-amber-500/10' },
              { label: 'OpenAI Cost', value: `$${stats.openai_total_cost.toFixed(4)}`, icon: DollarSign, color: 'text-cyan-500', bg: 'bg-cyan-500/10' },
              { label: 'Gemini Cost', value: `$${stats.gemini_total_cost.toFixed(4)}`, icon: DollarSign, color: 'text-pink-500', bg: 'bg-pink-500/10' },
              { label: 'Weekly Insights', value: stats.weekly_insights_requests.toLocaleString(), icon: Calendar, color: 'text-orange-500', bg: 'bg-orange-500/10' },
              { label: 'Chat Requests', value: stats.chat_requests.toLocaleString(), icon: Zap, color: 'text-yellow-500', bg: 'bg-yellow-500/10' }
            ].map((stat, index) => (
              <div
                key={index}
                className="bg-gradient-to-br from-slate-800/60 to-slate-700/30 p-6 rounded-2xl border border-white/5"
              >
                <div className="flex justify-between items-start mb-4">
                  <div className={`w-12 h-12 ${stat.bg} rounded-2xl flex items-center justify-center`}>
                    <stat.icon size={24} className={stat.color} />
                  </div>
                </div>
                <div className="text-2xl font-bold text-slate-100 mb-2">
                  {stat.value}
                </div>
                <div className="text-sm text-slate-400">
                  {stat.label}
                </div>
              </div>
            ))}
          </div>
        )}
      </div>

      {/* Budget Feature Stats */}
      {budgetStats && (
        <div className="mb-6">
          <button
            onClick={() => toggleSection('budget')}
            className="w-full flex items-center justify-between p-4 bg-gradient-to-br from-slate-800/60 to-slate-700/30 rounded-2xl border border-white/5 mb-4 hover:bg-slate-800/80 transition-colors"
          >
            <h2 className="text-xl font-bold text-slate-100">Budget Features Usage</h2>
            {expandedSections.budget ? <ChevronUp size={20} /> : <ChevronDown size={20} />}
          </button>

          {expandedSections.budget && (
            <div className="bg-gradient-to-br from-slate-800/60 to-slate-700/30 rounded-2xl border border-white/5 p-6">
              <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
                {Object.entries(budgetStats).filter(([key]) => key !== 'total').map(([feature, data]) => (
                  <div key={feature} className="p-5 bg-slate-900/40 rounded-xl border border-white/5">
                    <h3 className="text-sm font-semibold text-slate-300 mb-4 capitalize">
                      {feature.replace(/_/g, ' ')}
                    </h3>
                    <div className="space-y-3">
                      <div className="flex justify-between">
                        <span className="text-xs text-slate-400">Requests</span>
                        <span className="text-sm font-bold text-slate-100">{data.requests.toLocaleString()}</span>
                      </div>
                      <div className="flex justify-between">
                        <span className="text-xs text-slate-400">Tokens</span>
                        <span className="text-sm font-bold text-slate-100">{data.tokens.toLocaleString()}</span>
                      </div>
                      <div className="flex justify-between">
                        <span className="text-xs text-slate-400">Cost</span>
                        <span className="text-sm font-bold text-emerald-400">${data.cost.toFixed(4)}</span>
                      </div>
                      <div className="flex justify-between">
                        <span className="text-xs text-slate-400">Users</span>
                        <span className="text-sm font-bold text-slate-100">{data.unique_users}</span>
                      </div>
                    </div>
                  </div>
                ))}
              </div>
              <div className="mt-6 p-5 bg-blue-500/10 border border-blue-500/30 rounded-xl">
                <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
                  <div>
                    <div className="text-xs text-blue-300 mb-1">Total Requests</div>
                    <div className="text-2xl font-bold text-blue-400">{budgetStats.total.requests.toLocaleString()}</div>
                  </div>
                  <div>
                    <div className="text-xs text-blue-300 mb-1">Total Tokens</div>
                    <div className="text-2xl font-bold text-blue-400">{budgetStats.total.tokens.toLocaleString()}</div>
                  </div>
                  <div>
                    <div className="text-xs text-blue-300 mb-1">Total Cost</div>
                    <div className="text-2xl font-bold text-blue-400">${budgetStats.total.cost.toFixed(4)}</div>
                  </div>
                  <div>
                    <div className="text-xs text-blue-300 mb-1">Total Users</div>
                    <div className="text-2xl font-bold text-blue-400">{budgetStats.total.unique_users}</div>
                  </div>
                </div>
              </div>
            </div>
          )}
        </div>
      )}

      {/* Transaction Extraction Stats */}
      {transactionStats && (
        <div className="mb-6">
          <button
            onClick={() => toggleSection('transaction')}
            className="w-full flex items-center justify-between p-4 bg-gradient-to-br from-slate-800/60 to-slate-700/30 rounded-2xl border border-white/5 mb-4 hover:bg-slate-800/80 transition-colors"
          >
            <h2 className="text-xl font-bold text-slate-100">Transaction Extraction Usage</h2>
            {expandedSections.transaction ? <ChevronUp size={20} /> : <ChevronDown size={20} />}
          </button>

          {expandedSections.transaction && (
            <div className="bg-gradient-to-br from-slate-800/60 to-slate-700/30 rounded-2xl border border-white/5 p-6">
              <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
                {Object.entries(transactionStats).filter(([key]) => key !== 'total').map(([feature, data]) => (
                  <div key={feature} className="p-5 bg-slate-900/40 rounded-xl border border-white/5">
                    <h3 className="text-sm font-semibold text-slate-300 mb-4 capitalize">
                      {feature.replace(/_/g, ' ')}
                    </h3>
                    <div className="space-y-3">
                      <div className="flex justify-between">
                        <span className="text-xs text-slate-400">Requests</span>
                        <span className="text-sm font-bold text-slate-100">{data.requests.toLocaleString()}</span>
                      </div>
                      <div className="flex justify-between">
                        <span className="text-xs text-slate-400">Tokens</span>
                        <span className="text-sm font-bold text-slate-100">{data.tokens.toLocaleString()}</span>
                      </div>
                      <div className="flex justify-between">
                        <span className="text-xs text-slate-400">Cost</span>
                        <span className="text-sm font-bold text-emerald-400">${data.cost.toFixed(4)}</span>
                      </div>
                      <div className="flex justify-between">
                        <span className="text-xs text-slate-400">Users</span>
                        <span className="text-sm font-bold text-slate-100">{data.unique_users}</span>
                      </div>
                    </div>
                  </div>
                ))}
              </div>
              <div className="mt-6 p-5 bg-violet-500/10 border border-violet-500/30 rounded-xl">
                <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
                  <div>
                    <div className="text-xs text-violet-300 mb-1">Total Requests</div>
                    <div className="text-2xl font-bold text-violet-400">{transactionStats.total.requests.toLocaleString()}</div>
                  </div>
                  <div>
                    <div className="text-xs text-violet-300 mb-1">Total Tokens</div>
                    <div className="text-2xl font-bold text-violet-400">{transactionStats.total.tokens.toLocaleString()}</div>
                  </div>
                  <div>
                    <div className="text-xs text-violet-300 mb-1">Total Cost</div>
                    <div className="text-2xl font-bold text-violet-400">${transactionStats.total.cost.toFixed(4)}</div>
                  </div>
                  <div>
                    <div className="text-xs text-violet-300 mb-1">Total Users</div>
                    <div className="text-2xl font-bold text-violet-400">{transactionStats.total.unique_users}</div>
                  </div>
                </div>
              </div>
            </div>
          )}
        </div>
      )}

      {/* User Usage Table */}
      <div className="mb-6">
        <button
          onClick={() => toggleSection('users')}
          className="w-full flex items-center justify-between p-4 bg-gradient-to-br from-slate-800/60 to-slate-700/30 rounded-2xl border border-white/5 mb-4 hover:bg-slate-800/80 transition-colors"
        >
          <h2 className="text-xl font-bold text-slate-100">User AI Usage</h2>
          {expandedSections.users ? <ChevronUp size={20} /> : <ChevronDown size={20} />}
        </button>

        {expandedSections.users && (
          <>
            <div className="bg-gradient-to-br from-slate-800/60 to-slate-700/30 rounded-2xl border border-white/5 p-4 mb-4">
              <select
                value={sortBy}
                onChange={(e) => setSortBy(e.target.value)}
                className="px-4 py-3 bg-slate-900/50 border border-slate-600/30 rounded-xl text-slate-100 outline-none cursor-pointer focus:border-blue-500"
              >
                <option value="total_cost">Sort by Total Cost</option>
                <option value="total_tokens">Sort by Total Tokens</option>
                <option value="total_requests">Sort by Total Requests</option>
              </select>
            </div>

            <div className="bg-gradient-to-br from-slate-800/60 to-slate-700/30 rounded-2xl border border-white/5 overflow-hidden">
              <div className="overflow-x-auto">
                <table className="w-full border-collapse min-w-[1200px]">
                  <thead>
                    <tr className="bg-slate-900/50 border-b border-white/5">
                      {['User', 'Requests', 'Tokens (In/Out)', 'Total Cost', 'OpenAI', 'Gemini', 'Chat', 'Insights', 'Actions'].map((header, i) => (
                        <th key={i} className={`px-6 py-4 text-left text-slate-400 text-xs font-semibold uppercase ${i === 8 ? 'text-center' : ''}`}>
                          {header}
                        </th>
                      ))}
                    </tr>
                  </thead>
                  <tbody>
                    {userUsage.map((user, index) => (
                      <tr key={user.user_id} className="border-b border-white/5 hover:bg-slate-800/50 transition-colors">
                        <td className="px-6 py-5">
                          <div className="flex items-center gap-3">
                            <div className="w-10 h-10 bg-gradient-to-br from-blue-500 to-violet-500 rounded-xl flex items-center justify-center text-white font-bold">
                              {user.user_name.charAt(0).toUpperCase()}
                            </div>
                            <div>
                              <div className="text-sm font-semibold text-slate-100">{user.user_name}</div>
                              <div className="text-xs text-slate-400">{user.user_email}</div>
                            </div>
                          </div>
                        </td>
                        <td className="px-6 py-5 text-sm text-slate-300">{user.total_requests.toLocaleString()}</td>
                        <td className="px-6 py-5">
                          <div className="text-sm text-slate-300">{user.total_input_tokens.toLocaleString()}</div>
                          <div className="text-xs text-slate-500">{user.total_output_tokens.toLocaleString()}</div>
                        </td>
                        <td className="px-6 py-5">
                          <div className="text-sm font-bold text-emerald-400">${user.total_cost_usd.toFixed(4)}</div>
                        </td>
                        <td className="px-6 py-5 text-sm text-cyan-400">${user.openai_cost.toFixed(4)}</td>
                        <td className="px-6 py-5 text-sm text-pink-400">${user.gemini_cost.toFixed(4)}</td>
                        <td className="px-6 py-5 text-sm text-slate-300">{user.chat_requests_count}</td>
                        <td className="px-6 py-5">
                          <div className="text-sm text-slate-300">{user.weekly_insights_count}W</div>
                          <div className="text-xs text-slate-500">{user.monthly_insights_count}M</div>
                        </td>
                        <td className="px-6 py-5 text-center">
                          <button
                            onClick={() => {
                              setSelectedUser(user);
                              loadUserDetail(user.user_id);
                            }}
                            className="inline-flex items-center gap-1.5 px-4 py-2 bg-blue-500/15 border border-blue-500/30 rounded-lg text-blue-400 text-xs font-semibold hover:bg-blue-500/25"
                          >
                            <Eye size={14} />
                            Detail
                          </button>
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            </div>
          </>
        )}
      </div>

      {/* User Detail Modal */}
      {selectedUser && (
        <div 
          className="fixed inset-0 bg-black/70 backdrop-blur-sm flex items-center justify-center z-50 p-4"
          onClick={() => setSelectedUser(null)}
        >
          <div
            className="bg-gradient-to-br from-slate-800 to-slate-700 rounded-3xl p-8 max-w-6xl w-full max-h-[90vh] overflow-y-auto border border-white/10"
            onClick={(e) => e.stopPropagation()}
          >
            <div className="flex items-center justify-between mb-6">
              <div className="flex items-center gap-4">
                <div className="w-14 h-14 bg-gradient-to-br from-blue-500 to-violet-500 rounded-2xl flex items-center justify-center text-xl font-bold text-white">
                  {selectedUser.user_name.charAt(0).toUpperCase()}
                </div>
                <div>
                  <h2 className="text-2xl font-bold text-slate-100">{selectedUser.user_name}</h2>
                  <div className="text-sm text-slate-400">{selectedUser.user_email}</div>
                </div>
              </div>
              <button
                onClick={() => setSelectedUser(null)}
                className="p-2 hover:bg-slate-600/50 rounded-lg transition-colors"
              >
                <X size={24} className="text-slate-400" />
              </button>
            </div>

            <div className="grid grid-cols-2 md:grid-cols-4 gap-4 mb-6">
              {[
                { label: 'Total Requests', value: selectedUser.total_requests.toLocaleString() },
                { label: 'Total Tokens', value: selectedUser.total_tokens.toLocaleString() },
                { label: 'Total Cost', value: `$${selectedUser.total_cost_usd.toFixed(4)}` },
                { label: 'Chat Requests', value: selectedUser.chat_requests_count }
              ].map((stat, i) => (
                <div key={i} className="p-4 bg-slate-900/40 rounded-xl border border-white/5">
                  <div className="text-xs text-slate-400 mb-1">{stat.label}</div>
                  <div className="text-lg font-bold text-slate-100">{stat.value}</div>
                </div>
              ))}
            </div>

            <div className="mb-4">
              <select
                value={featureFilter}
                onChange={(e) => {
                  setFeatureFilter(e.target.value);
                }}
                className="w-full px-4 py-3 bg-slate-900/50 border border-slate-600/30 rounded-xl text-slate-100 outline-none"
              >
                <option value="">All Features</option>
                <option value="chat">Chat</option>
                <option value="weekly_insight">Weekly Insights</option>
                <option value="monthly_insight">Monthly Insights</option>
                <option value="translation">Translation</option>
                <option value="budget_suggestion">Budget Suggestion</option>
                <option value="budget_auto_create">Budget Auto Create</option>
                <option value="transaction_text_extraction">Text Extraction</option>
                <option value="transaction_image_extraction">Image Extraction</option>
                <option value="transaction_audio_transcription">Audio Transcription</option>
              </select>
            </div>

            <div className="space-y-3 max-h-96 overflow-y-auto">
              {userDetail.map((record) => (
                <div key={record.id} className="p-4 bg-slate-900/40 rounded-xl border border-white/5">
                  <div className="flex justify-between items-start mb-3">
                    <div>
                      <div className="text-sm font-semibold text-slate-100 capitalize mb-1">
                        {record.feature_type.replace(/_/g, ' ')}
                      </div>
                      <div className="text-xs text-slate-400">
                        {record.provider.toUpperCase()} - {record.model_name}
                      </div>
                    </div>
                    <div className="text-xs text-slate-500">
                      {new Date(record.created_at).toLocaleString()}
                    </div>
                  </div>
                  <div className="grid grid-cols-4 gap-4">
                    <div>
                      <div className="text-xs text-slate-500">Input Tokens</div>
                      <div className="text-sm font-bold text-blue-400">{record.input_tokens.toLocaleString()}</div>
                    </div>
                    <div>
                      <div className="text-xs text-slate-500">Output Tokens</div>
                      <div className="text-sm font-bold text-violet-400">{record.output_tokens.toLocaleString()}</div>
                    </div>
                    <div>
                      <div className="text-xs text-slate-500">Total Tokens</div>
                      <div className="text-sm font-bold text-slate-300">{record.total_tokens.toLocaleString()}</div>
                    </div>
                    <div>
                      <div className="text-xs text-slate-500">Cost</div>
                      <div className="text-sm font-bold text-emerald-400">${record.estimated_cost_usd.toFixed(6)}</div>
                    </div>
                  </div>
                </div>
              ))}
              {userDetail.length === 0 && (
                <div className="p-12 text-center text-slate-400">
                  No usage records found
                </div>
              )}
            </div>
          </div>
        </div>
      )}
    </div>
  );
};

export default AIUsageStats;