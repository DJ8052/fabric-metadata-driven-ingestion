# Configuration Contract v1

## Current state and scope

[ingestion_config.json](../config/ingestion_config.json) is the dataset catalog and contract. It contains exactly seven initial datasets: AdventureWorks `SalesLT.Customer`, the five ecommerce Blob CSV files, and USGS earthquakes. The five ecommerce FILE datasets are enabled because their ingestion has been implemented, tested, and verified successfully. SQL Server and REST ingestion are not implemented and remain disabled.

Disabled entries remain subject to structural validation. A disabled flag records that a source type is not ready for execution; it is not an assertion that the source is unavailable. Configuration validity does not by itself prove runtime readiness.

## Field definitions

Paths below are relative to a dataset in `datasets[]` unless identified as root fields. Every field in the current JSON is required, with explicit nullable values where discovery is unfinished. Source-only fields must be absent from other source types. All entries in the following tables are **static configuration**, including nulls and the Landing template; runtime values are listed separately below.

### A. Common dataset metadata

| Field | Purpose / type | Required | Applies to | Example | Supplied by |
| --- | --- | --- | --- | --- | --- |
| `contract_version` (root) | Integer contract version; v1 accepts `1` | Yes | All | `1` | Static |
| `landing_path_template` (root) | One shared deterministic path convention, relative to the Landing Lakehouse | Yes; exact v1 template | All | `Files/{source_system}/{dataset_id}/{run_id}/` | Static template; tokens resolved at runtime |
| `datasets` (root) | Nonempty array of dataset objects | Yes | All | Seven objects in the supplied file | Static |
| `dataset_id` | Stable, globally unique catalog identity and Landing dataset segment | Yes | All | `saleslt_customer` | Static |
| `enabled` | Boolean orchestration opt-in; never a string | Yes | All | `true` for the implemented FILE datasets; `false` for SQL and REST | Static |
| `source_system` | Stable source-system grouping and Landing source segment | Yes | All | `adventureworks` | Static |
| `source_type` | Controlled routing discriminator: `SQL`, `FILE`, `REST` | Yes | All | `SQL` | Static |
| `connection_alias` | Logical reference resolved externally to a Fabric connection | Yes | All | `sql_adventureworks` | Static |
| `keys` | Groups source identity separately from business identity | Yes | All | Object with the two fields below | Static |
| `keys.source_primary_key` | Ordered array of verified source primary-key column names; `null` means unknown, `[]` means confirmed absent | Yes; nullable | All | `null` | Static |
| `keys.business_key` | Ordered array of agreed business-grain key columns; `null` means undecided, `[]` means explicitly not applicable | Yes; nullable | All | `null` | Static |

Dataset IDs, source systems, aliases, and Bronze identifiers use lowercase letters, digits, and underscores, starting with a letter. IDs are globally unique, even across source systems; qualify IDs when onboarding another source would otherwise collide. Treat renaming an ID/source system as a migration because it changes the Landing path. Physical source object names preserve their case.

No keys are guessed from column names. In particular, a SQL primary key must be checked against the actual database; CSV identifiers and API event identifiers are not automatically declared primary keys or business keys. Snapshot replacement does not require key-based matching.

### B. Source-specific metadata

| Field | Purpose / type | Required | Applies to | Example | Supplied by |
| --- | --- | --- | --- | --- | --- |
| `source` | Object containing only the fields for its source type | Yes | All | SQL object in the catalog | Static |
| `source.database` | Source database name | Yes | SQL | `AdventureWorksLT2022` | Static |
| `source.schema` | Source schema name | Yes | SQL | `SalesLT` | Static |
| `source.table` | Source table name; no embedded SQL query | Yes | SQL | `Customer` | Static |
| `source.container` | Blob container within the account resolved by the alias | Yes | FILE | `source` | Static |
| `source.path` | Exact object path relative to the container; no wildcard, URL, or token | Yes | FILE | `customers.csv` | Static |
| `source.format` | Source file representation; v1 controlled set `CSV`, `PARQUET` | Yes | FILE | `CSV` | Static |
| `source.relative_path` | API resource path relative to the externally configured service root | Yes | REST | `fdsnws/event/1/query` | Static |
| `source.method` | HTTP method; v1 accepts only `GET` | Yes | REST | `GET` | Static |
| `source.response_format` | Expected raw response representation; v1 accepts `GEOJSON` | Yes | REST | `GEOJSON` | Static |
| `source.query_parameters` | Non-secret request-scope definition; `null` explicitly means not designed yet | Yes; null in v1 | REST | `null` | Static placeholder, not an executed request |

The initial aliases are `sql_adventureworks`, `blob_ecommerce`, and `rest_usgs`. Account/server endpoints, authentication, credentials, connection IDs, and environment-specific Lakehouse bindings remain outside this file. Aliases are not executable Fabric connection IDs. The FILE pattern currently means Azure Blob Storage, not every possible file connector.

The owner identifies storage account `ecommerceunifiedproject`, container `source`, and files `customers.csv`, `orders.csv`, `payments.csv`, `support_tickets.csv`, and `web_activities.csv`. Their FILE ingestion is implemented, tested, and verified successfully. The external `blob_ecommerce` connection binding selects that account; JSON retains only the existing container/path fields, so no contract extension is needed. These filenames do not establish columns, keys, relationships, incremental columns, or data-quality rules. All keys remain unknown until source inspection.

Inventory labels SQL_SERVER and AZURE_BLOB map to the existing v1 routing values `SQL` and `FILE`; these enums are unchanged. USGS retains `GEOJSON`, its existing JSON response representation. The ecommerce source-system and Bronze schema names are logical target organization, not claims about schemas inside the source files.

The REST path is relative to the public USGS service root `https://earthquake.usgs.gov/`. Its GET query endpoint and GeoJSON response option are documented in the [USGS API documentation](https://earthquake.usgs.gov/fdsnws/event/1/). Exact query parameters are deliberately not selected here. Before execution, define a bounded, complete retrieval and explicitly request GeoJSON; `response_format` alone does not send a query parameter. Do not fall back to API defaults when `query_parameters` is null. REST must remain disabled in v1; adding a reviewed query-parameter contract is a prerequisite to enabling it.

The five configured CSV files are covered by the implemented and verified FILE path. The active `cpy_landing_to_bronze` activity uses DelimitedText / CSV with first row header, comma delimiter, and UTF-8. These activity settings are not additional catalog keys; this v1 catalog does not encode delimiter, header, encoding, quoting, or type rules. `PARQUET` is an allowed file-format value for later onboarding, not a claim that a Parquet file source is present or supported by an implemented loader.

### C. Landing and target metadata

| Field | Purpose / type | Required | Applies to | Example | Supplied by |
| --- | --- | --- | --- | --- | --- |
| `landing` | Groups raw extract representation | Yes | All | Object with `format` | Static |
| `landing.format` | Raw extract representation; SQL: `TBD` until implemented and tested, FILE: same as `source.format`, REST: same as `source.response_format` | Yes | All | `TBD` | Static |
| `bronze` | Groups destination identifiers within the shared Bronze Lakehouse | Yes | All | Object with `schema` and `table` | Static |
| `bronze.schema` | Logical source-system schema | Yes | All | `adventureworkslt` | Static |
| `bronze.table` | Source-aligned Delta table name | Yes | All | `saleslt_customer` | Static |

Lakehouse bindings are fixed by project role: Landing uses `LH_Landing`, Bronze uses `LH_Bronze`, and configuration uses `LH_Configuration`. Environment binding is external; repeating Lakehouse names or IDs on every dataset would add no routing information. Bronze is always Delta in this contract, so no redundant target-format field is needed. Schema/table pairs must be unique within the shared Bronze Lakehouse.

SQL Landing representation is explicitly TBD until the SQL Server ingestion pattern is implemented and tested. `TBD` is an unresolved configuration marker, not a readable file format; SQL remains disabled while it is unresolved. FILE Landing retains the original file representation and REST Landing retains the raw response body. FILE raw preservation is implemented by Binary Copy; REST preservation remains a planned requirement. Parquet may be demonstrated later as an Azure Blob source file format.

Resolve the template as `Files/<source_system>/<dataset_id>/<run_id>/`, with `{run_id}` supplied by `@pipeline().RunId`. RunId-scoped Landing is implemented for FILE datasets. Both Copy activities use directory `@concat(item().source_system,'/',item().dataset_id,'/',pipeline().RunId)` under `LH_Landing` root `Files` and filename `@item().source.path`. Example: `Files/ecommerce/ecommerce_customers/<pipeline-run-id>/customers.csv`. No run ID or timestamp is stored in the catalog. Completion markers, processing-attempt identity, and formal replay controls remain future work; retained run directories alone do not implement safe replay.

### D. Load-policy metadata

| Field | Purpose / type | Required | Applies to | Example | Supplied by |
| --- | --- | --- | --- | --- | --- |
| `load_policy` | Separates extraction scope, Bronze write semantics, and business history | Yes | All | Object with the three fields below | Static |
| `load_policy.mode` | Extraction strategy; v1 controlled set is `FULL` only | Yes | All | `FULL` | Static |
| `load_policy.bronze_write` | Intended Bronze publication behavior; v1 accepts `REPLACE_SNAPSHOT` only | Yes | All | `REPLACE_SNAPSHOT` | Static |
| `load_policy.history` | Dataset-specific business-history policy; v1 accepts `NONE` only | Yes | All | `NONE` | Static |

`FULL` means all records in the selected source object or agreed API request scope, not necessarily the entire upstream system or earthquake catalog. `REPLACE_SNAPSHOT` means publishing the complete successful extract as the current contents of that dataset's Bronze table, including an intentionally validated empty snapshot. Never publish a partial/failed extraction or append a full rerun blindly. API scope must be agreed before replacement is enabled because each publication represents only that scope.

For the current FILE path, `cpy_landing_to_bronze` publishes to `LH_Bronze`, root `Tables`, schema `@item().bronze.schema`, and table `@item().bronze.table`, using table action **Overwrite**. This implements FULL / REPLACE_SNAPSHOT for the five enabled CSV datasets. Replay, completeness controls, empty-load policy, concurrent-writer protection, out-of-order publication controls, and failure recovery require future design and testing before safe replay or idempotency guarantees can be claimed. Overwrite does not remove duplicates already present in a source.

`NONE` disables business change-history policy; it does not disable raw extract retention. No SCD2 or CDC is implemented. Incremental loading is not accepted by v1: a later version can add `INCREMENTAL` and a dataset-specific nested policy inside `load_policy` without changing the common/source/target layout. Watermark column definitions would be static policy; actual last-successful watermark values belong to runtime state. Add only demonstrated policies with validation and loader support. Consumers must reject unsupported versions and enum values rather than silently treating them as FULL.

## Configuration versus runtime metadata

The catalog describes static intent. Runtime execution facts stay outside `ingestion_config.json`: no credentials, Fabric IDs, connection IDs, runtime RunIds, timestamps, row counts, audit information, or watermark values belong there. The owner-supplied deployed state is documented here; local validation does not independently inspect Fabric.

### IMPLEMENTED RUNTIME

| Value / behavior | Current implementation |
| --- | --- |
| `pipeline_run_id` | `pipeline().RunId`, referenced in pipeline expressions as `@pipeline().RunId`; execution identity, not a generated timestamp |
| `run_timestamp` | Pipeline String variable set by `set_run_timestamp` using `@utcNow()`; separate from RunId |
| RunId Landing directory | `Files/{source_system}/{dataset_id}/{run_id}/`, resolved using the pipeline RunId; original filename retained |
| Execution information | Fabric Monitor pipeline/activity execution information |
| Bronze publication | Native `cpy_landing_to_bronze` Copy with Overwrite, implementing the configured snapshot policy for enabled FILE datasets |

Current path: `set_run_timestamp -> lkp_ingestion_config -> fe_dataset_loop -> if_dataset_enabled -> cpy_file_to_landing -> cpy_landing_to_bronze`. Binary Copy retains Blob input; native CSV Copy publishes Bronze. The `ecommerce` schema and five configured tables exist. See the [README verification evidence](../README.md#verification-evidence) for the successful run and row counts.

`NB_Load_Bronze` is inactive in this path. Its previous implementation added `_ingested_at_utc`, `_source_system`, `_dataset_id`, and `_pipeline_run_id`; current native Copy Bronze tables do not contain these columns.

Traceability follows Fabric Monitor -> pipeline RunId -> LH_Landing RunId directory -> configuration -> LH_Bronze result. It locates the raw input associated with a run, but there is no durable direct pipeline RunId-to-Bronze Delta version relationship.

### PLANNED DURABLE AUDIT STATE

| Concept | Future purpose |
| --- | --- |
| Dataset-level status | Persist dataset outcomes under an agreed status vocabulary |
| Persisted row counts | Record measured counts with defined units; unknown is not zero |
| Sanitized errors | Retain failure context without secrets |
| Configuration reference | Identify the exact configuration content used by a run |
| Processing/replay attempt | Distinguish retries/reprocessing from the original extraction |
| Future watermark values | Persist last-successful incremental boundaries only after incremental loading is implemented |
| Possible Bronze version linkage | Link publication to a table version if designed and verified |

A dataset-level ingestion manifest is intentionally deferred to monitoring/auditing. Possible fields: `pipeline_run_id`, `dataset_id`, `source_system`, `landing_path`, `bronze_schema`, `bronze_table`, `run_timestamp`, `row_count`, and `status`. These are candidate audit fields, not new catalog keys or an implemented schema. No additional Lakehouse or Warehouse is created, and Spark is not reintroduced merely for lineage.

Retained raw files are a foundation for troubleshooting/reprocessing. Explicit replay workflows, processing-attempt identity, automated safe replay, completion markers, direct Bronze version linkage, and replay concurrency protection remain future work. `contract_version` versions the structure; it does not identify the exact catalog content used by a historical run.

## Local validation

Run `powershell -NoProfile -ExecutionPolicy Bypass -File tests/validate-config.ps1` from the repository root. The execution-policy override applies only to that process; it does not change the machine's persistent policy. The script uses built-in JSON parsing and checks required/allowed fields, types, controlled values, dataset and target uniqueness, source-specific shapes, format consistency, key definitions, and REST's disabled/unconfigured state. It makes no network or Fabric calls and writes no data.

Validation checks catalog structure only; it does not inspect source schemas, authenticate connections, or prove runtime execution. Content review remains necessary to keep secrets out of configuration. The ecommerce FILE datasets are enabled based on their implemented, tested, and verified ingestion. Keep SQL and REST disabled until their source-specific ingestion, access, scope, parsing, completeness, and publication behavior are implemented and verified.
