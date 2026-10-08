# Operations runbook

This runbook targets `WS_Metadata_Bronze_Demo` / `PL_Metadata_Ingestion`. Execution evidence is owner-reported on October 8, 2026; this review did not connect to Fabric. See [validation](testing-and-validation.md) and the [configuration contract](configuration-contract.md).

## Before running

1. Open the workspace and inspect `LH_Configuration`, `LH_Landing`, and `LH_Bronze`. Confirm the pipeline's actual connections and Lakehouse bindings, including permission to read sources and write destinations.
2. Inspect `LH_Configuration/Files/ingestion_config.json`. Compare its complete contents with the local [catalog](../config/ingestion_config.json); the local catalog has ten records (nine enabled and one disabled), but parity with the deployed catalog is unverified. Run the [local validator](../tests/validate-config.ps1) before using the JSON as an input.
3. Inspect Lookup output, ForEach Items, the Switch expression, FILE/SQL/DISABLED cases, default behavior, Copy dependencies, and Overwrite destinations. The verified ForEach and Switch expressions are recorded in the [README](../README.md). Wait activity details, activity suffixes, and concurrency settings require Fabric UI verification. Do not assume an unknown source type fails safely.
4. Check for another active writer to the same Bronze tables. Agree the replacement scope before running; this is a full snapshot, not an incremental load. Record the configuration used without recording secrets.
5. Validate the pipeline in the editor. Validation is a structural check, not proof of source access or correct results. Run only after configuration and destination review.

## Find and inspect a run

Use Fabric Monitor or the pipeline's **Run > View run history**, select the pipeline run, and open its activity runs. Copy activity details expose input, output, status, duration, and available errors/statistics. See Microsoft's [Copy monitoring instructions](https://learn.microsoft.com/en-us/fabric/data-factory/monitor-copy-activity).

Record RunId, start/end times, status, dataset identity, evaluated paths and destination, and available row/file counts. Drill into the ForEach iteration and Switch child activity; display names may end in `_copy1` or `_copy2`. Identify the dataset from evaluated input, not from the shared Copy name alone. A Binary file copy may expose file/byte metrics rather than meaningful parsed row counts.

For FILE, the previously documented path convention is `LH_Landing/Files/<source_system>/<dataset_id>/<pipeline-run-id>/<source.path>`. For example: `Files/ecommerce/ecommerce_customers/<pipeline-run-id>/customers.csv`. SQL uses Parquet; its exact directory and filename expression are **Requires Fabric UI verification**. Inspect the first SQL Copy's evaluated sink and the second Copy's evaluated source; do not guess `Cars.parquet` or browse a different run's folder.

## Troubleshooting

| Symptom | Investigation and next action |
| --- | --- |
| Lookup/JSON error | Check the deployed file is a single valid JSON document and inspect its returned shape. A confirmed October 8 development error passed the Lookup wrapper object to ForEach; the corrected Items expression selects `@activity('lkp_ingestion_config').output.value[0].datasets`. The run completed after that correction. |
| Wrong or missing branch | Check Boolean `enabled`, exact source-type casing, ForEach item, Switch expression/cases/default. Disabled behavior and unknown-type behavior need separate tests. |
| Connection failure | Check the selected Fabric connection, credential validity, source object permissions, firewall/network reachability, and any configured gateway. Do not assume a gateway exists or is required. |
| `PathNotFound` | Compare evaluated producer sink and consumer source: Lakehouse, Files root, casing, dataset, RunId, directory, filename and extension. Confirm the producer succeeded and created a complete extract. Check whether a retry used another run's path. This is a diagnostic example, not a recorded incident. |
| Bronze table missing | Check the correct `LH_Bronze` and schema/table, branch execution, second Copy result, mapping and permissions. Check Lakehouse Tables separately from SQL endpoint visibility; [metadata synchronization can lag](https://learn.microsoft.com/en-us/fabric/data-warehouse/sql-analytics-endpoint-performance). Do not rerun blindly. |
| Unexpected counts | Compare source and extract from the same logical capture time; inspect skipped rows, conversion failures, filters, mappings and the actual destination. Source changes after extraction can invalidate a later count comparison. |
| Run succeeded but dataset absent | Check disabled/default routes, dataset array completeness and per-iteration output. Pipeline success alone does not prove all expected tables were loaded. |

The working Switch expression is `@if(equals(item().enabled, false), 'DISABLED', item().source_type)`. These expressions are verified facts; the remaining deployed activity settings still require inspection in Fabric.

## Acceptance and SQL checks

Open the **SQL analytics endpoint of LH_Bronze** and execute the queries in [testing and validation](testing-and-validation.md). Verify table existence and individual counts, not only the grand total. For Azure SQL source checks, run `SELECT COUNT_BIG(*) FROM [dbo].[Cars];` in `adflookupdemo`, repeating for Countries, Movies and ServiceRequests with appropriate read permissions. A later source count is not evidence of the source snapshot used earlier.

Inspect Landing separately: file presence, expected format, readable content, and the run's Copy completion. For CSV, count parsed records rather than physical lines when fields can contain line breaks. Verify the zero-row SQL table remains queryable. End-to-end acceptance requires the expected branches, complete Landing extracts, successful Bronze copies and all expected tables/counts. Row counts alone do not prove value equality.

## Partial failures and recovery

A failed run can leave partial Landing files and a mix of old and new Bronze snapshots. No cross-table transaction or automated rollback/replay is established. Preserve diagnostics and identify which tables actually changed. Fix the cause and agree whether to run a fresh complete snapshot or perform a separately reviewed dataset recovery. A fresh pipeline run can read newer source data and creates a new RunId; it does not reproduce the old snapshot automatically.

Do not publish an incomplete extract, treat an error as an empty source, manually trigger the historical notebook, or replay an older extract over a newer Bronze table without explicit recovery planning. Retained Landing input is useful evidence but no completion marker or immutable-retention enforcement is demonstrated. Retry settings, retention cleanup, replay tooling, concurrency controls and durable audit tables remain unverified or unimplemented as detailed in the test matrix.

## Security and operational records

Use the source-specific authentication configured in Fabric connections; the actual authentication modes are **Not verified**. Keep passwords, tokens, SAS values and connection strings out of JSON, Git and screenshots. Review source read permissions, connection sharing, workspace roles, Lakehouse/OneLake access and SQL endpoint access separately. Landing may contain the same sensitive data as the source: a separate Lakehouse or folder is not automatically a security boundary.

Apply least privilege and define retention/deletion and sensitive-data handling before broader use. Store sanitized run evidence in an approved location; avoid copying raw records, credential-bearing URLs or full error payloads into documentation. This project does not implement a custom audit or reconciliation store.
