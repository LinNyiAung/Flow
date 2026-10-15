import { useState, useEffect } from 'react';
import { Zap, DollarSign, TrendingUp, Users, Calendar, Search, RefreshCw, Eye, X, ChevronDown, ChevronUp, AlertCircle } from 'lucide-react';
import { apiRequest, errorMessage, parseLocalDate } from './api';

// Safe number helpers so a missing field can't crash rendering.
const num = (v) => (typeof v === 'number' && Number.isFinite(v) ? v : Number(v) || 0);
const fmtInt = (v) => num(v).toLocaleString();
const fmtCost = (v, digits = 4) => `$${num(v).toFixed(digits)}`;
const initial = (s) => (typeof s === 'string' && s.length ? s.charAt(0).toUpperCase() : '?');

const isFeatureStats = (obj) => obj && typeof obj === 'object' && !Array.isArray(obj);

const InlineError = ({ message, onRetry }) => (
  <div className="p-6 md:p-10 bg-red-500/5 border border-red-500/20 rounded-2xl flex flex-col md:flex-row items-start md:items-center gap-4 mb-6">
    <AlertCircle size={22} className="text-red-400 flex-shrink-0" />
    <div className="flex-1 text-sm text-red-300">{message}</div>
    {onRetry && (
      <button
        onClick={onRetry}
        className="px-4 py-2 bg-red-500/15 border border-red-500/30 rounded-lg text-red-300 text-sm font-semibold hover:bg-red-500/25 transition-colors flex items-center gap-2"
      >
        <RefreshCw size={14} /> Retry
      </button>
    )}
  </div>
);

const FeatureStatsSection = ({ title, data, expanded, onToggle, accent }) => {
  if (!isFeatureStats(data)) return null;
  const total = isFeatureStats(data.total) ? data.total : {};
  const totalClasses = accent === 'violet'
    ? { box: 'bg-violet-500/10 border-violet-500/30', label: 'text-violet-300', value: 'text-violet-400' }
    : { box: 'bg-blue-500/10 border-blue-500/30', label: 'text-blue-300', value: 'text-blue-400' };
  return (
    <div className="mb-6">
      <button
        onClick={onToggle}
        className="w-full flex items-center justify-between p-4 bg-gradient-to-br from-slate-800/60 to-slate-700/30 rounded-2xl border border-white/5 mb-4 hover:bg-slate-800/80 transition-colors"
      >
        <h2 className="text-xl font-bold text-slate-100">{title}</h2>
        {expanded ? <ChevronUp size={20} /> : <ChevronDown size={20} />}
      </button>

      {expanded && (
        <div className="bg-gradient-to-br from-slate-800/60 to-slate-700/30 rounded-2xl border border-white/5 p-6">
          <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
            {Object.entries(data).filter(([key, v]) => key !== 'total' && isFeatureStats(v)).map(([feature, d]) => (
              <div key={feature} className="p-5 bg-slate-900/40 rounded-xl border border-white/5">
                <h3 className="text-sm font-semibold text-slate-300 mb-4 capitalize">
                  {feature.replace(/_/g, ' ')}
                </h3>
                <div className="space-y-3">
                  <div className="flex justify-between">
                    <span className="text-xs text-slate-400">Requests</span>
                    <span className="text-sm font-bold text-slate-100">{fmtInt(d.requests)}</span>
                  </div>
                  <div className="flex justify-between">
                    <span className="text-xs text-slate-400">Tokens</span>
                    <span className="text-sm font-bold text-slate-100">{fmtInt(d.tokens)}</span>
                  </div>
                  <div className="flex justify-between">
                    <span className="text-xs text-slate-400">Cost</span>
                    <span className="text-sm font-bold text-emerald-400">{fmtCost(d.cost)}</span>
                  </div>
                  <div className="flex justify-between">
                    <span className="text-xs text-slate-400">Users</span>
                    <span className="text-sm font-bold text-slate-100">{fmtInt(d.unique_users)}</span>
                  </div>
                </div>
              </div>
            ))}
          </div>
          <div className={`mt-6 p-5 border rounded-xl ${totalClasses.box}`}>
            <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
              {[
                { label: 'Total Requests', value: fmtInt(total.requests) },
                { label: 'Total Tokens', value: fmtInt(total.tokens) },
                { label: 'Total Cost', value: fmtCost(total.cost) },
                { label: 'Total Users', value: fmtInt(total.unique_users) },
              ].map((s) => (
                <div key={s.label}>
                  <div className={`text-xs mb-1 ${totalClasses.label}`}>{s.label}</div>
                  <div className={`text-2xl font-bold ${totalClasses.value}`}>{s.value}</div>
                </div>
              ))}
            </div>
          </div>
        </div>
      )}
    </div>
  );
};

const AIUsageStats = ({ token }) => {
  const [sortBy, setSortBy] = useState('total_cost');
  const [startDate, setStartDate] = useState('');
  const [endDate, setEndDate] = useState('');
  const [refreshKey, setRefreshKey] = useState(0);
  // Result of the last completed load, tagged with the query it answers.
  const [result, setResult] = useState({ key: null, data: null, error: null });

  const [selectedUser, setSelectedUser] = useState(null);
  const [featureFilter, setFeatureFilter] = useState('');
  const [detail, setDetail] = useState({ key: null, records: [], error: null });

  const [expandedSections, setExpandedSections] = useState({
    overview: true,
    users: true,
    budget: false,
    transaction: false
  });

  const queryKey = `${sortBy}|${startDate}|${endDate}|${refreshKey}`;
  const loading = result.key !== queryKey;

  useEffect(() => {
    let cancelled = false;
    const start = parseLocalDate(startDate);
    // Include the whole end day (backend filters with $lte).
    const end = parseLocalDate(endDate, true);
    const range = {
      start_date: start ? start.toISOString() : undefined,
      end_date: end ? end.toISOString() : undefined,
    };

    Promise.all([
      apiRequest('/api/admin/ai-usage/stats', { token, params: range }),
      apiRequest('/api/admin/ai-usage/users', { token, params: { ...range, sort_by: sortBy, limit: 50 } }),
      apiRequest('/api/admin/ai-usage/stats/budgets', { token, params: range }),
      apiRequest('/api/admin/ai-usage/stats/transactions', { token, params: range }),
    ])
      .then(([stats, userUsage, budgetStats, transactionStats]) => {
        if (cancelled) return;
        setResult({
          key: queryKey,
          error: null,
          data: {
            stats: isFeatureStats(stats) ? stats : null,
            userUsage: Array.isArray(userUsage) ? userUsage : [],
            budgetStats: isFeatureStats(budgetStats) ? budgetStats : null,
            transactionStats: isFeatureStats(transactionStats) ? transactionStats : null,
          },
        });
      })
      .catch((err) => {
        if (cancelled) return;
        console.error('Error loading AI usage data:', err);
        setResult({ key: queryKey, data: null, error: errorMessage(err, 'Failed to load AI usage data') });
      });

    return () => { cancelled = true; };
  }, [token, sortBy, startDate, endDate, queryKey]);

  const selectedUserId = selectedUser?.user_id ?? null;
  const detailKey = selectedUserId ? `${selectedUserId}|${featureFilter}` : null;
  const detailLoading = detailKey !== null && detail.key !== detailKey;

  useEffect(() => {
    if (!selectedUserId) return undefined;
    let cancelled = false;
    apiRequest(`/api/admin/ai-usage/user/${encodeURIComponent(selectedUserId)}`, {
      token,
      params: { feature_type: featureFilter, limit: 100 },
    })
      .then((records) => {
        if (!cancelled) setDetail({ key: detailKey, records: Array.isArray(records) ? records : [], error: null });
      })
      .catch((err) => {
        if (!cancelled) setDetail({ key: detailKey, records: [], error: errorMessage(err, 'Failed to load usage records') });
      });
    return () => { cancelled = true; };
  }, [token, selectedUserId, featureFilter, detailKey]);

  const refresh = () => setRefreshKey((k) => k + 1);

  const resetFilters = () => {
    // Batched into one render → the effect runs once with cleared filters.
    setStartDate('');
    setEndDate('');
    refresh();
  };

  const openUser = (user) => {
    setFeatureFilter('');
    setSelectedUser(user);
  };

  const toggleSection = (section) => {
    setExpandedSections(prev => ({ ...prev, [section]: !prev[section] }));
  };

  // Keep showing the last successful data while a reload is in flight.
  const data = result.data;
  const error = result.key === queryKey ? result.error : null;
  const stats = data?.stats;
  const userUsage = data?.userUsage ?? [];
  const records = detail.key === detailKey ? detail.records : [];
  const detailError = detail.key === detailKey ? detail.error : null;

  if (loading && !data && !result.error) {
    return (
      <div className="flex items-center justify-center p-20">
        <RefreshCw size={32} className="animate-spin text-blue-500" />
      </div>
    );
  }

  return (
    <div className="animate-slideIn">
      <div className="mb-8 mt-2 md:mt-0 flex items-start justify-between gap-4">
        <div>
          <h1 className="text-3xl md:text-4xl font-bold mb-2 bg-gradient-to-br from-slate-100 to-slate-400 bg-clip-text text-transparent">
            AI Usage & Token Costs
          </h1>
          <p className="text-slate-400 font-medium text-sm md:text-base">
            Monitor AI API usage and costs across all features
          </p>
        </div>
        {loading && <RefreshCw size={20} className="animate-spin text-blue-500 mt-3 flex-shrink-0" />}
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
              max={endDate || undefined}
              onChange={(e) => setStartDate(e.target.value)}
              className="w-full px-4 py-3 bg-slate-900/50 border border-slate-600/30 rounded-xl text-slate-100 outline-none focus:border-blue-500"
            />
          </div>
          <div>
            <label className="block text-slate-300 text-sm font-semibold mb-2">
              End Date <span className="text-slate-500 font-normal">(inclusive)</span>
            </label>
            <input
              type="date"
              value={endDate}
              min={startDate || undefined}
              onChange={(e) => setEndDate(e.target.value)}
              className="w-full px-4 py-3 bg-slate-900/50 border border-slate-600/30 rounded-xl text-slate-100 outline-none focus:border-blue-500"
            />
          </div>
          <div className="flex items-end gap-2">
            <button
              onClick={refresh}
              className="flex-1 px-6 py-3 bg-blue-500 hover:bg-blue-600 rounded-xl text-white font-semibold flex items-center justify-center gap-2"
            >
              <Search size={18} />
              Filter
            </button>
            <button
              onClick={resetFilters}
              title="Clear dates and reload"
              className="px-4 py-3 bg-slate-500/20 border border-slate-400/20 rounded-xl text-slate-400 hover:bg-slate-500/30"
            >
              <RefreshCw size={18} />
            </button>
          </div>
        </div>
      </div>

      {error && <InlineError message={error} onRetry={refresh} />}

      {data && (
        <>
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
                  { label: 'Total Requests', value: fmtInt(stats.total_requests), icon: Zap, color: 'text-blue-500', bg: 'bg-blue-500/10' },
                  { label: 'Total Tokens', value: fmtInt(stats.total_tokens), icon: TrendingUp, color: 'text-violet-500', bg: 'bg-violet-500/10' },
                  { label: 'Total Cost', value: fmtCost(stats.total_cost_usd), icon: DollarSign, color: 'text-emerald-500', bg: 'bg-emerald-500/10' },
                  { label: 'Active Users', value: fmtInt(stats.total_users), icon: Users, color: 'text-amber-500', bg: 'bg-amber-500/10' },
                  { label: 'OpenAI Cost', value: fmtCost(stats.openai_total_cost), icon: DollarSign, color: 'text-cyan-500', bg: 'bg-cyan-500/10' },
                  { label: 'Gemini Cost', value: fmtCost(stats.gemini_total_cost), icon: DollarSign, color: 'text-pink-500', bg: 'bg-pink-500/10' },
                  { label: 'Weekly Insights', value: fmtInt(stats.weekly_insights_requests), icon: Calendar, color: 'text-orange-500', bg: 'bg-orange-500/10' },
                  { label: 'Chat Requests', value: fmtInt(stats.chat_requests), icon: Zap, color: 'text-yellow-500', bg: 'bg-yellow-500/10' }
                ].map((stat) => (
                  <div
                    key={stat.label}
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

          <FeatureStatsSection
            title="Budget Features Usage"
            data={data.budgetStats}
            expanded={expandedSections.budget}
            onToggle={() => toggleSection('budget')}
            accent="blue"
          />

          <FeatureStatsSection
            title="Transaction Extraction Usage"
            data={data.transactionStats}
            expanded={expandedSections.transaction}
            onToggle={() => toggleSection('transaction')}
            accent="violet"
          />

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
                        {userUsage.map((user) => (
                          <tr key={user.user_id} className="border-b border-white/5 hover:bg-slate-800/50 transition-colors">
                            <td className="px-6 py-5">
                              <div className="flex items-center gap-3">
                                <div className="w-10 h-10 bg-gradient-to-br from-blue-500 to-violet-500 rounded-xl flex items-center justify-center text-white font-bold">
                                  {initial(user.user_name)}
                                </div>
                                <div>
                                  <div className="text-sm font-semibold text-slate-100">{user.user_name}</div>
                                  <div className="text-xs text-slate-400">{user.user_email}</div>
                                </div>
                              </div>
                            </td>
                            <td className="px-6 py-5 text-sm text-slate-300">{fmtInt(user.total_requests)}</td>
                            <td className="px-6 py-5">
                              <div className="text-sm text-slate-300">{fmtInt(user.total_input_tokens)}</div>
                              <div className="text-xs text-slate-500">{fmtInt(user.total_output_tokens)}</div>
                            </td>
                            <td className="px-6 py-5">
                              <div className="text-sm font-bold text-emerald-400">{fmtCost(user.total_cost_usd)}</div>
                            </td>
                            <td className="px-6 py-5 text-sm text-cyan-400">{fmtCost(user.openai_cost)}</td>
                            <td className="px-6 py-5 text-sm text-pink-400">{fmtCost(user.gemini_cost)}</td>
                            <td className="px-6 py-5 text-sm text-slate-300">{fmtInt(user.chat_requests_count)}</td>
                            <td className="px-6 py-5">
                              <div className="text-sm text-slate-300">{fmtInt(user.weekly_insights_count)}W</div>
                              <div className="text-xs text-slate-500">{fmtInt(user.monthly_insights_count)}M</div>
                            </td>
                            <td className="px-6 py-5 text-center">
                              <button
                                onClick={() => openUser(user)}
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
                  {userUsage.length === 0 && <div className="p-12 text-center text-slate-400">No AI usage in this period</div>}
                </div>
              </>
            )}
          </div>
        </>
      )}

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
                  {initial(selectedUser.user_name)}
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
                { label: 'Total Requests', value: fmtInt(selectedUser.total_requests) },
                { label: 'Total Tokens', value: fmtInt(selectedUser.total_tokens) },
                { label: 'Total Cost', value: fmtCost(selectedUser.total_cost_usd) },
                { label: 'Chat Requests', value: fmtInt(selectedUser.chat_requests_count) }
              ].map((stat) => (
                <div key={stat.label} className="p-4 bg-slate-900/40 rounded-xl border border-white/5">
                  <div className="text-xs text-slate-400 mb-1">{stat.label}</div>
                  <div className="text-lg font-bold text-slate-100">{stat.value}</div>
                </div>
              ))}
            </div>

            <div className="mb-4">
              <select
                value={featureFilter}
                onChange={(e) => setFeatureFilter(e.target.value)}
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
              {detailLoading ? (
                <div className="p-12 flex items-center justify-center">
                  <RefreshCw size={24} className="animate-spin text-blue-500" />
                </div>
              ) : detailError ? (
                <div className="p-8 text-center text-red-400 text-sm">{detailError}</div>
              ) : records.length === 0 ? (
                <div className="p-12 text-center text-slate-400">
                  No usage records found
                </div>
              ) : records.map((record) => (
                <div key={record.id} className="p-4 bg-slate-900/40 rounded-xl border border-white/5">
                  <div className="flex justify-between items-start mb-3">
                    <div>
                      <div className="text-sm font-semibold text-slate-100 capitalize mb-1">
                        {String(record.feature_type ?? '').replace(/_/g, ' ')}
                      </div>
                      <div className="text-xs text-slate-400">
                        {String(record.provider ?? '').toUpperCase()} - {record.model_name}
                      </div>
                    </div>
                    <div className="text-xs text-slate-500">
                      {record.created_at ? new Date(record.created_at).toLocaleString() : ''}
                    </div>
                  </div>
                  <div className="grid grid-cols-4 gap-4">
                    <div>
                      <div className="text-xs text-slate-500">Input Tokens</div>
                      <div className="text-sm font-bold text-blue-400">{fmtInt(record.input_tokens)}</div>
                    </div>
                    <div>
                      <div className="text-xs text-slate-500">Output Tokens</div>
                      <div className="text-sm font-bold text-violet-400">{fmtInt(record.output_tokens)}</div>
                    </div>
                    <div>
                      <div className="text-xs text-slate-500">Total Tokens</div>
                      <div className="text-sm font-bold text-slate-300">{fmtInt(record.total_tokens)}</div>
                    </div>
                    <div>
                      <div className="text-xs text-slate-500">Cost</div>
                      <div className="text-sm font-bold text-emerald-400">{fmtCost(record.estimated_cost_usd, 6)}</div>
                    </div>
                  </div>
                </div>
              ))}
            </div>
          </div>
        </div>
      )}
    </div>
  );
};

export default AIUsageStats;
