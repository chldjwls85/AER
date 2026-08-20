$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Drawing

$projectRoot = Split-Path -Parent $PSScriptRoot
$outputDirectory = Join-Path $projectRoot 'output\aer_global_readout_animation'
$frameDirectory = Join-Path $outputDirectory 'frames'
New-Item -ItemType Directory -Force -Path $frameDirectory | Out-Null

$width = 1200
$height = 675

function Get-Color {
    param([Parameter(Mandatory = $true)][string]$Hex)
    return [System.Drawing.ColorTranslator]::FromHtml($Hex)
}

$colors = @{
    Background    = Get-Color '#F5F7FB'
    Panel         = Get-Color '#FFFFFF'
    Ink           = Get-Color '#17223B'
    Muted         = Get-Color '#667085'
    Grid          = Get-Color '#D7DEEA'
    Inactive      = Get-Color '#E9EDF4'
    Active        = Get-Color '#BFEBD2'
    ActiveStrong  = Get-Color '#188A57'
    Scan          = Get-Color '#FFE1A8'
    ScanStrong    = Get-Color '#D97706'
    Selected      = Get-Color '#6967D8'
    SelectedLight = Get-Color '#DAD9FF'
    Locked        = Get-Color '#8B5CF6'
    Bus           = Get-Color '#2563EB'
    BusLight      = Get-Color '#DCEAFF'
    Border        = Get-Color '#C8D0DE'
    DarkPanel     = Get-Color '#24324D'
}

$fontTitle = New-Object System.Drawing.Font(
    'Pretendard SemiBold', 28,
    [System.Drawing.FontStyle]::Regular,
    [System.Drawing.GraphicsUnit]::Pixel)
$fontSubtitle = New-Object System.Drawing.Font(
    'Pretendard Medium', 15,
    [System.Drawing.FontStyle]::Regular,
    [System.Drawing.GraphicsUnit]::Pixel)
$fontStep = New-Object System.Drawing.Font(
    'Pretendard SemiBold', 24,
    [System.Drawing.FontStyle]::Regular,
    [System.Drawing.GraphicsUnit]::Pixel)
$fontBody = New-Object System.Drawing.Font(
    'Pretendard', 17,
    [System.Drawing.FontStyle]::Regular,
    [System.Drawing.GraphicsUnit]::Pixel)
$fontSmall = New-Object System.Drawing.Font(
    'Pretendard Medium', 13,
    [System.Drawing.FontStyle]::Regular,
    [System.Drawing.GraphicsUnit]::Pixel)
$fontTiny = New-Object System.Drawing.Font(
    'Pretendard', 11,
    [System.Drawing.FontStyle]::Regular,
    [System.Drawing.GraphicsUnit]::Pixel)
$fontState = New-Object System.Drawing.Font(
    'Pretendard SemiBold', 16,
    [System.Drawing.FontStyle]::Regular,
    [System.Drawing.GraphicsUnit]::Pixel)

function New-RoundedPath {
    param(
        [System.Drawing.RectangleF]$Rectangle,
        [float]$Radius
    )

    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $diameter = $Radius * 2
    $path.AddArc($Rectangle.X, $Rectangle.Y, $diameter, $diameter, 180, 90)
    $path.AddArc($Rectangle.Right - $diameter, $Rectangle.Y,
        $diameter, $diameter, 270, 90)
    $path.AddArc($Rectangle.Right - $diameter, $Rectangle.Bottom - $diameter,
        $diameter, $diameter, 0, 90)
    $path.AddArc($Rectangle.X, $Rectangle.Bottom - $diameter,
        $diameter, $diameter, 90, 90)
    $path.CloseFigure()
    return $path
}

function Draw-RoundedBox {
    param(
        [System.Drawing.Graphics]$Graphics,
        [System.Drawing.RectangleF]$Rectangle,
        [System.Drawing.Color]$Fill,
        [System.Drawing.Color]$Stroke,
        [float]$StrokeWidth = 1,
        [float]$Radius = 10
    )

    $path = New-RoundedPath $Rectangle $Radius
    $brush = New-Object System.Drawing.SolidBrush($Fill)
    $pen = New-Object System.Drawing.Pen($Stroke, $StrokeWidth)
    $Graphics.FillPath($brush, $path)
    $Graphics.DrawPath($pen, $path)
    $brush.Dispose()
    $pen.Dispose()
    $path.Dispose()
}

function Draw-Text {
    param(
        [System.Drawing.Graphics]$Graphics,
        [string]$Text,
        [System.Drawing.Font]$Font,
        [System.Drawing.Color]$Color,
        [float]$X,
        [float]$Y
    )

    $brush = New-Object System.Drawing.SolidBrush($Color)
    $Graphics.DrawString($Text, $Font, $brush, $X, $Y)
    $brush.Dispose()
}

function Draw-TextBlock {
    param(
        [System.Drawing.Graphics]$Graphics,
        [string]$Text,
        [System.Drawing.Font]$Font,
        [System.Drawing.Color]$Color,
        [System.Drawing.RectangleF]$Rectangle
    )

    $brush = New-Object System.Drawing.SolidBrush($Color)
    $format = New-Object System.Drawing.StringFormat
    $format.Trimming = [System.Drawing.StringTrimming]::EllipsisWord
    $Graphics.DrawString($Text, $Font, $brush, $Rectangle, $format)
    $format.Dispose()
    $brush.Dispose()
}

function Draw-Arrow {
    param(
        [System.Drawing.Graphics]$Graphics,
        [float]$X1,
        [float]$Y1,
        [float]$X2,
        [float]$Y2,
        [System.Drawing.Color]$Color
    )

    $pen = New-Object System.Drawing.Pen($Color, 2)
    $cap = New-Object System.Drawing.Drawing2D.AdjustableArrowCap(4, 5)
    $pen.CustomEndCap = $cap
    $Graphics.DrawLine($pen, $X1, $Y1, $X2, $Y2)
    $pen.Dispose()
    $cap.Dispose()
}

$activeBanks = @(2, 7, 20, 91, 147, 238)
$packetLabels = @('HEADER', 'TIME', 'DATA col1', 'DATA col3')
$packetValues = @('bank=2 row=1 mask=1010', 't_base=0x1234',
    'BIN4 · dt=0', 'GROUP3 · dt=3 · LAST')

$frames = @(
    [pscustomobject]@{
        Name='01_overview'; Step='STEP 1'; Title='센서 배열을 뱅크로 나눈다'
        Description='128×128픽셀을 2×2 타일로 묶고, 4×4타일을 하나의 뱅크로 구성한다. 전역 단계에서는 16×16개의 뱅크만 바라본다.'
        Pointer=-1; Scanned=@(); Selected=-1; Locked=$false; Output='대기'; Packet=-1; Flow=0
    },
    [pscustomobject]@{
        Name='02_bank_valid'; Step='STEP 2'; Title='이벤트가 있는 뱅크만 표시한다'
        Description='각 뱅크는 내부 tile_valid를 OR하여 bank_valid 한 비트를 만든다. 초록색 뱅크만 전역 선택기의 후보가 된다.'
        Pointer=-1; Scanned=@(); Selected=-1; Locked=$false; Output='bank_valid 생성'; Packet=-1; Flow=0
    },
    [pscustomobject]@{
        Name='03_pointer_start'; Step='STEP 3'; Title='행 우선 포인터에서 탐색을 시작한다'
        Description='포인터는 마지막으로 서비스한 뱅크의 다음 위치를 기억한다. 초기 상태에서는 bank 0, 즉 (row 0, col 0)부터 찾는다.'
        Pointer=0; Scanned=@(0); Selected=-1; Locked=$false; Output='후보 탐색'; Packet=-1; Flow=1
    },
    [pscustomobject]@{
        Name='04_skip_empty'; Step='STEP 4'; Title='빈 뱅크를 건너뛰고 bank 2를 찾는다'
        Description='bank 0과 1은 valid=0이므로 전송하지 않는다. 우선순위 논리가 같은 탐색에서 bank 2를 바로 선택한다.'
        Pointer=0; Scanned=@(0,1,2); Selected=2; Locked=$false; Output='grant = bank 2'; Packet=-1; Flow=1
    },
    [pscustomobject]@{
        Name='05_lock_bank'; Step='STEP 5'; Title='선택한 뱅크를 잠근다'
        Description='bank 2가 여러 워드의 행 패킷을 보내는 동안 다른 뱅크가 새 이벤트를 내도 선택을 바꾸지 않는다.'
        Pointer=0; Scanned=@(0,1,2); Selected=2; Locked=$true; Output='packet_lock = 1'; Packet=-1; Flow=2
    },
    [pscustomobject]@{
        Name='06_send_header'; Step='STEP 6'; Title='헤더 워드를 전송한다'
        Description='헤더에는 bank_id, 뱅크 내부 타일 행 번호, 이벤트가 존재하는 열 비트맵이 들어간다.'
        Pointer=0; Scanned=@(0,1,2); Selected=2; Locked=$true; Output='HEADER 전송'; Packet=0; Flow=3
    },
    [pscustomobject]@{
        Name='07_send_time'; Step='STEP 7'; Title='행 기준 타임스탬프를 한 번 보낸다'
        Description='같은 행의 모든 타일이 공유할 16비트 기준 시각을 보낸다. 이후 타일 워드는 4비트 시간차만 사용한다.'
        Pointer=0; Scanned=@(0,1,2); Selected=2; Locked=$true; Output='TIME 전송'; Packet=1; Flow=3
    },
    [pscustomobject]@{
        Name='08_send_data_1'; Step='STEP 8'; Title='유효한 첫 번째 열의 타일을 보낸다'
        Description='열 비트맵에서 가장 낮은 유효 열부터 전송한다. 이 예에서는 col 1의 네 ON 이벤트를 BIN4 한 워드로 보낸다.'
        Pointer=0; Scanned=@(0,1,2); Selected=2; Locked=$true; Output='DATA col1'; Packet=2; Flow=3
    },
    [pscustomobject]@{
        Name='09_send_last'; Step='STEP 9'; Title='마지막 열을 보내고 잠금을 해제한다'
        Description='col 3의 GROUP3 워드에 LAST를 표시한다. ready와 valid가 함께 1인 클록에서 전송이 끝나고 잠금이 풀린다.'
        Pointer=0; Scanned=@(0,1,2); Selected=2; Locked=$true; Output='DATA col3 · LAST'; Packet=3; Flow=3
    },
    [pscustomobject]@{
        Name='10_next_bank'; Step='STEP 10'; Title='다음 위치부터 bank 7을 선택한다'
        Description='포인터를 bank 3으로 옮긴다. bank 3~6은 비어 있으므로 건너뛰고 같은 행의 bank 7을 선택한다.'
        Pointer=3; Scanned=@(3,4,5,6,7); Selected=7; Locked=$false; Output='next grant = bank 7'; Packet=-1; Flow=1
    },
    [pscustomobject]@{
        Name='11_next_row'; Step='STEP 11'; Title='행 끝을 지나 다음 행으로 이어간다'
        Description='bank 7의 전송 뒤 row 0의 남은 뱅크가 비어 있다면 row 1로 넘어가 bank 20, 즉 (1,4)를 찾는다.'
        Pointer=8; Scanned=@(8..20); Selected=20; Locked=$false; Output='grant = bank 20'; Packet=-1; Flow=1
    },
    [pscustomobject]@{
        Name='12_repeat'; Step='STEP 12'; Title='같은 과정을 원형으로 반복한다'
        Description='마지막 bank 255 뒤에는 bank 0으로 돌아간다. 새 이벤트는 bank_valid에 반영되고, 단일 16비트 링크는 항상 한 패킷씩 처리한다.'
        Pointer=21; Scanned=@(); Selected=-1; Locked=$false; Output='계속 순환'; Packet=-1; Flow=1
    }
)

function Render-Frame {
    param(
        [Parameter(Mandatory = $true)]$Frame,
        [Parameter(Mandatory = $true)][int]$FrameNumber
    )

    $bitmap = New-Object System.Drawing.Bitmap(
        $width, $height,
        [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $graphics.TextRenderingHint =
        [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
    $graphics.Clear($colors.Background)

    Draw-Text $graphics '센서 전역 이벤트 읽기' $fontTitle $colors.Ink 42 24
    Draw-Text $graphics '128×128 pixels · 2×2 tile · 4×4 tiles/bank · 16×16 banks · 16-bit output' `
        $fontSubtitle $colors.Muted 43 61

    $gridPanel = New-Object System.Drawing.RectangleF(34, 96, 500, 520)
    Draw-RoundedBox $graphics $gridPanel $colors.Panel $colors.Border 1 16
    Draw-Text $graphics 'BANK VALID MAP' $fontSubtitle $colors.Muted 56 112

    $gridX = 64
    $gridY = 153
    $cell = 27
    $gap = 1

    foreach ($tick in @(0, 3, 7, 11, 15)) {
        Draw-Text $graphics $tick.ToString() $fontTiny $colors.Muted `
            ($gridX + $tick * $cell + 6) 134
        Draw-Text $graphics $tick.ToString() $fontTiny $colors.Muted `
            43 ($gridY + $tick * $cell + 6)
    }

    for ($row = 0; $row -lt 16; $row++) {
        for ($column = 0; $column -lt 16; $column++) {
            $bankIndex = $row * 16 + $column
            $fill = $colors.Inactive
            $stroke = $colors.Grid
            $strokeWidth = 1

            if (($FrameNumber -ge 2) -and ($activeBanks -contains $bankIndex)) {
                $fill = $colors.Active
                $stroke = $colors.ActiveStrong
            }
            if ($Frame.Scanned -contains $bankIndex) {
                $fill = $colors.Scan
                $stroke = $colors.ScanStrong
            }
            if ($Frame.Selected -eq $bankIndex) {
                $fill = $colors.Selected
                $stroke = $colors.Locked
                $strokeWidth = 3
            }

            $rectangle = New-Object System.Drawing.RectangleF(
                ($gridX + $column * $cell),
                ($gridY + $row * $cell),
                ($cell - $gap), ($cell - $gap))
            $brush = New-Object System.Drawing.SolidBrush($fill)
            $pen = New-Object System.Drawing.Pen($stroke, $strokeWidth)
            $graphics.FillRectangle($brush, $rectangle)
            $graphics.DrawRectangle($pen, $rectangle.X, $rectangle.Y,
                $rectangle.Width, $rectangle.Height)
            $brush.Dispose()
            $pen.Dispose()

            if (($FrameNumber -ge 2) -and
                ($activeBanks -contains $bankIndex) -and
                ($Frame.Selected -ne $bankIndex)) {
                $dotBrush = New-Object System.Drawing.SolidBrush($colors.ActiveStrong)
                $graphics.FillEllipse($dotBrush, $rectangle.X + 9,
                    $rectangle.Y + 9, 8, 8)
                $dotBrush.Dispose()
            }
            if ($Frame.Selected -eq $bankIndex) {
                $textBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)
                $textFormat = New-Object System.Drawing.StringFormat
                $textFormat.Alignment = [System.Drawing.StringAlignment]::Center
                $textFormat.LineAlignment = [System.Drawing.StringAlignment]::Center
                $graphics.DrawString($bankIndex.ToString(), $fontTiny, $textBrush,
                    $rectangle, $textFormat)
                $textFormat.Dispose()
                $textBrush.Dispose()
            }
        }
    }

    if ($Frame.Scanned.Count -gt 1) {
        $pathPen = New-Object System.Drawing.Pen($colors.ScanStrong, 2)
        $pathPen.DashStyle = [System.Drawing.Drawing2D.DashStyle]::Dash
        for ($pathIndex = 0; $pathIndex -lt ($Frame.Scanned.Count - 1);
             $pathIndex++) {
            $fromBank = $Frame.Scanned[$pathIndex]
            $toBank = $Frame.Scanned[$pathIndex + 1]
            $fromX = $gridX + ($fromBank % 16) * $cell + ($cell / 2)
            $fromY = $gridY + [math]::Floor($fromBank / 16) * $cell + ($cell / 2)
            $toX = $gridX + ($toBank % 16) * $cell + ($cell / 2)
            $toY = $gridY + [math]::Floor($toBank / 16) * $cell + ($cell / 2)
            $graphics.DrawLine($pathPen, $fromX, $fromY, $toX, $toY)
        }
        $pathPen.Dispose()
    }

    $legendY = 591
    $legendItems = @(
        @($colors.Active, 'event bank'),
        @($colors.Scan, 'searched'),
        @($colors.Selected, 'selected / locked'))
    $legendX = 61
    foreach ($item in $legendItems) {
        $legendBrush = New-Object System.Drawing.SolidBrush($item[0])
        $graphics.FillRectangle($legendBrush, $legendX, $legendY, 15, 15)
        $legendBrush.Dispose()
        Draw-Text $graphics $item[1] $fontTiny $colors.Muted ($legendX + 20) ($legendY - 1)
        $legendX += 132
    }

    $detailPanel = New-Object System.Drawing.RectangleF(550, 96, 616, 520)
    Draw-RoundedBox $graphics $detailPanel $colors.Panel $colors.Border 1 16

    Draw-Text $graphics $Frame.Step $fontSubtitle $colors.Selected 578 117
    Draw-Text $graphics $Frame.Title $fontStep $colors.Ink 578 142

    $flowLabels = @('BANK VALID', 'ROW / COL', 'PACKET LOCK', '16-bit BUS')
    $flowX = @(578, 720, 862, 1004)
    for ($flowIndex = 0; $flowIndex -lt 4; $flowIndex++) {
        $flowFill = $colors.Inactive
        $flowStroke = $colors.Border
        if ($flowIndex -eq $Frame.Flow) {
            $flowFill = if ($flowIndex -eq 3) { $colors.BusLight } else { $colors.SelectedLight }
            $flowStroke = if ($flowIndex -eq 3) { $colors.Bus } else { $colors.Selected }
        }
        $flowRectangle = New-Object System.Drawing.RectangleF(
            $flowX[$flowIndex], 190, 118, 48)
        Draw-RoundedBox $graphics $flowRectangle $flowFill $flowStroke 1.5 9

        $flowBrush = New-Object System.Drawing.SolidBrush($colors.Ink)
        $flowFormat = New-Object System.Drawing.StringFormat
        $flowFormat.Alignment = [System.Drawing.StringAlignment]::Center
        $flowFormat.LineAlignment = [System.Drawing.StringAlignment]::Center
        $graphics.DrawString($flowLabels[$flowIndex], $fontSmall, $flowBrush,
            $flowRectangle, $flowFormat)
        $flowFormat.Dispose()
        $flowBrush.Dispose()

        if ($flowIndex -lt 3) {
            Draw-Arrow $graphics ($flowX[$flowIndex] + 120) 214 `
                ($flowX[$flowIndex + 1] - 4) 214 $colors.Muted
        }
    }

    $descriptionRectangle = New-Object System.Drawing.RectangleF(578, 260, 558, 72)
    Draw-TextBlock $graphics $Frame.Description $fontBody $colors.Ink $descriptionRectangle

    $stateRectangle = New-Object System.Drawing.RectangleF(578, 344, 558, 92)
    Draw-RoundedBox $graphics $stateRectangle $colors.Background $colors.Border 1 10
    $pointerText = if ($Frame.Pointer -ge 0) {
        'bank ' + $Frame.Pointer + '  (' + [math]::Floor($Frame.Pointer / 16) +
        ',' + ($Frame.Pointer % 16) + ')'
    } else { '—' }
    $selectedText = if ($Frame.Selected -ge 0) {
        'bank ' + $Frame.Selected
    } else { '—' }
    $lockText = if ($Frame.Locked) { '1 · 선택 유지' } else { '0' }

    Draw-Text $graphics 'scan_ptr' $fontSmall $colors.Muted 596 359
    Draw-Text $graphics $pointerText $fontState $colors.Ink 688 356
    Draw-Text $graphics 'grant' $fontSmall $colors.Muted 596 390
    Draw-Text $graphics $selectedText $fontState $colors.Ink 688 387
    Draw-Text $graphics 'lock' $fontSmall $colors.Muted 856 359
    Draw-Text $graphics $lockText $fontState `
        $(if ($Frame.Locked) { $colors.Locked } else { $colors.Ink }) 922 356
    Draw-Text $graphics 'output' $fontSmall $colors.Muted 856 390
    Draw-Text $graphics $Frame.Output $fontState $colors.Bus 922 387

    for ($packetIndex = 0; $packetIndex -lt 4; $packetIndex++) {
        $packetX = 578 + $packetIndex * 140
        $packetFill = $colors.Inactive
        $packetStroke = $colors.Border
        if ($packetIndex -eq $Frame.Packet) {
            $packetFill = $colors.Bus
            $packetStroke = $colors.Bus
        }
        $packetRectangle = New-Object System.Drawing.RectangleF($packetX, 456, 130, 82)
        Draw-RoundedBox $graphics $packetRectangle $packetFill $packetStroke 1.5 10
        $packetTextColor = if ($packetIndex -eq $Frame.Packet) {
            [System.Drawing.Color]::White
        } else { $colors.Ink }
        Draw-Text $graphics $packetLabels[$packetIndex] $fontSmall `
            $packetTextColor ($packetX + 10) 468
        $packetValueRectangle = New-Object System.Drawing.RectangleF(
            ($packetX + 10), 490, 110, 37)
        Draw-TextBlock $graphics $packetValues[$packetIndex] $fontTiny `
            $packetTextColor $packetValueRectangle
    }

    Draw-Text $graphics '주황색 경로는 탐색 순서 설명용 · 빈 뱅크마다 클록을 쓰지 않고 우선순위 논리로 건너뜀' `
        $fontSmall $colors.Muted 578 562
    Draw-Text $graphics (('{0:D2}/12' -f $FrameNumber)) $fontSmall $colors.Muted 1094 586

    $framePath = Join-Path $frameDirectory ($Frame.Name + '.png')
    $bitmap.Save($framePath, [System.Drawing.Imaging.ImageFormat]::Png)
    $graphics.Dispose()
    $bitmap.Dispose()
    return $framePath
}

$framePaths = @()
for ($frameNumber = 1; $frameNumber -le $frames.Count; $frameNumber++) {
    $framePaths += Render-Frame $frames[$frameNumber - 1] $frameNumber
}

$contactSheet = New-Object System.Drawing.Bitmap(
    1200, 540, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$contactGraphics = [System.Drawing.Graphics]::FromImage($contactSheet)
$contactGraphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
$contactGraphics.Clear($colors.Background)
for ($frameIndex = 0; $frameIndex -lt $framePaths.Count; $frameIndex++) {
    $image = [System.Drawing.Image]::FromFile($framePaths[$frameIndex])
    $column = $frameIndex % 4
    $row = [math]::Floor($frameIndex / 4)
    $contactGraphics.DrawImage($image, $column * 300, $row * 180, 300, 169)
    $image.Dispose()
}
$contactPath = Join-Path $outputDirectory 'aer_global_readout_contact_sheet.png'
$contactSheet.Save($contactPath, [System.Drawing.Imaging.ImageFormat]::Png)
$contactGraphics.Dispose()
$contactSheet.Dispose()

$ffmpegCommand = Get-Command ffmpeg -ErrorAction SilentlyContinue
if (-not $ffmpegCommand) {
    throw 'ffmpeg was not found in PATH.'
}

$animationPath = Join-Path $outputDirectory 'aer_global_readout_step_by_step.webp'
$concatPath = Join-Path $outputDirectory 'frame_sequence.txt'
$concatLines = New-Object System.Collections.Generic.List[string]
foreach ($framePath in $framePaths) {
    $relativeFramePath = 'frames/' + [System.IO.Path]::GetFileName($framePath)
    $concatLines.Add("file '$relativeFramePath'")
    $concatLines.Add('duration 1.0')
}
$concatLines.Add("file 'frames/$([System.IO.Path]::GetFileName($framePaths[-1]))'")
[System.IO.File]::WriteAllLines(
    $concatPath, $concatLines,
    [System.Text.UTF8Encoding]::new($false))

& $ffmpegCommand.Source '-hide_banner' '-loglevel' 'error' '-y' `
    '-f' 'concat' '-safe' '0' '-i' $concatPath '-fps_mode' 'vfr' `
    '-loop' '0' '-c:v' 'libwebp_anim' '-quality' '90' `
    '-compression_level' '6' '-pix_fmt' 'yuva420p' $animationPath
if ($LASTEXITCODE -ne 0) {
    throw "ffmpeg failed with exit code $LASTEXITCODE."
}

$fontTitle.Dispose()
$fontSubtitle.Dispose()
$fontStep.Dispose()
$fontBody.Dispose()
$fontSmall.Dispose()
$fontTiny.Dispose()
$fontState.Dispose()

Write-Output "ANIMATION=$animationPath"
Write-Output "CONTACT_SHEET=$contactPath"
Write-Output "FRAMES=$($framePaths.Count)"
