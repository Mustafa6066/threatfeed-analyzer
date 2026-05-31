import { AggregateCharts } from './components/AggregateCharts';
import { ArticleGrid } from './components/ArticleGrid';
import { CveTable } from './components/CveTable';
import { Header } from './components/Header';
import { ShiftBrief } from './components/ShiftBrief';
import { StatsBar } from './components/StatsBar';
import { useDashboardData } from './hooks/useDashboardData';

export default function App() {
  const { data, error, loading, reload } = useDashboardData();

  if (loading) {
    return (
      <div className="loading-screen">
        <div className="loading-pulse" />
        <p>Loading threat intelligence…</p>
      </div>
    );
  }

  if (error || !data) {
    return (
      <div className="error-screen">
        <h2>Dashboard data not available</h2>
        <p>{error ?? 'Unknown error'}</p>
        <code>.\ThreatFeed-Analyzer.ps1</code>
        <p>then</p>
        <code>cd dashboard && npm run dev</code>
        <button type="button" onClick={reload} className="retry-btn">
          Retry
        </button>
        <style>{`
          .retry-btn {
            margin-top: 8px;
            padding: 10px 20px;
            border-radius: 8px;
            border: 1px solid var(--border);
            background: var(--accent-dim);
            color: var(--accent);
            font-family: var(--sans);
            font-weight: 600;
            cursor: pointer;
          }
          .retry-btn:hover {
            border-color: var(--accent);
          }
        `}</style>
      </div>
    );
  }

  const runId =
    data.runMeta && typeof data.runMeta === 'object' && 'runId' in data.runMeta
      ? String((data.runMeta as { runId?: string }).runId)
      : undefined;

  return (
    <div className="shell">
      <Header stats={data.stats} runId={runId} />
      <StatsBar stats={data.stats} />
      <ShiftBrief items={data.shiftBrief} />
      <AggregateCharts aggregates={data.aggregates} tracking={data.tracking} cves={data.cves} />
      <CveTable
        cves={data.cves}
        totalCount={data.stats.cveCount}
        cveDays={data.stats.cveDays}
        nvdWarning={data.stats.nvdWarning}
      />
      <ArticleGrid articles={data.articles} />
      <footer className="footer">
        ThreatFeed Analyzer · engine {String((data.runMeta as { engine?: string })?.engine ?? 'powershell')}
        · bundle v{data.version}
      </footer>
      <style>{`
        .footer {
          margin-top: 32px;
          padding-top: 16px;
          border-top: 1px solid var(--border);
          font-size: 11px;
          color: var(--muted);
          font-family: var(--mono);
        }
      `}</style>
    </div>
  );
}
