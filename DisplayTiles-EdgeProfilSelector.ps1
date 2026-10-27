Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# ================== VISUELS / HELPERS ==================

[void][System.Windows.Forms.Application]::EnableVisualStyles()

function Get-Color {
    param([Parameter(Mandatory)][string]$Value)
    try {
        if ($Value.StartsWith('#')) { return [System.Drawing.ColorTranslator]::FromHtml($Value) }
        else { return [System.Drawing.Color]::$Value }
    } catch { return [System.Drawing.Color]::SteelBlue }
}
function Get-LightenedColor([System.Drawing.Color]$c, [int]$delta = 14) {
    return [System.Drawing.Color]::FromArgb(
        $c.A,
        [Math]::Min(255, [Math]::Max(0, $c.R + $delta)),
        [Math]::Min(255, [Math]::Max(0, $c.G + $delta)),
        [Math]::Min(255, [Math]::Max(0, $c.B + $delta))
    )
}
function Luminance([System.Drawing.Color]$c) { 0.2126*$c.R + 0.7152*$c.G + 0.0722*$c.B }
function IdealTextColor([System.Drawing.Color]$bg) {
    if ((Luminance $bg) -lt 140) { [System.Drawing.Color]::White } else { [System.Drawing.Color]::FromArgb(30,30,30) }
}
function New-RoundedRectPath {
    param([System.Drawing.Rectangle]$Rect, [int]$Radius)
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $d = [Math]::Max(0, $Radius * 2)
    if ($d -le 0) { $path.AddRectangle($Rect); return $path }
    $path.AddArc($Rect.X, $Rect.Y, $d, $d, 180, 90)
    $path.AddArc($Rect.Right - $d, $Rect.Y, $d, $d, 270, 90)
    $path.AddArc($Rect.Right - $d, $Rect.Bottom - $d, $d, $d, 0, 90)
    $path.AddArc($Rect.X, $Rect.Bottom - $d, $d, $d, 90, 90)
    $path.CloseFigure()
    return $path
}
function Remove-Diacritics([string]$s) {
    if ([string]::IsNullOrWhiteSpace($s)) { return $s }
    $formD = $s.Normalize([Text.NormalizationForm]::FormD)
    $sb = New-Object System.Text.StringBuilder
    foreach ($ch in $formD.ToCharArray()) {
        if ([Globalization.CharUnicodeInfo]::GetUnicodeCategory($ch) -ne [Globalization.UnicodeCategory]::NonSpacingMark) { [void]$sb.Append($ch) }
    }
    $sb.ToString().Normalize([Text.NormalizationForm]::FormC)
}

# --- Helpers anti-flicker (réflexion) ---
function Set-DoubleBuffered {
    param([System.Windows.Forms.Control]$Control)
    $flags = [System.Reflection.BindingFlags]'Instance, NonPublic'
    $pi = $Control.GetType().GetProperty('DoubleBuffered', $flags)
    if ($pi) { $pi.SetValue($Control, $true, $null) }
}
function Enable-OptimizedDoubleBuffer {
    param([System.Windows.Forms.Form]$Form)
    $flags = [System.Reflection.BindingFlags]'Instance, NonPublic'
    $method = [System.Windows.Forms.Control].GetMethod('SetStyle', $flags)
    if ($method) {
        $cs = [System.Windows.Forms.ControlStyles]
        $method.Invoke($Form, @($cs::AllPaintingInWmPaint -bor $cs::UserPaint -bor $cs::OptimizedDoubleBuffer, $true)) | Out-Null
        $Form.UpdateStyles()
    }
}

# ================== THEME ==================

$Theme = [pscustomobject]@{
    Mode            = 'Dark'  # 'Light' ou 'Dark' au démarrage
    # Fond "fondu" (dégradé) pour chaque mode
    Bg1_Light       = [System.Drawing.Color]::FromArgb(250, 252, 255)
    Bg2_Light       = [System.Drawing.Color]::FromArgb(235, 240, 245)
    Bg1_Dark        = [System.Drawing.Color]::FromArgb(28, 30, 34)
    Bg2_Dark        = [System.Drawing.Color]::FromArgb(18, 20, 24)

    Fore_Light      = [System.Drawing.Color]::FromArgb(30, 30, 30)
    Fore_Dark       = [System.Drawing.Color]::Gainsboro
    Subtle_Light    = [System.Drawing.Color]::FromArgb(105,110,118)
    Subtle_Dark     = [System.Drawing.Color]::FromArgb(180,182,188)
    Accent          = [System.Drawing.Color]::FromArgb(0,120,212)

    HeaderPadding   = 20
    FontName        = 'Segoe UI'

    TileRadius      = 12
    TileSize        = [System.Drawing.Size]::new(180, 180)
    TileGap         = 20
    ShadowAlpha     = 42
    BorderAlpha     = 46
    HoverDelta      = 16
    UseLiquid       = $true   # false => flat uni

    Opacity         = 0.98    # effet "transparence" de la fenêtre (0.85..1.0)
}

function Get-Bg1() { if ($Theme.Mode -eq 'Dark') { $Theme.Bg1_Dark } else { $Theme.Bg1_Light } }
function Get-Bg2() { if ($Theme.Mode -eq 'Dark') { $Theme.Bg2_Dark } else { $Theme.Bg2_Light } }
function Get-Fore() { if ($Theme.Mode -eq 'Dark') { $Theme.Fore_Dark } else { $Theme.Fore_Light } }
function Get-Subtle(){ if ($Theme.Mode -eq 'Dark') { $Theme.Subtle_Dark } else { $Theme.Subtle_Light } }

# ================== DONNÉES & ACTION ==================

Set-Location $PSScriptRoot
$jsonPath = ".\tiles.json"
$Global:TilesConfig = Get-Content $jsonPath | ConvertFrom-Json

# Tentative de détection de msedge.exe (x86 ou x64)
$script:EdgeExe = @(
    "C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe",
    "C:\\Program Files\\Microsoft\\Edge\\Application\\msedge.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $script:EdgeExe) { $script:EdgeExe = 'msedge.exe' }

function Search-TileConfig($InternalName) {
    $Global:TilesConfig | Where-Object { $_.InternalName -eq $InternalName } | Select-Object -First 1
}
function Launch-EdgePorfil($InternalName, [switch]$InPrivate) {
    $tileCong = Search-TileConfig -InternalName $InternalName
    if ($tileCong) {
        $args = @("--profile-directory=`"$($tileCong.EdgeProfil)`"", $tileCong.Url)
        if ($InPrivate) { $args = @("--inprivate") + $args }
        Start-Process -FilePath $script:EdgeExe -ArgumentList ($args -join ' ')
    }
    if ($Global:form) { $Global:form.Close(); $Global:form.Dispose() }
}

# ================== FORM PRINCIPAL ==================

$Global:form = New-Object System.Windows.Forms.Form
$Global:form.Text = "Edge Selector"
$Global:form.StartPosition = 'CenterScreen'
$Global:form.AutoScaleMode = 'Dpi'
$Global:form.Opacity = $Theme.Opacity
$Global:form.ClientSize = [System.Drawing.Size]::new(1080, 840)
$Global:form.MinimumSize = [System.Drawing.Size]::new(880, 720)
$Global:form.KeyPreview = $true

# Anti-flicker
Set-DoubleBuffered -Control $Global:form
Enable-OptimizedDoubleBuffer -Form $Global:form

# Fond dégradé "fondu"
$Global:form.Add_Paint({
    $g = $_.Graphics
    $g.SmoothingMode = 'AntiAlias'
    $rect = [System.Drawing.Rectangle]::new(0,0,$this.ClientSize.Width,$this.ClientSize.Height)
    $lg = New-Object System.Drawing.Drawing2D.LinearGradientBrush($rect, (Get-Bg1), (Get-Bg2), 90.0)
    $g.FillRectangle($lg, $rect)
    $lg.Dispose()
})

# Premier plan sans rester always-on-top
$Global:form.Add_Shown({ $this.TopMost=$true; $this.Activate(); $this.BringToFront(); $this.TopMost=$false })
$Global:form.Add_KeyDown({ if ($_.KeyCode -eq 'Escape') { $this.Close() } })

$Global:form.SuspendLayout()

# ================== HEADER ==================

$header = New-Object System.Windows.Forms.TableLayoutPanel
$header.AutoSize = $true
$header.AutoSizeMode = 'GrowAndShrink'
$header.Dock = 'Top'
$header.Padding = [System.Windows.Forms.Padding]::new($Theme.HeaderPadding, $Theme.HeaderPadding, $Theme.HeaderPadding, 8)
$header.BackColor = [System.Drawing.Color]::Transparent
$header.ColumnCount = 2
$header.ColumnStyles.Add( (New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)) )
$header.ColumnStyles.Add( (New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::AutoSize)) )

$left = New-Object System.Windows.Forms.FlowLayoutPanel
$left.FlowDirection = 'TopDown'
$left.WrapContents = $false
$left.AutoSize = $true
$left.Dock = 'Fill'
$left.BackColor = [System.Drawing.Color]::Transparent

$title = New-Object System.Windows.Forms.Label
$title.Text = "Edge Selector"
$title.Font = New-Object System.Drawing.Font($Theme.FontName, 20, [System.Drawing.FontStyle]::Bold)
$title.AutoSize = $true
$title.ForeColor = Get-Fore

$subtitle = New-Object System.Windows.Forms.Label
$subtitle.Text = "Choisissez un profil • Recherche instantanée • ↑↓←→ pour naviguer • Entrée pour ouvrir • Échap pour fermer"
$subtitle.Font = New-Object System.Drawing.Font($Theme.FontName, 10)
$subtitle.AutoSize = $true
$subtitle.ForeColor = Get-Subtle

$left.Controls.Add($title)
$left.Controls.Add($subtitle)

$right = New-Object System.Windows.Forms.FlowLayoutPanel
$right.FlowDirection = 'LeftToRight'
$right.WrapContents = $false
$right.AutoSize = $true
$right.Dock = 'Right'
$right.BackColor = [System.Drawing.Color]::Transparent
$right.Padding = [System.Windows.Forms.Padding]::new(0, 4, 0, 0)

$search = New-Object System.Windows.Forms.TextBox
$search.Font = New-Object System.Drawing.Font($Theme.FontName, 10)
$search.Width = 300
$search.BorderStyle = 'FixedSingle'
$search.Text = ''
function Apply-SearchTheme {
    if ($Theme.Mode -eq 'Dark') {
        $search.BackColor = [System.Drawing.Color]::FromArgb(45,47,51)
        $search.ForeColor = [System.Drawing.Color]::Gainsboro
    } else {
        $search.BackColor = [System.Drawing.Color]::White
        $search.ForeColor = [System.Drawing.Color]::FromArgb(30,30,30)
    }
}
Apply-SearchTheme
$search.Margin = [System.Windows.Forms.Padding]::new(0, 0, 8, 0)

$darkToggle = New-Object System.Windows.Forms.CheckBox
$darkToggle.Appearance = 'Button'
$darkToggle.Text = 'Dark'
$darkToggle.AutoSize = $true
$darkToggle.Checked = ($Theme.Mode -eq 'Dark')
$darkToggle.Font = New-Object System.Drawing.Font($Theme.FontName, 9)
$darkToggle.FlatStyle = 'Popup'
$darkToggle.ForeColor = Get-Fore
$darkToggle.BackColor = [System.Drawing.Color]::FromArgb(40,40,44)
$darkToggle.Padding = [System.Windows.Forms.Padding]::new(6,3,6,3)

$right.Controls.Add($search)
$right.Controls.Add($darkToggle)

$header.Controls.Add($left, 0, 0)
$header.Controls.Add($right, 1, 0)
$Global:form.Controls.Add($header)

# ================== GRILLE ==================

$grid = New-Object System.Windows.Forms.FlowLayoutPanel
$grid.Dock = 'Fill'
$grid.WrapContents = $true
$grid.AutoScroll = $true
$grid.Padding = [System.Windows.Forms.Padding]::new($Theme.HeaderPadding, 10, $Theme.HeaderPadding, $Theme.HeaderPadding)
$grid.BackColor = [System.Drawing.Color]::Transparent
Set-DoubleBuffered -Control $grid
$Global:form.Controls.Add($grid)

$Global:form.ResumeLayout($true)

# ================== TOOLTIP & CONTEXT MENU ==================

$tooltip = New-Object System.Windows.Forms.ToolTip
$tooltip.InitialDelay = 180
$tooltip.ReshowDelay = 100

$ctx = New-Object System.Windows.Forms.ContextMenuStrip
$miOpen = $ctx.Items.Add("Ouvrir")
$miPrivate = $ctx.Items.Add("Ouvrir en InPrivate")
$ctx.Items.Add("-") | Out-Null
$miCopyUrl = $ctx.Items.Add("Copier l'URL")
$miOpenDir = $ctx.Items.Add("Ouvrir le dossier du profil")

# ================== HOVER ROBUSTE (parent + enfants) ==================

function Attach-HoverHandlers([System.Windows.Forms.Control]$ctl) {
    $ctl.Add_MouseEnter({
        $tile = $this
        while ($tile -and -not ($tile.Tag -and $tile.Tag.PSObject.Properties.Name -contains 'Config')) { $tile = $tile.Parent }
        if ($tile) { $tile.Tag.Hover = $true; $tile.Invalidate() }
    })
    $ctl.Add_MouseLeave({
        $tile = $this
        while ($tile -and -not ($tile.Tag -and $tile.Tag.PSObject.Properties.Name -contains 'Config')) { $tile = $tile.Parent }
        if ($tile) {
            $pt = $tile.PointToClient([System.Windows.Forms.Control]::MousePosition)
            if (-not $tile.ClientRectangle.Contains($pt)) { $tile.Tag.Hover = $false; $tile.Invalidate() }
        }
    })
    foreach ($child in $ctl.Controls) { Attach-HoverHandlers $child }
}

# ================== FABRIQUE DE TUILE ==================

function New-Tile([pscustomobject]$tileCong) {
    $baseColor = Get-Color $tileCong.BackColor
    $grad1 = if ($Theme.UseLiquid) { Get-LightenedColor $baseColor 10 } else { $baseColor }
    $grad2 = if ($Theme.UseLiquid) { Get-LightenedColor $baseColor -10 } else { $baseColor }
    $txtColor = IdealTextColor $baseColor

    $tile = New-Object System.Windows.Forms.Panel
    $tile.Name   = $tileCong.InternalName
    $tile.Size   = $Theme.TileSize
    $tile.Margin = [System.Windows.Forms.Padding]::new($Theme.TileGap)
    $tile.BackColor = [System.Drawing.Color]::Transparent
    $tile.Cursor = [System.Windows.Forms.Cursors]::Hand
    $tile.TabStop = $true
    $tile.Tag = [pscustomobject]@{
        Config = $tileCong
        Hover  = $false
        Base   = $baseColor
        Grad1  = $grad1
        Grad2  = $grad2
        Text   = $txtColor
        SearchIndex = (Remove-Diacritics("$($tileCong.Label) $($tileCong.InternalName) $($tileCong.EdgeProfil)")).ToLowerInvariant()
    }

    $tile.Add_Paint({
        $g = $_.Graphics
        $g.SmoothingMode = 'AntiAlias'
        $w = $this.Width; $h = $this.Height
        $rect = [System.Drawing.Rectangle]::new(0,0,$w-1,$h-1)
        $path = New-RoundedRectPath -Rect $rect -Radius $Theme.TileRadius
        $this.Region = New-Object System.Drawing.Region($path)

        $shadowRect = [System.Drawing.Rectangle]::new(4,6,$w-1,$h-1)
        $shadowPath = New-RoundedRectPath -Rect $shadowRect -Radius $Theme.TileRadius
        $shadowBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb($Theme.ShadowAlpha, 0,0,0))
        $g.FillPath($shadowBrush, $shadowPath); $shadowBrush.Dispose()

        $c1 = $this.Tag.Grad1; $c2 = $this.Tag.Grad2
        if ($this.Tag.Hover) { $c1 = Get-LightenedColor $c1 $Theme.HoverDelta; $c2 = Get-LightenedColor $c2 $Theme.HoverDelta }
        if ($Theme.UseLiquid) {
            $lg = New-Object System.Drawing.Drawing2D.LinearGradientBrush($rect, $c1, $c2, 45.0)
            $g.FillPath($lg, $path); $lg.Dispose()
        } else {
            $b = New-Object System.Drawing.SolidBrush($c1)
            $g.FillPath($b, $path); $b.Dispose()
        }

        $pen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb($Theme.BorderAlpha, 0,0,0), 1)
        $g.DrawPath($pen, $path); $pen.Dispose()

        if ($this.Focused) {
            $focusPen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(200, $Theme.Accent), 2)
            $g.DrawPath($focusPen, $path); $focusPen.Dispose()
        }
    })

    # Image ou placeholder
    $pictureArea = 72
    if (-not [string]::IsNullOrWhiteSpace($tileCong.ImagePath) -and (Test-Path $tileCong.ImagePath)) {
        $pb = New-Object System.Windows.Forms.PictureBox
        $pb.Size = [System.Drawing.Size]::new($pictureArea,$pictureArea)
        $pb.Location = [System.Drawing.Point]::new([Math]::Round(($tile.Width - $pictureArea)/2), 18)
        $pb.SizeMode = 'Zoom'
        try { $pb.Image = [System.Drawing.Image]::FromFile($tileCong.ImagePath) } catch {}
        $pb.BackColor = [System.Drawing.Color]::Transparent
        $tile.Controls.Add($pb)
    } else {
        $lblInit = New-Object System.Windows.Forms.Label
        $lblInit.Text = $tileCong.Label.Substring(0, [Math]::Min(1,$tileCong.Label.Length)).ToUpper()
        $lblInit.Font = New-Object System.Drawing.Font($Theme.FontName, 28, [System.Drawing.FontStyle]::Bold)
        $lblInit.Size = [System.Drawing.Size]::new($pictureArea,$pictureArea)
        $lblInit.TextAlign = 'MiddleCenter'
        $lblInit.ForeColor = IdealTextColor $baseColor
        $lblInit.BackColor = [System.Drawing.Color]::FromArgb(40,0,0,0)
        $lblInit.Location = [System.Drawing.Point]::new([Math]::Round(($tile.Width - $pictureArea)/2), 18)
        $tile.Controls.Add($lblInit)
    }

    # Label bas
    $label = New-Object System.Windows.Forms.Label
    $label.Text = $tileCong.Label
    $label.AutoSize = $false
    $label.Width = $tile.Width - 24
    $label.Height = 44
    $label.Location = [System.Drawing.Point]::new(12, ($tile.Height - 56))
    $label.Font = New-Object System.Drawing.Font($Theme.FontName, 10, [System.Drawing.FontStyle]::Regular)
    $label.ForeColor = $txtColor
    $label.BackColor = [System.Drawing.Color]::Transparent
    $label.TextAlign = 'MiddleCenter'
    $label.AutoEllipsis = $true
    $tile.Controls.Add($label)

    Attach-HoverHandlers $tile

    $tile.Add_Click({ Launch-EdgePorfil -InternalName $this.Name })
    $tile.Add_KeyDown({ if ($_.KeyCode -eq 'Enter') { Launch-EdgePorfil -InternalName $this.Name } })
    $tile.Add_GotFocus({ $script:lastFocus = $this })

    $tile.ContextMenuStrip = $ctx
    $tile.Add_MouseUp({ if ($_.Button -eq [System.Windows.Forms.MouseButtons]::Right) { $ctx.Tag = $this } })

    $tooltip.SetToolTip($tile, "$($tileCong.Label) — $($tileCong.EdgeProfil)")

    return $tile
}

# ================== PEUPLER GRILLE ==================

$grid.SuspendLayout()
$grid.Controls.Clear()
foreach ($tileParam in $Global:TilesConfig) { $grid.Controls.Add((New-Tile $tileParam)) }
$grid.ResumeLayout()
$grid.PerformLayout()

# Donner le focus initial à la première tuile visible
$firstVisible = $grid.Controls | Where-Object { $_.Visible } | Select-Object -First 1
if ($firstVisible) { $firstVisible.Focus(); $script:lastFocus = $firstVisible }

# ================== RECHERCHE ==================

$search.Add_TextChanged({
    $q = Remove-Diacritics($this.Text.Trim()).ToLowerInvariant()
    $grid.SuspendLayout()
    foreach ($t in $grid.Controls) {
        if (-not $t.Tag) { continue }
        $si = $t.Tag.SearchIndex
        $t.Visible = [string]::IsNullOrWhiteSpace($q) -or ($si -like "*$q*")
    }
    $grid.ResumeLayout()
    $grid.PerformLayout()

    # focus sur première tuile visible après filtrage
    $nv = $grid.Controls | Where-Object { $_.Visible } | Select-Object -First 1
    if ($nv) { $nv.Focus(); $script:lastFocus = $nv; $grid.ScrollControlIntoView($nv) }
})

# Permettre de sortir du champ recherche vers les tuiles avec les flèches
$search.Add_KeyDown({
    switch ($_.KeyCode) {
        'Down' { Move-Focus 'Down'; $_.SuppressKeyPress = $true }
        'Up'   { Move-Focus 'Up';   $_.SuppressKeyPress = $true }
        'Left' { Move-Focus 'Left'; $_.SuppressKeyPress = $true }
        'Right'{ Move-Focus 'Right';$_.SuppressKeyPress = $true }
    }
})

# ================== NAVIGATION CLAVIER ↑ ↓ ← → ==================

function Get-VisibleTiles {
    $tiles = @()
    foreach ($t in $grid.Controls) { if ($t.Visible) { $tiles += $t } }
    $tiles | Sort-Object @{e={$_.Top}}, @{e={$_.Left}}
}

function Move-Focus([string]$dir) {
    $tiles = Get-VisibleTiles
    if (-not $tiles) { return }

    $current = if ($script:lastFocus -and $script:lastFocus.Visible) { $script:lastFocus } else { $tiles[0] }
    $cx = $current.Left + ($current.Width  / 2)
    $cy = $current.Top  + ($current.Height / 2)

    $cand = $null
    $bestDist2 = [double]::PositiveInfinity

    foreach ($t in $tiles) {
        if ($t -eq $current) { continue }

        $tx = $t.Left + ($t.Width  / 2)
        $ty = $t.Top  + ($t.Height / 2)

        $dx = $cx - $tx
        $dy = $cy - $ty
        $dist2 = [math]::Pow($dx, 2) + [math]::Pow($dy, 2)

        switch ($dir) {
            'Left'  {
                if ($tx -lt ($cx - 5) -and [math]::Abs($ty - $cy) -le ($t.Height / 2)) { if ($dist2 -lt $bestDist2) { $bestDist2 = $dist2; $cand = $t } }
            }
            'Right' {
                if ($tx -gt ($cx + 5) -and [math]::Abs($ty - $cy) -le ($t.Height / 2)) { if ($dist2 -lt $bestDist2) { $bestDist2 = $dist2; $cand = $t } }
            }
            'Up'    {
                if ($ty -lt ($cy - 5)) { if ($dist2 -lt $bestDist2) { $bestDist2 = $dist2; $cand = $t } }
            }
            'Down'  {
                if ($ty -gt ($cy + 5)) { if ($dist2 -lt $bestDist2) { $bestDist2 = $dist2; $cand = $t } }
            }
        }
    }

    if ($cand) { 
        $cand.Focus()
        $script:lastFocus = $cand
        $grid.ScrollControlIntoView($cand)
    }
}

$Global:form.Add_KeyDown({
    switch ($_.KeyCode) {
        'Left'  { Move-Focus 'Left'  }
        'Right' { Move-Focus 'Right' }
        'Up'    { Move-Focus 'Up'    }
        'Down'  { Move-Focus 'Down'  }
    }
})

# ================== MENU CONTEXTUEL ==================

$miOpen.Add_Click({ if ($ctx.Tag) { Launch-EdgePorfil -InternalName $ctx.Tag.Name } })
$miPrivate.Add_Click({ if ($ctx.Tag) { Launch-EdgePorfil -InternalName $ctx.Tag.Name -InPrivate } })
$miCopyUrl.Add_Click({ if ($ctx.Tag) { [Windows.Forms.Clipboard]::SetText($ctx.Tag.Tag.Config.Url) } })
$miOpenDir.Add_Click({
    if ($ctx.Tag) {
        $dir = Join-Path $env:LOCALAPPDATA "Microsoft\Edge\User Data\$($ctx.Tag.Tag.Config.EdgeProfil)"
        if (Test-Path $dir) { Start-Process $dir }
    }
})

# ================== DARK / LIGHT ==================

function Apply-SearchTheme {
    if ($Theme.Mode -eq 'Dark') {
        $search.BackColor = [System.Drawing.Color]::FromArgb(45,47,51)
        $search.ForeColor = [System.Drawing.Color]::Gainsboro
    } else {
        $search.BackColor = [System.Drawing.Color]::White
        $search.ForeColor = [System.Drawing.Color]::FromArgb(30,30,30)
    }
}

function Apply-Theme() {
    $title.ForeColor      = Get-Fore
    $subtitle.ForeColor   = Get-Subtle
    $darkToggle.ForeColor = Get-Fore
    Apply-SearchTheme

    foreach ($c in $grid.Controls) {
        if (-not $c.Tag) { continue }
        $c.Tag.Text = IdealTextColor $c.Tag.Base
        foreach ($lab in $c.Controls | Where-Object { $_ -is [System.Windows.Forms.Label] }) { $lab.ForeColor = $c.Tag.Text }
        $c.Invalidate()
    }
    $Global:form.Invalidate()
}

$darkToggle.Add_CheckedChanged({
    $Theme.Mode = $(if ($this.Checked) { 'Dark' } else { 'Light' })
    Apply-Theme
})

# ================== SHOW ==================

[void]$Global:form.ShowDialog()
if ($Global:form) { $Global:form.Dispose() }
