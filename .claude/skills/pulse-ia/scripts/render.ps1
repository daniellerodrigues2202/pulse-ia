<#
  Pulse IA - gera o painel HTML a partir do JSON curado (em portugues)
  Uso:
    powershell -ExecutionPolicy Bypass -File render.ps1 -Content <content.json> -OutDir <pasta> [-NoOpen]
  Saida: <OutDir>\pulse-ia-DD-MM-AAAA.html  (abre no navegador padrao, salvo -NoOpen)
#>
param(
  [Parameter(Mandatory = $true)][string]$Content,
  [string]$OutDir = (Get-Location).Path,
  [switch]$NoOpen,
  [string]$PublishFile = ""
)

function Log([string]$level, [string]$msg) {
  $ts = (Get-Date).ToString("HH:mm:ss")
  $color = switch ($level) { "OK" {"Green"} "WARN" {"Yellow"} "ERRO" {"Red"} default {"Cyan"} }
  Write-Host "[$ts] [pulse-ia] [$level] $msg" -ForegroundColor $color
}
function Esc([string]$s) { if ($null -eq $s) { return "" }; return [System.Net.WebUtility]::HtmlEncode($s) }

if (-not (Test-Path $Content)) { Log "ERRO" "Arquivo de conteudo nao encontrado: $Content"; exit 1 }
$c = Get-Content $Content -Raw -Encoding UTF8 | ConvertFrom-Json
Log "INFO" "Renderizando painel a partir de $Content"

$stamp = $c.date
try { $dt = [datetime]::ParseExact($stamp, "dd-MM-yyyy", $null) } catch { $dt = Get-Date; $stamp = $dt.ToString("dd-MM-yyyy") }
$months = @("janeiro","fevereiro","mar&ccedil;o","abril","maio","junho","julho","agosto","setembro","outubro","novembro","dezembro")
$days = @("domingo","segunda-feira","ter&ccedil;a-feira","quarta-feira","quinta-feira","sexta-feira","s&aacute;bado")
$longDate = "" + $dt.Day + " de " + $months[$dt.Month - 1] + " de " + $dt.Year
$weekday = $days[[int]$dt.DayOfWeek]

function TitlePair($item) {
  $pt = Esc $item.title
  $en = Esc $item.title_original
  if (-not $en) { $en = $pt }
  return "<span class=""pt"">$pt</span><span class=""en"" lang=""en"">$en</span>"
}

# ---------- Principais ----------
$top = ""
$i = 0
foreach ($n in @($c.top)) {
  if (-not $n) { continue }
  $i++
  $cls = if ($i -eq 1) { "card card--lead" } else { "card" }
  $why = if ($n.why) { "<p class=""why""><span>Para produto</span>" + (Esc $n.why) + "</p>" } else { "" }
  $sumEn = if ($n.summary_original) { "<p class=""sum en"" lang=""en"">" + (Esc $n.summary_original) + "</p>" } else { "" }
  $sumPtCls = if ($n.summary_original) { "sum pt" } else { "sum" }
  $top += @"
<a class="$cls" href="$(Esc $n.url)" target="_blank" rel="noopener noreferrer">
  <div class="meta"><span class="tag">$(Esc $n.tag)</span><span>$(Esc $n.source)</span><span>$(Esc $n.date)</span></div>
  <h3>$(TitlePair $n)</h3>
  <p class="$sumPtCls">$(Esc $n.summary)</p>$sumEn
  $why
  <span class="go" aria-hidden="true">Ler original &#8599;</span>
</a>
"@
}

# ---------- Secundarias ----------
$sec = ""
foreach ($n in @($c.secondary)) {
  if (-not $n) { continue }
  $note = if ($n.note) { "<span class=""note"">" + (Esc $n.note) + "</span>" } else { "" }
  $sec += @"
<li><a href="$(Esc $n.url)" target="_blank" rel="noopener noreferrer">
  <span class="lmeta"><span class="tag tag--sm">$(Esc $n.tag)</span>$(Esc $n.source)</span>
  <span class="ltitle">$(TitlePair $n)$note</span>
  <span class="ldate">$(Esc $n.date) &#8599;</span>
</a></li>
"@
}

# ---------- Tendencias ----------
$trends = ""
foreach ($t in @($c.trends)) { if ($t) { $trends += "<li>" + (Esc $t) + "</li>" } }
if ($trends) { $trends = "<ul class=""trends"" aria-label=""Tend&ecirc;ncias"">$trends</ul>" }

# ---------- Fontes ----------
$src = ""
foreach ($s in @($c.sources)) {
  if (-not $s) { continue }
  $st = Esc $s.status
  $note = if ($s.note) { " &middot; " + (Esc $s.note) } else { "" }
  $href = if ($s.url -match "^https?://") { "<a href=""" + (Esc $s.url) + """ target=""_blank"" rel=""noopener noreferrer"">" + (Esc $s.name) + "</a>" } else { Esc $s.name }
  $src += "<li><span class=""dot dot--$st""></span>$href <span class=""muted"">($st$note)</span></li>"
}

$countTop = @($c.top).Count; $countSec = @($c.secondary).Count
$genAt = (Get-Date).ToString("dd/MM/yyyy HH:mm")
$modeNote = if ($c.mode -eq "date") { "<p class=""mode"">Edi&ccedil;&atilde;o hist&oacute;rica &middot; not&iacute;cias referentes a $longDate</p>" } else { "" }

$css = @'
:root{--bg:#fffdf7;--ink:#2b2d42;--plum:#6d597a;--sun:#f2cc8f;--ink-2:#55576b;--line:#ece6d6;--card:#ffffff;--sun-soft:#fbf0dc;--plum-soft:#efeaf2}
*{box-sizing:border-box;margin:0;padding:0}
html{-webkit-text-size-adjust:100%}
body{background:var(--bg);color:var(--ink);font-family:"Instrument Sans",system-ui,sans-serif;font-size:16px;line-height:1.55}
a{color:inherit;text-decoration:none}
.wrap{max-width:1180px;margin:0 auto;padding-left:max(16px,env(safe-area-inset-left,0px));padding-right:max(16px,env(safe-area-inset-right,0px))}
.lede>div,.list a>span,.card{min-width:0}
h1,h2,h3{text-wrap:balance}
@media (prefers-reduced-motion:reduce){.card{transition:none}.card:hover{transform:none}}
.meta,.eyebrow,.lmeta,.ldate,footer,.toggle,.why span,.go,.mode,.section-h small{font-family:"Space Grotesk",system-ui,sans-serif}
header{padding:48px 0 32px;border-bottom:1px solid var(--line)}
.bar{display:flex;justify-content:space-between;align-items:center;gap:12px;flex-wrap:wrap;margin-bottom:28px}
.eyebrow{font-size:12px;letter-spacing:.14em;text-transform:uppercase;color:var(--plum);font-weight:600}
.toggle{border:1px solid var(--plum);background:transparent;color:var(--plum);border-radius:999px;padding:6px 14px;font-size:13px;cursor:pointer}
.toggle:hover,.toggle[aria-pressed=true]{background:var(--plum);color:#fff}
h1{font-family:"Fraunces",Georgia,serif;font-weight:600;font-size:clamp(40px,7vw,76px);line-height:1;letter-spacing:-.02em}
h1 em{font-style:italic;font-weight:400;color:var(--plum)}
.date{font-family:"Fraunces",Georgia,serif;font-size:clamp(18px,2.4vw,24px);color:var(--ink-2);margin-top:10px}
.date b{font-weight:500;color:var(--ink)}
.lede{display:grid;grid-template-columns:minmax(0,1fr) 220px;gap:32px;margin-top:28px;align-items:start}
.lede h2{font-family:"Fraunces",Georgia,serif;font-weight:500;font-size:clamp(20px,2.6vw,28px);line-height:1.25;margin-bottom:10px}
.lede p{color:var(--ink-2);max-width:68ch}
.stats{border-left:3px solid var(--sun);padding-left:16px;font-family:"Space Grotesk",sans-serif;font-size:13px;color:var(--ink-2)}
.stats strong{display:block;font-family:"Fraunces",serif;font-size:34px;color:var(--ink);font-weight:500;line-height:1.1}
.stats div+div{margin-top:12px}
.mode{margin-top:16px;display:inline-block;background:var(--plum-soft);color:var(--plum);border-radius:6px;padding:4px 10px;font-size:13px}
.trends{list-style:none;display:flex;flex-wrap:wrap;gap:8px;margin-top:22px}
.trends li{background:var(--sun-soft);border:1px solid var(--sun);border-radius:999px;padding:4px 12px;font-size:14px}
section{padding:40px 0}
.section-h{display:flex;align-items:baseline;gap:12px;margin-bottom:20px}
.section-h h2{font-family:"Fraunces",Georgia,serif;font-weight:600;font-size:clamp(24px,3vw,32px)}
.section-h small{color:var(--plum);font-size:13px;letter-spacing:.06em;text-transform:uppercase}
.grid{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:18px}
.card{position:relative;display:flex;flex-direction:column;gap:12px;background:var(--card);border:1px solid var(--line);border-radius:14px;padding:22px;transition:transform .15s,box-shadow .15s,border-color .15s}
.card:hover{transform:translateY(-2px);box-shadow:0 10px 28px -16px rgba(43,45,66,.35);border-color:var(--plum)}
.card:focus-visible,.list a:focus-visible{outline:2px solid var(--plum);outline-offset:2px}
.card--lead{grid-column:span 2;grid-row:span 2;background:linear-gradient(160deg,#fff 55%,var(--sun-soft))}
.card h3{font-family:"Fraunces",Georgia,serif;font-weight:500;font-size:21px;line-height:1.25}
.card--lead h3{font-size:clamp(24px,3vw,34px)}
.sum{color:var(--ink-2);font-size:15px}
.card--lead .sum{font-size:17px}
.meta{display:flex;flex-wrap:wrap;gap:6px 12px;align-items:center;font-size:12px;color:var(--ink-2);text-transform:uppercase;letter-spacing:.05em}
.tag{background:var(--plum);color:#fff;border-radius:4px;padding:2px 8px;font-weight:600;letter-spacing:.04em}
.tag--sm{font-size:10px;padding:1px 6px;margin-right:8px}
.why{margin-top:auto;background:var(--sun-soft);border-radius:8px;padding:10px 12px;font-size:14px}
.why span{display:block;font-size:11px;text-transform:uppercase;letter-spacing:.08em;color:var(--plum);font-weight:600;margin-bottom:2px}
.go{font-size:13px;color:var(--plum);font-weight:600}
.list{list-style:none;border-top:1px solid var(--line)}
.list a{display:grid;grid-template-columns:190px minmax(0,1fr) 120px;gap:16px;align-items:baseline;padding:14px 4px;border-bottom:1px solid var(--line)}
.list a:hover{background:var(--plum-soft)}
.lmeta{font-size:12px;text-transform:uppercase;letter-spacing:.05em;color:var(--ink-2)}
.ltitle{font-size:16px}
.ltitle .note{display:block;color:var(--ink-2);font-size:14px;margin-top:2px}
.ldate{font-size:12px;color:var(--ink-2);text-align:right}
.en{display:none}
body.show-en .en{display:inline}
body.show-en p.en{display:block;font-style:italic}
body.show-en .pt{display:none}
footer{border-top:1px solid var(--line);padding:28px 0 48px;font-size:13px;color:var(--ink-2)}
footer .cols{display:flex;justify-content:space-between;gap:24px;flex-wrap:wrap}
footer ul{list-style:none}
footer li{margin:4px 0}
footer a{text-decoration:underline;text-decoration-color:var(--sun);text-underline-offset:3px}
.muted{color:#8a8b99}
.dot{display:inline-block;width:8px;height:8px;border-radius:50%;margin-right:8px;background:#bbb;vertical-align:middle}
.dot--ok{background:#5a9e6f}.dot--fallback{background:var(--sun)}.dot--falhou{background:#c0504d}
@page{size:A4;margin:12mm}
@media print{*{-webkit-print-color-adjust:exact;print-color-adjust:exact}.toggle{display:none}.card,.list li{break-inside:avoid}header{padding-top:8px}section{padding:24px 0}.card:hover{transform:none;box-shadow:none}}
@media (max-width:900px){.grid{grid-template-columns:repeat(2,minmax(0,1fr))}.card--lead{grid-column:span 2;grid-row:auto}.lede{grid-template-columns:1fr}.stats{display:flex;gap:24px;border-left:0;border-top:3px solid var(--sun);padding:12px 0 0}.stats div+div{margin-top:0}}
@media (max-width:600px){header{padding-top:28px}.grid{grid-template-columns:1fr}.card--lead{grid-column:auto}.list a{grid-template-columns:1fr;gap:4px}.ldate{text-align:left}}
'@

$js = @'
(function(){var b=document.querySelector('.toggle');if(!b)return;b.addEventListener('click',function(){var on=document.body.classList.toggle('show-en');b.setAttribute('aria-pressed',on);b.innerHTML=on?'Ver em portugu&ecirc;s':'Ver original (EN)';});})();
'@

$fonts = @"
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Fraunces:ital,opsz,wght@0,9..144,400;0,9..144,500;0,9..144,600;1,9..144,400&family=Instrument+Sans:wght@400;500;600&family=Space+Grotesk:wght@400;500;600&display=swap" rel="stylesheet">
<style>$css</style>
"@

$body = @"
<header><div class="wrap">
  <div class="bar"><span class="eyebrow">Pulse IA &middot; boletim de intelig&ecirc;ncia artificial</span><button class="toggle" type="button" aria-pressed="false">Ver original (EN)</button></div>
  <h1>Pulse <em>IA</em></h1>
  <p class="date">$weekday, <b>$longDate</b></p>
  $modeNote
  <div class="lede">
    <div><h2>$(Esc $c.headline)</h2><p>$(Esc $c.summary)</p></div>
    <div class="stats"><div><strong>$countTop</strong>destaques</div><div><strong>$countSec</strong>no radar</div></div>
  </div>
  $trends
</div></header>
<main class="wrap">
  <section aria-labelledby="h-top"><div class="section-h"><h2 id="h-top">Principais not&iacute;cias</h2><small>o que importa hoje</small></div>
    <div class="grid">$top</div>
  </section>
  <section aria-labelledby="h-sec"><div class="section-h"><h2 id="h-sec">Radar</h2><small>leitura r&aacute;pida</small></div>
    <ul class="list">$sec</ul>
  </section>
</main>
<footer><div class="wrap cols">
  <div><strong>Gerado em</strong> $genAt<br>Tradu&ccedil;&otilde;es e resumos gerados por IA &middot; clique em qualquer item para abrir a fonte original.</div>
  <div><strong>Fontes utilizadas</strong><ul>$src</ul></div>
</div></footer>
<script>$js</script>
"@

$html = "<!doctype html>`n<html lang=""pt-BR"">`n<head>`n<meta charset=""utf-8"">`n<meta name=""viewport"" content=""width=device-width,initial-scale=1"">`n<title>Pulse IA &middot; $stamp</title>`n$fonts</head>`n<body>`n$body</body>`n</html>`n"

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
# Modo recentes: um unico arquivo, sobrescrito todo dia. Modo data (pedido avulso): arquivo datado.
$outName = if ($c.mode -eq "date") { "pulse-ia-$stamp.html" } else { "pulse-ia.html" }
$outFile = Join-Path $OutDir $outName
[IO.File]::WriteAllText($outFile, $html, (New-Object Text.UTF8Encoding $false))
Log "OK" ("Painel salvo: $outFile ($countTop destaques, $countSec no radar)")

# Versao para publicar como Artifact (link compartilhavel): sem doctype/head/body, titulo fixo
if ($PublishFile) {
  $pubDir = Split-Path -Parent $PublishFile
  if ($pubDir) { New-Item -ItemType Directory -Force -Path $pubDir | Out-Null }
  $frag = "<title>Pulse IA</title>`n<meta name=""claude:viewport-fit-sides"" content=""cover"">`n$fonts`n$body"
  [IO.File]::WriteAllText($PublishFile, $frag, (New-Object Text.UTF8Encoding $false))
  Log "OK" "Versao para publicacao salva: $PublishFile"
  Write-Host "PUBLISH=$PublishFile"
}
if (-not $NoOpen) {
  try { Start-Process $outFile; Log "OK" "Abrindo no navegador padrao" } catch { Log "WARN" ("Nao foi possivel abrir automaticamente: " + $_.Exception.Message) }
}
Write-Host "HTML=$outFile"
