<#
  Pulse IA - publica o painel no GitHub Pages (link fixo, atualizado todo dia)
  Uso:
    powershell -ExecutionPolicy Bypass -File publish-github.ps1 -Html <pulse-ia-DD-MM-AAAA.html>
  Configuracao:
    - config.json (pasta da skill): github_owner, github_repo, branch
    - Token: variavel de ambiente PULSE_GH_TOKEN (nivel Usuario), criada pelo proprio usuario.
      Permissao necessaria: fine-grained token, so no repositorio, "Contents: Read and write".
  Envia:
    - index.html            -> pagina do link fixo (sempre o painel mais recente)
    - historico/<arquivo>   -> copia datada
#>
param(
  [Parameter(Mandatory = $true)][string]$Html,
  [string]$Config = "",
  [switch]$NoIndex
)

$ErrorActionPreference = "Stop"
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}

function Log([string]$level, [string]$msg) {
  $ts = (Get-Date).ToString("HH:mm:ss")
  $color = switch ($level) { "OK" {"Green"} "WARN" {"Yellow"} "ERRO" {"Red"} default {"Cyan"} }
  Write-Host "[$ts] [pulse-ia] [$level] $msg" -ForegroundColor $color
}

if (-not $Config) { $Config = Join-Path (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)) "config.json" }
if (-not (Test-Path $Html)) { Log "ERRO" "Arquivo nao encontrado: $Html"; exit 1 }
if (-not (Test-Path $Config)) { Log "ERRO" "config.json nao encontrado em $Config"; exit 1 }
$cfg = Get-Content $Config -Raw -Encoding UTF8 | ConvertFrom-Json
$owner = $cfg.github_owner; $repo = $cfg.github_repo; $branch = $cfg.branch
if (-not $branch) { $branch = "main" }
if (-not $owner -or -not $repo) { Log "ERRO" "Preencha github_owner e github_repo em $Config"; exit 1 }

$token = $env:PULSE_GH_TOKEN
if (-not $token) { $token = [Environment]::GetEnvironmentVariable("PULSE_GH_TOKEN", "User") }
if (-not $token) { Log "ERRO" "Variavel PULSE_GH_TOKEN nao encontrada (crie-a no nivel Usuario)."; exit 1 }

$headers = @{
  "Authorization"        = "Bearer $token"
  "Accept"               = "application/vnd.github+json"
  "X-GitHub-Api-Version" = "2022-11-28"
  "User-Agent"           = "pulse-ia-publisher"
}
$api = "https://api.github.com/repos/$owner/$repo/contents"

function Put-File([string]$path, [byte[]]$bytes, [string]$message) {
  $sha = $null
  try {
    $cur = Invoke-RestMethod -Uri "$api/$path`?ref=$branch" -Headers $headers -Method Get
    $sha = $cur.sha
  } catch {
    $code = 0; try { $code = [int]$_.Exception.Response.StatusCode } catch {}
    if ($code -ne 404) { throw }
  }
  $body = @{ message = $message; content = [Convert]::ToBase64String($bytes); branch = $branch }
  if ($sha) { $body.sha = $sha }
  $json = $body | ConvertTo-Json -Compress
  Invoke-RestMethod -Uri "$api/$path" -Headers $headers -Method Put -Body ([Text.Encoding]::UTF8.GetBytes($json)) -ContentType "application/json; charset=utf-8" | Out-Null
}

$bytes = [IO.File]::ReadAllBytes((Resolve-Path $Html))
$name = Split-Path -Leaf $Html
# arquivo sem data (pulse-ia.html): o historico no GitHub recebe o nome com a data de hoje
if ($name -notmatch '\d{2}-\d{2}-\d{4}') { $name = "pulse-ia-" + (Get-Date).ToString("dd-MM-yyyy") + ".html" }
$stamp = (Get-Date).ToString("dd-MM-yyyy HH:mm")
$ok = $true

if (-not $NoIndex) {
  try {
    Log "INFO" "GitHub: enviando index.html ($owner/$repo, $branch)"
    Put-File "index.html" $bytes "Pulse IA: painel de $stamp"
    Log "OK" "GitHub: index.html atualizado"
  } catch {
    $ok = $false
    Log "ERRO" ("GitHub: falha ao enviar index.html: " + $_.Exception.Message + " " + $_.ErrorDetails.Message)
  }
}
try {
  Log "INFO" "GitHub: enviando historico/$name"
  Put-File "historico/$name" $bytes "Pulse IA: historico $name"
  Log "OK" "GitHub: historico/$name salvo"
} catch {
  if ($NoIndex) { $ok = $false }
  Log "WARN" ("GitHub: falha ao salvar historico: " + $_.Exception.Message + " " + $_.ErrorDetails.Message)
}

$siteBase = "https://$($owner.ToLower()).github.io/$repo/"
if ($repo -ieq "$owner.github.io") { $siteBase = "https://$($owner.ToLower()).github.io/" }
if ($ok) {
  Log "OK" "Link fixo (atualiza em ~1-2 min): $siteBase"
  Write-Host "SITE_URL=$siteBase"
  Write-Host "HISTORY_URL=${siteBase}historico/$name"
} else { exit 2 }
