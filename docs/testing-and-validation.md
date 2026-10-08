# Testing and validation

## Evidence provenance

The project owner supplied the following Fabric execution and Bronze SQL results for **October 8, 2026**. They were not independently rerun during this documentation review. No screenshots, October 8 RunIds, activity outputs, source snapshots or original query text accompany the repository. The SQL below reproduces the count checks; it is not claimed to be the exact original SQL.

| Source | Bronze table | Verified rows |
| --- | --- | ---: |
| Azure SQL `dbo.Cars` | `adflookupdemo.cars` | 428 |
| Azure SQL `dbo.Countries` | `adflookupdemo.countries` | 17 |
| Azure SQL `dbo.Movies` | `adflookupdemo.movies` | 112 |
| Azure SQL `dbo.ServiceRequests` | `adflookupdemo.service_requests` | 0 |
| Blob `source/customers.csv` | `ecommerce.customers` | 15 |
| Blob `source/orders.csv` | `ecommerce.orders` | 15 |
| Blob `source/payments.csv` | `ecommerce.payments` | 15 |
| Blob `source/support_tickets.csv` | `ecommerce.support_tickets` | 15 |
| Blob `source/web_activities.csv` | `ecommerce.web_activities` | 15 |
| **SQL subtotal** | **4 tables** | **557** |
| **FILE subtotal** | **5 tables** | **75** |
| **Total** | **9 tables** | **632** |

The FILE source paths match the current local catalog and its committed predecessor; the deployed catalog still needs capture. Earlier repository documentation identifies the Azure SQL host as `devonadfsqldemo.database.windows.net`; verify the actual deployed connection binding in Fabric. The source database is `adflookupdemo`. SQL passed through Parquet Landing. The empty ServiceRequests source completed and produced a queryable Bronze table. One complete end-to-end run and a subsequent full run succeeded; counts remained unchanged. This supports repeatable snapshots for those inputs, not comprehensive idempotency, data equality, schema-drift resilience, cross-table consistency or partial-failure recovery.

Earlier documentation records a FILE-only success on October 7, 2026, 8:18:50 AM–8:19:57 AM, duration 1m 7s, supplied Run ID `11f3408-764a-449f-8de9-8f1c2a032d64`, Lookup 12s and ForEach 44s. Retained as historical owner-reported evidence; time zone and RunId transcription **Not verified**. Do not use it as an October 8 identifier or performance guarantee.

## October 8 Lookup wrapper error and resolution

An earlier ForEach Items expression iterated the Lookup `output.value` wrapper instead of the nested dataset array. As a result, the Switch received the root object (`contract_version`, `landing_path_template`, `datasets`) rather than a dataset record, and `item().enabled` was unavailable. The verified working expression is:

```text
@activity('lkp_ingestion_config').output.value[0].datasets
```

The verified Switch expression is:

```text
@if(equals(item().enabled, false), 'DISABLED', item().source_type)
```

After the corrected JSON configuration was deployed, the pipeline completed successfully. Subsequent SQL queries confirmed unchanged Bronze row counts. This owner-supplied execution evidence does not replace a pipeline export or independent access to Fabric.

## Reproducible Bronze count checks

Run against the SQL analytics endpoint of **LH_Bronze**. These historical expected values are valid only for the tested inputs; intentional source changes should change expected counts.

```sql
SELECT 'adflookupdemo.cars' AS table_name, COUNT_BIG(*) AS row_count FROM [adflookupdemo].[cars]
UNION ALL SELECT 'adflookupdemo.countries', COUNT_BIG(*) FROM [adflookupdemo].[countries]
UNION ALL SELECT 'adflookupdemo.movies', COUNT_BIG(*) FROM [adflookupdemo].[movies]
UNION ALL SELECT 'adflookupdemo.service_requests', COUNT_BIG(*) FROM [adflookupdemo].[service_requests]
UNION ALL SELECT 'ecommerce.customers', COUNT_BIG(*) FROM [ecommerce].[customers]
UNION ALL SELECT 'ecommerce.orders', COUNT_BIG(*) FROM [ecommerce].[orders]
UNION ALL SELECT 'ecommerce.payments', COUNT_BIG(*) FROM [ecommerce].[payments]
UNION ALL SELECT 'ecommerce.support_tickets', COUNT_BIG(*) FROM [ecommerce].[support_tickets]
UNION ALL SELECT 'ecommerce.web_activities', COUNT_BIG(*) FROM [ecommerce].[web_activities];
```

A missing table causes the query to fail; zero rows is different from a missing table. Inspect tables individually if necessary. Capture query time and RunId alongside results. Counts alone cannot reveal substitutions, duplicates with offsetting omissions, or value corruption.

## Verification layers and acceptance

| Layer | Why it matters | Evidence boundary |
| --- | --- | --- |
| JSON/contract validation | Detects malformed and inconsistent metadata | The current local validator covers the v1 catalog structure and metadata rules; neither this check nor JSON parsing inspects Fabric. |
| Pipeline editor validation | Checks structural configuration | No independent result recorded in this review. |
| Activity execution | Establishes which branches and copies completed | Owner reports successful end-to-end executions; per-activity output absent. |
| Copy metrics | Compares available rows/files read and written, errors/skips | Binary metrics may be bytes/files; metrics not supplied. |
| Landing inspection | Confirms actual run-specific extract exists and is readable | Paths/formats described; no independent file listing captured. |
| Bronze existence | Confirms expected destinations are queryable, including empty table | All nine owner-verified. |
| Bronze row counts | Checks each snapshot's size | Nine counts above owner-verified; no value-level comparison. |
| End-to-end acceptance | Combines correct inputs, routes, extracts and destinations | Demonstrated run/rerun; full evidence package remains to be captured. |

For future acceptance record the catalog version/content, evaluated dataset routing and paths, pipeline/child statuses, Copy metrics, Landing readability, Bronze existence/counts and source reconciliation for the same extraction point. A green run alone is insufficient.

## Capability and test matrix

| Classification | Scenario | Result / next acceptance criterion |
| --- | --- | --- |
| Implemented and owner-verified | Five CSV and four SQL snapshots | Nine tables, 632 rows for October 8 inputs. |
| Implemented and owner-verified | Full rerun, unchanged inputs | Same counts; stronger content equality not tested. |
| Implemented and owner-verified | Empty SQL source | Queryable zero-row ServiceRequests target. |
| Implemented but not fully tested | DISABLED route | Switch route supplied; dedicated false/true and mixed-route tests absent. Exact downstream activity is not verified. |
| Not verified | Snapshot response to changed inputs | Growth, deletion and nonempty-to-empty transition have not been tested. |
| Not verified | Config-only onboarding | Add one same-connection dataset without activity edits and reconcile output. |
| Not verified | Unknown type/malformed metadata | Confirm fail-safe behavior; exact default branch unavailable. |
| Not verified | Failure/retry/replay/concurrent runs | Inject failures in each stage; prove no incomplete/stale publication. |
| Not verified | Type conversion/schema changes | Test changed, missing and extra columns; no managed drift policy implemented. |
| Not implemented | Incremental, CDC, watermark state, REST ingestion | Separate design, implementation and acceptance required. |
| Not implemented | Durable dataset audit/reconciliation, automated safe replay | Monitoring and retained files are not these features. |
| Potential future work | Data quality, retention automation, observability | Define requirements and failure criteria before adding infrastructure. |

## Local review quality gates

Run `powershell -NoProfile -ExecutionPolicy Bypass -File tests/validate-config.ps1` from the repository root. The validator was updated to validate enabled SQL/Parquet records, FILE metadata, required Bronze destinations, Boolean enabled flags, unique dataset IDs and targets, v1 load policies, and structurally valid disabled-only REST metadata. It does not claim or require REST ingestion support.

No Fabric execution, SQL queries, notebook execution or dependency installation was performed by this review. The notebook is a historical implementation artifact, not a local test suite.

| Local review check | Result |
| --- | --- |
| Current catalog JSON syntax | Pass: ten records, nine enabled; one disabled REST metadata record. |
| Current PowerShell validator | Pass: ten records (nine enabled, one disabled); metadata, policy, and uniqueness checks passed. |
| Relative documentation links | Pass: relative Markdown links resolve across all five Markdown files. |
| Supplied table/count consistency | Pass: all nine counts in README and this document; 557 + 75 = 632. |
| Mermaid | Manual syntax review only; neither local Mermaid package/CLI nor global CLI available. Parser/render validation not performed; no dependencies installed. |
| Implementation preservation | Configuration, notebook, and Fabric artifacts unchanged; only documentation and the requested validator were modified. |
| Secrets | Limited credential-pattern scan and documentation content review found no introduced secrets; not an exhaustive repository security audit. |
| Git whitespace and scope | `git diff --check` passed; no staged changes. |

The documentation supports orientation and guided operation, but repository-only deployment/recovery is not reproducible until the deployed definitions are captured. Missing expressions and runtime guarantees remain explicitly labeled rather than inferred.
