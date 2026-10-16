CREATE TABLE voice_activation_requests (
  user_id TEXT PRIMARY KEY NOT NULL REFERENCES installations(user_id),
  requested_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);
