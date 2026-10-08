param(
    [string]$Path = (Join-Path $PSScriptRoot '../config/ingestion_config.json')
)

$ErrorActionPreference = 'Stop'

function Assert-Valid($Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

function Assert-Shape($Object, [string[]]$Fields, [string]$Location) {
    Assert-Valid ($Object -is [pscustomobject]) "$Location must be an object."
    $actual = @($Object.PSObject.Properties.Name)
    foreach ($field in $Fields) {
        Assert-Valid ($actual -ccontains $field) "$Location is missing $field."
    }
    foreach ($field in $actual) {
        Assert-Valid ($Fields -ccontains $field) "$Location has unsupported field $field."
    }
}

function Assert-Text($Value, [string]$Location) {
    Assert-Valid (($Value -is [string]) -and -not [string]::IsNullOrWhiteSpace($Value)) "$Location must be nonempty text."
}

function Assert-Identifier($Value, [string]$Location) {
    Assert-Text $Value $Location
    Assert-Valid ($Value -cmatch '^[a-z][a-z0-9_]*$') "$Location must be a lowercase identifier."
}

function Assert-RelativePath($Value, [string]$Location) {
    Assert-Text $Value $Location
    Assert-Valid ($Value -notmatch '(^/|\\|:|\?|#|\*|(^|/)\.\.?(/|$))') "$Location must be a relative object path without URL, query, wildcard, or traversal."
}

$config = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
Assert-Shape $config @('contract_version', 'landing_path_template', 'datasets') 'root'
Assert-Valid (($config.contract_version -is [int] -or $config.contract_version -is [long]) -and $config.contract_version -eq 1) 'Only integer contract_version 1 is supported.'
Assert-Text $config.landing_path_template 'landing_path_template'
Assert-Valid ($config.landing_path_template -ceq 'Files/{source_system}/{dataset_id}/{run_id}/') 'Unexpected Landing template.'
Assert-Valid (($config.datasets -is [array]) -and $config.datasets.Count -gt 0) 'datasets must be a nonempty array.'
$datasetIds = @{}
$targets = @{}

foreach ($dataset in $config.datasets) {
    Assert-Shape $dataset @('dataset_id', 'enabled', 'source_system', 'source_type', 'connection_alias', 'source', 'landing', 'bronze', 'keys', 'load_policy') 'dataset'
    $id = $dataset.dataset_id
    Assert-Identifier $id 'dataset_id'
    Assert-Valid (-not $datasetIds.ContainsKey($id)) "Duplicate dataset_id: $id"
    $datasetIds[$id] = $true
    Assert-Valid ($dataset.enabled -is [bool]) "$id enabled must be boolean."
    Assert-Identifier $dataset.source_system "$id source_system"
    Assert-Identifier $dataset.connection_alias "$id connection_alias"
    Assert-Text $dataset.source_type "$id source_type"
    Assert-Valid (@('SQL', 'FILE', 'REST') -ccontains $dataset.source_type) "$id has unsupported source_type."
    Assert-Shape $dataset.landing @('format') "$id landing"
    Assert-Text $dataset.landing.format "$id landing.format"
    Assert-Shape $dataset.bronze @('schema', 'table') "$id bronze"
    Assert-Identifier $dataset.bronze.schema "$id bronze.schema"
    Assert-Identifier $dataset.bronze.table "$id bronze.table"
    $target = $dataset.bronze.schema + '.' + $dataset.bronze.table
    Assert-Valid (-not $targets.ContainsKey($target)) "Duplicate Bronze target: $target"
    $targets[$target] = $true
    Assert-Shape $dataset.load_policy @('mode', 'bronze_write', 'history') "$id load_policy"
    foreach ($field in @('mode', 'bronze_write', 'history')) { Assert-Text $dataset.load_policy.$field "$id load_policy.$field" }
    Assert-Valid ($dataset.load_policy.mode -ceq 'FULL') "$id has unsupported load mode."
    Assert-Valid ($dataset.load_policy.bronze_write -ceq 'REPLACE_SNAPSHOT') "$id has unsupported Bronze write policy."
    Assert-Valid ($dataset.load_policy.history -ceq 'NONE') "$id has unsupported history policy."
    Assert-Shape $dataset.keys @('source_primary_key', 'business_key') "$id keys"
    foreach ($keyName in @('source_primary_key', 'business_key')) {
        $columns = $dataset.keys.$keyName
        if ($null -ne $columns) {
            Assert-Valid ($columns -is [array]) "$id keys.$keyName must be null or an array."
            $seenColumns = @{}
            foreach ($column in $columns) {
                Assert-Text $column "$id keys.$keyName column"
                Assert-Valid (-not $seenColumns.ContainsKey($column)) "$id keys.$keyName repeats a column."
                $seenColumns[$column] = $true
            }
        }
    }
    $source = $dataset.source
    switch -CaseSensitive ($dataset.source_type) {
        'SQL' {
            Assert-Shape $source @('database', 'schema', 'table') "$id source"
            foreach ($field in @('database', 'schema', 'table')) { Assert-Text $source.$field "$id source.$field" }
            Assert-Valid ($dataset.landing.format -ceq 'PARQUET') "$id SQL Landing format must be PARQUET."
        }
        'FILE' {
            Assert-Shape $source @('container', 'path', 'format') "$id source"
            Assert-Text $source.container "$id source.container"
            Assert-RelativePath $source.path "$id source.path"
            Assert-Text $source.format "$id source.format"
            Assert-Valid (@('CSV', 'PARQUET') -ccontains $source.format) "$id has unsupported file format."
            Assert-Valid ($dataset.landing.format -ceq $source.format) "$id FILE Landing must preserve source format."
        }
        'REST' {
            Assert-Valid (-not $dataset.enabled) "$id REST must remain disabled because REST ingestion is not implemented."
            Assert-Shape $source @('relative_path', 'method', 'response_format', 'query_parameters') "$id source"
            Assert-RelativePath $source.relative_path "$id source.relative_path"
            Assert-Text $source.method "$id source.method"
            Assert-Text $source.response_format "$id source.response_format"
            Assert-Valid ($source.method -ceq 'GET') "$id REST method must be GET."
            Assert-Valid ($source.response_format -ceq 'GEOJSON') "$id REST response must be GEOJSON."
            Assert-Valid ($dataset.landing.format -ceq $source.response_format) "$id REST Landing must preserve response format."
            Assert-Valid ($null -eq $source.query_parameters) "$id REST query-parameter contract is deferred in v1."
        }
    }
}

$enabledCount = @($config.datasets | Where-Object { $_.enabled }).Count
$disabledCount = $config.datasets.Count - $enabledCount
Write-Output "PASS: JSON syntax; contract v1; $($config.datasets.Count) datasets ($enabledCount enabled, $disabledCount disabled); unique IDs and Bronze targets; boolean enabled; FILE/SQL metadata; disabled-only REST metadata; Bronze destinations; full-snapshot load policy; key definitions; no extra fields."
