import {
  Area,
  AreaChart,
  Bar,
  BarChart,
  Cell,
  Pie,
  PieChart,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from 'recharts';
import { motion, useReducedMotion } from 'framer-motion';
import type { CveRow, DashboardBundle } from '../types';
import { fadeUp, inView, staggerContainer } from '../lib/motion';

interface Props {
  aggregates: DashboardBundle['aggregates'];
  tracking: DashboardBundle['tracking'];
  cves: CveRow[];
}

const SEV_ORDER = ['Critical', 'High', 'Medium', 'Low', 'Unknown'];
const SEV_COLOR: Record<string, string> = {
  Critical: '#fb5f7a',
  High: '#fb923c',
  Medium: '#facc15',
  Low: '#34d399',
  Unknown: '#7e93ad',
};

const tooltipStyle = {
  background: '#0c121c',
  border: '1px solid rgba(120,160,200,0.22)',
  borderRadius: 10,
  fontSize: 12,
  color: '#eaf0f8',
} as const;

export function AggregateCharts({ aggregates, tracking, cves }: Props) {
  const reduce = useReducedMotion();
  const animate = !reduce;

  const kwData = aggregates.keywords.labels.map((label, i) => ({
    name: truncate(label, 18),
    full: label,
    count: aggregates.keywords.values[i] ?? 0,
  }));

  const mitreData = aggregates.mitre.labels.map((label, i) => ({
    name: truncate(label, 22),
    full: label,
    count: aggregates.mitre.values[i] ?? 0,
  }));

  const sevData = buildSeverity(cves);
  const trendData = buildTrend(tracking);

  return (
    <motion.div
      className="viz-grid"
      variants={staggerContainer(0.08)}
      initial="hidden"
      whileInView="show"
      viewport={inView}
    >
      <motion.div className="panel viz-card" variants={fadeUp}>
        <h2 className="panel-title">Keyword distribution</h2>
        <Bars data={kwData} color="#38d9d0" animate={animate} />
      </motion.div>

      <motion.div className="panel viz-card" variants={fadeUp}>
        <h2 className="panel-title">MITRE ATT&CK</h2>
        <Bars data={mitreData} color="#6f8cff" animate={animate} />
      </motion.div>

      <motion.div className="panel viz-card" variants={fadeUp}>
        <h2 className="panel-title">CVE severity mix</h2>
        {sevData.length === 0 ? (
          <p className="empty">No CVE data in this bundle.</p>
        ) : (
          <div className="donut-wrap">
            <ResponsiveContainer width="100%" height={220}>
              <PieChart>
                <Pie
                  data={sevData}
                  dataKey="value"
                  nameKey="name"
                  innerRadius={58}
                  outerRadius={86}
                  paddingAngle={2}
                  stroke="none"
                  isAnimationActive={animate}
                >
                  {sevData.map((d) => (
                    <Cell key={d.name} fill={SEV_COLOR[d.name] ?? '#7e93ad'} />
                  ))}
                </Pie>
                <Tooltip contentStyle={tooltipStyle} />
              </PieChart>
            </ResponsiveContainer>
            <ul className="donut-legend">
              {sevData.map((d) => (
                <li key={d.name}>
                  <span className="dot" style={{ background: SEV_COLOR[d.name] }} />
                  {d.name}
                  <span className="dl-val">{d.value}</span>
                </li>
              ))}
            </ul>
          </div>
        )}
      </motion.div>

      <motion.div className="panel viz-card viz-wide" variants={fadeUp}>
        <h2 className="panel-title">Threat activity · tracked window</h2>
        {trendData.length === 0 ? (
          <p className="empty">No trend data yet — tracking builds over multiple runs.</p>
        ) : (
          <ResponsiveContainer width="100%" height={200}>
            <AreaChart data={trendData} margin={{ left: 0, right: 8, top: 8, bottom: 0 }}>
              <defs>
                <linearGradient id="trendFill" x1="0" y1="0" x2="0" y2="1">
                  <stop offset="0%" stopColor="#38d9d0" stopOpacity={0.42} />
                  <stop offset="100%" stopColor="#38d9d0" stopOpacity={0} />
                </linearGradient>
              </defs>
              <XAxis
                dataKey="day"
                tick={{ fill: '#7e93ad', fontSize: 10 }}
                axisLine={false}
                tickLine={false}
                minTickGap={24}
              />
              <YAxis
                tick={{ fill: '#7e93ad', fontSize: 10 }}
                axisLine={false}
                tickLine={false}
                width={28}
                allowDecimals={false}
              />
              <Tooltip contentStyle={tooltipStyle} />
              <Area
                type="monotone"
                dataKey="count"
                stroke="#38d9d0"
                strokeWidth={2}
                fill="url(#trendFill)"
                isAnimationActive={animate}
              />
            </AreaChart>
          </ResponsiveContainer>
        )}
      </motion.div>

      <style>{`
        .viz-grid {
          display: grid;
          grid-template-columns: repeat(3, 1fr);
          gap: 16px;
        }
        .viz-wide { grid-column: 1 / -1; }
        .viz-card { min-height: 280px; }
        .donut-wrap { display: flex; align-items: center; gap: 8px; flex-wrap: wrap; }
        .donut-wrap > div { flex: 1; min-width: 160px; }
        .donut-legend {
          list-style: none;
          margin: 0;
          padding: 0;
          display: flex;
          flex-direction: column;
          gap: 7px;
          font-size: 12px;
          color: var(--text-dim);
          min-width: 120px;
        }
        .donut-legend li { display: flex; align-items: center; gap: 8px; }
        .donut-legend .dot { width: 9px; height: 9px; border-radius: 3px; }
        .dl-val { margin-left: auto; font-family: var(--mono); color: var(--muted); }
        @media (max-width: 980px) {
          .viz-grid { grid-template-columns: 1fr 1fr; }
          .viz-wide { grid-column: 1 / -1; }
        }
        @media (max-width: 640px) {
          .viz-grid { grid-template-columns: 1fr; }
        }
      `}</style>
    </motion.div>
  );
}

function Bars({
  data,
  color,
  animate,
}: {
  data: { name: string; full: string; count: number }[];
  color: string;
  animate: boolean;
}) {
  if (data.length === 0) return <p className="empty">No data yet.</p>;
  return (
    <ResponsiveContainer width="100%" height={220}>
      <BarChart data={data} layout="vertical" margin={{ left: 4, right: 12, top: 4, bottom: 4 }}>
        <XAxis type="number" tick={{ fill: '#7e93ad', fontSize: 11 }} axisLine={false} tickLine={false} />
        <YAxis
          type="category"
          dataKey="name"
          width={104}
          tick={{ fill: '#b6c4d6', fontSize: 10 }}
          axisLine={false}
          tickLine={false}
        />
        <Tooltip
          cursor={{ fill: 'rgba(120,160,200,0.06)' }}
          contentStyle={tooltipStyle}
          labelFormatter={(_, payload) => payload?.[0]?.payload?.full ?? ''}
        />
        <Bar dataKey="count" fill={color} radius={[0, 5, 5, 0]} maxBarSize={16} isAnimationActive={animate} />
      </BarChart>
    </ResponsiveContainer>
  );
}

function buildSeverity(cves: CveRow[]): { name: string; value: number }[] {
  const counts = new Map<string, number>();
  for (const c of cves) {
    const sev = normalizeSeverity(c.severity);
    counts.set(sev, (counts.get(sev) ?? 0) + 1);
  }
  return SEV_ORDER.filter((s) => counts.has(s)).map((s) => ({ name: s, value: counts.get(s) ?? 0 }));
}

function normalizeSeverity(raw: string): string {
  const s = (raw || '').toLowerCase();
  if (s.startsWith('crit')) return 'Critical';
  if (s.startsWith('high')) return 'High';
  if (s.startsWith('med')) return 'Medium';
  if (s.startsWith('low')) return 'Low';
  return 'Unknown';
}

function buildTrend(tracking: DashboardBundle['tracking']): { day: string; count: number }[] {
  if (!tracking?.trendDays?.length || !tracking?.trendSeries?.length) return [];
  return tracking.trendDays.map((day, i) => {
    let total = 0;
    for (const series of tracking.trendSeries) total += series.values[i] ?? 0;
    return { day: shortDay(day), count: total };
  });
}

function shortDay(iso: string): string {
  try {
    return new Date(iso).toLocaleDateString(undefined, { month: 'short', day: 'numeric' });
  } catch {
    return iso;
  }
}

function truncate(s: string, n: number): string {
  return s.length > n ? `${s.slice(0, n - 1)}…` : s;
}
