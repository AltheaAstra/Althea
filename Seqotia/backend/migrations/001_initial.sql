CREATE TABLE IF NOT EXISTS folders (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL CHECK(length(name) BETWEEN 1 AND 120),
    parent_id INTEGER REFERENCES folders(id) ON DELETE RESTRICT,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    archived_at TEXT
);
CREATE INDEX IF NOT EXISTS idx_folders_parent ON folders(parent_id);

CREATE TABLE IF NOT EXISTS documents (
    id TEXT PRIMARY KEY,
    file_name TEXT NOT NULL,
    original_file_name TEXT,
    file_type TEXT NOT NULL,
    file_size INTEGER NOT NULL DEFAULT 0 CHECK(file_size >= 0),
    folder_id INTEGER REFERENCES folders(id) ON DELETE RESTRICT,
    category TEXT NOT NULL,
    created_by TEXT NOT NULL DEFAULT 'Local user',
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    processing_status TEXT NOT NULL,
    approval_status TEXT NOT NULL,
    current_version INTEGER NOT NULL DEFAULT 1,
    tags_json TEXT NOT NULL DEFAULT '[]',
    extracted_text_status TEXT NOT NULL,
    storage_key TEXT,
    extracted_text TEXT,
    metadata_json TEXT NOT NULL DEFAULT '{}',
    archived_at TEXT
);
CREATE INDEX IF NOT EXISTS idx_documents_updated ON documents(updated_at DESC);
CREATE INDEX IF NOT EXISTS idx_documents_category ON documents(category);
CREATE INDEX IF NOT EXISTS idx_documents_folder ON documents(folder_id);

CREATE TABLE IF NOT EXISTS document_history (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    document_id TEXT NOT NULL REFERENCES documents(id) ON DELETE CASCADE,
    version INTEGER NOT NULL,
    actor TEXT NOT NULL,
    action TEXT NOT NULL,
    details_json TEXT NOT NULL DEFAULT '{}',
    created_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_history_document ON document_history(document_id, created_at DESC);

CREATE TABLE IF NOT EXISTS ai_suggestions (
    id TEXT PRIMARY KEY,
    document_type TEXT NOT NULL,
    field_name TEXT NOT NULL,
    provider TEXT NOT NULL,
    created_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS ai_feedback (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    suggestion_id TEXT NOT NULL REFERENCES ai_suggestions(id) ON DELETE CASCADE,
    accepted INTEGER NOT NULL,
    correction TEXT,
    created_at TEXT NOT NULL
);
