import { useMemo, useState } from 'react';
import { motion } from 'framer-motion';
import type { DashboardArticle } from '../types';
import { fadeUp, inView, staggerContainer } from '../lib/motion';

interface Props {
  articles: DashboardArticle[];
}

export function ArticleGrid({ articles }: Props) {
  const [query, setQuery] = useState('');
  const [category, setCategory] = useState<string>('All');
  const [newOnly, setNewOnly] = useState(false);

  const categories = useMemo(() => {
    const set = new Set<string>();
    for (const a of articles) if (a.category) set.add(a.category);
    return ['All', ...Array.from(set).sort()];
  }, [articles]);

  const filtered = useMemo(() => {
    const q = query.trim().toLowerCase();
    return articles.filter((a) => {
      if (newOnly && !a.isNew) return false;
      if (category !== 'All' && a.category !== category) return false;
      if (!q) return true;
      return (
        a.title.toLowerCase().includes(q) ||
        a.summary.toLowerCase().includes(q) ||
        a.source.toLowerCase().includes(q) ||
        a.keywords.some((k) => k.toLowerCase().includes(q)) ||
        a.mitre.some((m) => m.id.toLowerCase().includes(q))
      );
    });
  }, [articles, query, category, newOnly]);

  return (
    <motion.section
      className="panel articles-section"
      id="articles"
      variants={fadeUp}
      initial="hidden"
      whileInView="show"
      viewport={inView}
    >
      <h2 className="panel-title">Tracked articles</h2>

      <div className="articles-toolbar">
        <input
          type="search"
          placeholder="Filter by title, source, keyword, MITRE…"
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          aria-label="Filter articles"
        />
        <span className="articles-count">
          {filtered.length} / {articles.length}
        </span>
      </div>

      <div className="articles-filters">
        {categories.map((c) => (
          <button
            key={c}
            type="button"
            className={`filter-pill${category === c ? ' active' : ''}`}
            onClick={() => setCategory(c)}
          >
            {c}
          </button>
        ))}
        <button
          type="button"
          className={`filter-pill${newOnly ? ' active' : ''}`}
          onClick={() => setNewOnly((v) => !v)}
        >
          New only
        </button>
      </div>

      <motion.div
        className="article-grid"
        variants={staggerContainer(0.03)}
        initial="hidden"
        animate="show"
        key={`${category}-${newOnly}-${query}`}
      >
        {filtered.map((a) => (
          <motion.article key={a.key} className="article-card" variants={fadeUp}>
            <div className="article-meta">
              <span className={`badge cat-${a.category || 'News'}`}>{a.category}</span>
              <span className="badge">{a.source}</span>
              {a.published ? <span className="badge">{formatDate(a.published)}</span> : null}
              {typeof a.priorityScore === 'number' ? (
                <span className="article-score">{a.priorityScore}</span>
              ) : null}
            </div>
            <h3>
              <a href={a.link} target="_blank" rel="noreferrer">
                {a.title}
              </a>
            </h3>
            {a.summary ? <p className="article-summary">{a.summary}</p> : null}
            <div className="chips-row">
              {a.keywords.map((k) => (
                <span key={k} className="chip kw">
                  {k}
                </span>
              ))}
              {a.mitre.map((m) => (
                <span key={m.id} className="chip mitre" title={m.name}>
                  {m.id}
                </span>
              ))}
            </div>
          </motion.article>
        ))}
      </motion.div>
      {filtered.length === 0 ? <p className="empty">No articles match your filter.</p> : null}

      <style>{`
        .articles-toolbar {
          display: flex;
          gap: 12px;
          align-items: center;
          margin-bottom: 12px;
        }
        .articles-toolbar input {
          flex: 1;
          min-width: 0;
          padding: 11px 14px;
          border-radius: var(--radius-sm);
          border: 1px solid var(--border);
          background: rgba(0, 0, 0, 0.25);
          color: var(--text);
          font-family: var(--sans);
          font-size: 14px;
          outline: none;
          transition: border-color 0.18s var(--ease), box-shadow 0.18s var(--ease);
        }
        .articles-toolbar input:focus {
          border-color: var(--accent);
          box-shadow: 0 0 0 3px var(--accent-dim);
        }
        .articles-count {
          font-family: var(--mono);
          font-size: 12px;
          color: var(--muted);
          white-space: nowrap;
        }
        .articles-filters {
          display: flex;
          flex-wrap: wrap;
          gap: 8px;
          margin-bottom: 18px;
        }
        .filter-pill {
          font-family: var(--sans);
          font-size: 12px;
          padding: 5px 12px;
          border-radius: 999px;
          border: 1px solid var(--border);
          background: transparent;
          color: var(--muted);
          cursor: pointer;
          transition: all 0.16s var(--ease);
        }
        .filter-pill:hover { color: var(--text); border-color: var(--border-strong); }
        .filter-pill.active {
          color: var(--accent);
          border-color: rgba(56,217,208,0.4);
          background: var(--accent-dim);
        }
        .article-grid {
          display: grid;
          grid-template-columns: repeat(auto-fill, minmax(300px, 1fr));
          gap: 14px;
          min-width: 0;
        }
        .article-card {
          padding: 16px;
          border-radius: var(--radius-sm);
          border: 1px solid var(--border);
          background: rgba(0, 0, 0, 0.18);
          transition: border-color 0.2s var(--ease), transform 0.2s var(--ease), box-shadow 0.2s var(--ease);
          min-width: 0;
          overflow: hidden;
          display: flex;
          flex-direction: column;
          gap: 8px;
        }
        .article-card:hover {
          border-color: rgba(56,217,208,0.32);
          transform: translateY(-3px);
          box-shadow: var(--shadow-soft);
        }
        .article-meta {
          display: flex;
          flex-wrap: wrap;
          gap: 6px;
          align-items: center;
        }
        .article-score {
          margin-left: auto;
          font-family: var(--mono);
          font-size: 14px;
          font-weight: 700;
          color: var(--accent);
        }
        .article-card h3 {
          margin: 0;
          font-size: 15.5px;
          line-height: 1.4;
          min-width: 0;
          overflow: hidden;
        }
        .article-card h3 a {
          color: var(--text);
          display: block;
          max-width: 100%;
          overflow-wrap: anywhere;
          word-break: break-word;
        }
        .article-card h3 a:hover { color: var(--accent); }
        .article-summary {
          margin: 0;
          font-size: 13px;
          color: var(--muted);
          line-height: 1.5;
          display: -webkit-box;
          -webkit-line-clamp: 3;
          -webkit-box-orient: vertical;
          overflow: hidden;
        }
        .article-card .chips-row { margin-top: auto; }
        @media (max-width: 560px) {
          .article-grid { grid-template-columns: 1fr; }
        }
      `}</style>
    </motion.section>
  );
}

function formatDate(iso: string): string {
  try {
    return new Date(iso).toLocaleDateString(undefined, { month: 'short', day: 'numeric' });
  } catch {
    return iso;
  }
}
