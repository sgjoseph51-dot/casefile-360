# CASEFILE 360: architecture

How the application is put together, written before the code so that every later decision has somewhere to fit. If you are new to the project, read this first.

- **Stack:** Python, Flask, SQLite, server-rendered HTML
- **Shape:** one web application, four layers, one database file
- **Status:** design agreed, no code written yet

## 1. The four layers

A single large `app.py` works for fifty lines and becomes unmanageable at five hundred. Instead the code is split into four layers, each with one job.

| Layer | Job | May call |
| --- | --- | --- |
| Routes | Receive a web request, call a service, render a page | Services |
| Services | Do the work: hash, parse, extract, correlate, build the timeline | Models and parsers |
| Models | Read and write the database | SQLite only |
| Parsers | Turn one evidence format into normalized events | Nothing else |

**The rule: a layer may only call the one below it.** A route never writes SQL. A parser never touches the database. Breaking this rule is what turns a small project into one nobody can change safely.

Three things follow from it:

- When something breaks, the layer tells you where to look. A wrong date on screen is a parser problem, not a route problem.
- Parsers can be tested without starting a web server, because they are ordinary functions that take text and return events.
- A new evidence format means a new parser and nothing else.

## 2. Folder structure

```
casefile-360/
├── backend/
│   ├── app.py              Creates the Flask application and registers routes
│   ├── config.py           Paths and settings in one place
│   ├── routes/             One file per screen
│   │   ├── cases.py
│   │   ├── evidence.py
│   │   ├── iocs.py
│   │   ├── timeline.py
│   │   ├── findings.py
│   │   └── grc.py
│   ├── services/           The real work
│   │   ├── case_service.py
│   │   ├── evidence_service.py
│   │   ├── ioc_service.py
│   │   ├── timeline_service.py
│   │   └── report_service.py
│   ├── models/             Database access
│   │   ├── db.py           Opens the connection, runs the schema
│   │   ├── case_model.py
│   │   ├── evidence_model.py
│   │   ├── event_model.py
│   │   ├── ioc_model.py
│   │   └── grc_model.py
│   ├── parsers/            One per evidence format
│   │   ├── base.py         The normalized event shape
│   │   ├── email_parser.py
│   │   ├── auth_parser.py
│   │   ├── dns_parser.py
│   │   ├── browser_parser.py
│   │   ├── endpoint_parser.py
│   │   ├── mailbox_parser.py
│   │   └── alert_parser.py
│   ├── templates/          HTML pages Flask renders
│   └── static/             CSS and a little JavaScript
├── database/
│   └── schema.sql          CREATE TABLE statements
├── evidence/               The synthetic evidence set
├── docs/
├── tools/
│   └── generate_evidence.py
└── tests/
```

Uploaded files are stored under `backend/uploads/`, which is excluded from Git. Evidence belongs in the repo only as the generated set in `evidence/`.

## 3. The normalized event

This is the most important decision in the document. Seven evidence formats cannot share a timeline unless they first become the same kind of thing.

Every parser, whatever it reads, returns a list of dictionaries with these keys:

| Field | Type | Meaning | Example |
| --- | --- | --- | --- |
| `timestamp` | Text, ISO 8601 UTC | When it happened | `2026-03-10T08:35:12Z` |
| `source_file` | Text | Which evidence file it came from | `authentication.log` |
| `evidence_id` | Text | Which upload it came from | `NC-001-E03` |
| `event_type` | Text | A short category | `sign_in` |
| `actor` | Text or empty | Who or what did it | `a.okafor` |
| `target` | Text or empty | What it was done to | `Exchange Online` |
| `description` | Text | One line a human can read | `Successful sign-in from 198.51.100.140, no MFA` |
| `raw` | Text (JSON) | The original record, unchanged | `{"timestamp": "...", ...}` |

Two rules about this shape:

- **Timestamps are stored in UTC and displayed in WAT.** The evidence files are already UTC; the conversion happens once, in the template, not scattered through the code.
- **`raw` is never dropped.** When an analyst asks why the platform claims something, the original record is right there.

The shape itself lives in `parsers/base.py`, so every parser imports it rather than inventing its own.

## 4. The evidence journey

What happens to `phishing-email.eml` from upload to timeline. Each step names the layer that does it.

| Step | Layer | What happens |
| --- | --- | --- |
| 1. Upload | Route (`evidence.py`) | Receives the file from the form, saves it to `backend/uploads/`, hands the path to the service |
| 2. Identify | Service (`evidence_service.py`) | Works out the type from the extension and contents: `.eml` is an email |
| 3. Hash | Service | Reads the saved file and computes its SHA-256 |
| 4. Record | Model (`evidence_model.py`) | Writes one row: evidence ID, filename, type, size, hash, upload time, uploader |
| 5. Parse | Parser (`email_parser.py`) | Reads a copy of the file and returns normalized events; never writes to the database |
| 6. Extract | Service (`ioc_service.py`) | Pulls IPs, domains, URLs, hashes and email addresses out of the events |
| 7. Store events | Model (`event_model.py`) | Writes the events, each linked to its evidence row |
| 8. Store IOCs | Model (`ioc_model.py`) | Writes new IOCs; links ones already seen to this evidence too |
| 9. Correlate | Service (`timeline_service.py`) | Finds every event whose text contains a known IOC value |
| 10. Timeline | Route (`timeline.py`) | Fetches events in time order and renders the page |

Notice what step 5 does not do. The parser returns events and stops. The service decides what to do with them. That separation is why a parser can be tested with ten lines of code and no web server.

## 5. The database

One SQLite file, `casefile.db`, created from `database/schema.sql`. Ten tables in three groups.

**Investigation**

| Table | Holds |
| --- | --- |
| `cases` | One row per incident: ID, title, status, severity, owner, opened time, summary |
| `evidence` | One row per uploaded file: ID, case, filename, type, size, SHA-256, upload time, parse status |
| `events` | The normalized events, many per evidence file |
| `iocs` | Indicators: type, value, first seen, analyst verdict |
| `findings` | Analyst conclusions, each linked to the evidence and events behind it |

**GRC**

| Table | Holds |
| --- | --- |
| `assets` | The thirteen NexaCore assets |
| `controls` | The eleven controls, documented state against observed state |
| `risks` | The risk register: statement, likelihood, impact, score, treatment, owner |

**Links**

| Table | Holds |
| --- | --- |
| `risk_control` | Which controls reduce which risk |
| `finding_risk` | Which technical finding raised which risk |

The two link tables are what keep GRC tied to the investigation. Without them the risk register is just an opinion; with them, every risk traces back to a line in a log file.

## 6. Why these choices

**Flask, not FastAPI.** Flask renders HTML pages directly, so a working screen exists without a separate JavaScript frontend. FastAPI is the better choice when the frontend is a separate application; here it would mean building two things instead of one. Flask also has fewer concepts to learn at once, which matters when the goal is understanding the code well enough to defend it.

**SQLite, not PostgreSQL.** SQLite is a single file and needs no server to install, configure or run. The whole database can be committed, inspected in DB Browser, or deleted and rebuilt in a second. The project will never have more than a few thousand events or more than one user at a time, which is far inside what SQLite handles comfortably. Moving to PostgreSQL later means changing one connection line, because the SQL itself is standard.

**Server-rendered HTML, not React.** The screens display data and accept a few form submissions. React solves problems this project does not have, and would add a build step, a package manager and a second language to debug.

**Plain `sqlite3`, not an ORM.** Writing the SQL by hand is a skill worth having and worth being asked about in an interview. The schema is small enough that an ORM would save little.

## 7. Out of scope for the MVP

Named here so that scope creep is a decision rather than an accident:

- User accounts, login and roles. The platform assumes one analyst.
- Live connections to a real SIEM, EDR or mail server. Evidence arrives as uploaded files.
- The AI SOC assistant. It comes after the core investigation flow works.
- PDF export. Reports render as HTML pages first.
- Anything handling real production data. The project rules forbid it.

## 8. Build order

Each step depends on the one before it, so they are built in this order:

1. Database and schema; a case can be created and listed.
2. Evidence upload, hashing and the evidence list.
3. The email parser and the evidence viewer.
4. The log parsers: authentication, DNS, browser, endpoint, mailbox, alerts.
5. IOC extraction and the IOC screen.
6. The timeline, merging every source.
7. Findings and the investigation report.
8. The GRC tables, risk register and executive report.

## 9. Open questions

- Whether a case can hold evidence from more than one incident. Assumed no for now.
- How to display an event whose timestamp is missing or unparseable. Likely a separate "unordered" section rather than guessing a time.
- Whether findings need version history. Assumed no for the MVP.

---
All organizations, people, systems and data referenced here are fictional and exist only for the CASEFILE 360 portfolio project.
