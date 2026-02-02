import React, { useState, useEffect } from 'react';
import { 
  MessageSquare, Star, CheckCircle, Clock, AlertCircle, 
  Trash2, Filter, Search, Bug, Lightbulb, ThumbsUp, HelpCircle 
} from 'lucide-react';

// API Configuration matches your existing App.jsx
const API_BASE_URL = 'https://flowfinance.onrender.com';

const FeedbackManagement = ({ token }) => {
  const [feedbacks, setFeedbacks] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  const [categoryFilter, setCategoryFilter] = useState('');
  const [statusFilter, setStatusFilter] = useState('');

  // Define API calls locally or import from a service if you refactor later
  const fetchFeedback = async () => {
    try {
      setLoading(true);
      const params = new URLSearchParams();
      if (categoryFilter) params.append('category', categoryFilter);
      
      const response = await fetch(`${API_BASE_URL}/api/admin/feedback?${params.toString()}`, {
        headers: { 'Authorization': `Bearer ${token}` }
      });
      
      if (!response.ok) throw new Error('Failed to fetch feedback');
      const data = await response.json();
      setFeedbacks(data);
      setError(null);
    } catch (err) {
      setError('Failed to load feedback data');
      console.error(err);
    } finally {
      setLoading(false);
    }
  };

  const updateStatus = async (id, newStatus) => {
    try {
      const response = await fetch(`${API_BASE_URL}/api/admin/feedback/${id}/status?status_update=${newStatus}`, {
        method: 'PUT',
        headers: { 'Authorization': `Bearer ${token}` }
      });

      if (!response.ok) throw new Error('Failed to update status');
      
      // Optimistic update
      setFeedbacks(feedbacks.map(fb => 
        fb.id === id ? { ...fb, status: newStatus } : fb
      ));
    } catch (err) {
      alert('Failed to update status');
    }
  };

  const deleteFeedback = async (id) => {
    if (!window.confirm('Are you sure you want to delete this feedback?')) return;
    
    try {
      const response = await fetch(`${API_BASE_URL}/api/admin/feedback/${id}`, {
        method: 'DELETE',
        headers: { 'Authorization': `Bearer ${token}` }
      });

      if (!response.ok) throw new Error('Failed to delete feedback');
      
      setFeedbacks(feedbacks.filter(fb => fb.id !== id));
    } catch (err) {
      alert('Failed to delete feedback');
    }
  };

  useEffect(() => {
    fetchFeedback();
  }, [categoryFilter]); // Refresh when filter changes

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

  return (
    <div className="space-y-6">
      {/* Header & Filters */}
      <div className="bg-slate-800 p-6 rounded-xl border border-slate-700 flex flex-col md:flex-row justify-between items-start md:items-center gap-4">
        <div>
          <h2 className="text-xl font-bold text-white flex items-center gap-2">
            <MessageSquare className="text-blue-400" />
            User Feedback
          </h2>
          <p className="text-slate-400 text-sm mt-1">Manage bug reports and feature requests</p>
        </div>
        
        <div className="flex gap-3">
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
          
          <button 
            onClick={fetchFeedback}
            className="p-2.5 bg-blue-600 text-white rounded-lg hover:bg-blue-700 transition-colors"
          >
            <Search size={18} />
          </button>
        </div>
      </div>

      {/* Stats Cards */}
      <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
        <div className="bg-slate-800 p-4 rounded-xl border border-slate-700">
          <div className="text-slate-400 text-sm mb-1">Total Feedback</div>
          <div className="text-2xl font-bold text-white">{feedbacks.length}</div>
        </div>
        <div className="bg-slate-800 p-4 rounded-xl border border-slate-700">
          <div className="text-slate-400 text-sm mb-1">Pending Review</div>
          <div className="text-2xl font-bold text-amber-400">
            {feedbacks.filter(f => f.status === 'pending').length}
          </div>
        </div>
        <div className="bg-slate-800 p-4 rounded-xl border border-slate-700">
          <div className="text-slate-400 text-sm mb-1">Avg Rating</div>
          <div className="text-2xl font-bold text-yellow-400 flex items-center gap-2">
            {(feedbacks.reduce((acc, curr) => acc + (curr.rating || 0), 0) / (feedbacks.filter(f => f.rating).length || 1)).toFixed(1)}
            <Star size={20} className="fill-yellow-400" />
          </div>
        </div>
      </div>

      {/* Feedback List */}
      <div className="bg-slate-800 rounded-xl border border-slate-700 overflow-hidden">
        {loading ? (
          <div className="p-12 text-center text-slate-400">Loading feedback...</div>
        ) : error ? (
          <div className="p-12 text-center text-red-400">{error}</div>
        ) : feedbacks.length === 0 ? (
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
                  <th className="p-4 text-right">Actions</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-slate-700">
                {feedbacks.map((item) => (
                  <tr key={item.id} className="hover:bg-slate-700/30 transition-colors">
                    <td className="p-4">
                      <div className="text-sm font-medium text-white">{item.user_name || 'Unknown'}</div>
                      <div className="text-xs text-slate-500">{item.user_email}</div>
                      <div className="text-xs text-slate-500 mt-1">
                        {new Date(item.created_at).toLocaleDateString()}
                      </div>
                    </td>
                    <td className="p-4">
                      <div className="flex items-center gap-2 text-sm text-slate-300 capitalize">
                        {getCategoryIcon(item.category)}
                        {item.category.replace('_', ' ')}
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
                      <select
                        value={item.status}
                        onChange={(e) => updateStatus(item.id, e.target.value)}
                        className={`text-xs font-medium px-2.5 py-1 rounded-full border appearance-none cursor-pointer ${getStatusColor(item.status)}`}
                      >
                        <option value="pending">Pending</option>
                        <option value="reviewed">Reviewed</option>
                        <option value="resolved">Resolved</option>
                      </select>
                    </td>
                    <td className="p-4 text-right">
                      <button 
                        onClick={() => deleteFeedback(item.id)}
                        className="p-2 text-slate-400 hover:text-red-400 hover:bg-red-400/10 rounded-lg transition-colors"
                        title="Delete Feedback"
                      >
                        <Trash2 size={16} />
                      </button>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>
    </div>
  );
};

export default FeedbackManagement;