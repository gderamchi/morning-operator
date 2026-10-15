CREATE TABLE installations (
  token_hash TEXT PRIMARY KEY NOT NULL,
  user_id TEXT NOT NULL UNIQUE
);

CREATE TABLE executions (
  user_id TEXT NOT NULL,
  request_id TEXT NOT NULL,
  fingerprint TEXT NOT NULL,
  state TEXT NOT NULL CHECK (state IN ('pending', 'complete', 'uncertain')),
  receipt_json TEXT,
  PRIMARY KEY (user_id, request_id),
  CHECK ((state = 'complete' AND receipt_json IS NOT NULL) OR (state <> 'complete' AND receipt_json IS NULL))
) WITHOUT ROWID;
