import { motion } from 'framer-motion';
import type { DashboardBundle } from '../types';
import { fadeUp } from '../lib/motion';

interface Props {
  stats: DashboardBundle['stats'];
  runId?: string;
}

export function Header({ stats, runId }: Props) {
  const ratio = stats.feedsTotal > 0 ? stats.feedsOk / stats.feedsTotal : 0;
  const health = ratio >= 0.9 ? 'ok' : ratio >= 0.6 ? 'warn' : 'crit';
  const healthLabel = health === 'ok' ? 'Healthy' : health === 'warn' ? 'Degraded' : 'Errors';

  return (
    <motion.header className="header" variants={fadeUp} initial="hidden" animate="show">
      <div className="header-brand">
        <span className="header-icon" aria-hidden>
          <svg viewBox="0 0 24 24" fill="none">
            <path
              d="M12 3l7 3v5c0 4.5-3 8-7 10-4-2-7-5.5-7-10V6l7-3z"
              stroke="currentColor"
              strokeWidth="1.6"
              strokeLinejoin="round"
            />
            <path d="M9 12l2 2 4-4" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" />
          </svg>
        </span>
        <div>
          <h1>ThreatFeed</h1>
          <p className="header-sub">SOC shift intelligence · zero-token priority scoring</p>
        </div>
      </div>

      <div className="header-meta">
        <span className={`health health-${health}`}>
          <span className="health-dot" />
          {healthLabel} · {stats.feedsOk}/{stats.feedsTotal} feeds
        </span>
        <span className="header-time">Updated {formatRelative(stats.generatedAt)}</span>
        {runId ? <span className="header-run">run {runId}</span> : null}
      </div>

      <style>{`
        .header {
          display: flex;
          flex-wrap: wrap;
          align-items: center;
          justify-content: space-between;
          gap: 16px;
          padding-bottom: var(--space-3);
          border-bottom: 1px solid var(--border);
        }
        .header-brand {
          display: flex;
          gap: 14px;
          align-items: center;
          min-width: 240px;
        }
        .header-icon {
          width: 44px;
          height: 44px;
          display: grid;
          place-items: center;
          color: var(--accent);
          border: 1px solid var(--border-strong);
          border-radius: 12px;
          background: var(--accent-dim);
          box-shadow: inset 0 0 18px -8px var(--accent-glow);
        }
        .header-icon svg { width: 24px; height: 24px; }
        .header h1 {
          margin: 0;
          font-size: 24px;
          font-weight: 700;
          letter-spacing: -0.03em;
          background: linear-gradient(120deg, var(--text), var(--accent));
          -webkit-background-clip: text;
          background-clip: text;
          -webkit-text-fill-color: transparent;
        }
        .header-sub {
          margin: 3px 0 0;
          font-size: 13px;
          color: var(--muted);
        }
        .header-meta {
          display: flex;
          flex-direction: column;
          align-items: flex-end;
          gap: 5px;
        }
        .health {
          display: inline-flex;
          align-items: center;
          gap: 7px;
          font-size: 12px;
          font-weight: 600;
          padding: 5px 11px;
          border-radius: 999px;
          border: 1px solid var(--border);
        }
        .health-dot {
          width: 8px;
          height: 8px;
          border-radius: 50%;
          position: relative;
        }
        .health-ok { color: var(--low); border-color: rgba(52,211,153,0.32); background: rgba(52,211,153,0.08); }
        .health-ok .health-dot { background: var(--low); box-shadow: 0 0 0 0 rgba(52,211,153,0.6); animation: pulse 2.4s infinite; }
        .health-warn { color: var(--warn); border-color: rgba(245,176,66,0.32); background: rgba(245,176,66,0.08); }
        .health-warn .health-dot { background: var(--warn); }
        .health-crit { color: var(--crit); border-color: rgba(251,95,122,0.32); background: rgba(251,95,122,0.08); }
        .health-crit .health-dot { background: var(--crit); }
        .header-time {
          font-family: var(--mono);
          font-size: 12px;
          color: var(--text-dim);
        }
        .header-run {
          font-family: var(--mono);
          font-size: 11px;
          color: var(--muted);
        }
        @keyframes pulse {
          0% { box-shadow: 0 0 0 0 rgba(52,211,153,0.5); }
          70% { box-shadow: 0 0 0 7px rgba(52,211,153,0); }
          100% { box-shadow: 0 0 0 0 rgba(52,211,153,0); }
        }
        @media (max-width: 560px) {
          .header-meta { align-items: flex-start; }
        }
      `}</style>
    </motion.header>
  );
}

function formatRelative(iso: string): string {
  try {
    const then = new Date(iso).getTime();
    const diff = Date.now() - then;
    const mins = Math.round(diff / 60000);
    if (mins < 1) return 'just now';
    if (mins < 60) return `${mins}m ago`;
    const hrs = Math.round(mins / 60);
    if (hrs < 24) return `${hrs}h ago`;
    const days = Math.round(hrs / 24);
    return `${days}d ago`;
  } catch {
    return iso;
  }
}
