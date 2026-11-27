import { useState, useEffect, useCallback, useMemo } from 'react';
import { RefreshCw, AlertCircle, Search } from 'lucide-react';
import { apiRequest, errorMessage, canWrite } from './api';
import { card, field } from './appControlShared';
import TextRow from './TextRow';

const matches = (item, q) => {
  if (!q) return true;
  const hay = [
    item.key, item.default.en, item.default.my,
    item.override?.en?.text, item.override?.my?.text,
  ].filter(Boolean).join('\n').toLowerCase();
  return hay.includes(q);
};

const isChanged = (item) => !!(item.override?.en || item.override?.my);

const Texts = ({ token, adminRole, ConfirmDialog }) => {
  const writable = canWrite(adminRole);
  const [texts, setTexts] = useState([]);
  const [loading, setLoading] = useState(true);
  const [loadError, setLoadError] = useState(null);
  const [query, setQuery] = useState('');
  const [onlyChanged, setOnlyChanged] = useState(false);

  const fetchTexts = useCallback(async () => {
    try {
      const data = await apiRequest('/api/admin/texts', { token });
      setTexts(data.texts);
      setLoadError(null);
    } catch (err) {
      setLoadError(errorMessage(err, 'Failed to load texts'));
    } finally {
      setLoading(false);
    }
  }, [token]);

  useEffect(() => {
    fetchTexts();
  }, [fetchTexts]);

  const reloadAll = () => {
    setLoading(true);
    fetchTexts();
  };

  // Refetch after a conflict. The rows stay mounted, so the person's typing is kept (their editors follow the new
  // server text but keep a dirty draft). Resolves to null on success or an error message; nothing changes on failure.
  const reloadOne = async () => {
    try {
      const data = await apiRequest('/api/admin/texts', { token });
      setTexts(data.texts);
      setLoadError(null);
      return null;
    } catch (err) {
      return errorMessage(err, 'Failed to reload this text');
    }
  };

  const onChanged = (key, lang, override) => {
    setTexts((list) => list.map((t) => (t.key === key
      ? { ...t, override: { ...t.override, [lang]: override } }
      : t)));
  };

  const q = query.trim().toLowerCase();
  const visible = useMemo(
    () => texts.filter((t) => matches(t, q) && (!onlyChanged || isChanged(t))),
    [texts, q, onlyChanged],
  );
  const areas = useMemo(() => {
    const out = [];
    for (const t of visible) {
      let g = out.find((a) => a.name === t.area);
      if (!g) { g = { name: t.area, items: [] }; out.push(g); }
      g.items.push(t);
    }
    return out;
  }, [visible]);
  const changedCount = useMemo(() => texts.filter(isChanged).length, [texts]);

  if (loading && texts.length === 0) {
    return <div className="flex items-center justify-center p-20"><RefreshCw size={32} className="animate-spin text-blue-500" /></div>;
  }

  return (
    <div className="animate-slideIn">
      <div className="mb-8 mt-2 md:mt-0 flex items-start justify-between gap-4">
        <div className="min-w-0">
          <h1 className="text-3xl md:text-4xl font-bold mb-2 bg-gradient-to-br from-slate-100 to-slate-400 bg-clip-text text-transparent">
            Texts
          </h1>
          <p className="text-slate-400 font-medium text-sm md:text-base">
            Edit the words the app and its emails show{writable ? '' : ' (read-only)'}. Keep every {'{placeholder}'} exactly as listed.
          </p>
        </div>
        <button onClick={reloadAll} title="Reload" aria-label="Reload"
          className="p-3 bg-slate-500/20 border border-slate-400/20 rounded-xl text-slate-400 hover:bg-slate-500/30 flex-shrink-0">
          <RefreshCw size={18} className={loading ? 'animate-spin' : ''} />
        </button>
      </div>

      {loadError && (
        <div className="p-6 bg-red-500/5 border border-red-500/20 rounded-2xl flex flex-col md:flex-row items-start md:items-center gap-4 mb-6">
          <AlertCircle size={22} className="text-red-400 flex-shrink-0" />
          <div className="flex-1 text-sm text-red-300">{loadError}</div>
          <button onClick={reloadAll} className="px-4 py-2 bg-red-500/15 border border-red-500/30 rounded-lg text-red-300 text-sm font-semibold hover:bg-red-500/25 flex items-center gap-2">
            <RefreshCw size={14} /> Retry
          </button>
        </div>
      )}

      <div className="flex flex-col md:flex-row md:items-center gap-3 mb-6">
        <div className="relative flex-1 min-w-0">
          <Search size={16} className="absolute left-3 top-1/2 -translate-y-1/2 text-slate-500" />
          <input type="search" aria-label="Search texts" placeholder="Search by key or text, in either language"
            value={query} onChange={(e) => setQuery(e.target.value)} className={`${field} pl-9`} />
        </div>
        <button type="button" aria-pressed={onlyChanged} onClick={() => setOnlyChanged((v) => !v)}
          className={`px-4 py-2.5 rounded-xl text-sm font-semibold border flex-shrink-0 ${onlyChanged
            ? 'bg-blue-500/20 border-blue-500/40 text-blue-200'
            : 'bg-slate-500/20 border-slate-500/30 text-slate-300 hover:bg-slate-500/30'}`}>
          Changed ({changedCount})
        </button>
      </div>

      {areas.length === 0 && !loadError && (
        <div className="text-sm text-slate-400 p-6 text-center">
          {onlyChanged && !q ? 'No texts have been changed yet.' : 'No texts match.'}
        </div>
      )}

      {areas.map((area) => (
        <div key={area.name} className="mb-8">
          <h2 className="text-base font-bold text-slate-200 mb-3">
            {area.name} <span className="text-slate-500 font-semibold">({area.items.length})</span>
          </h2>
          <div className={`${card} overflow-hidden`}>
            {area.items.map((item) => (
              <TextRow key={item.key} item={item} writable={writable}
                token={token} ConfirmDialog={ConfirmDialog} onChanged={onChanged} onReload={reloadOne} />
            ))}
          </div>
        </div>
      ))}
    </div>
  );
};

export default Texts;
