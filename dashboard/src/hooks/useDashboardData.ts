import { useEffect, useState } from 'react';
import type { DashboardBundle } from '../types';

const DATA_URL = `${import.meta.env.BASE_URL}data/dashboard.json`;

export function useDashboardData() {
  const [data, setData] = useState<DashboardBundle | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    let cancelled = false;
    (async () => {
      try {
        const res = await fetch(DATA_URL, { cache: 'no-store' });
        if (!res.ok) throw new Error(`HTTP ${res.status} — run ThreatFeed-Analyzer.ps1 or .\\Sync-DashboardData.ps1`);
        const json = (await res.json()) as DashboardBundle;
        if (!cancelled) setData(json);
      } catch (e) {
        if (!cancelled) setError(e instanceof Error ? e.message : 'Failed to load dashboard data');
      } finally {
        if (!cancelled) setLoading(false);
      }
    })();
    return () => {
      cancelled = true;
    };
  }, []);

  return { data, error, loading, reload: () => window.location.reload() };
}
