# Metadata-driven ingestion in Microsoft Fabric

Dataset-specific pipelines duplicate orchestration and make onboarding and troubleshooting harder. This project uses a seven-dataset JSON catalog to reuse orchestration, source selection, Landing paths, and Bronze targets while keeping source-specific extraction concerns separate.

## Current implementation

The five ecommerce CSV datasets are enabled and verified in workspace `WS_Metadata_Bronze_Demo`. Pipeline `PL_Metadata_Ingestion` uses native Fabric Copy activities to retain raw files in `LH_Landing` and publish source-aligned Delta snapshots in `LH_Bronze`. `LH_Configuration` is the configuration Lakehouse. SQL and REST remain disabled and unimplemented.

The deployed state and run evidence below were supplied by the project owner; this repository update does not independently execute or inspect Fabric.

```text
set_run_timestamp
  -> lkp_ingestion_config
  -> fe_dataset_loop
  -> if_dataset_enabled
  -> cpy_file_to_landing
  -> cpy_landing_to_bronze
```

`set_run_timestamp` sets the pipeline String variable `run_timestamp = @utcNow()`. The separate execution identity `@pipeline().RunId` supplies the Landing run folder; it is not a timestamp.

Copy 1 performs a Binary copy from Azure Blob account `ecommerceunifiedproject`, using container `@item().source.container` and filename `@item().source.path`. Its destination is `LH_Landing`, root `Files`, directory `@concat(item().source_system,'/',item().dataset_id,'/',pipeline().RunId)`, with the same filename.

Copy 2 reads that exact Landing directory and filename as DelimitedText / CSV with first-row headers, comma delimiter, and UTF-8 encoding. It writes to `LH_Bronze`, root `Tables`, schema `@item().bronze.schema`, table `@item().bronze.table`, with table action **Overwrite**. This implements `FULL / REPLACE_SNAPSHOT / NONE` for the five FILE datasets.

Landing retains the raw input, for example `Files/ecommerce/ecommerce_customers/<pipeline-run-id>/customers.csv`. Bronze exposes the current source-aligned table snapshot. RunId-scoped Landing is implemented; formal replay orchestration is future work.

## Seven-dataset inventory

| Dataset | Type | Enabled | Source | Bronze target | Verified rows |
| --- | --- | --- | --- | --- | --- |
| `ecommerce_customers` | FILE | `true` | `source/customers.csv` | `ecommerce.customers` | 15 |
| `ecommerce_orders` | FILE | `true` | `source/orders.csv` | `ecommerce.orders` | 15 |
| `ecommerce_payments` | FILE | `true` | `source/payments.csv` | `ecommerce.payments` | 15 |
| `ecommerce_support_tickets` | FILE | `true` | `source/support_tickets.csv` | `ecommerce.support_tickets` | 15 |
| `ecommerce_web_activities` | FILE | `true` | `source/web_activities.csv` | `ecommerce.web_activities` | 15 |
| `saleslt_customer` | SQL | `false` | `AdventureWorksLT2022.SalesLT.Customer` | `adventureworkslt.saleslt_customer` (planned) | Not loaded |
| `earthquakes` | REST | `false` | USGS earthquakes | `usgs.earthquakes` (planned) | Not loaded |

The `ecommerce` schema and its five tables exist: **75 rows total**. SQL uses logical alias `sql_adventureworks`; its Landing representation remains `TBD`, with no gateway or connection status assumed. REST uses `rest_usgs`; exact request/query scope remains undecided. FILE uses `blob_ecommerce`.

## Verification evidence

The owner verified a successful run on **2026-10-07**, from **8:18:50 AM to 8:19:57 AM**, lasting **1 minute 7 seconds**, with status **Succeeded**. Pipeline Run ID: `11f3408-764a-449f-8de9-8f1c2a032d64` (recorded as supplied). Observed activity durations were 12 seconds for `lkp_ingestion_config` and 44 seconds for `fe_dataset_loop`. All five enabled FILE datasets completed. These observations and row counts are verification evidence, not a performance guarantee.

## Previous notebook and current traceability

[NB_Load_Bronze.py](notebooks/NB_Load_Bronze.py) previously processed CSV Landing files into Bronze successfully. It is **inactive in the current FILE path**. Native Copy replaced notebook-per-dataset execution because Spark startup/runtime overhead was disproportionate for these small CSV datasets. The notebook remains an implementation artifact and a possible option when Spark transformations justify it.

The previous notebook added `_ingested_at_utc`, `_source_system`, `_dataset_id`, and `_pipeline_run_id`. The current native Copy Bronze tables do not contain these columns.

Current troubleshooting follows **Fabric Monitor -> pipeline RunId -> LH_Landing RunId directory -> configuration -> LH_Bronze result**. The RunId locates the corresponding retained raw input. There is no durable direct pipeline RunId-to-Bronze Delta version relationship. Retained input provides a foundation for reprocessing, not automated safe replay.

## Remaining scope

SQL ingestion is the next source pattern. REST ingestion, a dataset-level ingestion manifest/audit, retry policies, formal replay controls, processing-attempt identity, completion markers, direct Bronze version linkage, and replay concurrency protection remain future work. No additional Lakehouse or Warehouse is being created for audit, and Spark is not being reintroduced solely for lineage.

Advanced schema contracts, schema drift handling, quarantine/dead-letter handling, incremental loading, watermarks, CDC, deduplication where justified, Silver validation/standardization/quarantine, and configuration tables if later justified are also future work. Gold, star schemas, semantic models, and Power BI are out of scope.

## Repository layout

```text
fabric-metadata-driven-ingestion/
|-- .gitignore
|-- README.md
|-- config/
|   |-- .gitkeep
|   `-- ingestion_config.json
|-- docs/
|   |-- architecture.md
|   `-- configuration-contract.md
|-- fabric/
|   `-- .gitkeep
|-- notebooks/
|   |-- .gitkeep
|   `-- NB_Load_Bronze.py
`-- tests/
    |-- .gitkeep
    `-- validate-config.ps1
```

`fabric/` is a placeholder for reviewed Fabric artifacts; the deployed pipeline is documented here rather than exported in that directory. See [architecture and decisions](docs/architecture.md) and [Configuration Contract v1](docs/configuration-contract.md).

Validate the catalog locally:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests/validate-config.ps1
```

The validator checks static configuration, not live Fabric execution.

## Security boundaries

Keep credentials, passwords, connection strings, access keys, SAS tokens, API secrets, Fabric resource IDs, connection IDs, machine-specific settings, and actual raw data out of Git. Resolve credentials and environment bindings through approved external connections/secret management. Display names and logical aliases are documentation/configuration context, not deployable connection identifiers.

Keep runtime RunIds, timestamps, counts, errors, audit information, and watermark values out of `ingestion_config.json`. The run evidence above belongs in documentation. Ignore rules supplement content review; they do not replace it.
