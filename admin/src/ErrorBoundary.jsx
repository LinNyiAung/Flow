import { Component } from 'react';
import { AlertTriangle, RefreshCw } from 'lucide-react';

/**
 * Catches render errors in a section of the panel so a single bad response
 * can't blank the whole app. Give it a `resetKey` (e.g. the active tab) to
 * clear the error when the user navigates elsewhere.
 */
export default class ErrorBoundary extends Component {
  constructor(props) {
    super(props);
    this.state = { error: null, resetKey: props.resetKey };
  }

  static getDerivedStateFromError(error) {
    return { error };
  }

  static getDerivedStateFromProps(props, state) {
    if (props.resetKey !== state.resetKey) {
      return { error: null, resetKey: props.resetKey };
    }
    return null;
  }

  componentDidCatch(error, info) {
    console.error('Admin panel render error:', error, info?.componentStack);
  }

  render() {
    if (!this.state.error) return this.props.children;
    return (
      <div className="p-10 md:p-16 bg-red-500/5 border border-red-500/20 rounded-2xl text-center animate-slideIn">
        <AlertTriangle size={36} className="text-red-400 mx-auto mb-4" />
        <h2 className="text-xl font-bold text-slate-100 mb-2">Something went wrong displaying this page</h2>
        <p className="text-sm text-slate-400 mb-6 break-words">{this.state.error?.message || 'Unexpected error'}</p>
        <button
          onClick={() => this.setState({ error: null })}
          className="inline-flex items-center gap-2 px-5 py-2.5 bg-blue-500/15 border border-blue-500/30 rounded-xl text-blue-400 text-sm font-semibold hover:bg-blue-500/25 transition-colors"
        >
          <RefreshCw size={16} /> Try again
        </button>
      </div>
    );
  }
}
