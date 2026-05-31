export interface MitreTag {
  id: string;
  name: string;
}

export interface DashboardArticle {
  key: string;
  title: string;
  link: string;
  summary: string;
  source: string;
  category: string;
  published: string;
  firstSeen: string;
  keywords: string[];
  mitre: MitreTag[];
  priorityScore?: number;
  reasonChips?: string[];
  isNew?: boolean;
}

export interface CveRow {
  id: string;
  published: string;
  score: number | null;
  severity: string;
  description: string;
}

export interface TrackingRow {
  topic: string;
  total: number;
  last7: number;
  prev7: number;
  trend: 'up' | 'down' | 'flat' | string;
  lastSeen: string;
  spark: number[];
}

export interface DashboardBundle {
  version: number;
  generatedAt: string;
  runMeta?: Record<string, unknown>;
  stats: {
    generatedAt: string;
    feedsTotal: number;
    feedsOk: number;
    fetched: number;
    matched: number;
    new: number;
    duplicates: number;
    cveCount: number;
    totalTracked: number;
    topicCount: number;
    cveDays: number;
    nvdWarning?: string | null;
  };
  shiftBrief: DashboardArticle[];
  articles: DashboardArticle[];
  aggregates: {
    keywords: { labels: string[]; values: number[] };
    mitre: { labels: string[]; values: number[] };
  };
  tracking: {
    rows: TrackingRow[];
    trendDays: string[];
    trendSeries: { topic: string; values: number[] }[];
  };
  cves: CveRow[];
}
