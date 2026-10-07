# Fabric notebook source

# METADATA ********************
# META {
# META   "kernel_info": { "name": "synapse_pyspark" },
# META   "dependencies": {}
# META }

# PARAMETERS CELL ********************
# Configure LH_Bronze as default and attach LH_Landing in Fabric.
# Pass the full ABFS path to one completed, immutable Landing file.
dataset_id = ""
source_system = ""
landing_path = ""
bronze_schema = ""
bronze_table = ""
source_format = ""
pipeline_run_id = ""

# METADATA ********************
# META {
# META   "language": "python",
# META   "language_group": "synapse_pyspark",
# META   "tags": ["parameters"]
# META }

# CELL ********************
# Validate before any Spark read or write. No connection IDs or secrets belong here.
import json
import re
from urllib.parse import unquote, urlsplit

parameters = {
    "dataset_id": dataset_id,
    "source_system": source_system,
    "landing_path": landing_path,
    "bronze_schema": bronze_schema,
    "bronze_table": bronze_table,
    "source_format": source_format,
    "pipeline_run_id": pipeline_run_id,
}
for name, value in parameters.items():
    if not isinstance(value, str) or not value.strip():
        raise ValueError(f"Missing required parameter '{name}': supply a nonempty string.")
    if value != value.strip():
        raise ValueError(f"Parameter '{name}' must not have leading/trailing whitespace.")

if source_format.upper() != "CSV":
    raise ValueError(f"Unsupported source_format '{source_format}': v1 supports CSV only.")

for name in ("dataset_id", "source_system", "bronze_schema", "bronze_table"):
    if not re.fullmatch(r"[a-z][a-z0-9_]*", parameters[name]):
        raise ValueError(f"Parameter '{name}' must be a lowercase contract identifier.")

# Relative Files/... paths resolve against default LH_Bronze, not LH_Landing.
# Resolve the actual LH_Landing root in the pipeline, outside versioned config.
uri = urlsplit(landing_path)
parts = unquote(uri.path).strip("/").split("/")
if (
    uri.scheme != "abfss"
    or not uri.netloc
    or not uri.username
    or uri.password is not None
    or not (uri.hostname or "").endswith(".dfs.fabric.microsoft.com")
    or uri.query
    or uri.fragment
    or len(parts) != 6
    or parts[1:4] != ["Files", source_system, dataset_id]
    or any(part in ("", ".", "..") for part in parts)
    or any(char in unquote(uri.path) for char in "*?[]{}\\")
    or uri.path.endswith("/")
):
    raise ValueError(
        "landing_path must be an absolute, credential-free ABFS file path in LH_Landing: "
        "abfss://<workspace>@<onelake-host>/<lakehouse>/Files/"
        "<source_system>/<dataset_id>/<landing-run-id>/<original_file_name>. "
        "Directories, globs and query strings are not supported."
    )

target_table = f"`{bronze_schema}`.`{bronze_table}`"
target_name = f"{bronze_schema}.{bronze_table}"

# METADATA ********************
# META { "language": "python", "language_group": "synapse_pyspark" }

# CELL ********************
# Keep format-specific reading separate from the common Bronze write.
from pyspark.sql import functions as F

spark.conf.set("spark.sql.session.timeZone", "UTC")
spark.conf.set("spark.databricks.delta.schema.autoMerge.enabled", "false")


def read_landing(path, file_format):
    if file_format.upper() == "CSV":
        return (
            spark.read.option("header", "true")
            .option("inferSchema", "true")
            .option("mode", "FAILFAST")
            .csv(path)
        )
    raise ValueError(f"Unsupported source_format '{file_format}': v1 supports CSV only.")


try:
    source_df = read_landing(landing_path, source_format)
except Exception as exc:
    raise RuntimeError(f"Landing read failed for dataset '{dataset_id}'.") from exc

observed_schema = source_df.schema.json()
print("Observed Landing schema:")
print(observed_schema)

# Extension point: add explicit, versioned source-schema validation here later.
# Do not silently replace source columns when adding operational metadata.
metadata_columns = {"_ingested_at_utc", "_source_system", "_dataset_id", "_pipeline_run_id"}
collisions = sorted(name for name in source_df.columns if name.lower() in metadata_columns)
if collisions:
    raise ValueError(f"Source columns collide with reserved operational columns: {collisions}")

# METADATA ********************
# META { "language": "python", "language_group": "synapse_pyspark" }

# CELL ********************
# Preserve source columns and rows; inference is representation, not business cleansing.
bronze_df = (
    source_df.withColumn("_ingested_at_utc", F.current_timestamp())
    .withColumn("_source_system", F.lit(source_system))
    .withColumn("_dataset_id", F.lit(dataset_id))
    .withColumn("_pipeline_run_id", F.lit(pipeline_run_id))
)

spark.sql(f"CREATE SCHEMA IF NOT EXISTS `{bronze_schema}`")
if spark.catalog.tableExists(target_table):
    if spark.catalog.getTable(target_table).tableType != "MANAGED":
        raise ValueError(f"Target '{target_name}' exists but is not a managed table.")
    if spark.sql(f"DESCRIBE DETAIL {target_table}").first()["format"] != "delta":
        raise ValueError(f"Target '{target_name}' exists but is not Delta.")
    # Minimal fail-closed guard, not a schema-drift management framework.
    # Ignore nullable flags; do not allow implicit casts, missing or extra columns.
    existing = {field.name: field.dataType for field in spark.table(target_table).schema}
    incoming = {field.name: field.dataType for field in bronze_df.schema}
    if existing != incoming:
        raise ValueError(
            f"Schema mismatch for '{target_name}': source plus operational columns "
            "must match existing target column names/types. No schema evolution was applied."
        )

# METADATA ********************
# META { "language": "python", "language_group": "synapse_pyspark" }

# CELL ********************
# FULL + REPLACE_SNAPSHOT + history NONE only; serialize writers per target.
# Cache/count the same snapshot that is written. Landing must remain immutable.
snapshot = bronze_df.cache()
try:
    row_count = snapshot.count()
    (
        snapshot.write.format("delta")
        .mode("overwrite")
        .option("partitionOverwriteMode", "static")
        .option("mergeSchema", "false")
        .option("overwriteSchema", "false")
        .saveAsTable(target_table)
    )
except Exception as exc:
    raise RuntimeError(
        f"Bronze snapshot load failed for dataset '{dataset_id}', "
        f"pipeline run '{pipeline_run_id}', target '{target_name}'."
    ) from exc
finally:
    snapshot.unpersist()

# Only emitted after saveAsTable returns successfully. This is not durable audit state.
print(json.dumps({
    "pipeline_run_id": pipeline_run_id,
    "dataset_id": dataset_id,
    "landing_path": landing_path,
    "target_bronze_table": target_name,
    "row_count": row_count,
    "status": "SUCCESS",
}, indent=2))

# METADATA ********************
# META { "language": "python", "language_group": "synapse_pyspark" }
