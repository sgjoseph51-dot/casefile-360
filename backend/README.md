# backend

The Flask application. See [../docs/architecture/architecture.md](../docs/architecture/architecture.md) for the full design.

| Folder | Job | May call |
| --- | --- | --- |
| `routes/` | Receive a web request, call a service, render a page | Services |
| `services/` | Do the work: hash, parse, extract, correlate | Models and parsers |
| `models/` | Read and write the database | SQLite only |
| `parsers/` | Turn one evidence format into normalized events | Nothing else |
| `templates/` | HTML pages | |

**The rule: a layer may only call the one below it.** Routes never write SQL. Parsers never touch the database.

Uploaded files go to `backend/uploads/`, which Git ignores. The synthetic evidence set lives in `evidence/` at the repo root.

---
All organizations, people, systems and data referenced here are fictional and exist only for the CASEFILE 360 portfolio project.
