param([switch]$Preparo, [switch]$Reiniciado)

# Baixador - servidor local invisivel.
# Nao abra este arquivo direto: use o atalho "Baixar Video" na area de trabalho.

$ErrorActionPreference = 'Stop'
try   { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 }
catch { try { [Net.ServicePointManager]::SecurityProtocol = 3072 } catch { } }

# ------------------------------------------------------------------
#  QUALIDADE - a unica coisa que vale a pena mexer neste arquivo.
#  Altura maxima do video, em pixels. Menor = arquivo menor,
#  download mais rapido e menos esforco para tocar.
#
#     1080   tela cheia HD           ~15 MB por minuto
#      720   certo para notebook      ~7 MB por minuto   <-- escolhido
#      480   notebook bem antigo      ~4 MB por minuto
#
#  Medido de verdade no YouTube: um video de 14 min em 1080p deu 207 MB.
# ------------------------------------------------------------------
$Qualidade = 720

# ------------------------------------------------------------------
#  ONDE SALVAR
#  Vazio ('') = usa as pastas do proprio Windows, que e o que ele ja
#  conhece e o que o Explorer mostra na lateral:
#        Videos\YouTube   e   Musicas\YouTube
#
#  Ou escreva um caminho fixo, sem barra no final. Exemplos:
#        $PastaVideos  = 'D:\Videos do Vovo'
#        $PastaMusicas = 'C:\Users\Gmsan\Music\YouTube'
#
#  Se a pasta escolhida nao existir e nao puder ser criada (HD externo
#  desligado, por exemplo), ele volta sozinho para a pasta do Windows
#  em vez de dar erro na cara dele.
# ------------------------------------------------------------------
$PastaVideos  = ''
$PastaMusicas = ''

# ------------------------------------------------------------------
#  ATUALIZACAO DO PROPRIO PROGRAMA
#  Toda vez que ele abre, o Baixador compara servidor.ps1 e pagina.html
#  com os do GitHub e se atualiza sozinho. E assim que voce conserta e
#  melhora as coisas de casa, sem precisar ir ate o PC dele.
#
#  ATENCAO: o GitHub manda em tudo. Os ajustes aqui de cima (qualidade,
#  pastas) tambem vem de la. Se voce mexer no arquivo do PC dele, na
#  proxima abertura volta ao que esta no repositorio. Edite o repositorio,
#  nao o arquivo local.
#
#  Deixe vazio ('') para desligar a atualizacao automatica.
#  Ou crie um arquivo dados\nao-atualizar.txt para congelar so aquele PC.
# ------------------------------------------------------------------
$RepoGitHub = 'https://raw.githubusercontent.com/Gmsantos23/baixador_yt/main'

$Base       = $PSScriptRoot
$Dados      = Join-Path $Base 'dados'
$Programas  = Join-Path $Dados 'programas'
$Backup     = Join-Path $Dados 'backup'
$YtDlp      = Join-Path $Programas 'yt-dlp.exe'
$FFDir      = Join-Path $Programas 'ffmpeg'
$FFExe      = Join-Path $FFDir 'ffmpeg.exe'
$DenoExe    = Join-Path $Programas 'deno.exe'
$Sistema64  = [Environment]::Is64BitOperatingSystem
$ArqPreparo = Join-Path $Dados 'preparo.txt'
$ArqSaida   = Join-Path $Dados 'saida.txt'
$ArqErros   = Join-Path $Dados 'erros.txt'
$ArqCaminho = Join-Path $Dados 'caminho.txt'
$Icone      = Join-Path $Dados 'baixador.ico'
$MarcaAtalho= Join-Path $Dados 'atalho.ok'
$Pagina     = Join-Path $Base 'pagina.html'
$Porta      = 47821

New-Item -ItemType Directory -Force -Path $Dados     | Out-Null
New-Item -ItemType Directory -Force -Path $Programas | Out-Null


# ============================ utilidades ============================

function Ler-Texto($caminho) {
    if (-not (Test-Path -LiteralPath $caminho)) { return '' }
    try {
        $fs = [IO.File]::Open($caminho, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
        $sr = New-Object IO.StreamReader($fs, [Text.Encoding]::UTF8)
        $t  = $sr.ReadToEnd()
        $sr.Close(); $fs.Close()
        return $t
    } catch { return '' }
}

function Passo($pct, $texto) {
    try { [IO.File]::WriteAllText($ArqPreparo, "$pct|$texto", [Text.Encoding]::UTF8) } catch { }
}

function Baixar-Web($url, $destino, $texto, $ini, $fim) {
    $req = [Net.HttpWebRequest]::Create($url)
    $req.UserAgent = 'Baixador/1.0'
    $req.Timeout   = 60000
    $resp  = $req.GetResponse()
    $total = $resp.ContentLength
    $ent   = $resp.GetResponseStream()
    $sai   = [IO.File]::Create($destino)
    $buf   = New-Object byte[] 131072
    $lido  = 0
    $ultimo = -1
    while ($true) {
        $n = $ent.Read($buf, 0, $buf.Length)
        if ($n -le 0) { break }
        $sai.Write($buf, 0, $n)
        $lido += $n
        if ($total -gt 0) {
            $p = [int]($ini + ($fim - $ini) * ($lido / $total))
            if ($p -ne $ultimo) { Passo $p $texto; $ultimo = $p }
        }
    }
    $sai.Close(); $ent.Close(); $resp.Close()
}


# ====================== modo preparo (1a vez) =======================

if ($Preparo) {
    try {
        Add-Type -AssemblyName System.IO.Compression.FileSystem

        if (-not (Test-Path -LiteralPath $YtDlp)) {
            Passo 1 'Baixando os componentes...'
            $urlYt = 'https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp.exe'
            if (-not $Sistema64) {
                $urlYt = 'https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_x86.exe'
            }
            Baixar-Web $urlYt $YtDlp 'Baixando os componentes...' 1 20
        }

        # ffmpeg e deno so tem versao 64 bits. Num Windows 32 bits o programa
        # continua funcionando, limitado aos formatos que ja vem prontos do YouTube.
        if ($Sistema64 -and -not (Test-Path -LiteralPath $FFExe)) {
            Passo 21 'Baixando o conversor de video...'
            $zip = Join-Path $Dados 'ff.zip'
            Baixar-Web 'https://github.com/yt-dlp/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-win64-gpl.zip' `
                       $zip 'Baixando o conversor de video...' 21 58

            Passo 60 'Instalando...'
            New-Item -ItemType Directory -Force -Path $FFDir | Out-Null
            $pacote = [IO.Compression.ZipFile]::OpenRead($zip)
            foreach ($item in $pacote.Entries) {
                if ($item.Name -eq 'ffmpeg.exe' -or $item.Name -eq 'ffprobe.exe') {
                    [IO.Compression.ZipFileExtensions]::ExtractToFile($item, (Join-Path $FFDir $item.Name), $true)
                }
            }
            $pacote.Dispose()
            Remove-Item -LiteralPath $zip -Force
            if (-not (Test-Path -LiteralPath $FFExe)) { throw 'ffmpeg nao foi encontrado no pacote' }
        }

        # O YouTube exige rodar JavaScript para liberar todos os formatos.
        # Sem isso, o yt-dlp avisa que a extracao esta descontinuada.
        # Se falhar, seguimos assim mesmo: e melhoria, nao requisito.
        if ($Sistema64 -and -not (Test-Path -LiteralPath $DenoExe)) {
            try {
                Passo 64 'Baixando o motor do YouTube...'
                $zip2 = Join-Path $Dados 'deno.zip'
                Baixar-Web 'https://github.com/denoland/deno/releases/latest/download/deno-x86_64-pc-windows-msvc.zip' `
                           $zip2 'Baixando o motor do YouTube...' 64 90

                Passo 92 'Instalando...'
                $pacote2 = [IO.Compression.ZipFile]::OpenRead($zip2)
                foreach ($item in $pacote2.Entries) {
                    if ($item.Name -eq 'deno.exe') {
                        [IO.Compression.ZipFileExtensions]::ExtractToFile($item, $DenoExe, $true)
                    }
                }
                $pacote2.Dispose()
                Remove-Item -LiteralPath $zip2 -Force
            } catch { }
        }

        Passo 95 'Atualizando...'
        try {
            $idade = ((Get-Date) - (Get-Item -LiteralPath $YtDlp).LastWriteTime).TotalDays
            if ($idade -gt 2) {
                & $YtDlp -U 2>&1 | Out-Null
                (Get-Item -LiteralPath $YtDlp).LastWriteTime = Get-Date
            }
        } catch { }

        Passo 100 'Pronto'
    } catch {
        Passo (-1) ('FALHA ' + $_.Exception.Message)
    }
    exit
}


# ===================== atalho na area de trabalho ====================

function Criar-Icone($destino) {
    Add-Type -AssemblyName System.Drawing
    $t   = 256
    $bmp = New-Object System.Drawing.Bitmap($t, $t)
    $g   = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.Clear([System.Drawing.Color]::Transparent)

    $r    = 56
    $arco = New-Object System.Drawing.Drawing2D.GraphicsPath
    $arco.AddArc(0, 0, $r, $r, 180, 90)
    $arco.AddArc($t - $r, 0, $r, $r, 270, 90)
    $arco.AddArc($t - $r, $t - $r, $r, $r, 0, 90)
    $arco.AddArc(0, $t - $r, $r, $r, 90, 90)
    $arco.CloseFigure()

    $tinta = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 200, 40, 30))
    $g.FillPath($tinta, $arco)

    # New-Object em vez de ::new() para nao exigir PowerShell 5
    $pontos = [System.Drawing.PointF[]]@(
        (New-Object System.Drawing.PointF(98, 76)),
        (New-Object System.Drawing.PointF(98, 180)),
        (New-Object System.Drawing.PointF(186, 128))
    )
    $g.FillPolygon([System.Drawing.Brushes]::White, $pontos)
    $g.Dispose()

    $ms = New-Object System.IO.MemoryStream
    $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
    $png = $ms.ToArray()

    $fs = [IO.File]::Create($destino)
    $bw = New-Object System.IO.BinaryWriter($fs)
    $bw.Write([UInt16]0); $bw.Write([UInt16]1); $bw.Write([UInt16]1)
    $bw.Write([byte]0); $bw.Write([byte]0); $bw.Write([byte]0); $bw.Write([byte]0)
    $bw.Write([UInt16]1); $bw.Write([UInt16]32)
    $bw.Write([UInt32]$png.Length); $bw.Write([UInt32]22)
    $bw.Write($png)
    $bw.Close(); $fs.Close()
}

function Criar-Atalho {
    $mesa = [Environment]::GetFolderPath('Desktop')
    if (-not $mesa) { return }
    $ws   = New-Object -ComObject WScript.Shell
    $lnk  = $ws.CreateShortcut((Join-Path $mesa 'Baixar Video.lnk'))
    $lnk.TargetPath       = (Join-Path $env:WINDIR 'System32\wscript.exe')
    $lnk.Arguments        = '"' + (Join-Path $Base 'Baixador.vbs') + '"'
    $lnk.WorkingDirectory = $Base
    $lnk.Description      = 'Baixar videos do YouTube'
    $lnk.WindowStyle      = 7
    if (Test-Path -LiteralPath $Icone) { $lnk.IconLocation = $Icone + ',0' }
    $lnk.Save()
}


# ==================== atualizacao do programa =======================

function Ja-Rodando {
    # Pergunta a porta em vez de tentar ocupa-la: assim, quando ele clica
    # duas vezes no atalho, a segunda janela abre na hora, sem passar pela
    # checagem de atualizacao.
    try {
        $c = New-Object System.Net.Sockets.TcpClient
        $esperando = $c.BeginConnect('127.0.0.1', $Porta, $null, $null)
        $respondeu = $esperando.AsyncWaitHandle.WaitOne(400)
        $ligado = ($respondeu -and $c.Connected)
        $c.Close()
        return $ligado
    } catch { return $false }
}

function Impressao([byte[]]$dados) {
    $md5 = [Security.Cryptography.MD5]::Create()
    return [BitConverter]::ToString($md5.ComputeHash($dados))
}

function Atualizar-Programa {
    # Devolve $true quando o proprio servidor.ps1 mudou - e so nesse caso
    # que vale a pena reiniciar, porque o PowerShell ja leu o arquivo todo
    # na memoria. O pagina.html e lido a cada visita, entao pega na hora.
    #
    # De proposito o Baixador.vbs NAO e atualizado: ele e a porta de
    # entrada. Se um arquivo dele chegasse quebrado do repositorio, o
    # programa ficaria morto no PC dele sem jeito de consertar de longe.
    if (-not $RepoGitHub) { return $false }
    if (Test-Path -LiteralPath (Join-Path $Dados 'nao-atualizar.txt')) { return $false }

    $trocouServidor = $false
    try { New-Item -ItemType Directory -Force -Path $Backup | Out-Null } catch { }

    foreach ($nome in @('servidor.ps1', 'pagina.html')) {
        try {
            $req = [Net.HttpWebRequest]::Create("$RepoGitHub/$nome")
            $req.UserAgent        = 'Baixador/1.0'
            $req.Timeout          = 5000
            $req.ReadWriteTimeout = 5000
            $resp = $req.GetResponse()
            $ms   = New-Object System.IO.MemoryStream
            $resp.GetResponseStream().CopyTo($ms)
            $resp.Close()
            $novo = $ms.ToArray()
        } catch {
            # sem internet, GitHub fora do ar, repositorio movido: desiste
            # de tudo e abre o programa com o que ja esta no disco.
            return $trocouServidor
        }

        try {
            if ($novo.Length -lt 300) { continue }   # resposta curta demais: suspeita

            $local = Join-Path $Base $nome
            $atual = $null
            if (Test-Path -LiteralPath $local) { $atual = [IO.File]::ReadAllBytes($local) }
            if ($atual -and (Impressao $atual) -eq (Impressao $novo)) { continue }

            # Antes de trocar o motor, confere se o PowerShell novo compila.
            # Um erro de digitacao no repositorio deixaria o PC dele morto,
            # e ele nao teria como desfazer.
            if ($nome -eq 'servidor.ps1') {
                $falhas = $null
                [void][System.Management.Automation.Language.Parser]::ParseInput(
                    [Text.Encoding]::UTF8.GetString($novo), [ref]$null, [ref]$falhas)
                if ($falhas -and $falhas.Count -gt 0) { continue }
            }

            if ($atual) { [IO.File]::WriteAllBytes((Join-Path $Backup $nome), $atual) }
            [IO.File]::WriteAllBytes($local, $novo)
            if ($nome -eq 'servidor.ps1') { $trocouServidor = $true }
        } catch { }
    }
    return $trocouServidor
}


# ============================= servidor =============================

if (Ja-Rodando) {
    # ja tem um no ar: so traz a janela de volta
    Start-Process ("http://127.0.0.1:$Porta/")
    exit
}

if (-not $Reiniciado) {
    if (Atualizar-Programa) {
        # o motor mudou: sobe de novo ja com o codigo novo. O -Reiniciado
        # impede que isso vire um ciclo sem fim.
        $cmd = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $PSCommandPath + '" -Reiniciado'
        Start-Process -FilePath 'powershell.exe' -ArgumentList $cmd -WindowStyle Hidden
        exit
    }
}

$ouvinte = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Loopback, $Porta)
try {
    $ouvinte.Start()
} catch {
    Start-Process ("http://127.0.0.1:$Porta/")
    exit
}

# O marcador guarda a pasta onde o programa estava da ultima vez, e nao um
# simples "ja fiz". Assim o atalho se refaz sozinho quando a pasta muda de
# lugar ou vai para outro computador - que sao justamente as duas horas em
# que o atalho antigo teria quebrado.
$marcado = ''
if (Test-Path -LiteralPath $MarcaAtalho) { $marcado = (Ler-Texto $MarcaAtalho).Trim() }
if ($marcado -ne $Base) {
    try { Criar-Icone $Icone } catch { }
    try { Criar-Atalho }      catch { }
    try { [IO.File]::WriteAllText($MarcaAtalho, $Base, [Text.Encoding]::UTF8) } catch { }
}

$script:Proc        = $null
$script:ProcPreparo = $null
$script:Fase        = 'parado'
$script:Pct         = 0
$script:Titulo      = ''
$script:Texto       = ''
$script:Erro        = ''
$script:Arquivo     = ''
$script:Pasta       = ''
$script:PastaNome   = ''
$script:PastaCodigo = 'video'

$precisaPreparo = $false
if (-not (Test-Path -LiteralPath $YtDlp)) { $precisaPreparo = $true }
if ($Sistema64) {
    if (-not (Test-Path -LiteralPath $FFExe))   { $precisaPreparo = $true }
    if (-not (Test-Path -LiteralPath $DenoExe)) { $precisaPreparo = $true }
}
if (-not $precisaPreparo) {
    try {
        if (((Get-Date) - (Get-Item -LiteralPath $YtDlp).LastWriteTime).TotalDays -gt 2) { $precisaPreparo = $true }
    } catch { }
}
if ($precisaPreparo) {
    Passo 0 'Preparando...'
    $cmd = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $PSCommandPath + '" -Preparo'
    $script:ProcPreparo = Start-Process -FilePath 'powershell.exe' -ArgumentList $cmd -WindowStyle Hidden -PassThru
    $script:Fase = 'preparando'
}

Start-Process ("http://127.0.0.1:$Porta/")


function Citar($s) {
    if ($s -match '[\s"]') { return '"' + ($s -replace '"', '\"') + '"' }
    return $s
}

function Mensagem-Erro {
    $e = (Ler-Texto $ArqErros) + "`n" + (Ler-Texto $ArqSaida)
    if ($e -match "confirm you're not a bot|Sign in to confirm")      { return 'O YouTube pediu uma confirmacao de seguranca. Espere alguns minutos e tente de novo.' }
    if ($e -match 'age-restricted|inappropriate for some users')      { return 'Esse video tem restricao de idade e nao pode ser baixado.' }
    if ($e -match 'Private video|members-only|join this channel')     { return 'Esse video e privado ou so para membros do canal.' }
    if ($e -match 'Video unavailable|has been removed|not available') { return 'Esse video nao esta mais disponivel no YouTube.' }
    if ($e -match 'Unsupported URL|is not a valid URL')               { return 'Esse endereco nao parece ser de um video.' }
    if ($e -match 'Failed to resolve|getaddrinfo|Temporary failure|timed out|Connection|Network') { return 'Parece que a internet caiu. Verifique a conexao e tente de novo.' }
    if ($e -match 'No space left|space')                              { return 'O computador esta sem espaco livre.' }
    return 'Nao consegui baixar esse video. Tente outro link.'
}

function Atualizar-Estado {

    if ($script:ProcPreparo -ne $null) {
        if (-not $script:ProcPreparo.HasExited) {
            $t = Ler-Texto $ArqPreparo
            $script:Fase  = 'preparando'
            $script:Pct   = 0
            $script:Texto = 'Preparando...'
            if ($t -match '^(-?\d+)\|(.*)$') {
                $script:Pct   = [int]$matches[1]
                $script:Texto = $matches[2]
            }
            if ($script:Pct -lt 0) { $script:Pct = 0 }
            return
        }
        $t = Ler-Texto $ArqPreparo
        $script:ProcPreparo = $null
        $script:Texto = ''
        $script:Pct   = 0
        if ($t.StartsWith('-1|')) {
            $script:Fase = 'erro'
            $script:Erro = 'Nao consegui baixar os componentes. Verifique a internet e abra o Baixador de novo.'
        } else {
            $script:Fase = 'parado'
        }
        return
    }

    if ($script:Proc -eq $null) { return }

    $saida = Ler-Texto $ArqSaida

    $prog = [regex]::Matches($saida, 'PROG\|\s*([\d.]+)%\|(.*)')
    if ($prog.Count -gt 0) {
        $ultimo = $prog[$prog.Count - 1]
        $bruto  = [double]$ultimo.Groups[1].Value
        $nome   = $ultimo.Groups[2].Value.Trim()
        if ($nome -and $nome -ne 'NA') { $script:Titulo = $nome }
    } else {
        $bruto = 0.0
    }

    $faixas = 1
    $m = [regex]::Match($saida, 'Downloading\s+\d+\s+format\(s\):\s*(\S+)')
    if ($m.Success) { $faixas = ($m.Groups[1].Value -split '\+').Count }

    $passo = ([regex]::Matches($saida, '\[download\]\s+Destination:')).Count
    if ($passo -lt 1)       { $passo  = 1 }
    if ($passo -gt $faixas) { $faixas = $passo }

    $calc = [int]((($passo - 1) + ($bruto / 100.0)) / $faixas * 95.0)
    if ($calc -gt $script:Pct) { $script:Pct = $calc }

    if ($script:Fase -ne 'finalizando') { $script:Fase = 'baixando' }
    if ($saida -match '\[Merger\]|\[ExtractAudio\]|\[EmbedThumbnail\]|\[Metadata\]|\[VideoRemuxer\]|Merging formats') {
        $script:Fase = 'finalizando'
        if ($script:Pct -lt 96) { $script:Pct = 96 }
    }

    if ($script:Proc.HasExited) {
        # ExitCode so fica confiavel depois do WaitForExit (o processo ja terminou,
        # entao isso retorna na hora). Ainda assim, o sinal que vale e o arquivo final.
        try { $script:Proc.WaitForExit() } catch { }
        $codigo = 1
        try { if ($script:Proc.ExitCode -ne $null) { $codigo = $script:Proc.ExitCode } } catch { }
        $script:Proc = $null

        $c = (Ler-Texto $ArqCaminho).Trim()
        if ($c) {
            $achado = (($c -split "`n")[0]).Trim()
            if ($achado -and (Test-Path -LiteralPath $achado)) { $script:Arquivo = $achado }
        }

        if ($script:Arquivo -or $codigo -eq 0) {
            $script:Pct  = 100
            $script:Fase = 'pronto'
            if ($script:Arquivo) {
                try { $script:Titulo = [IO.Path]::GetFileNameWithoutExtension($script:Arquivo) } catch { }
            }
        } else {
            $script:Fase = 'erro'
            $script:Erro = Mensagem-Erro
        }
    }
}

function Resolver-Pasta($escolhida, $idPadrao, $nomePadrao) {
    # Tenta a pasta escrita no topo do arquivo. Se ela nao puder ser criada
    # (HD externo desligado, pendrive fora, caminho digitado errado), volta
    # calado para a pasta do Windows: melhor salvar no lugar errado do que
    # mostrar um erro que ele nao vai saber resolver sozinho.
    if ($escolhida) {
        try {
            New-Item -ItemType Directory -Force -Path $escolhida | Out-Null
            return $escolhida
        } catch { }
    }
    $raiz = [Environment]::GetFolderPath($idPadrao)
    if (-not $raiz) { $raiz = Join-Path $env:USERPROFILE $nomePadrao }
    $p = Join-Path $raiz 'YouTube'
    New-Item -ItemType Directory -Force -Path $p | Out-Null
    return $p
}

function Iniciar-Download($url, $tipo) {
    foreach ($f in @($ArqSaida, $ArqErros, $ArqCaminho)) {
        try { Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue } catch { }
    }

    $temFfmpeg = Test-Path -LiteralPath $FFExe

    if ($tipo -eq 'audio') {
        $pasta = Resolver-Pasta $PastaMusicas 'MyMusic' 'Music'
        $script:PastaCodigo = 'audio'
    } else {
        $pasta = Resolver-Pasta $PastaVideos 'MyVideos' 'Videos'
        $script:PastaCodigo = 'video'
    }
    $script:Pasta = $pasta

    # A pagina escreve o nome bonito ("Videos > YouTube") quando e a pasta
    # padrao. So mandamos o caminho quando ele foi trocado la em cima -
    # assim os acentos ficam todos no HTML, que e UTF-8 de verdade.
    $script:PastaNome = ''
    if ($tipo -eq 'audio') {
        if ($PastaMusicas -and $pasta -eq $PastaMusicas) { $script:PastaNome = $pasta }
    } else {
        if ($PastaVideos -and $pasta -eq $PastaVideos) { $script:PastaNome = $pasta }
    }

    $lista = New-Object System.Collections.Generic.List[string]
    $lista.Add('--ignore-config')
    $lista.Add('--no-colors')
    $lista.Add('--no-warnings')
    $lista.Add('--newline')
    $lista.Add('--progress')
    $lista.Add('--progress-delta'); $lista.Add('0.4')
    $lista.Add('--no-playlist')
    $lista.Add('--no-mtime')
    $lista.Add('--retries');            $lista.Add('10')
    $lista.Add('--fragment-retries');   $lista.Add('10')
    $lista.Add('--concurrent-fragments'); $lista.Add('4')
    $lista.Add('--trim-filenames');     $lista.Add('120')
    if ($temFfmpeg) { $lista.Add('--ffmpeg-location'); $lista.Add($FFDir) }
    $lista.Add('--progress-template');  $lista.Add('download:PROG|%(progress._percent_str)s|%(info.title)s')
    $lista.Add('--print-to-file');      $lista.Add('after_move:%(filepath)s'); $lista.Add($ArqCaminho)
    $lista.Add('--no-simulate')
    $lista.Add('--no-quiet')

    $q = $Qualidade

    if ($tipo -eq 'audio' -and $temFfmpeg) {
        $lista.Add('-f'); $lista.Add('ba/b')
        $lista.Add('-x')
        $lista.Add('--audio-format');  $lista.Add('mp3')
        $lista.Add('--audio-quality'); $lista.Add('0')
        $lista.Add('--embed-thumbnail')
        $lista.Add('--embed-metadata')

    } elseif ($tipo -eq 'audio') {
        # sem ffmpeg nao da para converter: guarda o som como m4a,
        # que o Windows toca do mesmo jeito
        $lista.Add('-f'); $lista.Add('ba[ext=m4a]/ba/b')

    } elseif ($temFfmpeg) {
        # avc1 + m4a primeiro: e o unico par que toca em qualquer lugar
        # (Media Player antigo, pendrive na TV, celular). AV1/VP9 so como ultimo recurso,
        # porque nenhum notebook antigo tem decodificacao em hardware para eles.
        $lista.Add('-f')
        $lista.Add("bv*[vcodec^=avc1][height<=$q]+ba[ext=m4a]/b[vcodec^=avc1][height<=$q]/bv*[ext=mp4][height<=$q]+ba/b[ext=mp4][height<=$q]/bv*[height<=$q]+ba/b[height<=$q]/b")
        $lista.Add('--merge-output-format'); $lista.Add('mp4')

    } else {
        # sem ffmpeg: so formatos que ja vem prontos, sem precisar juntar video e som
        $lista.Add('-f'); $lista.Add("b[ext=mp4][height<=$q]/b[height<=$q]/b")
    }

    $lista.Add('-o'); $lista.Add((Join-Path $pasta '%(title)s.%(ext)s'))
    $lista.Add('--'); $lista.Add($url)

    $linha = ($lista | ForEach-Object { Citar $_ }) -join ' '

    $script:Pct     = 0
    $script:Titulo  = ''
    $script:Erro    = ''
    $script:Arquivo = ''
    $script:Fase    = 'baixando'

    $env:PYTHONIOENCODING = 'utf-8'
    # o yt-dlp acha o deno sozinho pelo PATH; assim nao dependemos do nome da opcao
    if ($env:PATH -notlike ($Programas + ';*')) { $env:PATH = $Programas + ';' + $env:PATH }

    $script:Proc = Start-Process -FilePath $YtDlp -ArgumentList $linha -NoNewWindow -PassThru `
                                 -RedirectStandardOutput $ArqSaida -RedirectStandardError $ArqErros
}

function Parar-Download {
    if ($script:Proc -ne $null) {
        try { & taskkill.exe /PID $script:Proc.Id /T /F 2>&1 | Out-Null } catch { }
        $script:Proc = $null
    }
    $script:Fase = 'parado'
    $script:Pct  = 0
}

function Responder($fluxo, $status, $tipo, [byte[]]$corpo) {
    $cab = "HTTP/1.1 $status`r`n" +
           "Content-Type: $tipo`r`n" +
           "Content-Length: $($corpo.Length)`r`n" +
           "Cache-Control: no-store`r`n" +
           "Connection: close`r`n`r`n"
    $b = [Text.Encoding]::ASCII.GetBytes($cab)
    $fluxo.Write($b, 0, $b.Length)
    if ($corpo.Length -gt 0) { $fluxo.Write($corpo, 0, $corpo.Length) }
    $fluxo.Flush()
}

function Responder-Json($fluxo, $objeto) {
    $txt = $objeto | ConvertTo-Json -Compress
    Responder $fluxo '200 OK' 'application/json; charset=utf-8' ([Text.Encoding]::UTF8.GetBytes($txt))
}


# ---------------------------- laco principal ----------------------------

$ocioso = Get-Date

while ($true) {

    if (-not $ouvinte.Pending()) {
        Start-Sleep -Milliseconds 100
        if ($script:Proc -eq $null -and $script:ProcPreparo -eq $null -and
            ((Get-Date) - $ocioso).TotalMinutes -gt 10) { break }
        continue
    }

    $ocioso  = Get-Date
    $cliente = $ouvinte.AcceptTcpClient()

    try {
        $cliente.ReceiveTimeout = 8000
        $cliente.SendTimeout    = 8000
        $fluxo = $cliente.GetStream()

        # --- ler a requisicao ---
        $ms  = New-Object System.IO.MemoryStream
        $buf = New-Object byte[] 4096
        $fim = -1
        while ($fim -lt 0) {
            $n = $fluxo.Read($buf, 0, $buf.Length)
            if ($n -le 0) { break }
            $ms.Write($buf, 0, $n)
            $bytes = $ms.ToArray()
            for ($i = 0; $i -lt $bytes.Length - 3; $i++) {
                if ($bytes[$i] -eq 13 -and $bytes[$i+1] -eq 10 -and $bytes[$i+2] -eq 13 -and $bytes[$i+3] -eq 10) {
                    $fim = $i; break
                }
            }
        }
        if ($fim -lt 0) { $cliente.Close(); continue }

        $bytes    = $ms.ToArray()
        $cabecalho = [Text.Encoding]::ASCII.GetString($bytes, 0, $fim)
        $linhas   = $cabecalho -split "`r`n"
        $partes   = $linhas[0] -split ' '
        $metodo   = $partes[0]
        $rota     = $partes[1]
        if ($rota.Contains('?')) { $rota = $rota.Substring(0, $rota.IndexOf('?')) }

        $tamanho = 0
        foreach ($l in $linhas) {
            if ($l -match '^(?i)Content-Length:\s*(\d+)') { $tamanho = [int]$matches[1] }
        }

        $corpo = ''
        if ($tamanho -gt 0) {
            $cb   = New-Object byte[] $tamanho
            $tem  = $bytes.Length - ($fim + 4)
            if ($tem -gt $tamanho) { $tem = $tamanho }
            if ($tem -gt 0) { [Array]::Copy($bytes, $fim + 4, $cb, 0, $tem) }
            while ($tem -lt $tamanho) {
                $n = $fluxo.Read($cb, $tem, $tamanho - $tem)
                if ($n -le 0) { break }
                $tem += $n
            }
            $corpo = [Text.Encoding]::UTF8.GetString($cb)
        }

        # --- rotas ---
        switch ($rota) {

            '/' {
                if (Test-Path -LiteralPath $Pagina) {
                    Responder $fluxo '200 OK' 'text/html; charset=utf-8' ([IO.File]::ReadAllBytes($Pagina))
                } else {
                    Responder $fluxo '404 Not Found' 'text/plain; charset=utf-8' ([Text.Encoding]::UTF8.GetBytes('pagina.html nao encontrada'))
                }
            }

            '/favicon.ico' {
                if (Test-Path -LiteralPath $Icone) {
                    Responder $fluxo '200 OK' 'image/x-icon' ([IO.File]::ReadAllBytes($Icone))
                } else {
                    Responder $fluxo '204 No Content' 'text/plain' (New-Object byte[] 0)
                }
            }

            '/estado' {
                Atualizar-Estado
                Responder-Json $fluxo @{
                    fase   = $script:Fase
                    pct    = $script:Pct
                    titulo = $script:Titulo
                    texto  = $script:Texto
                    erro   = $script:Erro
                    pasta  = $script:PastaNome
                    tipo   = $script:PastaCodigo
                }
            }

            '/iniciar' {
                $ok = $false
                try {
                    $pedido = $corpo | ConvertFrom-Json
                    $url    = ([string]$pedido.url).Trim()
                    $tipo   = [string]$pedido.tipo
                    if ($url -match '^https?://' -and $script:Proc -eq $null -and $script:ProcPreparo -eq $null) {
                        Iniciar-Download $url $tipo
                        $ok = $true
                    }
                } catch {
                    $script:Fase = 'erro'
                    $script:Erro = 'Nao consegui comecar. Tente de novo.'
                }
                Responder-Json $fluxo @{ ok = $ok }
            }

            '/cancelar' {
                Parar-Download
                Responder-Json $fluxo @{ ok = $true }
            }

            '/limpar' {
                if ($script:Proc -eq $null -and $script:ProcPreparo -eq $null) {
                    $script:Fase = 'parado'
                    $script:Pct  = 0
                    $script:Erro = ''
                }
                Responder-Json $fluxo @{ ok = $true }
            }

            '/abrir' {
                try {
                    if ($script:Arquivo -and (Test-Path -LiteralPath $script:Arquivo)) {
                        Start-Process 'explorer.exe' -ArgumentList ('/select,"' + $script:Arquivo + '"')
                    } elseif ($script:Pasta -and (Test-Path -LiteralPath $script:Pasta)) {
                        Start-Process 'explorer.exe' -ArgumentList ('"' + $script:Pasta + '"')
                    }
                } catch { }
                Responder-Json $fluxo @{ ok = $true }
            }

            default {
                Responder $fluxo '404 Not Found' 'text/plain; charset=utf-8' ([Text.Encoding]::UTF8.GetBytes('nao encontrado'))
            }
        }

    } catch {
    } finally {
        try { $cliente.Close() } catch { }
    }
}

try { $ouvinte.Stop() } catch { }
