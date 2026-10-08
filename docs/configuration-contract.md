# Metadata configuration contract

## Evidence and repository mismatch

The deployed catalog is `LH_Configuration/Files/ingestion_config.json`. Its complete current contents are **Not verified**. No deployed catalog capture or pipeline export is present.

The local [configuration](../config/ingestion_config.json) was already modified before review and initially contained invalid SQL fragments. An external edit during review replaced them with valid v1 JSON: five enabled FILE records, four enabled SQL records and one disabled REST placeholder (ten records total). This documentation task did not edit the catalog. Its parity with the deployed file remains **Not verified**.

The committed predecessor has a v1 root with five ecommerce records and disabled AdventureWorks/USGS examples. It is historical, not the current nine-table deployment. The [validator](../tests/validate-config.ps1) still requires disabled SQL with Landing `TBD`. The corrected JSON resolves the syntax issue but not the validator mismatch. Reconcile validation rules with the demonstrated SQL path in a separate implementation change, after confirming deployed-file parity.

## Human-readable schema

All fields below are required by the legacy validator; explicit nulls are allowed only where stated. No current pipeline expression was independently verified from an export.

| Field | Type and meaning | Runtime consumption evidence |
| --- | --- | --- |
| `contract_version` | Root integer, `1` | Legacy validator consumes it; pipeline enforcement **Not verified**. |
| `landing_path_template` | Root string, exactly `Files/{source_system}/{dataset_id}/{run_id}/` | Path convention; dynamic consumption **Not verified**. Earlier FILE expressions constructed paths directly. |
| `datasets` | Root nonempty array | Intended loop input; actual Lookup shape and ForEach Items require UI verification. |
| `dataset_id` | Unique lowercase identifier | Previously documented FILE path segment; SQL identities present in the local catalog. |
| `enabled` | Boolean, not string | Owner reports DISABLED routing with Wait; expression/precedence unverified. |
| `source_system` | Lowercase grouping identifier | Previously documented FILE path segment; not a security boundary. |
| `source_type` | Case-sensitive `FILE`, `SQL`, historical `REST` | FILE/SQL demonstrated; REST unimplemented. Exact Switch/default rules unverified. |
| `connection_alias` | Lowercase logical label | Descriptive; no dynamic alias-to-connection resolver evidenced. |
| `source` | Source-specific object | Supplies object selection conceptually; exact current bindings unverified. |
| `landing` | Object with `format` | CSV FILE and Parquet SQL demonstrated; dynamic format dispatch unverified. |
| `bronze` | Object with `schema`, `table` | FILE bindings previously documented; SQL targets corroborated by reported counts. |
| `keys` | Object with `source_primary_key`, `business_key` | Each null or array of nonempty names; descriptive/reserved, not merge or deduplication controls. |
| `load_policy` | Object with `mode`, `bronze_write`, `history` | Describes snapshot behavior; dynamic policy dispatch/enforcement unverified. |

Dataset IDs, source systems, aliases and Bronze identifiers follow `^[a-z][a-z0-9_]*$`. Physical source names retain case. Dataset IDs and Bronze schema/table pairs must be unique. Renaming identifiers can change Landing addresses or destinations. Key arrays cannot repeat columns. `null` means unknown/undecided; an empty array means confirmed absent/not applicable. Never infer keys from names.

| Source type | Source fields | Landing and validation |
| --- | --- | --- |
| SQL | `database`, `schema`, `table`: nonempty strings | Local records use `PARQUET`, confirmed by owner execution. Legacy validator still requires `TBD` and disabled SQL. JSON-driven database switching **Not verified**; inspect connection binding. |
| FILE | `container`, `path`, `format`: nonempty strings | Relative container path; CSV demonstrated. Legacy validator also accepts `PARQUET`, which does not establish a working FILE Parquet loader. Landing format must equal source format. |
| REST, historical only | `relative_path`, `method`, `response_format`, `query_parameters` | Legacy values: `GET`, `GEOJSON`, null query parameters, disabled only. Request scope and loader unimplemented. |

The validator rejects extra fields, inappropriate source fields, duplicate identities/targets, absolute/URL paths, backslashes, queries, fragments, wildcards and traversal segments. Disabled records still undergo structural validation. CSV header/delimiter/encoding, mappings, SQL queries, credentials and Fabric IDs are not fields in this contract. Lakehouse and connection bindings live outside the JSON.

## Load policy

| Value | Meaning | Limits |
| --- | --- | --- |
| `mode: FULL` | Extract the selected source object's full snapshot | No watermark or CDC; completeness still needs validation. |
| `bronze_write: REPLACE_SNAPSHOT` | Replace current Bronze contents with the successful extract | No deduplication or cross-table transaction. |
| `history: NONE` | No business change-history policy | Does not disable Landing retention or define Delta history retention. |

These are the legacy validator's only accepted policies. Editing a string does not implement another strategy. Runtime RunIds, timestamps, counts, errors, watermarks and secrets belong outside static JSON.

## Representative SQL record

Reproduced from the current uncommitted catalog. This individual Cars object is not a complete catalog or a captured deployed file.

```json
{
  "dataset_id": "azuresql_cars",
  "enabled": true,
  "source_system": "adflookupdemo",
  "source_type": "SQL",
  "connection_alias": "azuresql_adflookupdemo",
  "source": { "database": "adflookupdemo", "schema": "dbo", "table": "Cars" },
  "landing": { "format": "PARQUET" },
  "bronze": { "schema": "adflookupdemo", "table": "cars" },
  "keys": { "source_primary_key": null, "business_key": null },
  "load_policy": { "mode": "FULL", "bronze_write": "REPLACE_SNAPSHOT", "history": "NONE" }
}
```

## Representative FILE record

Reproduced from the current local catalog and also present in the committed predecessor. Its target appears in the owner's October 8 results. Compare with Fabric before reuse.

```json
{
  "dataset_id": "ecommerce_customers",
  "enabled": true,
  "source_system": "ecommerce",
  "source_type": "FILE",
  "connection_alias": "blob_ecommerce",
  "source": { "container": "source", "path": "customers.csv", "format": "CSV" },
  "landing": { "format": "CSV" },
  "bronze": { "schema": "ecommerce", "table": "customers" },
  "keys": { "source_primary_key": null, "business_key": null },
  "load_policy": { "mode": "FULL", "bronze_write": "REPLACE_SNAPSHOT", "history": "NONE" }
}
```

The intended root encloses records in `datasets`, alongside integer `contract_version: 1` and the shared `landing_path_template`. Neither example replaces the complete deployed catalog.

## Source onboarding

For another table in the existing Azure SQL database, verify source permissions/types, assign unique dataset and Bronze identities, preserve schema/table case, use SQL/Parquet and snapshot policy, and check both SQL copies resolve the record. Verify the connection database and actual Landing filename. Configuration-only onboarding requires an acceptance test; it has not been proven by the supplied evidence.

For another CSV in the existing Blob source, verify container/path, parsing compatibility (previously documented headers, comma delimiter, UTF-8), target uniqueness and both FILE copies. Different delimiters, nested paths or mappings can require pipeline changes.

For a new connection, provision authentication, permissions, networking and reviewed activity bindings. A new source type additionally needs routing, extraction, representation handling, validation and end-to-end tests. Aliases do not provision or dynamically switch connections. Reconcile the local catalog and validator before using them as onboarding gates.
