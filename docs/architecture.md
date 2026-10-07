# Architecture and decisions

## CURRENT: deployed FILE path

The project owner's verified implementation uses workspace `WS_Metadata_Bronze_Demo`, Lakehouses `LH_Configuration`, `LH_Landing`, and `LH_Bronze`, and pipeline `PL_Metadata_Ingestion`. Five ecommerce FILE datasets are enabled; SQL and REST are disabled and unimplemented. This document records that supplied evidence, not an independent live inspection.

```text
Configuration -> Lookup -> ForEach -> enabled check
  -> Blob-to-Landing Copy -> Landing-to-Bronze Copy

set_run_timestamp
  -> lkp_ingestion_config
  -> fe_dataset_loop
  -> if_dataset_enabled
  -> cpy_file_to_landing
  -> cpy_landing_to_bronze
```

The [catalog](../config/ingestion_config.json) separates identity, source metadata, logical connection aliases, Landing representation, Bronze targets, keys, and load policy. Reuse comes from resolving dataset metadata inside the loop. The current enabled path is FILE; a generalized SQL/REST execution path is not implemented. The [contract](configuration-contract.md) defines static and runtime boundaries.

`set_run_timestamp` creates a pipeline String variable `run_timestamp = @utcNow()`. `@pipeline().RunId` is the separate pipeline execution identity and Landing directory token. The timestamp does not generate or replace the RunId.

## CURRENT: two Copy activities

| Setting | `cpy_file_to_landing` | `cpy_landing_to_bronze` |
| --- | --- | --- |
| Source | Azure Blob account `ecommerceunifiedproject` | `LH_Landing`, root `Files` |
| Source container | `@item().source.container` (currently `source`) | Not applicable |
| Source directory | Configured Blob object location | `@concat(item().source_system,'/',item().dataset_id,'/',pipeline().RunId)` |
| Source filename | `@item().source.path` | `@item().source.path` |
| Format | Binary: retain the original raw file | DelimitedText / CSV: first row header, comma delimiter, UTF-8 |
| Destination | `LH_Landing`, root `Files` | `LH_Bronze`, root `Tables` |
| Destination directory | `@concat(item().source_system,'/',item().dataset_id,'/',pipeline().RunId)` | Not applicable |
| Destination filename | `@item().source.path` | Not applicable |
| Destination schema / table | Not applicable | `@item().bronze.schema` / `@item().bronze.table` |
| Table action | Not applicable | **Overwrite** |

### Landing: retained raw input

The static template remains `Files/{source_system}/{dataset_id}/{run_id}/`. Runtime substitutes `pipeline().RunId` for `{run_id}`. For example:

```text
Files/ecommerce/ecommerce_customers/<pipeline-run-id>/customers.csv
```

RunId-scoped raw retention is implemented. Both Copy activities use the same run directory and filename. The retained input can be located for troubleshooting or future reprocessing without rereading a changed source. Completion markers, explicit retention policy, processing-attempt identity, and automated safe replay remain future work; a directory alone is not proof of a completed extract.

### Bronze: current source-aligned snapshot

Native Copy Overwrite implements `FULL / REPLACE_SNAPSHOT / NONE` for the ecommerce CSV datasets. One `LH_Bronze` groups targets by schema. The `ecommerce` schema exists, containing `customers`, `orders`, `payments`, `support_tickets`, and `web_activities`, each verified at 15 rows (75 total). SQL target `adventureworkslt.saleslt_customer` and REST target `usgs.earthquakes` remain planned; their configured names do not establish that those schemas/tables exist.

Bronze exposes the current Delta snapshot; Landing preserves raw input. `history: NONE` does not disable raw retention and does not promise business history. Snapshot overwrite is not deduplication, incremental loading, CDC, or an exactly-once/replay guarantee. Advanced schema contracts and schema drift handling remain planned.

## CURRENT: verification and troubleshooting

The owner verified pipeline Run ID `11f3408-764a-449f-8de9-8f1c2a032d64` on 2026-10-07, from 8:18:50 AM to 8:19:57 AM: **Succeeded**, 1 minute 7 seconds. `lkp_ingestion_config` took 12 seconds and `fe_dataset_loop` took 44 seconds. All five enabled FILE datasets completed. These supplied observations are verification evidence, not a performance guarantee.

```text
Fabric Monitor
  -> pipeline RunId
  -> LH_Landing RunId directory
  -> configuration
  -> LH_Bronze result
```

The RunId identifies the corresponding raw Landing directory. There is no durable direct pipeline RunId-to-Bronze Delta version relationship. A current Bronze snapshot and current catalog alone do not establish the historical table version or exact configuration content used by a past run.

## INACTIVE / PREVIOUS APPROACH: Spark notebook

[NB_Load_Bronze.py](../notebooks/NB_Load_Bronze.py), artifact `NB_Load_Bronze`, previously processed CSV Landing files into Bronze successfully. Native Copy replaced notebook-per-dataset execution because Spark startup/runtime overhead was disproportionate for these small CSV datasets. Spark remains a possible future option where transformations justify its runtime.

The notebook is retained as an implementation artifact, inactive in the current FILE path. Its processing logic remains unchanged. Historically it read CSV with schema inference and FAILFAST, applied a target-schema guard, and overwrote a managed Delta table. Those notebook-specific behaviors are not claims about the current Copy activities.

The previous notebook added `_ingested_at_utc`, `_source_system`, `_dataset_id`, and `_pipeline_run_id`. Current native Copy Bronze tables do not contain these operational columns. The notebook's completion output was not a durable audit manifest. Do not insert the notebook into the active FILE branch or reintroduce Spark solely for lineage.

## PLANNED: SQL, REST, and operating controls

SQL Server ingestion is next: dataset `saleslt_customer`, source `AdventureWorksLT2022.SalesLT.Customer`, alias `sql_adventureworks`, disabled. Landing representation remains `TBD` until implemented and tested. Gateway configuration and connection status are not asserted.

USGS dataset `earthquakes`, alias `rest_usgs`, remains disabled and unimplemented. Exact request/query scope is undecided; null query parameters are not instructions to use API defaults. Source type and Landing representation remain separate concerns.

A dataset-level ingestion manifest is intentionally deferred to monitoring/auditing. Possible future fields are `pipeline_run_id`, `dataset_id`, `source_system`, `landing_path`, `bronze_schema`, `bronze_table`, `run_timestamp`, `row_count`, and `status`. This is a design candidate, not an implemented schema. No additional Lakehouse or Warehouse is introduced for it.

Formal replay requires an explicit workflow, processing-attempt identity, automated safe replay, completion markers, direct Bronze version linkage, and concurrency protection. Retained raw files provide the foundation only; retries, concurrent writers, and out-of-order publication require explicit policies and verification.

Remaining work also includes retry policies, advanced schema contracts, schema drift handling, quarantine/dead-letter handling, incremental loading, watermarks, CDC, and deduplication where justified. Source primary keys and business keys remain separate unknowns in the catalog; do not guess them from column names. Configuration tables can be evaluated when editing, querying, or governance needs justify them.

Silver validation, standardization, and quarantine are future work. Gold, star schemas, semantic models, and Power BI are excluded.

## Security and environment boundaries

Logical aliases and display names do not contain credentials or deployable Fabric IDs. Bind connections and Lakehouses externally; keep secrets, environment-specific IDs, and actual Landing data out of Git. Schema organization in a shared Lakehouse is not a claim of source-level security isolation. Runtime facts belong outside static JSON; future durable audit must retain sanitized errors and appropriate configuration references.
