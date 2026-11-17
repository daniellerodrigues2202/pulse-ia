<#
  Pulse IA - coleta de fontes
  Uso:
    powershell -ExecutionPolicy Bypass -File fetch.ps1                 # dia atual (recentes)
    powershell -ExecutionPolicy Bypass -File fetch.ps1 -Date 15-03-2025 # data especifica
  Saida: JSON bruto em $env:TEMP\pulse-ia\raw-DD-MM-AAAA.json (caminho impresso no fim).
  Regra: se uma fonte falhar, registra no log e segue com as demais.
#>
param(
  [string]$Date = "",
  [int]$MaxArxiv = 40,
  [string]$OutDir = ""
)
# Windows usa %TEMP%; Linux (nuvem) nao tem TEMP, entao cai no temp do sistema (/tmp)
if (-not $OutDir) { $OutDir = Join-Path ([IO.Path]::GetTempPath()) "pulse-ia" }

$ErrorActionPreference = "Continue"
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}
$UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36"

function Log([string]$level, [string]$msg) {
  $ts = (Get-Date).ToString("HH:mm:ss")
  $color = switch ($level) { "OK" {"Green"} "WARN" {"Yellow"} "ERRO" {"Red"} default {"Cyan"} }
  Write-Host "[$ts] [pulse-ia] [$level] $msg" -ForegroundColor $color
}

function Clean([string]$s) {
  if (-not $s) { return "" }
  $s = [regex]::Replace($s, "<[^>]+>", " ")
  $s = [System.Net.WebUtility]::HtmlDecode($s)
  return ([regex]::Replace($s, "\s+", " ")).Trim()
}

function Get-Url([string]$url) {
  $r = Invoke-WebRequest -Uri $url -UserAgent $UA -UseBasicParsing -TimeoutSec 40 `
       -Headers @{ "Accept" = "text/html,application/xml;q=0.9,*/*;q=0.8"; "Accept-Language" = "en-US,en;q=0.9" }
  # forca leitura em UTF-8
  $ms = $r.RawContentStream
  if ($ms) { $ms.Position = 0; return (New-Object IO.StreamReader($ms, [Text.Encoding]::UTF8)).ReadToEnd() }
  return $r.Content
}

# ---------- Data alvo ----------
$targetDate = $null
if ($Date) {
  try { $targetDate = [datetime]::ParseExact($Date, "dd-MM-yyyy", $null) }
  catch { Log "ERRO" "Data invalida '$Date'. Use DD-MM-AAAA."; exit 1 }
  Log "INFO" ("Modo data especifica: " + $targetDate.ToString("dd-MM-yyyy"))
} else {
  Log "INFO" "Modo recentes (hoje)"
}
$stamp = if ($targetDate) { $targetDate.ToString("dd-MM-yyyy") } else { (Get-Date).ToString("dd-MM-yyyy") }

$result = [ordered]@{
  generated_at = (Get-Date).ToString("s")
  target_date  = $stamp
  mode         = $(if ($targetDate) { "date" } else { "recent" })
  sources      = @()
  arxiv        = @()
  venturebeat  = @()
}

# ---------- arXiv ----------
function Get-ArxivApi([string]$query) {
  $xmlText = Get-Url ("https://export.arxiv.org/api/query?" + $query)
  [xml]$x = $xmlText
  $out = @()
  foreach ($e in @($x.feed.entry)) {
    if (-not $e) { continue }
    $id = ($e.id -replace "^.*/abs/", "") -replace "v\d+$", ""
    $authors = @($e.author | ForEach-Object { $_.name }) | Select-Object -First 5
    $cats = @($e.category | ForEach-Object { $_.term })
    $out += [ordered]@{
      id = $id; title = (Clean $e.title); abstract = (Clean $e.summary)
      authors = ($authors -join ", "); subjects = ($cats -join "; ")
      published = $e.published; url = "https://arxiv.org/abs/$id"
    }
  }
  return ,$out
}

$arxivStatus = [ordered]@{ name = "arXiv cs.AI"; url = "https://arxiv.org/list/cs.AI/recent"; status = "falhou"; note = "" }
try {
  if ($targetDate) {
    $d = $targetDate.ToString("yyyyMMdd")
    Log "INFO" "arXiv: consultando API por submittedDate $d"
    $q = "search_query=cat:cs.AI+AND+submittedDate:[${d}0000+TO+${d}2359]&sortBy=submittedDate&sortOrder=descending&max_results=$MaxArxiv"
    $items = Get-ArxivApi $q
    if ($items.Count -eq 0) {
      # fim de semana/feriado: amplia para +-2 dias
      $a = $targetDate.AddDays(-2).ToString("yyyyMMdd"); $b = $targetDate.AddDays(2).ToString("yyyyMMdd")
      Log "WARN" "arXiv: nada no dia exato, ampliando janela $a..$b"
      $q = "search_query=cat:cs.AI+AND+submittedDate:[${a}0000+TO+${b}2359]&sortBy=submittedDate&sortOrder=descending&max_results=$MaxArxiv"
      $items = Get-ArxivApi $q
      $arxivStatus.note = "janela ampliada +-2 dias"
    }
    $arxivStatus.url = "https://export.arxiv.org/api/query (cat:cs.AI, $d)"
  } else {
    Log "INFO" "arXiv: lendo https://arxiv.org/list/cs.AI/recent"
    # arXiv so aceita show em 25/50/100/250/500/1000/2000
    $show = (@(25, 50, 100, 250) | Where-Object { $_ -ge $MaxArxiv } | Select-Object -First 1); if (-not $show) { $show = 250 }
    $html = Get-Url "https://arxiv.org/list/cs.AI/recent?skip=0&show=$show"
    $h3 = [regex]::Match($html, "<h3>\s*([^<(]+)")
    if ($h3.Success) { $arxivStatus.note = "listagem de " + $h3.Groups[1].Value.Trim() }
    $pairs = [regex]::Matches($html, "(?s)<dt>.*?id=""(\d{4}\.\d{4,5})"".*?</dt>\s*<dd>(.*?)</dd>")
    $items = @()
    foreach ($m in $pairs) {
      $dd = $m.Groups[2].Value
      $title = Clean (([regex]::Match($dd, "(?s)list-title[^>]*>(.*?)</div>")).Groups[1].Value -replace "(?s)<span class='descriptor'>.*?</span>", "")
      $auth  = Clean (([regex]::Match($dd, "(?s)list-authors'>(.*?)</div>")).Groups[1].Value)
      $subj  = Clean (([regex]::Match($dd, "(?s)list-subjects'>(.*?)</div>")).Groups[1].Value -replace "(?s)<span class='descriptor'>.*?</span>", "")
      $items += [ordered]@{ id = $m.Groups[1].Value; title = $title; abstract = ""; authors = $auth; subjects = $subj; published = ""; url = "https://arxiv.org/abs/" + $m.Groups[1].Value }
      if ($items.Count -ge $MaxArxiv) { break }
    }
    Log "INFO" ("arXiv: " + $items.Count + " artigos na listagem; buscando resumos (abstracts)")
    if ($items.Count -gt 0) {
      try {
        $ids = ($items | ForEach-Object { $_.id }) -join ","
        $api = Get-ArxivApi ("id_list=$ids&max_results=" + $items.Count)
        $map = @{}; foreach ($a in $api) { $map[$a.id] = $a }
        foreach ($it in $items) { if ($map.ContainsKey($it.id)) { $it.abstract = $map[$it.id].abstract; $it.published = $map[$it.id].published } }
      } catch { Log "WARN" ("arXiv: falha ao buscar abstracts (" + $_.Exception.Message + "), seguindo so com titulos") }
    }
  }
  $result.arxiv = $items
  $arxivStatus.status = "ok"
  Log "OK" ("arXiv: " + $items.Count + " itens coletados")
} catch {
  $arxivStatus.note = $_.Exception.Message
  Log "ERRO" ("arXiv falhou: " + $_.Exception.Message + " -> seguindo")
}
$result.sources += $arxivStatus

# ---------- VentureBeat ----------
$vbStatus = [ordered]@{ name = "VentureBeat AI"; url = "https://venturebeat.com/category/ai/"; status = "falhou"; note = "" }
$vbItems = @()
foreach ($feed in @("https://venturebeat.com/category/ai/feed/")) {
  try {
    Log "INFO" "VentureBeat: tentando feed $feed"
    [xml]$rss = Get-Url $feed
    foreach ($it in @($rss.rss.channel.item)) {
      if (-not $it) { continue }
      $pub = $null; try { $pub = [datetime]::Parse($it.pubDate) } catch {}
      if ($targetDate -and $pub -and ($pub.Date -ne $targetDate.Date)) { continue }
      $cats = @($it.category | ForEach-Object { if ($_ -is [string]) { $_ } else { $_.'#cdata-section' } }) -join ", "
      $t = $it.title; if ($t -isnot [string]) { $t = $t.InnerText }
      $desc = $it.description; if ($desc -and $desc -isnot [string]) { $desc = $desc.InnerText }
      $vbItems += [ordered]@{ title = (Clean $t); url = $it.link; published = $(if ($pub) { $pub.ToString("yyyy-MM-dd") } else { "" }); excerpt = (Clean $desc); categories = $cats }
    }
    $vbStatus.status = "ok"; $vbStatus.note = "via RSS"
    break
  } catch {
    Log "WARN" ("VentureBeat: feed falhou (" + $_.Exception.Message + ")")
  }
}
if ($vbStatus.status -ne "ok") {
  try {
    Log "INFO" "VentureBeat: tentando HTML da categoria"
    $html = Get-Url "https://venturebeat.com/category/ai/"
    $seen = @{}
    foreach ($m in [regex]::Matches($html, "(?s)<a[^>]+href=""(https://venturebeat\.com/[a-z-]+/[a-z0-9-]{20,})/?""[^>]*>(.*?)</a>")) {
      $u = $m.Groups[1].Value; $t = Clean $m.Groups[2].Value
      if ($t.Length -lt 25 -or $seen.ContainsKey($u)) { continue }
      $seen[$u] = 1
      $vbItems += [ordered]@{ title = $t; url = $u; published = ""; excerpt = ""; categories = "" }
    }
    $vbStatus.status = "ok"; $vbStatus.note = "via HTML"
  } catch {
    $vbStatus.note = "bloqueado para script (" + $_.Exception.Message + "); usar fallback WebFetch"
    Log "ERRO" ("VentureBeat falhou: " + $_.Exception.Message + " -> seguindo (fallback: WebFetch pelo Claude)")
  }
}
if ($vbStatus.status -eq "ok") { Log "OK" ("VentureBeat: " + $vbItems.Count + " itens coletados") }
if ($targetDate -and $vbStatus.status -eq "ok" -and $vbItems.Count -eq 0) {
  $vbStatus.note += "; feed nao cobre a data pedida - complementar com WebSearch"
  Log "WARN" "VentureBeat: nenhum item na data pedida (feed so tem recentes)"
}
$result.venturebeat = $vbItems
$result.sources += $vbStatus

# ---------- Saida ----------
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$outFile = Join-Path $OutDir "raw-$stamp.json"
$json = $result | ConvertTo-Json -Depth 8
[IO.File]::WriteAllText($outFile, $json, (New-Object Text.UTF8Encoding $false))
$okCount = @($result.sources | Where-Object { $_.status -eq "ok" }).Count
Log "OK" ("Coleta concluida: $okCount/" + $result.sources.Count + " fontes ok, " + $result.arxiv.Count + " arXiv, " + $result.venturebeat.Count + " VentureBeat")
Write-Host "RAW_JSON=$outFile"
