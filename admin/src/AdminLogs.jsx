import { useState, useEffect, useRef } from 'react';
import { Activity, RefreshCw, ChevronLeft, ChevronRight } from 'lucide-react';
import { getAdminLogs, getAdminLogFilters, errorMessage } from './api';

const PAGE_SIZE = 50;

const fmtWhen = (iso) => (iso ? new Date(iso).toLocaleString([], { dateStyle: 'medium', timeStyle: 'medium' }) : '');
const actionLabel = (a) => String(a || '').replace(/_/g, ' ').replace(/\b\w/g, (l) => l.toUpperCase());

const selectCls = 'flex-1 min-w-[160px] px-4 py-3 bg-slate-900/50 border border-slate-600/20 rounded-xl text-slate-100 text-[15px] outline-none cursor-pointer focus:border-blue-500/50';
const pageBtn = 'inline-flex items-center gap-1.5 px-4 py-2.5 bg-slate-500/20 border border-slate-400/20 rounded-xl text-slate-300 text-sm font-semibold hover:bg-slate-500/30 transition-colors disabled:opacity-40 disabled:cursor-not-allowed';

/**
 * The audit trail of admin actions (super admin only; the parent mounts it only for them). Owns its filters
 * (action, admin, a person's email), its paging (50 a page, newest first) and its loading.
 */
const AdminLogs = ({ token }) => {
  const [filters, setFilters] = useState({ actions: [], admin_emails: [] });
  const [action, setAction] = useState('');
  const [adminEmail, setAdminEmail] = useState('');
  const [emailInput, setEmailInput] = useState('');
  const [userEmail, setUserEmail] = useState(''); // the debounced search
  const appliedEmail = useRef('');
  const [page, setPage] = useState(0);
  const [reloadKey, setReloadKey] = useState(0);
  const [data, setData] = useState({ key: null, rows: [], error: null });

  const queryKey = `${action}|${adminEmail}|${userEmail}|${page}|${reloadKey}`;
  const loading = data.key !== queryKey;

  useEffect(() => {
    let cancelled = false;
    getAdminLogFilters(token)
      .then((f) => { if (!cancelled) setFilters({ actions: f?.actions || [], admin_emails: f?.admin_emails || [] }); })
      .catch((err) => console.error(err)); // the selects just stay empty
    return () => { cancelled = true; };
  }, [token]);

  // The search box applies half a second after typing stops; a new search starts at the first page.
  useEffect(() => {
    const next = emailInput.trim();
    if (next === appliedEmail.current) return undefined;
    const t = setTimeout(() => {
      appliedEmail.current = next;
      setUserEmail(next);
      setPage(0);
    }, 500);
    return () => clearTimeout(t);
  }, [emailInput]);

  useEffect(() => {
    let cancelled = false;
    getAdminLogs(token, {
      skip: page * PAGE_SIZE, limit: PAGE_SIZE,
      action, admin_email: adminEmail, user_email: userEmail,
    })
      .then((rows) => { if (!cancelled) setData({ key: queryKey, rows: Array.isArray(rows) ? rows : [], error: null }); })
      .catch((err) => {
        if (cancelled) return;
        console.error(err);
        setData({ key: queryKey, rows: [], error: errorMessage(err, 'Failed to load the activity logs') });
      });
    return () => { cancelled = true; };
  }, [token, action, adminEmail, userEmail, page, queryKey]);

  const changeFilter = (setter) => (e) => { setter(e.target.value); setPage(0); };
  const rows = data.rows;
  const filtered = !!(action || adminEmail || userEmail);

  return (
    <div className="animate-slideIn">
      <div className="mb-6 md:mb-8 mt-2 md:mt-0">
        <h1 className="text-3xl md:text-4xl font-bold mb-2 bg-gradient-to-br from-slate-100 to-slate-400 bg-clip-text text-transparent">Activity Logs</h1>
        <p className="text-slate-400 font-medium text-sm md:text-base">Audit trail of all admin actions, newest first. Times are in your local time.</p>
      </div>

      <div className="bg-gradient-to-br from-slate-800/60 to-slate-700/30 p-4 md:p-6 rounded-2xl border border-white/5 mb-6 flex flex-wrap gap-4">
        <select value={action} onChange={changeFilter(setAction)} aria-label="Action" className={selectCls}>
          <option value="">All actions</option>
          {filters.actions.map((a) => <option key={a} value={a}>{actionLabel(a)}</option>)}
        </select>
        <select value={adminEmail} onChange={changeFilter(setAdminEmail)} aria-label="Admin" className={selectCls}>
          <option value="">All admins</option>
          {filters.admin_emails.map((a) => <option key={a} value={a}>{a}</option>)}
        </select>
        <input type="search" value={emailInput} onChange={(e) => setEmailInput(e.target.value)} maxLength={200}
          aria-label="Person's email" placeholder="Search a person's email"
          className="flex-[2] min-w-[200px] px-4 py-3 bg-slate-900/50 border border-slate-600/20 rounded-xl text-slate-100 text-[15px] outline-none focus:border-blue-500/50" />
        <button onClick={() => setReloadKey((k) => k + 1)} title="Reload"
          className="px-4 py-3 bg-slate-500/20 border border-slate-400/20 rounded-xl text-slate-400 hover:bg-slate-500/30 transition-colors">
          <RefreshCw size={18} className={loading ? 'animate-spin' : ''} />
        </button>
      </div>

      <div className="bg-gradient-to-br from-slate-800/60 to-slate-700/30 rounded-2xl border border-white/5 p-4 md:p-8">
        {loading ? (
          <div className="p-16 flex items-center justify-center"><RefreshCw size={28} className="animate-spin text-blue-500" /></div>
        ) : data.error ? (
          <div role="alert" className="p-12 text-center text-red-400">{data.error}</div>
        ) : rows.length === 0 ? (
          <div className="p-16 text-center text-slate-400">{filtered ? 'No activity matches these filters' : 'No activity logs found'}</div>
        ) : (
          rows.map((log) => (
            <div key={log.id} className="p-4 md:p-5 bg-slate-900/40 rounded-xl mb-3 border border-white/5">
              <div className="flex flex-col md:flex-row md:justify-between md:items-start mb-3 gap-2">
                <div className="flex items-center gap-3">
                  <div className="w-9 h-9 bg-blue-500/15 rounded-lg flex items-center justify-center flex-shrink-0"><Activity size={18} className="text-blue-500" /></div>
                  <div className="min-w-0">
                    <div className="text-[15px] font-semibold text-slate-100 mb-1">{actionLabel(log.action)}</div>
                    <div className="text-[13px] text-slate-500 break-all">
                      by {log.admin_email}
                      {!log.admin_id && <span className="ml-2 text-amber-400/80">(not an admin)</span>}
                    </div>
                    {log.target_user_email && <div className="text-[13px] text-slate-400 break-all">on {log.target_user_email}</div>}
                  </div>
                </div>
                <div className="text-[13px] text-slate-500 pl-12 md:pl-0 flex-shrink-0">{fmtWhen(log.timestamp)}</div>
              </div>
              {log.details && <div className="p-3 bg-slate-800/50 rounded-lg text-[13px] text-slate-400 font-mono ml-0 md:ml-12 break-words">{log.details}</div>}
            </div>
          ))
        )}

        <div className="flex items-center justify-between gap-3 mt-4">
          <button onClick={() => setPage((p) => Math.max(0, p - 1))} disabled={page === 0 || loading} className={pageBtn}>
            <ChevronLeft size={16} /> Newer
          </button>
          <span className="text-xs text-slate-500">Page {page + 1}</span>
          <button onClick={() => setPage((p) => p + 1)} disabled={loading || rows.length < PAGE_SIZE} className={pageBtn}>
            Older <ChevronRight size={16} />
          </button>
        </div>
      </div>
    </div>
  );
};

export default AdminLogs;
