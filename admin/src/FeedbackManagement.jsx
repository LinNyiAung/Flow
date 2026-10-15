import { useState, useEffect } from 'react';
import {
  MessageSquare, Star, Trash2, Search, Bug, Lightbulb, ThumbsUp, RefreshCw
} from 'lucide-react';
import { apiRequest, errorMessage, canWrite, isSuperAdmin } from './api';

const PAGE_SIZE = 25;

const FeedbackManagement = ({ token, adminRole }) => {
  const [categoryFilter, setCategoryFilter] = useState('');
  const [statusFilter, setStatusFilter] = useState('');
  const [refreshKey, setRefreshKey] = useState(0);
  const [list, setList] = useState({ key: null, items: [], hasMore: false, error: null });
  const [loadingMore, setLoadingMore] = useState(false);
  const [stats, setStats] = useState({ data: null, error: null });

  const writable = canWrite(adminRole);
  const canDelete = isSuperAdmin(adminRole);

  const queryKey = `${categoryFilter}|${statusFilter}|${refreshKey}`;
  const loading = list.key !== queryKey;

  // Feedback list (first page) — reloads whenever filters change or on refresh.
  useEffect(() => {
    let cancelled = false;
    apiRequest('/api/admin/feedback', {
      token,
      // `status` is sent for servers that support it; we also filter client-side below.
      params: { category: categoryFilter, status: statusFilter, skip: 0, limit: PAGE_SIZE },
    })
      .then((data) => {
        if (cancelled) return;
        const items = Array.isArray(data) ? data : [];
        setList({ key: queryKey, items, hasMore: items.length === PAGE_SIZE, error: null });
      })
      .catch((err) => {
        if (cancelled) return;
        console.error(err);
        setList({ key: queryKey, items: [], hasMore: false, error: errorMessage(err, 'Failed to load feedback data') });
      });
    return () => { cancelled = true; };
  }, [token, categoryFilter, statusFilter, queryKey]);

  // Summary stats over ALL feedback (not just the loaded page).
  useEffect(() => {
    let cancelled = false;
    apiRequest('/api/admin/feedback/stats', { token })
      .then((data) => { if (!cancelled) setStats({ data, error: null }); })
      .catch((err) => { if (!cancelled) setStats({ data: null, error: errorMessage(err, 'Failed to load stats') }); });
    return () => { cancelled = true; };
  }, [token, refreshKey]);

  const refresh = () => setRefreshKey((k) => k + 1);

  // Re-read the summary after a change without reloading the list.
  const reloadStats = () => {
    apiRequest('/api/admin/feedback/stats', { token })
      .then((data) => setStats({ data, error: null }))
      .catch(() => {});
  };

  const loadMore = async () => {
    const keyAtStart = queryKey;
    setLoadingMore(true);
    try {
      const data = await apiRequest('/api/admin/feedback', {
        token,
        params: { category: categoryFilter, status: statusFilter, skip: list.items.length, limit: PAGE_SIZE },
      });
      const items = Array.isArray(data) ? data : [];
      setList((prev) => {
        if (prev.key !== keyAtStart) return prev; // filters changed meanwhile — drop stale page
        const seen = new Set(prev.items.map((f) => f.id));
        return { ...prev, items: [...prev.items, ...items.filter((f) => !seen.has(f.id))], hasMore: items.length === PAGE_SIZE };
      });
    } catch (err) {
      alert(errorMessage(err, 'Failed to load more feedback'));
    } finally {
      setLoadingMore(false);
    }
  };

  const updateStatus = async (id, newStatus) => {
    try {
      await apiRequest(`/api/admin/feedback/${encodeURIComponent(id)}/status`, {
        token,
        method: 'PUT',
        params: { status_update: newStatus },
      });
      setList((prev) => ({ ...prev, items: prev.items.map((fb) => (fb.id === id ? { ...fb, status: newStatus } : fb)) }));
      reloadStats();
    } catch (err) {
      alert(errorMessage(err, 'Failed to update status'));
    }
  };

  const deleteFeedback = async (id) => {
    if (!window.confirm('Are you sure you want to delete this feedback?')) return;
    try {
      await apiRequest(`/api/admin/feedback/${encodeURIComponent(id)}`, { token, method: 'DELETE' });
      setList((prev) => ({ ...prev, items: prev.items.filter((fb) => fb.id !== id) }));
      reloadStats();
    } catch (err) {
      alert(errorMessage(err, 'Failed to delete feedback'));
    }
  };

  // Helper to render stars
  const renderStars = (rating) => {
    if (!rating) return <span className="text-slate-500 text-sm">No rating</span>;
    return (
      <div className="flex gap-0.5">
        {[...Array(5)].map((_, i) => (
          <Star
            key={i}
            size={14}
            className={i < rating ? "fill-yellow-400 text-yellow-400" : "text-slate-600"}
          />
        ))}
      </div>
    );
  };

  // Helper for category icons
  const getCategoryIcon = (category) => {
    switch(category) {
      case 'bug': return <Bug size={16} className="text-red-400" />;
      case 'feature_request': return <Lightbulb size={16} className="text-yellow-400" />;
      case 'usability': return <ThumbsUp size={16} className="text-blue-400" />;
      default: return <MessageSquare size={16} className="text-slate-400" />;
    }
  };

  // Helper for status colors
  const getStatusColor = (status) => {
    switch(status) {
      case 'resolved': return 'bg-emerald-500/10 text-emerald-400 border-emerald-500/20';
      case 'reviewed': return 'bg-blue-500/10 text-blue-400 border-blue-500/20';
      default: return 'bg-amber-500/10 text-amber-400 border-amber-500/20';
    }
  };

  const feedbacks = statusFilter ? list.items.filter((f) => f.status === statusFilter) : list.items;
  const s = stats.data;
  const statValue = (v) => (s ? (Number(v) || 0).toLocaleString() : '—');
  const avgRating = s && typeof s.average_rating === 'number' ? s.average_rating.toFixed(1) : '—';

  return (
    <div className="space-y-6">
      {/* Header & Filters */}
      <div className="bg-slate-800 p-6 rounded-xl border border-slate-700 flex flex-col md:flex-row justify-between items-start md:items-center gap-4">
        <div>
          <h2 className="text-xl font-bold text-white flex items-center gap-2">
            <MessageSquare className="text-blue-400" />
            User Feedback
          </h2>
          <p className="text-slate-400 text-sm mt-1">
            Manage bug reports and feature requests{!writable && ' (read-only)'}
          </p>
        </div>

        <div className="flex flex-wrap gap-3">
          <select
            value={categoryFilter}
            onChange={(e) => setCategoryFilter(e.target.value)}
            className="bg-slate-900 border border-slate-700 text-slate-300 text-sm rounded-lg p-2.5 focus:ring-blue-500 focus:border-blue-500"
          >
            <option value="">All Categories</option>
            <option value="bug">Bugs</option>
            <option value="feature_request">Feature Requests</option>
            <option value="usability">Usability</option>
            <option value="general">General</option>
          </select>

          <select
            value={statusFilter}
            onChange={(e) => setStatusFilter(e.target.value)}
            className="bg-slate-900 border border-slate-700 text-slate-300 text-sm rounded-lg p-2.5 focus:ring-blue-500 focus:border-blue-500"
          >
            <option value="">All Statuses</option>
            <option value="pending">Pending</option>
            <option value="reviewed">Reviewed</option>
            <option value="resolved">Resolved</option>
          </select>

          <button
            onClick={refresh}
            title="Reload"
            className="p-2.5 bg-blue-600 text-white rounded-lg hover:bg-blue-700 transition-colors"
          >
            <Search size={18} />
          </button>
        </div>
      </div>

      {/* Stats Cards (all feedback) */}
      <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
        <div className="bg-slate-800 p-4 rounded-xl border border-slate-700">
          <div className="text-slate-400 text-sm mb-1">Total Feedback</div>
          <div className="text-2xl font-bold text-white">{statValue(s?.total)}</div>
        </div>
        <div className="bg-slate-800 p-4 rounded-xl border border-slate-700">
          <div className="text-slate-400 text-sm mb-1">Pending Review</div>
          <div className="text-2xl font-bold text-amber-400">{statValue(s?.pending)}</div>
        </div>
        <div className="bg-slate-800 p-4 rounded-xl border border-slate-700">
          <div className="text-slate-400 text-sm mb-1">Resolved</div>
          <div className="text-2xl font-bold text-emerald-400">{statValue(s?.resolved)}</div>
        </div>
        <div className="bg-slate-800 p-4 rounded-xl border border-slate-700">
          <div className="text-slate-400 text-sm mb-1">Avg Rating</div>
          <div className="text-2xl font-bold text-yellow-400 flex items-center gap-2">
            {avgRating}
            <Star size={20} className="fill-yellow-400" />
          </div>
        </div>
      </div>
      {stats.error && <div className="text-sm text-red-400 -mt-3">{stats.error}</div>}

      {/* Feedback List */}
      <div className="bg-slate-800 rounded-xl border border-slate-700 overflow-hidden">
        {loading ? (
          <div className="p-12 text-center text-slate-400">Loading feedback...</div>
        ) : list.error ? (
          <div className="p-12 text-center text-red-400">{list.error}</div>
        ) : feedbacks.length === 0 && !list.hasMore ? (
          <div className="p-12 text-center text-slate-400">No feedback found</div>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-left">
              <thead className="bg-slate-900/50 text-slate-400 text-xs uppercase">
                <tr>
                  <th className="p-4">Date / User</th>
                  <th className="p-4">Type</th>
                  <th className="p-4">Message</th>
                  <th className="p-4">Rating</th>
                  <th className="p-4">Status</th>
                  {canDelete && <th className="p-4 text-right">Actions</th>}
                </tr>
              </thead>
              <tbody className="divide-y divide-slate-700">
                {feedbacks.map((item) => (
                  <tr key={item.id} className="hover:bg-slate-700/30 transition-colors">
                    <td className="p-4">
                      <div className="text-sm font-medium text-white">{item.user_name || 'Unknown'}</div>
                      <div className="text-xs text-slate-500">{item.user_email}</div>
                      <div className="text-xs text-slate-500 mt-1">
                        {item.created_at ? new Date(item.created_at).toLocaleDateString() : ''}
                      </div>
                    </td>
                    <td className="p-4">
                      <div className="flex items-center gap-2 text-sm text-slate-300 capitalize">
                        {getCategoryIcon(item.category)}
                        {String(item.category ?? '').replace(/_/g, ' ')}
                      </div>
                    </td>
                    <td className="p-4">
                      <div className="text-sm text-slate-300 max-w-md">
                        {item.message}
                      </div>
                    </td>
                    <td className="p-4">
                      {renderStars(item.rating)}
                    </td>
                    <td className="p-4">
                      {writable ? (
                        <select
                          value={item.status}
                          onChange={(e) => updateStatus(item.id, e.target.value)}
                          className={`text-xs font-medium px-2.5 py-1 rounded-full border appearance-none cursor-pointer ${getStatusColor(item.status)}`}
                        >
                          <option value="pending">Pending</option>
                          <option value="reviewed">Reviewed</option>
                          <option value="resolved">Resolved</option>
                        </select>
                      ) : (
                        <span className={`text-xs font-medium px-2.5 py-1 rounded-full border capitalize ${getStatusColor(item.status)}`}>
                          {item.status}
                        </span>
                      )}
                    </td>
                    {canDelete && (
                      <td className="p-4 text-right">
                        <button
                          onClick={() => deleteFeedback(item.id)}
                          className="p-2 text-slate-400 hover:text-red-400 hover:bg-red-400/10 rounded-lg transition-colors"
                          title="Delete Feedback"
                        >
                          <Trash2 size={16} />
                        </button>
                      </td>
                    )}
                  </tr>
                ))}
              </tbody>
            </table>
            {list.hasMore && (
              <div className="p-4 border-t border-slate-700 flex justify-center">
                <button
                  onClick={loadMore}
                  disabled={loadingMore}
                  className="px-5 py-2.5 bg-slate-700/60 border border-slate-600 rounded-lg text-slate-300 text-sm font-semibold hover:bg-slate-700 transition-colors flex items-center gap-2 disabled:opacity-50"
                >
                  {loadingMore && <RefreshCw size={14} className="animate-spin" />}
                  Load more
                </button>
              </div>
            )}
          </div>
        )}
      </div>
    </div>
  );
};

export default FeedbackManagement;
