import { motion } from 'framer-motion';
import type { DashboardArticle } from '../types';
import { fadeUp, inView, staggerContainer } from '../lib/motion';

interface Props {
  items: DashboardArticle[];
}

export function ShiftBrief({ items }: Props) {
  return (
    <motion.section
      className="panel shift-brief"
      id="shift-brief"
      variants={fadeUp}
      initial="hidden"
      whileInView="show"
      viewport={inView}
    >
      <div className="shift-head">
        <h2 className="panel-title">Shift brief · top priority</h2>
        <span className="shift-count">{items.length} ranked</span>
      </div>

      {items.length === 0 ? (
        <p className="empty">No keyword matches this run.</p>
      ) : (
        <motion.ol
          className="shift-list"
          variants={staggerContainer(0.05)}
          initial="hidden"
          whileInView="show"
          viewport={inView}
        >
          {items.map((a, i) => (
            <motion.li key={a.key} className="shift-item" variants={fadeUp}>
              <span className="shift-rank">{String(i + 1).padStart(2, '0')}</span>
              <div className="shift-body">
                <div className="shift-meta">
                  <span className="shift-score" title="Local PriorityScore">
                    {a.priorityScore ?? '—'}
                  </span>
                  <span className={`badge cat-${a.category || 'News'}`}>{a.category}</span>
                  <span className="badge">{a.source}</span>
                  {a.isNew ? <span className="badge badge-new">new</span> : null}
                  {a.published ? <span className="badge">{formatDate(a.published)}</span> : null}
                </div>
                <a className="shift-title" href={a.link} target="_blank" rel="noreferrer">
                  {a.title}
                </a>
                {a.reasonChips && a.reasonChips.length > 0 ? (
                  <div className="chips-row">
                    {a.reasonChips.map((r) => (
                      <span key={r} className="chip reason">
                        {r}
                      </span>
                    ))}
                  </div>
                ) : null}
              </div>
            </motion.li>
          ))}
        </motion.ol>
      )}

      <style>{`
        .shift-brief {
          border-color: rgba(56, 217, 208, 0.2);
          background:
            radial-gradient(120% 100% at 0% 0%, rgba(56, 217, 208, 0.08), transparent 55%),
            var(--panel);
        }
        .shift-head {
          display: flex;
          align-items: center;
          justify-content: space-between;
          gap: 12px;
        }
        .shift-count {
          font-family: var(--mono);
          font-size: 11px;
          color: var(--muted);
        }
        .shift-list {
          list-style: none;
          margin: 0;
          padding: 0;
          display: grid;
          gap: 10px;
        }
        .shift-item {
          display: flex;
          gap: 14px;
          padding: 14px 16px;
          border-radius: var(--radius-sm);
          border: 1px solid var(--border);
          background: rgba(0, 0, 0, 0.22);
          transition: border-color 0.2s var(--ease), transform 0.2s var(--ease), background 0.2s var(--ease);
        }
        .shift-item:hover {
          border-color: rgba(56, 217, 208, 0.3);
          background: rgba(56, 217, 208, 0.04);
          transform: translateX(2px);
        }
        .shift-rank {
          font-family: var(--mono);
          font-size: 15px;
          font-weight: 600;
          color: var(--muted);
          min-width: 26px;
          padding-top: 2px;
        }
        .shift-body { flex: 1; min-width: 0; }
        .shift-meta {
          display: flex;
          flex-wrap: wrap;
          gap: 6px;
          align-items: center;
          margin-bottom: 8px;
        }
        .shift-score {
          font-family: var(--mono);
          font-size: 16px;
          font-weight: 700;
          color: var(--accent);
          min-width: 30px;
        }
        .badge-new {
          color: var(--accent);
          border-color: rgba(56, 217, 208, 0.4);
          background: var(--accent-dim);
          text-transform: uppercase;
          letter-spacing: 0.08em;
          font-size: 10px;
        }
        .shift-title {
          display: block;
          font-size: 16px;
          font-weight: 600;
          color: var(--text);
          line-height: 1.4;
          margin-bottom: 8px;
          overflow-wrap: anywhere;
        }
        .shift-title:hover { color: var(--accent); }
      `}</style>
    </motion.section>
  );
}

function formatDate(iso: string): string {
  try {
    return new Date(iso).toLocaleString(undefined, {
      month: 'short',
      day: 'numeric',
      hour: '2-digit',
      minute: '2-digit',
    });
  } catch {
    return iso;
  }
}
