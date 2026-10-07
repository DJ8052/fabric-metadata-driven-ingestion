# Architecture and decisions

## Status and boundaries

This document distinguishes local implementation from PLANNED runtime capabilities. CURRENT STATE: the owner reports workspace `WS_Metadata_Bronze_Demo` with schema-enabled `LH_Configuration`, `LH_Landing`, and `LH_Bronze`, and pipeline `PL_Metadata_Ingestion` reading configuration and looping through datasets. The repository contains Configuration Contract v1, a seven-dataset catalog, a local validator, and an authored CSV Landing-to-Bronze notebook. The pipeline and live Lakehouse state have not been inspected here; the notebook has not been uploaded or executed in Fabric by this work. A Silver Lakehouse has not been reported as created.

## Reusable source patterns

Reuse orchestration and load contracts while separating extraction where connectors behave differently. Do not assume one universal Copy Activity can handle every connector identically.

| Pattern | Initial inputs | Planned responsibilities / decisions to validate |
| --- | --- | --- |
| SQL Server | SQL Server Express; `AdventureWorksLT2022.SalesLT` tables | Validate network/gateway access and authentication; discover schema and primary keys; choose extract format, consistency expectations, and full versus incremental extraction per dataset |
| Blob / file | Account `ecommerceunifiedproject`, container `source`: `customers.csv`, `orders.csv`, `payments.csv`, `support_tickets.csv`, `web_activities.csv` | Select source objects, retain originals, identify file version/overwrite behavior, and configure CSV encoding, delimiters, headers, and types; extend to Parquet later |
| REST | USGS Earthquake API JSON/GeoJSON | Define time windows, request parameters, bounded retrieval, response completeness, retry behavior, and API-specific pagination/limits where applicable; retain raw response bodies before flattening |

The SQL Server connector supports pipeline copy and gateway connection options; local SQL Express connectivity still requires validation in the actual environment. No gateway or Fabric connection is assumed configured. See the [Microsoft SQL Server connector overview](https://learn.microsoft.com/en-us/fabric/data-factory/connector-sql-server-database-overview).

Exact connector settings and REST retrieval mechanics will be validated before implementation. Source type and file format are separate concepts: a Blob source can deliver CSV or Parquet, and a SQL extract may use a different representation in Landing.

## Landing: durable extraction boundary

`LH_Landing` will hold raw extracts under its Files area. Contract v1 defines this logical convention for the future runtime:

```text
Files/<source_system>/<dataset_id>/<run_id>/[source files or response parts]
```

`run_id` is planned to include a UTC timestamp and a uniqueness component. Naming, retry/attempt handling, retention, and completion markers remain design work. Readers must distinguish completed extracts from partial or failed runs before Bronze loading is enabled.

Preserve Blob source files without transformation, retain REST response bodies, and retain SQL query results in an explicitly selected extract format before downstream changes. For SQL, “raw” means the extracted records, not a database backup or transaction log. Keep related non-secret extraction context sufficient to interpret an extract, including request/query scope and extraction time.

Landing allows reprocessing from a known extraction without rereading a changed or unavailable source. It adds storage cost and retention responsibilities. Replay is a future capability: run-scoped storage alone does not provide safe replay, idempotency, or exactly-once processing. Actual Landing contents belong in Fabric storage, never Git.

## Bronze: source-aligned Delta tables

`LH_Bronze` will expose source-aligned Delta tables with minimal structural transformations needed to read heterogeneous extracts. The authored [NB_Load_Bronze.py](../notebooks/NB_Load_Bronze.py) implements the first CSV path: **retained Landing file -> generic Bronze notebook -> managed Delta table**. Its format-specific reader is separate from the shared write path. Additional readers, including nested responses, remain future work. The notebook performs no source extraction.

The notebook adds `_ingested_at_utc`, `_source_system`, `_dataset_id`, and `_pipeline_run_id`; a source column colliding with these names fails instead of being overwritten. Completion output retains the supplied Landing path and processing run ID. A replay can use an older Landing run path with a new processing run ID. Durable provenance/audit storage and GeoJSON handling remain future work.

Contract v1 selects FULL extraction and REPLACE_SNAPSHOT publication for the seven initial datasets, with history NONE. The local CSV loader implements a Delta overwrite with schema merging/replacement disabled; it is not yet verified in Fabric. Reprocessing the same immutable file replaces business rows without accumulating duplicates; operational timestamps/run IDs can change. This does not remove duplicate records already present in a source. Later datasets may justify other policies through a versioned contract extension. No incremental watermark, deduplication, merge, or business-history behavior is implemented.

### CSV notebook behavior and limits

The notebook contains five cells: parameter defaults; validation; CSV read and observed-schema output; operational columns and target checks; snapshot overwrite and completion output. All seven parameters are mandatory strings. `source_format` accepts CSV only. `landing_path` must be an absolute OneLake ABFS path to one file under `Files/<source_system>/<dataset_id>/<landing-run-id>/<original_file_name>`. A relative Files path would resolve against default `LH_Bronze`, so it is rejected. Environment-specific path roots are supplied by Fabric, not stored in repository configuration.

CSV is read with `header=true`, `inferSchema=true`, and `mode=FAILFAST`. No business cleansing, renaming, deduplication, or Silver rules are applied. Inference can change representation (for example numeric-looking identifiers can lose leading zeroes) and vary between snapshots; raw Landing remains authoritative. CSV dialect/encoding and parser behavior must be verified against the actual files. FAILFAST is parser behavior, not a complete data-quality or row-width validation system.

The observed source schema is printed before adding operational columns, with a clear extension point for future explicit source-schema validation. On an existing managed Delta target, a minimal guard requires the same column names and types as the incoming frame, including operational columns; nullable flags and column order are not compared. Differences fail instead of being cast, merged, or accepted through schema replacement. This is not a versioned source contract, drift reconciliation, or quarantine implementation. New tables use the observed schema; invalid Delta column names fail rather than being silently renamed.

The schema is created if absent, and `saveAsTable` writes a managed Delta table without a custom storage path. The counted frame is cached for the write and unpersisted afterward. SUCCESS output is printed only after a successful write and includes run ID, dataset ID, Landing path, target, and row count. Spark/Delta failures propagate with context. The completion print is not durable audit state or an exactly-once guarantee. A readable empty snapshot can replace the target with zero rows; empty-load policy remains a later decision.

### Fabric setup for the first Bronze test

1. Import the authored `.py` source as `NB_Load_Bronze` in `WS_Metadata_Bronze_Demo`, using PySpark. Verify cell boundaries and mark the first cell as the parameter cell if import does not preserve the marker. This is newly authored source, not an export from an existing Fabric notebook.
2. Attach `LH_Bronze` and pin it as the default; also attach `LH_Landing`. Restart an existing Spark session after changing the default. The two-part target name resolves in the default Lakehouse. Ensure the notebook activity's execution identity can read Landing and create schemas/write tables in Bronze.
3. In `PL_Metadata_Ingestion`, place a Notebook activity inside the FILE/CSV branch of the dataset loop, dependent on **successful completion** of the Landing copy. Select `NB_Load_Bronze`. Invoke it only for enabled datasets with FULL / REPLACE_SNAPSHOT / NONE. This notebook does not receive or implement alternative load policies.
4. In the Notebook activity's Settings > Base parameters, pass the following case-sensitive names, all as String. The expressions assume `item()` is the current dataset object, not a wrapper or an entire configuration document.

| Notebook parameter | Pipeline expression / value |
| --- | --- |
| `dataset_id` | `@item().dataset_id` |
| `source_system` | `@item().source_system` |
| `landing_path` | Absolute ABFS path to the exact successfully copied file; see below |
| `bronze_schema` | `@item().bronze.schema` |
| `bronze_table` | `@item().bronze.table` |
| `source_format` | `@item().landing.format` |
| `pipeline_run_id` | `@pipeline().RunId` |

For normal ingestion, **if the Copy destination uses `pipeline().RunId` as its run folder**, add a pipeline String parameter `landing_files_root` containing the real LH_Landing ABFS root through `/Files/` (trailing slash included), copied from the Lakehouse UI. Then use:

```text
@concat(pipeline().parameters.landing_files_root, item().source_system, '/', item().dataset_id, '/', pipeline().RunId, '/', item().source.path)
```

This expression matches the current flat Blob filenames. If the Copy activity uses a different runtime run-folder expression or filename, use that exact same value here; no existing activity/output/variable name is assumed. For replay, pass the original completed file path rather than constructing one from the new processing run ID. The notebook does not verify the Lakehouse ID's identity or extraction completeness: correctly binding the ABFS root to LH_Landing and invoking after a complete copy are pipeline responsibilities.

Keep one writer per Bronze target at a time, including across concurrent pipeline runs. The notebook has no lock, checkpoint, or protection against an older replay replacing newer data. Schema checks before writing are not a concurrency lock. Its UTC and no-auto-merge settings affect its Spark session; avoid sharing that session with workloads requiring conflicting settings.

The setup follows Microsoft's [notebook import and attachment guidance](https://learn.microsoft.com/en-us/fabric/data-engineering/how-to-use-notebook), [parameter-cell guidance](https://learn.microsoft.com/en-us/fabric/data-engineering/author-execute-notebook#integrate-a-notebook), and [cross-Lakehouse path guidance](https://learn.microsoft.com/en-us/fabric/data-engineering/lakehouse-notebook-load-data). Write options follow [Delta batch-write documentation](https://docs.delta.io/delta-batch/). Actual import, parameter injection, paths, permissions, CSV parsing, schema enforcement, and managed-table overwrite still require Fabric verification.

### One shared Bronze Lakehouse

Use one `LH_Bronze` for the demo and organize tables by source-system schemas, with candidate names `adventureworkslt`, `ecommerce`, and `usgs`. These are proposals, not existing schemas. Preserve the original SQL schema (`SalesLT`) and table identity in metadata; resolve naming collisions explicitly.

Fabric Lakehouse schemas support named table groupings, which fits this organization. See [Microsoft Lakehouse schemas documentation](https://learn.microsoft.com/en-us/fabric/data-engineering/lakehouse-schemas).

A shared Lakehouse reduces demo administration and centralizes conventions. It also couples lifecycle and operational management across sources. Schema organization alone is not a claim of source-level security isolation. Separate Lakehouses may become appropriate if ownership, isolation, scale, or retention needs diverge.

## Metadata-driven orchestration

Planned flow: **Configuration -> Lookup -> ForEach -> source-type routing -> reusable ingestion pattern -> Bronze load**.

The local [Configuration Contract v1](configuration-contract.md) and [JSON catalog](../config/ingestion_config.json) define the seven initial datasets. The owner reports configuration-driven looping in `PL_Metadata_Ingestion`; the deployed configuration location and Lookup output shape have not been verified here. No configuration table exists in this repository.

The contract separates common identity/routing and key metadata, a source-specific object, Landing/Bronze target metadata, and load policy. Logical aliases keep connection binding external. A single Landing template avoids repeating path rules; per-dataset formats tell the future loader how extracts are represented. Distinct primary-key and business-key fields remain null until verified. Load mode, snapshot publication, and history are separate decisions. Versioning permits later incremental policies without restructuring every dataset. See the contract for every field and its rationale.

The five ecommerce FILE entries are enabled for ingestion testing; SQL and REST remain disabled. SQL Landing representation is explicitly TBD until the SQL Server ingestion pattern is implemented and tested; Blob preserves CSV, and REST preserves GeoJSON. SQL extract compatibility, CSV parsing, and API request scope still require design/verification; REST query parameters are explicitly null, not an instruction to use API defaults. The local validator checks structure, types, controlled values, and uniqueness, not execution readiness. Runtime run IDs, timestamps, counts, errors, and watermark values stay out of the static catalog.

Validate configuration before execution. Route to SQL, file, or REST extraction, then pass a completed Landing run and dataset contract to the Bronze loader. Retry limits, concurrency, failure isolation, and partial-success reporting need explicit policies; ForEach alone does not establish them. Evaluate configuration tables later when queryability, operational edits, or governance outweigh JSON's reviewability and simplicity.

## Primary keys, business keys, and history

- A **source primary key** identifies a record according to the source's declared constraint. Discover SQL constraints rather than inferring them from column names. CSV and API identifiers require separate uniqueness and nullability validation; they may have no enforced primary key.
- A **business key** identifies a business entity at an agreed grain. It may differ from the source primary key, may be composite, and may require standardization. Never assume a technically unique identifier is a stable business key.
- Record both concepts separately, including “unknown” or “not applicable” where justified. A dataset without a reliable key must not silently receive a key-based update policy.
- Preserve raw run history in Landing. Bronze Delta storage and retained extracts do not automatically constitute an SCD2 implementation or indefinite business history.
- Add SCD2/change-history only for a demonstrated requirement with explicit identity, change detection, effective dates, deletion/late-arrival semantics, and retention. Decide the appropriate layer per use case; do not apply SCD2 to every Bronze table.

## Planned operations and Silver boundary

Long-term reliability requirements include idempotent sinks, durable run/checkpoint state, replay/backfill, deliberate schema-drift protection, quarantine/dead-letter handling, deduplication where keys and semantics justify it, watermarks/incremental processing where appropriate, and CDC where supported and justified. The CSV notebook currently provides snapshot overwrite, operational columns, retained path in completion output, clear failures, and a minimal target-schema guard. It does not implement the remaining mechanisms.

Later audit/monitoring should connect extraction and Bronze load outcomes using source, dataset, run, timing, counts, status, and sanitized errors. Replay should select an existing completed Landing run and record a distinct processing attempt. Fabric tests must demonstrate safe retries and duplicate prevention for each selected load policy before those guarantees are claimed.

Silver will consume Bronze for validation, standardization, data-quality rules, and quarantine with failure reasons and provenance. Rules, quarantine storage, accepted/rejected reconciliation, and reprocessing procedures will be designed later. Landing remains the preserved extraction boundary even when Silver rejects records. No Silver Lakehouse name or artifacts are assigned in this step.

Gold, dimensional/star models, semantic models, and Power BI are excluded.

## Assumptions and unresolved decisions

- Owner-reported resources and source inventory are the starting point; access and data contents remain unverified.
- Display names are documentation context. Fabric resource IDs, connection IDs, host-specific settings, and credentials remain external.
- Initial datasets are now cataloged: SalesLT.Customer, the five ecommerce Blob CSV files, and USGS earthquakes. Extraction scopes, source keys, business keys, file schemas, and refresh schedules still need confirmation before runtime implementation.
- Source patterns share orchestration and conventions but may require different activities or code after connector validation.
- Raw retention, concurrency, load policies, schema drift handling, replay semantics, and history requirements need explicit decisions in later phases.
