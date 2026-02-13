param(
  [string]$LibraryPath = "",
  [string]$BaseUrl = "https://andres2002-sys.github.io/revista",
  [ValidateSet("auto","embed","remote","assets")]
  [string]$Mode = "auto",
  [string]$SingleName = "",
  [int]$SingleIndex = -1
)

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
if(-not $LibraryPath){
  $LibraryPath = Join-Path $root "revista-library.json"
  if(-not (Test-Path $LibraryPath)){
    $LibraryPath = Join-Path $env:USERPROFILE "Downloads\revista-library.json"
  }
}

if(-not (Test-Path $LibraryPath)){
  Write-Error "No se encontro revista-library.json (buscado en repo y Descargas)."
  exit 1
}

$fileInfo = Get-Item $LibraryPath
if($Mode -eq "auto"){
  if($fileInfo.Length -gt 50MB){
    $Mode = "assets"
  }else{
    $Mode = "embed"
  }
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
  Write-Error "Formato invalido en revista-library.json"
  exit 1
}

$items = @($library.items)
if($SingleName){
  $items = @($items | Where-Object { $_.name -eq $SingleName })
  if(-not $items.Count){
    Write-Error "No se encontro una revista con el nombre especificado."
    exit 1
  }
}elseif($SingleIndex -ge 0){
  if($SingleIndex -ge $items.Count){
    Write-Error "SingleIndex fuera de rango."
    exit 1
  }
  $items = @($items[$SingleIndex])
}elseif($Mode -eq "assets" -and $items.Count -gt 1){
  $items = @($items[0])
}

$viewsDir = Join-Path $root "views"
New-Item -ItemType Directory -Force -Path $viewsDir | Out-Null
$baseHtml = Get-Content -Raw -Encoding UTF8 (Join-Path $root "index.html")

function NewShareBlob([string]$json){
  $response = Invoke-WebRequest -Method Post -Uri "https://jsonblob.com/api/jsonBlob" `
    -ContentType "application/json" `
    -Headers @{ Accept = "application/json" } `
    -Body $json
  $location = $response.Headers["Location"]
  if(-not $location){ throw "No se recibio URL." }
  return $location
}

function BuildViewerLink([string]$baseUrl, [string]$blobUrl){
  $cleanBase = $baseUrl.TrimEnd("/")
  $encoded = [uri]::EscapeDataString($blobUrl)
  if($cleanBase -match '\.html$'){
    return "$cleanBase?mode=view&src=$encoded"
  }
  return "$cleanBase/?mode=view&src=$encoded"
}

function GetDataUrlInfo([string]$dataUrl){
  if([string]::IsNullOrWhiteSpace($dataUrl)){ return $null }
  if($dataUrl -match '^data:(?<mime>[^;]+);base64,(?<data>.+)$'){
    return @{ Mime = $matches['mime']; Data = $matches['data'] }
  }
  return $null
}

function GetExtensionFromMime([string]$mime){
  switch -Regex ($mime){
    '^image/jpeg' { return 'jpg' }
    '^image/jpg' { return 'jpg' }
    '^image/png' { return 'png' }
    '^image/webp' { return 'webp' }
    '^image/gif' { return 'gif' }
    '^audio/mpeg' { return 'mp3' }
    '^audio/mp3' { return 'mp3' }
    '^audio/wav' { return 'wav' }
    '^audio/ogg' { return 'ogg' }
    '^audio/webm' { return 'webm' }
    '^audio/aac' { return 'aac' }
    '^audio/mp4' { return 'm4a' }
    default { return 'bin' }
  }
}

function WriteDataUrlToFile([string]$dataUrl, [string]$fileBase){
  $info = GetDataUrlInfo $dataUrl
  if(-not $info){ return $null }
  $ext = GetExtensionFromMime $info.Mime
  $path = "$fileBase.$ext"
  $bytes = [Convert]::FromBase64String($info.Data)
  [IO.File]::WriteAllBytes($path, $bytes)
  return $path
}

$links = @()
$indexItems = @()
$mdLinks = @()

foreach($item in $items){
  if(-not $item.pages){ continue }
  $slug = Slugify($item.name)
  if(-not $slug){ $slug = $item.id }

  if($Mode -eq "embed"){
    $json = ($item | ConvertTo-Json -Depth 30) -replace '</script>', '<\\/script>'
    $embed = '<script type="application/json" id="embeddedData">' + $json + '</' + 'script>' + "`n"
    $out = $baseHtml -replace '</head>', ($embed + '</head>')
    $out = $out -replace '<title>.*?</title>', ("<title>" + $item.name + "</title>")
    $fileName = "$slug.html"
    $outPath = Join-Path $viewsDir $fileName
    Set-Content -Encoding UTF8 -Path $outPath -Value $out
    $url = "$BaseUrl/views/$fileName"
  }elseif($Mode -eq "assets"){
    $assetDir = Join-Path $viewsDir ("assets\" + $slug)
    New-Item -ItemType Directory -Force -Path $assetDir | Out-Null
    $pagesOut = @()
    $i = 1
    foreach($page in $item.pages){
      $pageOut = [ordered]@{}
      $imgOut = ""
      $audioOut = ""

      $img = $page.img
      if($img -and $img -match '^data:'){
        $fileBase = Join-Path $assetDir ("page-{0:D3}" -f $i)
        $filePath = WriteDataUrlToFile $img $fileBase
        if($filePath){ $imgOut = "assets/$slug/" + (Split-Path $filePath -Leaf) }
      }else{
        $imgOut = $img
      }

      $audio = $page.audio
      if($audio -and $audio -match '^data:'){
        $fileBase = Join-Path $assetDir ("audio-{0:D3}" -f $i)
        $filePath = WriteDataUrlToFile $audio $fileBase
        if($filePath){ $audioOut = "assets/$slug/" + (Split-Path $filePath -Leaf) }
      }else{
        $audioOut = $audio
      }

      $pageOut.img = $imgOut
      $pageOut.audio = $audioOut
      if($page.hotspots){ $pageOut.hotspots = $page.hotspots }
      $pagesOut += $pageOut
      $i++
    }

    $payload = @{ pages = $pagesOut }
    $json = ($payload | ConvertTo-Json -Depth 30) -replace '</script>', '<\\/script>'
    $embed = '<script type="application/json" id="embeddedData">' + $json + '</' + 'script>' + "`n"
    $out = $baseHtml -replace '</head>', ($embed + '</head>')
    $out = $out -replace '<title>.*?</title>', ("<title>" + $item.name + "</title>")
    $fileName = "$slug.html"
    $outPath = Join-Path $viewsDir $fileName
    Set-Content -Encoding UTF8 -Path $outPath -Value $out
    $url = "$BaseUrl/views/$fileName"
  }else{
    $payload = @{ pages = $item.pages } | ConvertTo-Json -Depth 30
    $blobUrl = NewShareBlob $payload
    $url = BuildViewerLink $BaseUrl $blobUrl
  }

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
    return '_Sin links todavia. Ejecuta `publish-library.ps1` para generarlos._'
  }
  $lines = @()
  foreach($item in $items){
    $name = [string]$item.Name
    if([string]::IsNullOrWhiteSpace($name)){ $name = "Revista" }
    $name = $name -replace '\s+',' '
    $lines += "- ${name}: $($item.Url)"
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
