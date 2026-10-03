param(
    [Parameter(Position=0)][ValidateSet('init','start','stop','reset','check','shell','status')]
    [string]$Action = 'status'
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$bin = 'E:\PostgreSQL18\bin'
$data = Join-Path $root 'var\pgdata'
$log = Join-Path $root 'var\postgres.log'
$port = if ($env:EASYERP_PG_PORT) { $env:EASYERP_PG_PORT } else { '55432' }
$env:PGHOST = '127.0.0.1'
$env:PGPORT = $port
$env:PGUSER = 'erp_demo'

function Pg([string]$exe, [string[]]$arguments) {
    $command = Join-Path $bin "$exe.exe"
    if (-not (Test-Path -LiteralPath $command)) { throw "PostgreSQL 18 command missing: $command" }
    & $command @arguments
    if ($LASTEXITCODE -ne 0) { throw "$exe failed with exit code $LASTEXITCODE" }
}

switch ($Action) {
    init {
        if (Test-Path -LiteralPath (Join-Path $data 'PG_VERSION')) { throw "Cluster already exists: $data" }
        New-Item -ItemType Directory -Path (Join-Path $root 'var') -Force | Out-Null
        Pg 'initdb' @('-D',$data,'-U','erp_demo','--encoding=UTF8','--locale=C','--auth-host=trust','--auth-local=trust','--no-instructions')
    }
    start {
        Pg 'pg_ctl' @('-D',$data,'-l',$log,'-o',"-p $port -h 127.0.0.1",'-w','start')
    }
    stop { Pg 'pg_ctl' @('-D',$data,'-m','fast','-w','stop') }
    status { Pg 'pg_ctl' @('-D',$data,'status') }
    reset {
        Pg 'psql' @('-d','postgres','-v','ON_ERROR_STOP=1','-c','DROP DATABASE IF EXISTS easyerp_demo WITH (FORCE)')
        Pg 'psql' @('-d','postgres','-v','ON_ERROR_STOP=1','-c','CREATE DATABASE easyerp_demo ENCODING UTF8')
        Pg 'psql' @('-d','easyerp_demo','-v','ON_ERROR_STOP=1','-f',(Join-Path $root 'db\001_schema.sql'))
        Pg 'psql' @('-d','easyerp_demo','-v','ON_ERROR_STOP=1','-f',(Join-Path $root 'db\002_demo.sql'))
        Pg 'psql' @('-d','easyerp_demo','-v','ON_ERROR_STOP=1','-f',(Join-Path $root 'db\003_checks.sql'))
    }
    check { Pg 'psql' @('-d','easyerp_demo','-v','ON_ERROR_STOP=1','-f',(Join-Path $root 'db\003_checks.sql')) }
    shell { Pg 'psql' @('-d','easyerp_demo') }
}
