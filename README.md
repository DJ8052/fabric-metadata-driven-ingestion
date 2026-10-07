# Metadata-driven ingestion in Microsoft Fabric

A data engineering portfolio project for reusable ingestion from SQL Server, Azure Blob Storage, and a REST API into raw Landing files and Bronze Delta tables, with a later Silver validation layer.

## Engineering problem

Dataset-specific pipelines duplicate orchestration and make source onboarding, recovery, and operational changes difficult. Relational tables, files, and API responses also have different extraction requirements. Reuse must account for those differences while providing consistent configuration, storage conventions, and traceability.

## Project objective

Build a metadata-driven framework that routes datasets to reusable source-specific ingestion patterns, preserves raw extracts for replay, and loads a shared Bronze Lakehouse. Begin with JSON configuration; evaluate configuration tables after the contract and operating needs are understood.

## Source systems

| Source | Initial scope | Format / behavior |
| --- | --- | --- |
| Local SQL Server Express | `AdventureWorksLT2022`, initially `SalesLT.Customer` | Landing representation TBD until the SQL Server ingestion pattern is implemented and tested |
| Azure Blob Storage | Account `ecommerceunifiedproject`, container `source`: `customers.csv`, `orders.csv`, `payments.csv`, `support_tickets.csv`, `web_activities.csv` | CSV initially; Parquet may be added later |
| USGS Earthquake API | Earthquake observations | JSON/GeoJSON responses; request scope remains to be decided |

Source availability is reported by the project owner. Connections, permissions, schemas, and data contents have not been verified in this step.

## High-level architecture — PLANNED

```text
Configuration -> Lookup -> ForEach -> source-type routing
                                       |
SQL Server --------\                   v
Azure Blob ---------> Reusable SQL / file / REST ingestion patterns
USGS REST API -----/                   |
                                       v
                          LH_Landing: raw extracts
                          source / dataset / run
                                       |
                                       v
                          LH_Bronze: Delta tables
                          schemas by source system
                                       |
                                       v
                          Silver (future Lakehouse)
                          validation / standardization /
                          data quality / quarantine
```

This is a design, not an executable pipeline. Connector-specific extraction feeds a planned reusable Bronze loader. See [architecture and tradeoffs](docs/architecture.md).

## CURRENT STATE

- The project owner has created workspace `WS_Metadata_Bronze_Demo` and schema-enabled Lakehouses `LH_Configuration`, `LH_Landing`, and `LH_Bronze`. These resources were not inspected from this repository.
- This repository contains project documentation, ignore rules, [Configuration Contract v1](docs/configuration-contract.md), a [seven-dataset JSON catalog](config/ingestion_config.json), and a lightweight local validator. All seven datasets are initially disabled pending source/connection validation.
- No ingestion, pipeline, notebook, Bronze table, audit process, replay process, or Silver layer is implemented here. No successful ingestion run is claimed; the configuration has not been uploaded to Fabric.

## PLANNED phases

| Phase | Deliverable | Status |
| --- | --- | --- |
| 0 | Repository structure and architecture documentation | Present in this working tree; awaiting review |
| 1 | JSON configuration contract, source inventory, key discovery, and connection validation | Local v1 contract and initial catalog present; key discovery and connection validation pending |
| 2 | SQL, file, and REST extraction patterns; metadata-driven routing; raw Landing conventions | Planned |
| 3 | Generic Bronze load notebook with format-aware parsing and explicit dataset load policies | Planned |
| 4 | Ingestion audit/monitoring, failure handling, and replay with tested duplicate prevention | Planned |
| 5 | Silver validation, standardization, data quality, and quarantine; selective history where justified | Planned |
| Later evaluation | Configuration tables when editing, querying, or governance needs justify them | Planned |

Source primary keys and business keys will be recorded separately. SCD2/change-history requires a dataset-specific use case; it is not the default Bronze behavior.

## Repository layout

```text
fabric-metadata-driven-ingestion/
├── .gitignore
├── README.md
├── config/
│   ├── .gitkeep
│   └── ingestion_config.json
├── docs/
│   ├── architecture.md
│   └── configuration-contract.md
├── fabric/
│   └── .gitkeep
├── notebooks/
│   └── .gitkeep
└── tests/
    ├── .gitkeep
    └── validate-config.ps1
```

`config/` contains non-secret configuration; `tests/` contains local contract validation. `notebooks/` is reserved for future authored notebooks and `fabric/` for genuine, reviewed Fabric artifacts when available. `.gitkeep` files are scaffolding placeholders. Run `powershell -NoProfile -ExecutionPolicy Bypass -File tests/validate-config.ps1` to validate the catalog locally (process-scoped policy override only).

## Security and scope

Never commit credentials, passwords, connection strings, access keys, SAS tokens, API secrets, machine-specific secrets, environment-specific Fabric IDs, or actual raw/landing data. Keep credentials in approved external connection/secret management and resolve environment-specific values outside versioned configuration. Workspace and Lakehouse display names above provide context, not deployable identifiers.

Ignore rules cover common local secrets, environment settings, data locations, and generated files; they do not replace reviewing file contents before a future commit. JSON is intentionally not ignored globally because non-secret configuration will later be versioned.

Gold, star schemas, semantic models, and Power BI are outside this project's scope. This phase adds only local configuration, documentation, and validation; no Fabric runtime implementation, deployment, commit, or push.
