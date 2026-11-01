-- Archive table for Bing daily wallpapers (metadata in D1, binary assets in R2)
CREATE TABLE IF NOT EXISTS bing_wallpapers (
  end_date TEXT PRIMARY KEY,
  start_date TEXT NOT NULL,
  title TEXT NOT NULL,
  copyright TEXT NOT NULL,
  copyright_link TEXT,
  url_base TEXT NOT NULL,
  full_r2_key TEXT NOT NULL,
  thumb_r2_key TEXT NOT NULL,
  byte_size INTEGER NOT NULL DEFAULT 0,
  thumb_byte_size INTEGER NOT NULL DEFAULT 0,
  mkt TEXT NOT NULL DEFAULT 'zh-CN',
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_bing_wallpapers_end_date ON bing_wallpapers(end_date DESC);
