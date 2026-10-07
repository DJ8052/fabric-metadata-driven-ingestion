# Configuration Contract v1

## Current state and scope

[ingestion_config.json](../config/ingestion_config.json) is a local dataset catalog and design contract. It contains exactly seven initial datasets: AdventureWorks `SalesLT.Customer`, the five ecommerce Blob CSV files, and USGS earthquakes. No Fabric runtime consumes it yet. No connection, pipeline, notebook, table, or ingestion behavior is implemented by this file.

All datasets start disabled pending connection and parsing validation. Disabled entries remain subject to structural validation. This is not an assertion that the sources are unavailable. Configuration validity does not mean execution readiness.

## Field definitions

Paths below are relative to a dataset in `datasets[]` unless identified as root fields. Every field in the current JSON is required, with explicit nullable values where discovery is unfinished. Source-only fields must be absent from other source types. All entries in the following tables are **static configuration**, including nulls and the Landing template; runtime values are listed separately below.

### A. Common dataset metadata

| Field | Purpose / type | Required | Applies to | Example | Supplied by |
| --- | --- | --- | --- | --- | --- |
| `contract_version` (root) | Integer contract version; v1 accepts `1` | Yes | All | `1` | Static |
| `landing_path_template` (root) | One shared deterministic path convention, relative to the Landing Lakehouse | Yes; exact v1 template | All | `Files/{source_system}/{dataset_id}/{run_id}/` | Static template; tokens resolved at runtime |
| `datasets` (root) | Nonempty array of dataset objects | Yes | All | Seven objects in the supplied file | Static |
| `dataset_id` | Stable, globally unique catalog identity and Landing dataset segment | Yes | All | `saleslt_customer` | Static |
| `enabled` | Boolean orchestration opt-in; never a string | Yes | All | `false` | Static |
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

The owner identifies storage account `ecommerceunifiedproject`, container `source`, and files `customers.csv`, `orders.csv`, `payments.csv`, `support_tickets.csv`, and `web_activities.csv`. The external `blob_ecommerce` connection binding will select that account; JSON retains only the existing container/path fields, so no contract extension is needed. These filenames do not establish columns, keys, relationships, incremental columns, or data-quality rules. All keys remain unknown until source inspection.

Inventory labels SQL_SERVER and AZURE_BLOB map to the existing v1 routing values `SQL` and `FILE`; these enums are unchanged. USGS retains `GEOJSON`, its existing JSON response representation. The ecommerce source-system and Bronze schema names are logical target organization, not claims about schemas inside the source files.

The REST path is relative to the public USGS service root `https://earthquake.usgs.gov/`. Its GET query endpoint and GeoJSON response option are documented in the [USGS API documentation](https://earthquake.usgs.gov/fdsnws/event/1/). Exact query parameters are deliberately not selected here. Before execution, define a bounded, complete retrieval and explicitly request GeoJSON; `response_format` alone does not send a query parameter. Do not fall back to API defaults when `query_parameters` is null. REST must remain disabled in v1; adding a reviewed query-parameter contract is a prerequisite to enabling it.

CSV delimiter, header, encoding, quoting, and type rules are also not inferred from filenames. Add verified parsing options to the FILE source contract when implementing the loader. `PARQUET` is an allowed file-format value for later onboarding, not a claim that a Parquet file source is present or supported by an implemented loader.

### C. Landing and target metadata

| Field | Purpose / type | Required | Applies to | Example | Supplied by |
| --- | --- | --- | --- | --- | --- |
| `landing` | Groups raw extract representation | Yes | All | Object with `format` | Static |
| `landing.format` | Raw extract representation; SQL: `TBD` until implemented and tested, FILE: same as `source.format`, REST: same as `source.response_format` | Yes | All | `TBD` | Static |
| `bronze` | Groups destination identifiers within the shared Bronze Lakehouse | Yes | All | Object with `schema` and `table` | Static |
| `bronze.schema` | Logical source-system schema | Yes | All | `adventureworkslt` | Static |
| `bronze.table` | Source-aligned Delta table name | Yes | All | `saleslt_customer` | Static |

Lakehouse bindings are fixed by project role: Landing uses `LH_Landing`, Bronze uses `LH_Bronze`, and future runtime configuration is intended for `LH_Configuration`. Environment binding is external; repeating Lakehouse names or IDs on every dataset would add no routing information. Bronze is always Delta in this contract, so no redundant target-format field is needed. Schema/table pairs must be unique within the shared Bronze Lakehouse.

SQL Landing representation is explicitly TBD until the SQL Server ingestion pattern is implemented and tested. `TBD` is an unresolved configuration marker, not a readable file format; SQL remains disabled while it is unresolved. FILE Landing retains the original file representation and REST Landing retains the raw response body. These are preservation requirements, not transformations already implemented. Parquet may be demonstrated later as an Azure Blob source file format.

Resolve the template as `Files/<source_system>/<dataset_id>/<run_id>/`. For Customer, the static prefix is `Files/adventureworks/saleslt_customer/`; the runtime appends its actual run ID. No run ID or timestamp is stored in the catalog. Every fresh extraction gets a unique runtime run ID. Completed extracts are immutable: retries must not overwrite completed content. Partial-attempt handling and completion markers are future runtime responsibilities. Replay reads an existing completed extraction run and uses a separate processing attempt identity; it does not rewrite Landing.

### D. Load-policy metadata

| Field | Purpose / type | Required | Applies to | Example | Supplied by |
| --- | --- | --- | --- | --- | --- |
| `load_policy` | Separates extraction scope, Bronze write semantics, and business history | Yes | All | Object with the three fields below | Static |
| `load_policy.mode` | Extraction strategy; v1 controlled set is `FULL` only | Yes | All | `FULL` | Static |
| `load_policy.bronze_write` | Intended Bronze publication behavior; v1 accepts `REPLACE_SNAPSHOT` only | Yes | All | `REPLACE_SNAPSHOT` | Static |
| `load_policy.history` | Dataset-specific business-history policy; v1 accepts `NONE` only | Yes | All | `NONE` | Static |

`FULL` means all records in the selected source object or agreed API request scope, not necessarily the entire upstream system or earthquake catalog. `REPLACE_SNAPSHOT` means publishing the complete successful extract as the current contents of that dataset's Bronze table, including an intentionally validated empty snapshot. Never publish a partial/failed extraction or append a full rerun blindly. API scope must be agreed before replacement is enabled because each publication represents only that scope.

Replaying the same immutable extract should yield the same business rows without accumulating duplicates. The future loader must validate completeness, control concurrent writers and out-of-order runs, define empty-load handling, and test failure recovery before claiming idempotency. Processing timestamps may differ between attempts; logical row-set idempotency does not require identical audit metadata. Replaying an older run into the current target intentionally restores an older snapshot and must be an explicit operational choice.

`NONE` disables business change-history policy; it does not disable raw extract retention. No SCD2 or CDC is implemented. Incremental loading is not accepted by v1: a later version can add `INCREMENTAL` and a dataset-specific nested policy inside `load_policy` without changing the common/source/target layout. Watermark column definitions would be static policy; actual last-successful watermark values belong to runtime state. Add only demonstrated policies with validation and loader support. Consumers must reject unsupported versions and enum values rather than silently treating them as FULL.

## Configuration versus runtime metadata

The catalog describes intent. Execution facts belong in future run/audit state, not in `ingestion_config.json`.

| Runtime field / concept | Purpose | Required when implemented | Applies to | Example | Supplied by |
| --- | --- | --- | --- | --- | --- |
| `run_id` | Unique identity of an extraction and its immutable Landing directory | Every extraction | All | Generated UTC timestamp plus uniqueness component | Runtime |
| Processing attempt ID | Distinguishes retries/replays of the same extraction | Every processing attempt | All | Generated attempt identifier | Runtime |
| Ingestion timestamp | Records when processing occurred | Every load | All | Actual UTC execution time | Runtime |
| Status | Records progress/outcome | Every attempt | All | Success or failure, under a future controlled vocabulary | Runtime |
| Rows read / written | Records measured counts, with units defined for nested payloads | Where measurable; unknown must not mean zero | All | Measured integer | Runtime |
| Errors | Sanitized failure details | Failed attempts where available | All | Sanitized connector error | Runtime |
| Watermark values | Tracks last successful incremental boundary | Only future incremental datasets | Where justified | Observed source boundary | Runtime; deferred |
| Resolved request scope / files / completion evidence | Identifies what was actually extracted and whether complete | Before safe publication/replay | All | Actual response-part list or source object version | Runtime |
| Configuration version/content reference | Identifies the exact dataset definition used by a run | Before reproducible replay | All | Reference to retained configuration content | Runtime |

These runtime names and examples are conceptual, not an implemented audit schema. `contract_version` versions the structure; it does not identify the exact configuration contents used by a historical run.

## Local validation

Run `powershell -NoProfile -ExecutionPolicy Bypass -File tests/validate-config.ps1` from the repository root. The execution-policy override applies only to that process; it does not change the machine's persistent policy. The script uses built-in JSON parsing and checks required/allowed fields, types, controlled values, dataset and target uniqueness, source-specific shapes, format consistency, key definitions, and REST's disabled/unconfigured state. It makes no network or Fabric calls and writes no data.

Validation does not inspect source schemas, authenticate connections, prove parsing behavior, or implement ingestion. Content review remains necessary to keep secrets out of configuration. Before enabling execution, finish source discovery, connection binding, CSV/GeoJSON parsing, completeness criteria, and safe publication behavior.
