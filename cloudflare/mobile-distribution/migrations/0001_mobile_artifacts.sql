CREATE TABLE IF NOT EXISTS builds (
  app TEXT NOT NULL,
  platform TEXT NOT NULL CHECK (platform = 'harmony'),
  source_sha TEXT NOT NULL,
  version TEXT NOT NULL,
  build TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'uploaded' CHECK (status IN ('uploaded', 'revoked')),
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (app, platform, source_sha, build)
);

CREATE TABLE IF NOT EXISTS artifacts (
  app TEXT NOT NULL,
  platform TEXT NOT NULL CHECK (platform = 'harmony'),
  source_sha TEXT NOT NULL,
  build TEXT NOT NULL,
  name TEXT NOT NULL,
  object_key TEXT NOT NULL,
  sha256 TEXT NOT NULL,
  bytes INTEGER NOT NULL CHECK (bytes > 0),
  content_type TEXT NOT NULL,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (app, platform, source_sha, build, name),
  UNIQUE (app, object_key)
);

CREATE INDEX IF NOT EXISTS builds_by_source
  ON builds (app, platform, source_sha, updated_at);

CREATE INDEX IF NOT EXISTS artifacts_by_source
  ON artifacts (app, platform, source_sha);
