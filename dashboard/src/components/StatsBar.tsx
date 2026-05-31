import { useEffect, useRef, useState } from 'react';
import { animate, motion, useReducedMotion } from 'framer-motion';
import type { DashboardBundle } from '../types';
import { fadeUp, staggerContainer } from '../lib/motion';

interface Props {
  stats: DashboardBundle['stats'];
}

const items: { key: keyof DashboardBundle['stats']; label: string; accent?: boolean }[] = [
  { key: 'feedsOk', label: 'Feeds OK' },
  { key: 'fetched', label: 'Fetched' },
  { key: 'matched', label: 'Matched', accent: true },
  { key: 'new', label: 'New today', accent: true },
  { key: 'totalTracked', label: 'Tracked · 45d' },
  { key: 'cveCount', label: 'CVEs' },
];

export function StatsBar({ stats }: Props) {
  return (
    <motion.div
      className="stats-bar"
      variants={staggerContainer(0.06)}
      initial="hidden"
      animate="show"
    >
      {items.map(({ key, label, accent }) => {
        const numeric = stats[key] as number;
        const suffix = key === 'feedsOk' ? `/${stats.feedsTotal}` : '';
        return (
          <motion.div key={key} className={`stat-card${accent ? ' stat-accent' : ''}`} variants={fadeUp}>
            <div className="stat-n">
              <AnimatedNumber value={numeric} />
              {suffix ? <span className="stat-suffix">{suffix}</span> : null}
            </div>
            <div className="stat-l">{label}</div>
          </motion.div>
        );
      })}
      <style>{`
        .stats-bar {
          display: grid;
          grid-template-columns: repeat(auto-fit, minmax(140px, 1fr));
          gap: 12px;
        }
        .stat-card {
          position: relative;
          background: var(--panel);
          border: 1px solid var(--border);
          border-radius: var(--radius-sm);
          padding: 16px 18px;
          overflow: hidden;
          transition: border-color 0.2s var(--ease), transform 0.2s var(--ease);
        }
        .stat-card::after {
          content: '';
          position: absolute;
          inset: 0 auto 0 0;
          width: 2px;
          background: var(--border-strong);
          transition: background 0.2s var(--ease);
        }
        .stat-accent::after { background: var(--accent); box-shadow: 0 0 14px var(--accent-glow); }
        .stat-card:hover { border-color: var(--border-strong); transform: translateY(-2px); }
        .stat-n {
          font-family: var(--mono);
          font-size: 28px;
          font-weight: 600;
          color: var(--text);
          letter-spacing: -0.03em;
          line-height: 1.1;
          display: flex;
          align-items: baseline;
        }
        .stat-accent .stat-n { color: var(--accent); }
        .stat-suffix { font-size: 16px; color: var(--muted); margin-left: 2px; }
        .stat-l {
          margin-top: 6px;
          font-size: 10px;
          text-transform: uppercase;
          letter-spacing: 0.12em;
          color: var(--muted);
        }
      `}</style>
    </motion.div>
  );
}

function AnimatedNumber({ value }: { value: number }) {
  const reduce = useReducedMotion();
  const [display, setDisplay] = useState(reduce ? value : 0);
  const ref = useRef(value);

  useEffect(() => {
    if (reduce) {
      setDisplay(value);
      return;
    }
    const controls = animate(ref.current, value, {
      duration: 0.9,
      ease: [0.22, 1, 0.36, 1],
      onUpdate: (v) => setDisplay(Math.round(v)),
    });
    ref.current = value;
    return () => controls.stop();
  }, [value, reduce]);

  return <span>{display.toLocaleString()}</span>;
}
