-- CASEFILE 360 database schema
-- Create the database with:  sqlite3 casefile.db < database/schema.sql
--
-- Ten tables in three groups: investigation, GRC, and the links between them.
-- All timestamps are stored as ISO 8601 text in UTC, for example 2026-03-10T08:35:12Z.
-- They are converted to WAT for display, never in the database.

PRAGMA foreign_keys = ON;

-- ============================================================ INVESTIGATION

-- One row per incident.
CREATE TABLE IF NOT EXISTS cases (
    case_id     TEXT PRIMARY KEY,              -- NC-001
    title       TEXT NOT NULL,
    status      TEXT NOT NULL DEFAULT 'Open',  -- Open, Investigating, Contained, Closed
    severity    TEXT NOT NULL DEFAULT 'Medium',-- Low, Medium, High, Critical
    owner       TEXT,                          -- analyst username, e.g. c.nwosu
    opened_at   TEXT NOT NULL,
    closed_at   TEXT,
    summary     TEXT
);

-- One row per uploaded file. The hash is what makes the evidence defensible.
CREATE TABLE IF NOT EXISTS evidence (
    evidence_id     TEXT PRIMARY KEY,          -- NC-001-E03
    case_id         TEXT NOT NULL,
    filename        TEXT NOT NULL,
    file_type       TEXT,                      -- email, auth_log, dns_log, browser_csv, ...
    size_bytes      INTEGER,
    sha256          TEXT NOT NULL,
    stored_path     TEXT NOT NULL,             -- where the copy lives on disk
    source          TEXT,                      -- which system it came from
    acquired_at     TEXT,                      -- when it was collected from that system
    uploaded_at     TEXT NOT NULL,
    uploaded_by     TEXT,
    parse_status    TEXT NOT NULL DEFAULT 'pending', -- pending, parsed, failed
    parse_error     TEXT,
    notes           TEXT,
    FOREIGN KEY (case_id) REFERENCES cases(case_id)
);

-- The normalized events. Every parser writes rows in this one shape,
-- which is what lets seven different formats share a single timeline.
CREATE TABLE IF NOT EXISTS events (
    event_id    INTEGER PRIMARY KEY AUTOINCREMENT,
    case_id     TEXT NOT NULL,
    evidence_id TEXT NOT NULL,
    timestamp   TEXT,                          -- UTC; NULL if the source had none
    source_file TEXT NOT NULL,
    event_type  TEXT NOT NULL,                 -- sign_in, dns_query, process_start, ...
    actor       TEXT,
    target      TEXT,
    description TEXT NOT NULL,
    raw         TEXT,                          -- the original record, unchanged
    is_key      INTEGER NOT NULL DEFAULT 0,    -- analyst flagged this as important
    FOREIGN KEY (case_id) REFERENCES cases(case_id),
    FOREIGN KEY (evidence_id) REFERENCES evidence(evidence_id)
);

-- Indicators of compromise. The verdict column is the analyst's, not the platform's.
CREATE TABLE IF NOT EXISTS iocs (
    ioc_id       INTEGER PRIMARY KEY AUTOINCREMENT,
    case_id      TEXT NOT NULL,
    ioc_type     TEXT NOT NULL,                -- ip, domain, url, hash, email, filename
    value        TEXT NOT NULL,
    first_seen   TEXT,                         -- earliest event timestamp holding it
    source_file  TEXT,                         -- where it was first extracted
    verdict      TEXT NOT NULL DEFAULT 'unknown', -- malicious, benign, unknown
    notes        TEXT,
    FOREIGN KEY (case_id) REFERENCES cases(case_id),
    UNIQUE (case_id, ioc_type, value)          -- the same IOC is recorded once per case
);

-- Which events an IOC appears in. One IOC matches many events, and one event
-- can hold several IOCs, so the relationship needs its own table.
CREATE TABLE IF NOT EXISTS ioc_event (
    ioc_id   INTEGER NOT NULL,
    event_id INTEGER NOT NULL,
    PRIMARY KEY (ioc_id, event_id),
    FOREIGN KEY (ioc_id) REFERENCES iocs(ioc_id),
    FOREIGN KEY (event_id) REFERENCES events(event_id)
);

-- Analyst conclusions. Every finding must be supported by evidence.
CREATE TABLE IF NOT EXISTS findings (
    finding_id   INTEGER PRIMARY KEY AUTOINCREMENT,
    case_id      TEXT NOT NULL,
    title        TEXT NOT NULL,
    detail       TEXT,
    confidence   TEXT NOT NULL DEFAULT 'medium', -- low, medium, high
    created_at   TEXT NOT NULL,
    created_by   TEXT,
    FOREIGN KEY (case_id) REFERENCES cases(case_id)
);

-- Which evidence and events support a finding.
CREATE TABLE IF NOT EXISTS finding_evidence (
    finding_id  INTEGER NOT NULL,
    evidence_id TEXT NOT NULL,
    event_id    INTEGER,                       -- optional: a specific event
    PRIMARY KEY (finding_id, evidence_id, event_id),
    FOREIGN KEY (finding_id) REFERENCES findings(finding_id),
    FOREIGN KEY (evidence_id) REFERENCES evidence(evidence_id),
    FOREIGN KEY (event_id) REFERENCES events(event_id)
);

-- ===================================================================== GRC

-- The NexaCore assets, from docs/company/asset-inventory.md
CREATE TABLE IF NOT EXISTS assets (
    asset_id         TEXT PRIMARY KEY,         -- A-02
    name             TEXT NOT NULL,
    owner            TEXT,
    criticality      TEXT,                     -- Low, Medium, High, Critical
    business_process TEXT
);

-- The controls, from docs/company/security-controls.md
CREATE TABLE IF NOT EXISTS controls (
    control_id       TEXT PRIMARY KEY,         -- C-01
    name             TEXT NOT NULL,
    control_type     TEXT,                     -- Preventive, Detective, Corrective
    documented_state TEXT,                     -- what the policy says
    observed_state   TEXT,                     -- what the evidence shows
    effectiveness    TEXT,                     -- Effective, Partial, Ineffective, Not tested
    evidence_ref     TEXT,                     -- the evidence that proves it
    FOREIGN KEY (evidence_ref) REFERENCES evidence(evidence_id)
);

-- The risk register. Score is likelihood x impact, calculated by the application.
CREATE TABLE IF NOT EXISTS risks (
    risk_id    TEXT PRIMARY KEY,               -- R-01
    case_id    TEXT,
    statement  TEXT NOT NULL,
    asset_id   TEXT,
    likelihood INTEGER CHECK (likelihood BETWEEN 1 AND 5),
    impact     INTEGER CHECK (impact BETWEEN 1 AND 5),
    treatment  TEXT,                           -- Mitigate, Accept, Transfer, Avoid
    action     TEXT,
    owner      TEXT,
    due_date   TEXT,
    status     TEXT NOT NULL DEFAULT 'Open',   -- Open, In progress, Closed
    FOREIGN KEY (case_id) REFERENCES cases(case_id),
    FOREIGN KEY (asset_id) REFERENCES assets(asset_id)
);

-- =================================================================== LINKS
-- These two tables are what keep GRC tied to the investigation. Without them
-- the risk register is an opinion; with them, every risk traces back to a log line.

CREATE TABLE IF NOT EXISTS risk_control (
    risk_id    TEXT NOT NULL,
    control_id TEXT NOT NULL,
    PRIMARY KEY (risk_id, control_id),
    FOREIGN KEY (risk_id) REFERENCES risks(risk_id),
    FOREIGN KEY (control_id) REFERENCES controls(control_id)
);

CREATE TABLE IF NOT EXISTS finding_risk (
    finding_id INTEGER NOT NULL,
    risk_id    TEXT NOT NULL,
    PRIMARY KEY (finding_id, risk_id),
    FOREIGN KEY (finding_id) REFERENCES findings(finding_id),
    FOREIGN KEY (risk_id) REFERENCES risks(risk_id)
);

-- ================================================================= INDEXES
-- The timeline sorts by time, and the IOC screen counts matches. These make both quick.

CREATE INDEX IF NOT EXISTS idx_events_case_time ON events(case_id, timestamp);
CREATE INDEX IF NOT EXISTS idx_events_evidence  ON events(evidence_id);
CREATE INDEX IF NOT EXISTS idx_iocs_case        ON iocs(case_id);
CREATE INDEX IF NOT EXISTS idx_evidence_case    ON evidence(case_id);
