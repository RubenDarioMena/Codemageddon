param([int]$Port=8765,[switch]$NoBrowser)
$ErrorActionPreference='Stop'
$Root=[IO.Path]::GetFullPath($PSScriptRoot)
$RootPrefix=$Root.TrimEnd('\','/')+[IO.Path]::DirectorySeparatorChar
$Url="http://localhost:$Port/"
$Mime=@{'.html'='text/html';'.htm'='text/html';'.css'='text/css';'.js'='text/javascript';'.mjs'='text/javascript';'.json'='application/json';'.svg'='image/svg+xml';'.png'='image/png';'.jpg'='image/jpeg';'.jpeg'='image/jpeg';'.webp'='image/webp';'.gif'='image/gif';'.ico'='image/x-icon';'.woff2'='font/woff2';'.woff'='font/woff';'.wasm'='application/wasm'}
$Live=@'
<script data-codemageddon-live>
(()=>{let v=null;async function check(){try{const r=await fetch('/__live_version',{cache:'no-store'});if(!r.ok)return;const n=await r.text();if(v!==null&&v!==n)location.reload();v=n}catch(e){}}check();setInterval(check,1200)})();
</script>
'@
function Get-Version {
  $ticks=0L
  $count=0
  Get-ChildItem -LiteralPath $Root -File -Recurse -ErrorAction SilentlyContinue |
    Where-Object { $_.Extension -in @('.html','.htm','.css','.js','.json','.svg','.png','.jpg','.jpeg','.webp','.wasm') -and $_.FullName -notmatch '[\\/](node_modules|\.git)[\\/]' } |
    ForEach-Object { $count++; if($_.LastWriteTimeUtc.Ticks -gt $ticks){$ticks=$_.LastWriteTimeUtc.Ticks} }
  return ($ticks.ToString()+':'+$count.ToString())
}
$Listener=[Net.HttpListener]::new()
$Listener.Prefixes.Add($Url)
try {
  $Listener.Start()
  Write-Host "Codemageddon live server: $Url" -ForegroundColor Green
  Write-Host "Serving: $Root"
  Write-Host 'Press Ctrl+C to stop.'
  if(-not $NoBrowser){Start-Process $Url}
  while($Listener.IsListening){
    $Context=$Listener.GetContext()
    $Response=$Context.Response
    try{
      if($Context.Request.HttpMethod -notin @('GET','HEAD')){$Response.StatusCode=405;continue}
      $Requested=[Uri]::UnescapeDataString($Context.Request.Url.AbsolutePath)
      if($Requested -eq '/__live_version'){
        $Bytes=[Text.Encoding]::UTF8.GetBytes((Get-Version))
        $Response.ContentType='text/plain; charset=utf-8'
      }else{
        $Relative=$Requested.TrimStart('/').Replace('/',[IO.Path]::DirectorySeparatorChar)
        if(-not $Relative){$Relative='index.html'}
        $Path=[IO.Path]::GetFullPath((Join-Path $Root $Relative))
        if(-not $Path.StartsWith($RootPrefix,[StringComparison]::OrdinalIgnoreCase)){$Response.StatusCode=403;continue}
        if(-not [IO.File]::Exists($Path)){$Response.StatusCode=404;continue}
        $Ext=[IO.Path]::GetExtension($Path).ToLowerInvariant()
        $Response.ContentType=if($Mime.ContainsKey($Ext)){$Mime[$Ext]}else{'application/octet-stream'}
        if($Ext -in @('.html','.htm')){
          $Html=[IO.File]::ReadAllText($Path,[Text.Encoding]::UTF8)
          $Bytes=[Text.Encoding]::UTF8.GetBytes($Html+[Environment]::NewLine+$Live)
        }else{
          $Bytes=[IO.File]::ReadAllBytes($Path)
        }
      }
      $Response.Headers['Cache-Control']='no-store'
      $Response.ContentLength64=$Bytes.Length
      if($Context.Request.HttpMethod -ne 'HEAD'){$Response.OutputStream.Write($Bytes,0,$Bytes.Length)}
    }catch{Write-Warning $_.Exception.Message}
    finally{$Response.Close()}
  }
}finally{
  if($Listener.IsListening){$Listener.Stop()}
  $Listener.Close()
}
