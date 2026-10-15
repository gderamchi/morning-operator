CREATE TABLE public_catalogs (
  toolkit_slug TEXT NOT NULL,
  toolkit_version TEXT NOT NULL,
  payload_json TEXT NOT NULL,
  PRIMARY KEY (toolkit_slug, toolkit_version)
) WITHOUT ROWID;
