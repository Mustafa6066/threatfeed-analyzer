import { useMemo, useState } from 'react';
import { motion } from 'framer-motion';
import type { CveRow } from '../types';
import { fadeUp, inView } from '../lib/motion';

interface Props {
  cves: CveRow[];
  totalCount: number;
  cveDays: number;
  nvdWarning?: string | null;
}

type SortKey = 'score' | 'published' | 'severity';
const SEV_RANK: Record<string, number> = { critical: 4, high: 3, medium: 2, low: 1, unknown: 0 };

export function CveTable({ cves, totalCount, cveDays, nvdWarning }: Props) {
  const [sortKey, setSortKey] = useState<SortKey>('score');
  const [asc, setAsc] = useState(false);

  const sorted = useMemo(() => {
    const rows = [...cves];
    rows.sort((a, b) => {
      let cmp = 0;
      if (sortKey === 'score') cmp = (a.score ?? -1) - (b.score ?? -1);
      else if (sortKey === 'severity')
        cmp = (SEV_RANK[(a.severity || '').toLowerCase()] ?? 0) - (SEV_RANK[(b.severity || '').toLowerCase()] ?? 0);
      else cmp = String(a.published).localeCompare(String(b.published));
      return asc ? cmp : -cmp;
    });
    return rows;
  }, [cves, sortKey, asc]);

  const toggle = (key: SortKey) => {
    if (key === sortKey) setAsc((v) => !v);
    else {
      setSortKey(key);
      setAsc(false);
    }
  };

  const arrow = (key: SortKey) => (key === sortKey ? (asc ? ' ↑' : ' ↓') : '');

  return (
    <motion.section
      className="panel cve-section"
      id="cves"
      variants={fadeUp}
      initial="hidden"
      whileInView="show"
      viewport={inView}
    >
      <h2 className="panel-title">
        CVE digest · last {cveDays}d ({totalCount} total · showing {cves.length})
      </h2>
      {nvdWarning ? <p className="cve-warn">{nvdWarning}</p> : null}
      {cves.length === 0 ? (
        <p className="empty">No CVE data in this bundle.</p>
      ) : (
        <div className="cve-table-wrap">
          <table className="cve-table">
            <thead>
              <tr>
                <th>CVE</th>
                <th className="sortable" onClick={() => toggle('score')}>
                  CVSS{arrow('score')}
                </th>
                <th className="sortable" onClick={() => toggle('severity')}>
                  Severity{arrow('severity')}
                </th>
                <th className="sortable" onClick={() => toggle('published')}>
                  Published{arrow('published')}
                </th>
                <th>Summary</th>
              </tr>
            </thead>
            <tbody>
              {sorted.map((c) => (
                <tr key={c.id}>
                  <td>
                    <a href={`https://nvd.nist.gov/vuln/detail/${c.id}`} target="_blank" rel="noreferrer">
                      {c.id}
                    </a>
                  </td>
                  <td className="mono">{c.score ?? '—'}</td>
                  <td>
                    <span className={`sev sev-${(c.severity || 'unknown').toLowerCase()}`}>{c.severity}</span>
                  </td>
                  <td className="mono">{c.published}</td>
                  <td className="cve-desc">{c.description}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
      <style>{`
        .cve-warn { color: var(--warn); font-size: 13px; margin: -6px 0 12px; }
        .cve-table-wrap { overflow-x: auto; }
        .cve-table { width: 100%; border-collapse: collapse; font-size: 13px; }
        .cve-table th {
          text-align: left;
          padding: 10px 12px;
          font-size: 10px;
          text-transform: uppercase;
          letter-spacing: 0.08em;
          color: var(--muted);
          border-bottom: 1px solid var(--border);
          position: sticky;
          top: 0;
          background: var(--panel-solid);
          white-space: nowrap;
        }
        .cve-table th.sortable { cursor: pointer; user-select: none; }
        .cve-table th.sortable:hover { color: var(--accent); }
        .cve-table td {
          padding: 10px 12px;
          border-bottom: 1px solid rgba(120,160,200,0.07);
          vertical-align: top;
        }
        .cve-table tbody tr { transition: background 0.15s var(--ease); }
        .cve-table tbody tr:hover td { background: rgba(56,217,208,0.04); }
        .mono { font-family: var(--mono); font-size: 12px; }
        .cve-desc { color: var(--text-dim); max-width: 460px; line-height: 1.45; }
        .sev {
          font-size: 10px;
          font-weight: 700;
          text-transform: uppercase;
          letter-spacing: 0.04em;
          padding: 2px 9px;
          border-radius: 999px;
        }
        .sev-critical { background: rgba(251,95,122,0.18); color: var(--crit); }
        .sev-high { background: rgba(251,146,60,0.18); color: var(--high); }
        .sev-medium { background: rgba(250,204,21,0.15); color: var(--med); }
        .sev-low { background: rgba(52,211,153,0.15); color: var(--low); }
        .sev-unknown { color: var(--muted); }
      `}</style>
    </motion.section>
  );
}
