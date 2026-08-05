# PUENTE GLORY -> APP DE CAJA
# Lee la contadora Glory GFS-220 por red y publica el ultimo conteo en la app.
# Correr en una PC de la red que quede prendida mientras cuentan.

$IP_GLORY   = "192.168.2.170"
$PUERTO     = 9200
$APP_URL    = "https://script.google.com/macros/s/AKfycbxL_UQ0p1e0QDZ1PGgz5G71aMgfl9iLcf32lR_KU7bzOvNh4KyLVGnDLF30HFzkr7j5wg/exec"
$SECRETO    = "GLORY-PUENTE-9200"
$LOG        = "C:\Users\luqaa\caja-tesoreria\glory\puente.log"

# Tabla codigo de denominacion -> valor en pesos (serie 1-2-5, calibrada 2026-08-05)
$DENOM = @{
  "04" = 10;   "05" = 20;    "06" = 50;    "07" = 100;
  "08" = 200;  "09" = 500;   "10" = 1000;  "11" = 2000;
  "12" = 5000; "13" = 10000; "14" = 20000
}

$script:ultimaSesion = ""

function Log($m) {
  $l = (Get-Date -Format "HH:mm:ss") + "  " + $m
  Write-Output $l
  Add-Content -Path $LOG -Value $l -Encoding UTF8
}

# Convierte el texto de una trama en total de pesos y cantidad de billetes.
# Renglones "06,<cod>,<cant>" separados por CR (0x0D).
function ParsearConteo($texto) {
  $totalPesos = 0
  $totalBilletes = 0
  foreach ($r in ($texto -split "`r")) {
    $p = $r -split ","
    if ($p.Count -ge 3 -and $p[0].Trim() -eq "06") {
      $cod = $p[1].Trim().PadLeft(2, "0")
      $cant = 0
      [void][int]::TryParse($p[2].Trim(), [ref]$cant)
      if ($DENOM.ContainsKey($cod) -and $cant -gt 0) {
        $totalPesos += $DENOM[$cod] * $cant
        $totalBilletes += $cant
      }
    }
  }
  return @{ pesos = $totalPesos; billetes = $totalBilletes }
}

function Publicar($pesos, $billetes, $sesion) {
  $cuerpo = @{ accion = "conteo"; secreto = $SECRETO; valor = $pesos; billetes = $billetes; sesion = $sesion } | ConvertTo-Json -Compress
  try {
    Invoke-RestMethod -Uri $APP_URL -Method Post -Body $cuerpo -ContentType "text/plain" -TimeoutSec 20 | Out-Null
    Log ("  -> PUBLICADO en la app: `$$pesos ($billetes billetes)")
  } catch {
    Log ("  -> error publicando: " + $_.Exception.Message)
  }
}

# Procesa una trama; si es un resultado final SV1 con sesion nueva, publica.
function ProcesarTrama($bytes) {
  $texto = -join ($bytes | ForEach-Object { if ($_ -ge 32 -and $_ -le 126) { [char]$_ } elseif ($_ -eq 13) { "`r" } else { "" } })
  $m = [regex]::Match($texto, "SV1\d+,(\d+),")
  if (-not $m.Success) { return }
  $sesion = $m.Groups[1].Value
  $r = ParsearConteo $texto
  if ($r.pesos -le 0) { return }
  if ($sesion -eq $script:ultimaSesion) { return }
  $script:ultimaSesion = $sesion
  Log ("CONTEO nuevo (sesion $sesion): `$$($r.pesos) en $($r.billetes) billetes")
  Publicar $r.pesos $r.billetes $sesion
}

function CorrerPuente {
  $ENQ = [byte[]](0x05)
  $ACK = [byte[]](0x06)
  Log "=== PUENTE GLORY iniciado. Contadora en $IP_GLORY`:$PUERTO ==="
  while ($true) {
    try {
      $cli = New-Object System.Net.Sockets.TcpClient
      $t = $cli.ConnectAsync($IP_GLORY, $PUERTO)
      if (-not ($t.Wait(4000) -and $cli.Connected)) { Log "no conecta, reintento en 5s"; Start-Sleep 5; continue }
      Log "conectado a la contadora."
      $st = $cli.GetStream()
      $buf = New-Object byte[] 16384
      $ultimoEnq = (Get-Date).AddSeconds(-10)
      while ($cli.Connected) {
        while ($st.DataAvailable) {
          $n = $st.Read($buf, 0, $buf.Length)
          if ($n -le 0) { break }
          $trama = New-Object System.Collections.Generic.List[byte]
          for ($i = 0; $i -lt $n; $i++) {
            $b = $buf[$i]
            $trama.Add($b)
            if ($b -eq 0x03) { ProcesarTrama $trama.ToArray(); $trama.Clear() }
          }
          try { $st.Write($ACK, 0, $ACK.Length); $st.Flush() } catch {}
        }
        if (((Get-Date) - $ultimoEnq).TotalSeconds -ge 3) {
          try { $st.Write($ENQ, 0, $ENQ.Length); $st.Flush() } catch { break }
          $ultimoEnq = Get-Date
        }
        Start-Sleep -Milliseconds 120
      }
    } catch {
      Log ("error de conexion: " + $_.Exception.Message)
    }
    try { $cli.Close() } catch {}
    Log "conexion caida, reconectando en 4s..."
    Start-Sleep 4
  }
}

CorrerPuente
