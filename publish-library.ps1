param(
  [string]$LibraryPath = "",
  [string]$BaseUrl = "https://andres2002-sys.github.io/revista"
)

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
if(-not $LibraryPath){
  $LibraryPath = Join-Path $root "revista-library.json"
  if(-not (Test-Path $LibraryPath)){
    $LibraryPath = Join-Path $env:USERPROFILE "Downloads\revista-library.json"
  }
}

if(-not (Test-Path $LibraryPath)){
  Write-Error "No se encontró revista-library.json (buscado en repo y Descargas)."
  exit 1
}

function Slugify([string]$text){
  if([string]::IsNullOrWhiteSpace($text)){ return $null }
  $slug = $text.ToLower() -replace '[^a-z0-9]+','-'
  $slug = $slug.Trim('-')
  if([string]::IsNullOrWhiteSpace($slug)){ return $null }
  return $slug
}

$library = Get-Content -Raw -Encoding UTF8 $LibraryPath | ConvertFrom-Json
if(-not $library.items){
  Write-Error "Formato inválido en revista-library.json"
  exit 1
}

$viewsDir = Join-Path $root "views"
New-Item -ItemType Directory -Force -Path $viewsDir | Out-Null
$baseHtml = Get-Content -Raw -Encoding UTF8 (Join-Path $root "index.html")

$links = @()
$indexItems = @()
$mdLinks = @()

foreach($item in $library.items){
  if(-not $item.pages){ continue }
  $slug = Slugify($item.name)
  if(-not $slug){ $slug = $item.id }
  $json = ($item | ConvertTo-Json -Depth 30) -replace '</script>', '<\\/script>'
  $embed = '<script type="application/json" id="embeddedData">' + $json + '</' + 'script>' + "`n"
  $out = $baseHtml -replace '</head>', ($embed + '</head>')
  $out = $out -replace '<title>.*?</title>', ("<title>" + $item.name + "</title>")
  $fileName = "$slug.html"
  $outPath = Join-Path $viewsDir $fileName
  Set-Content -Encoding UTF8 -Path $outPath -Value $out
  $url = "$BaseUrl/views/$fileName"
  $links += $url
  $mdLinks += [PSCustomObject]@{ Name = $item.name; Url = $url }
  $indexItems += "<li><a href=`"$url`">$($item.name)</a></li>"
}

$indexHtml = @"
<!DOCTYPE html>
<html lang="es">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>Biblioteca de Revistas</title>
  <style>
    body{font-family:Arial,sans-serif;margin:20px;background:#111;color:#fff}
    a{color:#f59e0b;text-decoration:none}
    li{margin:8px 0}
  </style>
</head>
<body>
  <h1>Biblioteca de Revistas</h1>
  <ul>
    $([string]::Join("`n", $indexItems))
  </ul>
</body>
</html>
"@

Set-Content -Encoding UTF8 -Path (Join-Path $viewsDir "index.html") -Value $indexHtml

function BuildMarkdownLinks($items){
  if(-not $items -or $items.Count -eq 0){
    return '_Sin links todavía. Ejecuta `publish-library.ps1` para generarlos._'
  }
  $lines = @()
  foreach($item in $items){
    $name = [string]$item.Name
    if([string]::IsNullOrWhiteSpace($name)){ $name = "Revista" }
    $name = $name -replace '\s+',' '
    $lines += "- $name: $($item.Url)"
  }
  return [string]::Join("`n", $lines)
}

$readmePath = Join-Path $root "README.md"
if(Test-Path $readmePath){
  $readme = Get-Content -Raw -Encoding UTF8 $readmePath
  $start = "<!-- MAGAZINE_LINKS_START -->"
  $end = "<!-- MAGAZINE_LINKS_END -->"
  $mdBlock = BuildMarkdownLinks $mdLinks
  if($readme -match [regex]::Escape($start) -and $readme -match [regex]::Escape($end)){
    $pattern = "(?s)$([regex]::Escape($start)).*?$([regex]::Escape($end))"
    $replacement = "$start`n$mdBlock`n$end"
    $readme = [regex]::Replace($readme, $pattern, $replacement)
  }else{
    $readme = $readme + "`n`n## Revistas publicadas`n$start`n$mdBlock`n$end`n"
  }
  Set-Content -Encoding UTF8 -Path $readmePath -Value $readme
}

Write-Output "Generado en: $viewsDir"
Write-Output "Links:"
$links | ForEach-Object { Write-Output $_ }
