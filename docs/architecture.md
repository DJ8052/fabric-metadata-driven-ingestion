# Architecture and design decisions

The [README](../README.md) contains the topology; the [contract](configuration-contract.md) defines evidence boundaries. Owner-supplied October 8, 2026 results supersede the earlier FILE-only state. This review did not access live Fabric.

## Boundaries and execution

`WS_Metadata_Bronze_Demo` contains `PL_Metadata_Ingestion` and three Lakehouses. Configuration lives in `LH_Configuration`; extracts in `LH_Landing`; current Delta tables in `LH_Bronze`, grouped under `ecommerce` and `adflookupdemo`. Source records never pass through the configuration Lakehouse.

Control flow: `lkp_ingestion_config -> fe_dataset_loop -> sw_ingestion_route`. The verified ForEach Items expression is `@activity('lkp_ingestion_config').output.value[0].datasets`; the verified Switch expression is `@if(equals(item().enabled, false), 'DISABLED', item().source_type)`. FILE and SQL use separate Copy paths; disabled records follow the DISABLED route. Deployed child activity names may include `_copy1`/`_copy2`. The exact DISABLED activity, default route, dependency conditions and concurrency require Fabric UI verification. Earlier repository documentation mentions a `set_run_timestamp` variable, but its current existence and consumers are unverified. Old `if_dataset_enabled` and development test activities are not documented as active.

Lookup retrieves configuration in a wrapper containing the configuration object in `output.value[0]`; ForEach iterates that object's `datasets` array. An earlier expression iterated the wrapper itself, causing the Switch to receive a root object without `enabled`. The corrected ForEach expression above resolved the Lookup-wrapper error and a subsequent pipeline run completed. Microsoft's [Lookup](https://learn.microsoft.com/en-us/fabric/data-factory/lookup-activity) and [activity model](https://learn.microsoft.com/en-us/fabric/data-factory/activity-overview) explain these product roles, but cannot establish other deployment settings.

Data flow: Blob -> FILE extract -> Landing CSV -> FILE Bronze load -> Delta; Azure SQL -> SQL extract -> Landing Parquet -> SQL Bronze load -> Delta. Publication follows extraction conceptually; actual dependency conditions need the missing export. There is no demonstrated coordinated transaction across all nine tables.

## Runtime contract and evidence

Earlier documentation records String variable `run_timestamp = @utcNow()`. This is distinct from `@pipeline().RunId`; current variable settings/consumers are unverified. FILE previously used directory `@concat(item().source_system,'/',item().dataset_id,'/',pipeline().RunId)` under root Files, filename `@item().source.path`, Blob container `@item().source.container`, and Bronze `@item().bronze.schema` / `@item().bronze.table`. These are prior documented expressions, not freshly inspected definitions.

SQL metadata names database/schema/table and Bronze destination; the owner confirms Parquet Landing and Overwrite. Exact SQL expressions, filenames, connection selection and type mappings are unavailable. SQL records have no `source.path`; do not extrapolate a SQL filename from the FILE branch.

Landing separates extracts by run. A folder alone is not a completion marker, immutable-storage guarantee or replay workflow. No cleanup schedule, manifest or exact configuration-to-run capture is demonstrated. Bronze contains current snapshots. Microsoft's [Lakehouse Copy documentation](https://learn.microsoft.com/en-us/fabric/data-factory/connector-lakehouse-copy-activity) defines Overwrite as replacing data and schema; this does not establish project schema-drift safety or a retention/rollback policy.

## Compact decision log

Except for the earlier recorded notebook replacement rationale, the following are architectural assessments, not claims about the author's original reasoning.

| Choice | Benefit | Tradeoff |
| --- | --- | --- |
| JSON metadata | Reviewable dataset definitions separate from orchestration | Requires versioning, validation and deployment synchronization. |
| Lookup + ForEach + Switch | Shared orchestration with source-specific branches | Routing/defaults and concurrency need explicit checks. |
| Native Copy | Fits straightforward movement without custom transformations | Connector parsing/mappings still need tests. Earlier docs record avoiding disproportionate Spark startup overhead for tiny CSVs. |
| SQL Landing Parquet | Typed columnar intermediate extract | SQL-to-Parquet-to-Delta type compatibility needs verification. |
| RunId folders | Execution-specific diagnostics and possible future replay | Storage growth, incomplete extracts and replay order need controls. |
| Delta Bronze | Queryable current table snapshots | Individual writes do not provide a nine-table transaction. |
| Full overwrite | Simple current state without watermark state | Repeated full reads/writes; no business change history. |
| Configuration Lakehouse | Separate configuration lifecycle/access management | Additional binding; actual permissions determine isolation. |

## Repository artifacts and follow-up

[NB_Load_Bronze.py](../notebooks/NB_Load_Bronze.py) is preserved unchanged and inactive in the documented native Copy flow. Earlier docs record successful CSV loading before replacement. Its code uses Spark CSV inference/FAILFAST, a schema guard, managed Delta overwrite and `_ingested_at_utc`, `_source_system`, `_dataset_id`, `_pipeline_run_id` columns. These are notebook behaviors, not active Copy guarantees. Prior docs say native FILE tables lack those metadata columns; current SQL column schemas are **Not verified**. Notebook output is not durable audit state.

`fabric/` contains only `.gitkeep`; no pipeline export or deployable definition is available. Older AdventureWorks/SQL Server planning and disabled USGS examples are historical, not part of the current Azure SQL/Blob ingestion inventory. Do not treat them as active source support.

Highest-value follow-ups: sanitized pipeline/catalog capture; reproducible execution evidence; onboarding and growth/deletion tests; empty-after-nonempty, failure/replay/concurrency and schema/type tests. Incremental/CDC, REST, reconciliation/audit and Silver remain future scope; Gold and reporting are outside this demonstration.
