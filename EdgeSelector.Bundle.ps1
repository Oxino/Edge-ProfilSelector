# ============================================================
#  FICHIER GÃ‰NÃ‰RÃ‰ AUTOMATIQUEMENT PAR build.ps1 - NE PAS Ã‰DITER
#  Bundle mono-fichier pour un dÃ©marrage optimisÃ©.
#  GÃ©nÃ©rÃ© le : 2026-08-21 11:34:41
# ============================================================

<#
.SYNOPSIS
    Point d'entrée de l'application Edge Profil Selector.
.DESCRIPTION
    Charge les assemblies nécessaires (WPF + WinForms), dot-source les classes,
    lit la configuration, instancie les dépendances puis démarre le contrôleur
    et affiche l'interface principale.

.VERSION
    1.0
    2.0: Tuile Drag & Drop + Reposition
    3.0: Gestion interface Graphique
    4.0: Améliorations diverses
    5.0: add, update, delete tiles + context menu
         Théme Dark/light
         Add profil card
    5.1: UI optimization, shadow, border, margin, drop shadow effect
    
#>

# Chargement des assemblies WPF (PresentationFramework/Core, WindowsBase) pour l'UI.
# System.Windows.Forms N'EST PAS chargé ici : il ne sert que dans la boîte de
# dialogue d'ajout (ColorDialog/OpenFileDialog) et y est chargé à la demande,
# ce qui allège et accélère le démarrage de la fenêtre principale.
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

# Se positionne dans le répertoire du script et mémorise la racine du projet.
Set-Location $PSScriptRoot
$root = $PSScriptRoot

# --- Dot-sourcing des classes (l'ordre respecte les dépendances) ---
# --- INLINE: src\UI\ColorHelper.ps1 ---
. ([ScriptBlock]::Create(@'
class ColorHelper {
    static [string] GetShade([string]$hex, [double]$factor) {
        try {
            $h = $hex.TrimStart('#')
            if ($h.Length -eq 3) {
                $h = ($h.ToCharArray() | ForEach-Object { "$_$_" }) -join ''
            }
            $r = [Convert]::ToInt32($h.Substring(0, 2), 16)
            $g = [Convert]::ToInt32($h.Substring(2, 2), 16)
            $b = [Convert]::ToInt32($h.Substring(4, 2), 16)
            $nr = [math]::Round([math]::Min(255, [math]::Max(0, $r * $factor)))
            $ng = [math]::Round([math]::Min(255, [math]::Max(0, $g * $factor)))
            $nb = [math]::Round([math]::Min(255, [math]::Max(0, $b * $factor)))
            return ('#{0:X2}{1:X2}{2:X2}' -f $nr, $ng, $nb)
        }
        catch {
            return $hex
        }
    }
    static [string] Mix([string]$hex, [string]$withHex, [double]$ratio) {
        try {
            $a = $hex.TrimStart('#')
            $b = $withHex.TrimStart('#')
            if ($a.Length -eq 3) { $a = ($a.ToCharArray() | ForEach-Object { "$_$_" }) -join '' }
            if ($b.Length -eq 3) { $b = ($b.ToCharArray() | ForEach-Object { "$_$_" }) -join '' }
            $ar = [Convert]::ToInt32($a.Substring(0, 2), 16)
            $ag = [Convert]::ToInt32($a.Substring(2, 2), 16)
            $ab = [Convert]::ToInt32($a.Substring(4, 2), 16)
            $br = [Convert]::ToInt32($b.Substring(0, 2), 16)
            $bg = [Convert]::ToInt32($b.Substring(2, 2), 16)
            $bb = [Convert]::ToInt32($b.Substring(4, 2), 16)
            $nr = [math]::Round($ar + ($br - $ar) * $ratio)
            $ng = [math]::Round($ag + ($bg - $ag) * $ratio)
            $nb = [math]::Round($ab + ($bb - $ab) * $ratio)
            return ('#{0:X2}{1:X2}{2:X2}' -f [int]$nr, [int]$ng, [int]$nb)
        }
        catch {
            return $hex
        }
    }
    static [string[]] GetThemeShades([string]$hex, [string]$theme, [double]$lighter, [double]$darker) {
        if ($theme -eq 'Light') {
            $soft = [ColorHelper]::Mix($hex, '#FFFFFF', 0.55)
            return @(
                [ColorHelper]::GetShade($soft, 1.06),
                [ColorHelper]::GetShade($soft, 0.90)
            )
        }
        return @(
            [ColorHelper]::GetShade($hex, $lighter),
            [ColorHelper]::GetShade($hex, $darker)
        )
    }
}
'@))
# --- END: src\UI\ColorHelper.ps1 ---

# --- INLINE: src\UI\ThemeManager.ps1 ---
. ([ScriptBlock]::Create(@'
class ThemeManager {
    hidden [string] $Current
    ThemeManager([string]$initial) {
        $this.Current = if ($initial -eq 'Light') { 'Light' } else { 'Dark' }
    }
    [string] GetCurrent() { return $this.Current }
    hidden static [System.Windows.Media.Color] Col([string]$hex) {
        return [System.Windows.Media.ColorConverter]::ConvertFromString($hex)
    }
    hidden static [System.Windows.Media.SolidColorBrush] Solid([string]$hex, [double]$opacity) {
        $b = [System.Windows.Media.SolidColorBrush]::new([ThemeManager]::Col($hex))
        $b.Opacity = $opacity
        $b.Freeze()
        return $b
    }
    hidden static [System.Windows.Media.LinearGradientBrush] Gradient([string[]]$hexes) {
        $g = [System.Windows.Media.LinearGradientBrush]::new()
        $g.StartPoint = [System.Windows.Point]::new(0, 0)
        $g.EndPoint   = [System.Windows.Point]::new(1, 1)
        $n = $hexes.Count
        for ($i = 0; $i -lt $n; $i++) {
            $offset = if ($n -le 1) { 0 } else { $i / ($n - 1) }
            $g.GradientStops.Add(
                [System.Windows.Media.GradientStop]::new([ThemeManager]::Col($hexes[$i]), $offset))
        }
        $g.Freeze()
        return $g
    }
    hidden [hashtable] Palette([string]$name) {
        if ($name -eq 'Light') {
            return @{
                Bg             = [ThemeManager]::Gradient(@('#F7F9FC', '#EAF1FB', '#DCE8F7'))
                TextPrimary    = [ThemeManager]::Solid('#14203A', 1.0)
                TextSecondary  = [ThemeManager]::Solid('#3A4A66', 1.0)
                Accent         = [ThemeManager]::Solid('#0078D4', 1.0)
                AccentHover    = [ThemeManager]::Solid('#2B90E0', 1.0)
                AccentText     = [ThemeManager]::Solid('#FFFFFF', 1.0)
                GlassFill      = [ThemeManager]::Solid('#14203A', 0.05)
                GlassFillHover = [ThemeManager]::Solid('#14203A', 0.12)
                GlassStroke    = [ThemeManager]::Solid('#14203A', 0.15)
            }
        }
        return @{
            Bg             = [ThemeManager]::Gradient(@('#1A1A2E', '#16213E', '#0F3460'))
            TextPrimary    = [ThemeManager]::Solid('#FFFFFF', 1.0)
            TextSecondary  = [ThemeManager]::Solid('#DDE6F6', 1.0)
            Accent         = [ThemeManager]::Solid('#6ABEF5', 1.0)
            AccentHover    = [ThemeManager]::Solid('#8CCEF8', 1.0)
            AccentText     = [ThemeManager]::Solid('#0F3460', 1.0)
            GlassFill      = [ThemeManager]::Solid('#FFFFFF', 0.08)
            GlassFillHover = [ThemeManager]::Solid('#FFFFFF', 0.20)
            GlassStroke    = [ThemeManager]::Solid('#FFFFFF', 0.25)
        }
    }
    [void] Apply([System.Windows.Window]$window, [string]$name) {
        if ($null -eq $window) { return }
        $p = $this.Palette($name)
        $r = $window.Resources
        $r['BgBrush']             = $p.Bg
        $r['TextPrimaryBrush']    = $p.TextPrimary
        $r['TextSecondaryBrush']  = $p.TextSecondary
        $r['AccentBrush']         = $p.Accent
        $r['AccentHoverBrush']    = $p.AccentHover
        $r['AccentTextBrush']     = $p.AccentText
        $r['GlassFillBrush']      = $p.GlassFill
        $r['GlassFillHoverBrush'] = $p.GlassFillHover
        $r['GlassStrokeBrush']    = $p.GlassStroke
        $this.Current = $name
    }
    [string] Toggle([System.Windows.Window]$window) {
        $next = if ($this.Current -eq 'Dark') { 'Light' } else { 'Dark' }
        $this.Apply($window, $next)
        return $next
    }
    [string] ToggleIcon() {
        if ($this.Current -eq 'Dark') { return [char]0x2600 }
        return [char]0x263E
    }
}
'@))
# --- END: src\UI\ThemeManager.ps1 ---

# --- INLINE: src\Models\TileModel.ps1 ---
. ([ScriptBlock]::Create(@'
class TileModel {
    [string] $Title
    [string] $Image
    [string] $Profil
    [string] $Url
    [string] $Couleur
    [string] $Color1
    [string] $Color2
    [int]    $Order
    [PSCustomObject] ToJsonObject() {
        return [PSCustomObject]@{
            Titre   = $this.Title
            Image   = $this.Image
            Profil  = $this.Profil
            Url     = $this.Url
            Couleur = $this.Couleur
            Order   = $this.Order
        }
    }
}
'@))
# --- END: src\Models\TileModel.ps1 ---

# --- INLINE: src\Factory\TileFactory.ps1 ---
. ([ScriptBlock]::Create(@'
class TileFactory {
    hidden [hashtable] $ShadeFactors
    hidden [string]    $DefaultColor
    hidden [string]    $Theme
    TileFactory([hashtable]$shadeFactors, [string]$defaultColor) {
        $this.ShadeFactors = $shadeFactors
        $this.DefaultColor = $defaultColor
        $this.Theme        = 'Dark'
    }
    [void] SetTheme([string]$theme) { $this.Theme = $theme }
    [void] ApplyShades([TileModel]$tile) {
        $shades = [ColorHelper]::GetThemeShades(
            $tile.Couleur, $this.Theme, $this.ShadeFactors.Lighter, $this.ShadeFactors.Darker)
        $tile.Color1 = $shades[0]
        $tile.Color2 = $shades[1]
    }
    [TileModel] CreateFromJson([PSCustomObject]$item, [int]$order) {
        $color = if ($item.Couleur) { $item.Couleur } else { $this.DefaultColor }
        $tile         = [TileModel]::new()
        $tile.Title   = $item.Titre
        $tile.Image   = $item.Image
        $tile.Profil  = $item.Profil
        $tile.Url     = $item.Url
        $tile.Couleur = $color
        $tile.Order   = if ($null -ne $item.Order) { $item.Order } else { $order }
        $this.ApplyShades($tile)
        return $tile
    }
    [TileModel] CreateNew([string]$title, [string]$image, [string]$profil, [string]$color, [string]$url, [int]$order) {
        if ([string]::IsNullOrWhiteSpace($color)) { $color = $this.DefaultColor }
        return $this.CreateFromJson(
            [PSCustomObject]@{
                Titre = $title; Image = $image; Profil = $profil; Couleur = $color; Url = $url
            }, $order)
    }
}
'@))
# --- END: src\Factory\TileFactory.ps1 ---

# --- INLINE: src\Parser\TileParser.ps1 ---
. ([ScriptBlock]::Create(@'
class TileParser {
    hidden [string]      $JsonPath
    hidden [TileFactory] $Factory
    hidden [string]      $Theme
    hidden [double]      $WinWidth
    hidden [double]      $WinHeight
    TileParser([string]$jsonPath, [TileFactory]$factory) {
        $this.JsonPath  = $jsonPath
        $this.Factory   = $factory
        $this.Theme     = 'Dark'
        $this.WinWidth  = 0
        $this.WinHeight = 0
    }
    [System.Collections.Generic.List[TileModel]] Load() {
        $tiles = [System.Collections.Generic.List[TileModel]]::new()
        if (-not (Test-Path $this.JsonPath)) { return $tiles }
        $raw = Get-Content -Path $this.JsonPath -Raw | ConvertFrom-Json
        $items = $null
        if ($raw -is [System.Array]) {
            $items = $raw
        }
        elseif ($null -ne $raw.PSObject.Properties['Tiles']) {
            $items = $raw.Tiles
            if ($raw.Theme) { $this.Theme = $raw.Theme }
            if ($raw.PSObject.Properties['WindowWidth']  -and $raw.WindowWidth)  { $this.WinWidth  = [double]$raw.WindowWidth }
            if ($raw.PSObject.Properties['WindowHeight'] -and $raw.WindowHeight) { $this.WinHeight = [double]$raw.WindowHeight }
        }
        else {
            $items = @($raw)
        }
        $i = 0
        foreach ($item in $items) {
            $tiles.Add($this.Factory.CreateFromJson($item, $i))
            $i++
        }
        return $tiles
    }
    [string] GetTheme() { return $this.Theme }
    [void] SetTheme([string]$theme) { $this.Theme = $theme }
    [double] GetWindowWidth() { return $this.WinWidth }
    [double] GetWindowHeight() { return $this.WinHeight }
    [void] SetWindowSize([double]$width, [double]$height) {
        $this.WinWidth  = $width
        $this.WinHeight = $height
    }
    [void] Save([System.Collections.Generic.List[TileModel]]$tiles) {
        $export = @($tiles | Sort-Object Order | ForEach-Object { $_.ToJsonObject() })
        $data = [PSCustomObject]@{
            Theme        = $this.Theme
            WindowWidth  = $this.WinWidth
            WindowHeight = $this.WinHeight
            Tiles        = $export
        }
        $data | ConvertTo-Json -Depth 4 | Set-Content -Path $this.JsonPath -Encoding UTF8
    }
}
'@))
# --- END: src\Parser\TileParser.ps1 ---

# --- INLINE: src\Services\EdgeLauncher.ps1 ---
. ([ScriptBlock]::Create(@'
class EdgeLauncher {
    hidden [string] $ExePath
    hidden [string] $ArgTemplate
    EdgeLauncher([hashtable]$edgeConfig) {
        $this.ArgTemplate = $edgeConfig.Arguments
        $this.ExePath = $this.ResolveExePath($edgeConfig.ExePath)
    }
    hidden [string] ResolveExePath([string]$configured) {
        if (-not [string]::IsNullOrWhiteSpace($configured) -and (Test-Path $configured)) {
            return $configured
        }
        $candidates = @(
            (Join-Path $env:ProgramFiles        'Microsoft\Edge\Application\msedge.exe'),
            (Join-Path ${env:ProgramFiles(x86)} 'Microsoft\Edge\Application\msedge.exe'),
            (Join-Path $env:LOCALAPPDATA        'Microsoft\Edge\Application\msedge.exe')
        )
        foreach ($c in $candidates) {
            if (-not [string]::IsNullOrWhiteSpace($c) -and (Test-Path $c)) { return $c }
        }
        $regPaths = @(
            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\msedge.exe',
            'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\App Paths\msedge.exe'
        )
        foreach ($rp in $regPaths) {
            try {
                $val = (Get-ItemProperty -Path $rp -ErrorAction Stop).'(default)'
                if (-not [string]::IsNullOrWhiteSpace($val) -and (Test-Path $val)) { return $val }
            } catch {}
        }
        return $null
    }
    [bool] IsAvailable() {
        return (-not [string]::IsNullOrWhiteSpace($this.ExePath)) -and (Test-Path $this.ExePath)
    }
    [void] Launch($tile) {
        if (-not $tile) { return }
        if (-not $this.IsAvailable()) {
            throw "Microsoft Edge est introuvable. Vérifiez le chemin dans la configuration (ExePath)."
        }
        if ([string]::IsNullOrWhiteSpace($tile.Profil)) {
            throw "Aucun profil n'est défini pour la tuile « $($tile.Title) »."
        }
        Write-Host "Launch edge profile: $($tile.Title)"
        $arguments = $this.ArgTemplate -f $tile.Profil, $tile.Url
        Start-Process -FilePath $this.ExePath -ArgumentList $arguments
    }
}
'@))
# --- END: src\Services\EdgeLauncher.ps1 ---

# --- INLINE: src\UI\UIManager.ps1 ---
. ([ScriptBlock]::Create(@'
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
class UIManager {
    [System.Windows.Window] $Window
    hidden [hashtable]      $Controls = @{}
    UIManager([string]$xamlPath) {
        $xaml = [System.IO.File]::ReadAllText($xamlPath, [System.Text.Encoding]::UTF8)
        $reader = [System.Xml.XmlReader]::Create([System.IO.StringReader]$xaml)
        $this.Window = [System.Windows.Markup.XamlReader]::Load($reader)
        $reader.Close()
        if ($null -eq $this.Window) {
            throw "Echec du chargement du XAML : $xamlPath"
        }
    }
    [object] Get([string]$name) {
        if (-not $this.Controls.ContainsKey($name)) {
            $this.Controls[$name] = $this.Window.FindName($name)
        }
        return $this.Controls[$name]
    }
    [void] SetTiles([System.Collections.IEnumerable]$tiles) {
        ($this.Get('TileList')).ItemsSource = $tiles
    }
    [void] Show() {
        $this.Window.WindowStartupLocation = [System.Windows.WindowStartupLocation]::CenterScreen
        $this.Window.Topmost = $true
        $this.Window.ShowDialog() | Out-Null
        $this.Window.Topmost = $false
    }
}
'@))
# --- END: src\UI\UIManager.ps1 ---

# --- INLINE: src\Features\DragDropManager.ps1 ---
. ([ScriptBlock]::Create(@'
class DragDropManager {
    hidden [object] $TileList
    hidden [object] $Controller
    hidden $StartPoint
    hidden $DraggedItem
    hidden [bool] $IsDragStarted
    hidden $DraggedContainer
    DragDropManager([object]$tileList, [object]$controller) {
        $this.TileList   = $tileList
        $this.Controller = $controller
    }
    [void] Enable() {
        $mgr = $this
        $this.TileList.AllowDrop = $true
        $this.TileList.Add_PreviewMouseLeftButtonDown({
            param($s, $e) $mgr.OnMouseDown($e)
        }.GetNewClosure())
        $this.TileList.Add_PreviewMouseMove({
            param($s, $e) $mgr.OnMouseMove($e)
        }.GetNewClosure())
        $this.TileList.Add_PreviewMouseLeftButtonUp({
            param($s, $e) $mgr.OnMouseUp($e)
        }.GetNewClosure())
        $this.TileList.Add_DragOver({
            param($s, $e) $mgr.OnDragOver($e)
        }.GetNewClosure())
        $this.TileList.Add_Drop({
            param($s, $e) $mgr.OnDrop($e)
        }.GetNewClosure())
    }
    hidden [void] OnMouseDown($e) {
        $this.StartPoint       = $e.GetPosition($null)
        $this.DraggedItem      = $this.GetTileFromPoint($e.OriginalSource)
        $this.DraggedContainer = $this.GetContainerFromPoint($e.OriginalSource)
        $this.IsDragStarted    = $false
    }
    hidden [void] OnMouseMove($e) {
        if ($e.LeftButton -ne [System.Windows.Input.MouseButtonState]::Pressed) { return }
        if ($null -eq $this.DraggedItem) { return }
        if ($this.IsDragStarted) { return }
        $pos = $e.GetPosition($null)
        $dx  = [Math]::Abs($pos.X - $this.StartPoint.X)
        $dy  = [Math]::Abs($pos.Y - $this.StartPoint.Y)
        if ($dx -lt [System.Windows.SystemParameters]::MinimumHorizontalDragDistance -and
            $dy -lt [System.Windows.SystemParameters]::MinimumVerticalDragDistance) {
            return
        }
        $this.IsDragStarted = $true
        $this.Controller.SetDragging($true)
        $this.SetDraggedOpacity(0.4)
        try {
            $data = New-Object System.Windows.DataObject('TileModel', $this.DraggedItem)
            [System.Windows.DragDrop]::DoDragDrop($this.TileList, $data, [System.Windows.DragDropEffects]::Move) | Out-Null
        }
        finally {
            $this.SetDraggedOpacity(1.0)
            $this.Controller.SetDragging($false)
            $this.DraggedItem      = $null
            $this.DraggedContainer = $null
        }
    }
    hidden [void] OnMouseUp($e) {
        if ($this.IsDragStarted) { $this.IsDragStarted = $false; return }
        $tile = $this.GetTileFromPoint($e.OriginalSource)
        if ($null -ne $tile) {
            $this.Controller.LaunchTile($tile)
        }
    }
    hidden [void] OnDragOver($e) {
        $e.Effects = [System.Windows.DragDropEffects]::Move
        $e.Handled = $true
        if ($null -eq $this.DraggedItem) { return }
        $target = $this.GetTileFromPoint($e.OriginalSource)
        if ($null -eq $target -or $target -eq $this.DraggedItem) { return }
        $toIndex = $this.Controller.IndexOfInView($target)
        if ($toIndex -lt 0) { return }
        $this.Controller.MoveTileInView($this.DraggedItem, $toIndex)
        $this.SetDraggedOpacity(0.4)
    }
    hidden [void] OnDrop($e) {
        if (-not $e.Data.GetDataPresent('TileModel')) { return }
        $this.Controller.CommitReorder()
        $e.Handled = $true
    }
    hidden [void] SetDraggedOpacity([double]$opacity) {
        if ($null -eq $this.DraggedItem) { return }
        $container = $this.TileList.ItemContainerGenerator.ContainerFromItem($this.DraggedItem)
        if ($null -ne $container) {
            $this.DraggedContainer = $container
            $container.Opacity = $opacity
        }
    }
    hidden [object] GetTileFromPoint($source) {
        $container = $this.GetContainerFromPoint($source)
        if ($null -eq $container) { return $null }
        return $container.DataContext
    }
    hidden [object] GetContainerFromPoint($source) {
        $current = $source
        while ($null -ne $current -and $current -isnot [System.Windows.Controls.ListBoxItem]) {
            if ($current -is [System.Windows.Media.Visual] -or
                $current -is [System.Windows.Media.Media3D.Visual3D]) {
                $current = [System.Windows.Media.VisualTreeHelper]::GetParent($current)
            } else {
                return $null
            }
        }
        return $current
    }
}
'@))
# --- END: src\Features\DragDropManager.ps1 ---

# --- INLINE: src\Controller\AppController.ps1 ---
. ([ScriptBlock]::Create(@'
class AppController {
    hidden [UIManager]    $UI
    hidden [TileParser]   $Parser
    hidden [TileFactory]  $Factory
    hidden [EdgeLauncher] $Launcher
    hidden [hashtable]    $Config
    hidden [string]       $Root
    hidden [ThemeManager] $Theme
    hidden [System.Collections.Generic.List[TileModel]] $Tiles
    hidden [System.Collections.ObjectModel.ObservableCollection[TileModel]] $View
    hidden [DragDropManager] $DragDrop
    hidden [bool]            $IsDragging
    AppController([UIManager]$ui, [TileParser]$parser, [TileFactory]$factory,
                  [EdgeLauncher]$launcher, [hashtable]$config, [string]$root, [ThemeManager]$theme) {
        $this.UI       = $ui
        $this.Parser   = $parser
        $this.Factory  = $factory
        $this.Launcher = $launcher
        $this.Config   = $config
        $this.Root     = $root
        $this.Theme    = $theme
    }
    [void] Initialize() {
        $this.Tiles = $this.Parser.Load()
        $this.Factory.SetTheme($this.Parser.GetTheme())
        foreach ($t in $this.Tiles) { $this.Factory.ApplyShades($t) }
        $this.Theme.Apply($this.UI.Window, $this.Parser.GetTheme())
        $w = $this.Parser.GetWindowWidth()
        $h = $this.Parser.GetWindowHeight()
        if ($w -ge $this.UI.Window.MinWidth)  { $this.UI.Window.Width  = $w }
        if ($h -ge $this.UI.Window.MinHeight) { $this.UI.Window.Height = $h }
        $this.View = [System.Collections.ObjectModel.ObservableCollection[TileModel]]::new()
        $this.UI.SetTiles($this.View)
        $this.RefreshTiles($this.Tiles)
        $this.BindEvents()
        ($this.UI.Get('SearchBox')).Focus() | Out-Null
    }
    hidden [void] RefreshTiles([System.Collections.IEnumerable]$tiles) {
        $this.View.Clear()
        foreach ($t in $tiles) { $this.View.Add($t) }
    }
    hidden [void] BindEvents() {
        $ctrl      = $this
        $win       = $this.UI.Window
        $searchBox = $this.UI.Get('SearchBox')
        $tileList  = $this.UI.Get('TileList')
        $win.Add_MouseLeftButtonDown({
            param($s, $e)
            $node = $e.OriginalSource
            while ($null -ne $node) {
                if ($node -is [System.Windows.Controls.Primitives.ButtonBase] -or
                    $node -is [System.Windows.Controls.Primitives.Thumb] -or
                    $node -is [System.Windows.Controls.ListBoxItem] -or
                    $node -is [System.Windows.Controls.TextBox] -or
                    $node -is [System.Windows.Controls.Primitives.ScrollBar]) {
                    return
                }
                if ($node -is [System.Windows.Media.Visual] -or
                    $node -is [System.Windows.Media.Media3D.Visual3D]) {
                    $node = [System.Windows.Media.VisualTreeHelper]::GetParent($node)
                } else { break }
            }
            try { $win.DragMove() } catch {}
        }.GetNewClosure())
        ($this.UI.Get('MinimizeButton')).Add_Click({
            $win.WindowState = [System.Windows.WindowState]::Minimized
        }.GetNewClosure())
        ($this.UI.Get('CloseButton')).Add_Click({ $win.Close() }.GetNewClosure())
        $win.Add_Closing({
            param($s, $e)
            try {
                if ($win.WindowState -eq [System.Windows.WindowState]::Normal) {
                    $ctrl.SaveWindowSize($win.Width, $win.Height)
                }
            } catch {}
        }.GetNewClosure())
        $searchBox.Add_TextChanged({ $ctrl.OnSearch() }.GetNewClosure())
        ($this.UI.Get('ClearButton')).Add_Click({
            $searchBox.Clear(); $searchBox.Focus()
        }.GetNewClosure())
        $searchBox.Add_KeyDown({ param($s, $e) $ctrl.OnSearchKeyDown($e) }.GetNewClosure())
        ($this.UI.Get('AddTileButton')).Add_Click({ $ctrl.OpenAddDialog() }.GetNewClosure())
        $themeBtn = $this.UI.Get('ThemeToggleButton')
        $themeBtn.Content = $this.Theme.ToggleIcon()
        $themeBtn.Add_Click({ $ctrl.ToggleTheme() }.GetNewClosure())
        $this.DragDrop = [DragDropManager]::new($tileList, $this)
        $this.DragDrop.Enable()
        try {
            $menu = $win.FindResource('TileContextMenu')
            if ($null -ne $menu) {
                foreach ($mi in $menu.Items) {
                    if ($mi -isnot [System.Windows.Controls.MenuItem]) { continue }
                    switch ($mi.Header) {
                        'Modifier' {
                            $mi.Add_Click({
                                param($s, $e)
                                $tile = $menu.PlacementTarget.DataContext
                                if ($null -ne $tile) { $ctrl.OpenEditDialog($tile) }
                            }.GetNewClosure())
                        }
                        'Supprimer' {
                            $mi.Add_Click({
                                param($s, $e)
                                $tile = $menu.PlacementTarget.DataContext
                                if ($null -ne $tile) { $ctrl.RemoveTile($tile) }
                            }.GetNewClosure())
                        }
                    }
                }
            }
        } catch {}
    }
    hidden [void] OnSearch() {
        $searchBox       = $this.UI.Get('SearchBox')
        $placeholderText = $this.UI.Get('PlaceholderText')
        $clearButton     = $this.UI.Get('ClearButton')
        $text            = $searchBox.Text
        $empty = [string]::IsNullOrWhiteSpace($text)
        $placeholderText.Visibility = if ($empty) { 'Visible' } else { 'Hidden' }
        $clearButton.Visibility     = if ($empty) { 'Hidden' }  else { 'Visible' }
        if ($empty) {
            $this.RefreshTiles($this.Tiles)
        } else {
            $filter = $text.ToLower()
            $filtered = @($this.Tiles | Where-Object { $_.Title.ToLower().Contains($filter) })
            $this.RefreshTiles($filtered)
        }
    }
    hidden [void] OnSearchKeyDown([System.Windows.Input.KeyEventArgs]$e) {
        $searchBox = $this.UI.Get('SearchBox')
        $tileList  = $this.UI.Get('TileList')
        switch ($e.Key) {
            'Return' {
                if ($tileList.Items.Count -gt 0) {
                    $tileList.SelectedIndex = 0
                    $tileList.Focus()
                }
                $e.Handled = $true
            }
            'Escape' {
                if ([string]::IsNullOrWhiteSpace($searchBox.Text)) {
                    $this.UI.Window.Close()
                } else {
                    $searchBox.Clear()
                    $this.RefreshTiles($this.Tiles)
                    $searchBox.Focus()
                }
                $e.Handled = $true
            }
        }
    }
    [void] LaunchTile([object]$tile) {
        if ($this.IsDragging) { return }
        if ($null -eq $tile)  { return }
        try {
            $this.Launcher.Launch($tile)
            $this.UI.Window.Close()
        }
        catch {
            [System.Windows.MessageBox]::Show(
                $_.Exception.Message, 'Lancement impossible',
                [System.Windows.MessageBoxButton]::OK,
                [System.Windows.MessageBoxImage]::Error) | Out-Null
        }
    }
    hidden [void] OpenAddDialog() {
        $this.ShowTileDialog($null)
    }
    [void] OpenEditDialog([object]$tile) {
        $this.ShowTileDialog($tile)
    }
    hidden [void] ShowTileDialog([object]$tile) {
        $ctrl     = $this
        $isEdit   = ($null -ne $tile)
        $xamlPath = Join-Path $this.Root $this.Config.Views.AddTile
        $addUI    = New-Object UIManager -ArgumentList $xamlPath
        $this.Theme.Apply($addUI.Window, $this.Theme.GetCurrent())
        $addWin   = $addUI.Window
        $titleBar = $addUI.Get('TitleBar')
        $titleBar.Add_MouseLeftButtonDown({
            param($s, $e)
            $node = $e.OriginalSource
            while ($null -ne $node -and $node -ne $s) {
                if ($node -is [System.Windows.Controls.Button]) { return }
                if ($node -is [System.Windows.Media.Visual]) {
                    $node = [System.Windows.Media.VisualTreeHelper]::GetParent($node)
                } else { break }
            }
            try { $addWin.DragMove() } catch {}
        }.GetNewClosure())
        if ($isEdit) {
            ($addUI.Get('DialogTitle')).Text = 'Modifier le profil'
            ($addUI.Get('SaveAddButton')).Content = 'Enregistrer'
            ($addUI.Get('TitleBox')).Text  = $tile.Title
            ($addUI.Get('ImageBox')).Text  = $tile.Image
            ($addUI.Get('ProfilBox')).Text = $tile.Profil
            ($addUI.Get('ColorBox')).Text  = $tile.Couleur
        }
        ($addUI.Get('CloseButton')).Add_Click({ $addWin.Close() }.GetNewClosure())
        Add-Type -AssemblyName System.Windows.Forms
        ($addUI.Get('PickColorButton')).Add_Click({
            $cd = New-Object System.Windows.Forms.ColorDialog
            if ($cd.ShowDialog() -eq 'OK') {
                ($addUI.Get('ColorBox')).Text = ('#{0:X2}{1:X2}{2:X2}' -f $cd.Color.R, $cd.Color.G, $cd.Color.B)
            }
        }.GetNewClosure())
        ($addUI.Get('BrowseImageButton')).Add_Click({
            $ofd = New-Object System.Windows.Forms.OpenFileDialog
            $ofd.Filter = 'Images|*.png;*.jpg;*.jpeg;*.bmp;*.gif'
            if ($ofd.ShowDialog() -eq 'OK') {
                ($addUI.Get('ImageBox')).Text = $ofd.FileName
            }
        }.GetNewClosure())
        ($addUI.Get('SaveAddButton')).Add_Click({
            $title = ($addUI.Get('TitleBox')).Text.Trim()
            if ([string]::IsNullOrWhiteSpace($title)) {
                [System.Windows.MessageBox]::Show('Le titre est requis', 'Erreur',
                    [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning) | Out-Null
                return
            }
            $img = ($addUI.Get('ImageBox')).Text.Trim()
            $prf = ($addUI.Get('ProfilBox')).Text.Trim()
            $col = ($addUI.Get('ColorBox')).Text.Trim()
            if ($isEdit) {
                $ctrl.UpdateTile($tile, $title, $img, $prf, $col)
            } else {
                $ctrl.AddTile($title, $img, $prf, $col)
            }
            $addUI.Window.Close()
        }.GetNewClosure())
        ($addUI.Get('CancelAddButton')).Add_Click({ $addUI.Window.Close() }.GetNewClosure())
        $urlLink = $addUI.Get('ProfileUrlLink')
        $urlLink.Add_MouseEnter({ param($s, $e) $s.FontWeight = [System.Windows.FontWeights]::Bold }.GetNewClosure())
        $urlLink.Add_MouseLeave({ param($s, $e) $s.FontWeight = [System.Windows.FontWeights]::Normal }.GetNewClosure())
        $urlLink.Add_MouseLeftButtonUp({
            param($s, $e)
            $ctrl.PlayCopyAnimation($addUI)
            $s.Dispatcher.BeginInvoke([System.Windows.Threading.DispatcherPriority]::Background,
                [action]{ try { [System.Windows.Clipboard]::SetText($s.Text) } catch {} }) | Out-Null
        }.GetNewClosure())
        $addUI.Window.Owner = $this.UI.Window
        $addUI.Window.ShowDialog() | Out-Null
    }
    hidden [void] PlayCopyAnimation([object]$addUI) {
        $icon      = $addUI.Get('CopyIcon')
        $iconScale = $addUI.Window.FindName('CopyIconScale')
        if ($null -eq $icon) { return }
        $ms = { param($n) [System.Windows.Duration]::new([timespan]::FromMilliseconds($n)) }
        $fadeIn = [System.Windows.Media.Animation.DoubleAnimation]::new(0, 1, (& $ms 90))
        $icon.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $fadeIn)
        if ($null -ne $iconScale) {
            $pop = [System.Windows.Media.Animation.DoubleAnimation]::new(0.3, 1.0, (& $ms 130))
            $pop.EasingFunction = [System.Windows.Media.Animation.BackEase]@{ EasingMode = 'EaseOut'; Amplitude = 0.6 }
            $iconScale.BeginAnimation([System.Windows.Media.ScaleTransform]::ScaleXProperty, $pop)
            $iconScale.BeginAnimation([System.Windows.Media.ScaleTransform]::ScaleYProperty, $pop)
        }
        $dirs = @(
            @(-14, -10), @(14, -10), @(-16, 2),
            @(16, 2),   @(-8, 12),  @(8, 12)
        )
        $timer = [System.Windows.Threading.DispatcherTimer]::new()
        $timer.Interval = [timespan]::FromMilliseconds(650)
        $win = $addUI.Window
        $timer.Add_Tick({
            $timer.Stop()
            $iconOut = [System.Windows.Media.Animation.DoubleAnimation]::new(1, 0, (& $ms 250))
            $icon.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $iconOut)
            if ($null -ne $iconScale) {
                $shrink = [System.Windows.Media.Animation.DoubleAnimation]::new(1.0, 1.6, (& $ms 250))
                $iconScale.BeginAnimation([System.Windows.Media.ScaleTransform]::ScaleXProperty, $shrink)
                $iconScale.BeginAnimation([System.Windows.Media.ScaleTransform]::ScaleYProperty, $shrink)
            }
            for ($i = 0; $i -lt 6; $i++) {
                $p  = $win.FindName("P$($i + 1)")
                $pt = $win.FindName("P$($i + 1)T")
                if ($null -eq $p -or $null -eq $pt) { continue }
                $dx = $dirs[$i][0]; $dy = $dirs[$i][1]
                $easeOut = [System.Windows.Media.Animation.CubicEase]@{ EasingMode = 'EaseOut' }
                $ax = [System.Windows.Media.Animation.DoubleAnimation]::new(0, $dx, (& $ms 350))
                $ax.EasingFunction = $easeOut
                $ay = [System.Windows.Media.Animation.DoubleAnimation]::new(0, $dy, (& $ms 350))
                $ay.EasingFunction = $easeOut
                $pt.BeginAnimation([System.Windows.Media.TranslateTransform]::XProperty, $ax)
                $pt.BeginAnimation([System.Windows.Media.TranslateTransform]::YProperty, $ay)
                $op = [System.Windows.Media.Animation.DoubleAnimationUsingKeyFrames]::new()
                $op.Duration = (& $ms 350)
                $op.KeyFrames.Add([System.Windows.Media.Animation.LinearDoubleKeyFrame]::new(1, [System.Windows.Media.Animation.KeyTime]::FromPercent(0.1))) | Out-Null
                $op.KeyFrames.Add([System.Windows.Media.Animation.LinearDoubleKeyFrame]::new(0, [System.Windows.Media.Animation.KeyTime]::FromPercent(1.0))) | Out-Null
                $p.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $op)
            }
        }.GetNewClosure())
        $timer.Start()
    }
    [void] AddTile([string]$title, [string]$image, [string]$profil, [string]$color) {
        $tile = $this.Factory.CreateNew($title, $image, $profil, $color, $null, $this.Tiles.Count)
        $this.Tiles.Add($tile)
        $this.Parser.Save($this.Tiles)
        $this.RefreshTiles($this.Tiles)
    }
    [void] UpdateTile([object]$tile, [string]$title, [string]$image, [string]$profil, [string]$color) {
        if ($null -eq $tile) { return }
        $updated = $this.Factory.CreateNew($title, $image, $profil, $color, $tile.Url, $tile.Order)
        $idx = $this.Tiles.IndexOf($tile)
        if ($idx -ge 0) { $this.Tiles[$idx] = $updated } else { $this.Tiles.Add($updated) }
        $this.Parser.Save($this.Tiles)
        $this.OnSearch()
    }
    [void] RemoveTile([object]$tile) {
        if ($null -eq $tile) { return }
        $answer = [System.Windows.MessageBox]::Show(
            "Supprimer la tuile « $($tile.Title) » ?", 'Confirmation',
            [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Question)
        if ($answer -ne [System.Windows.MessageBoxResult]::Yes) { return }
        $this.Tiles.Remove($tile) | Out-Null
        for ($i = 0; $i -lt $this.Tiles.Count; $i++) { $this.Tiles[$i].Order = $i }
        $this.Parser.Save($this.Tiles)
        $this.OnSearch()
    }
    [void] SetDragging([bool]$value) {
        $this.IsDragging = $value
    }
    [int] IndexOfInView([object]$item) {
        return $this.View.IndexOf($item)
    }
    [void] MoveTileInView([object]$item, [int]$toIndex) {
        $from = $this.View.IndexOf($item)
        if ($from -lt 0) { return }
        if ($toIndex -lt 0) { $toIndex = 0 }
        if ($toIndex -ge $this.View.Count) { $toIndex = $this.View.Count - 1 }
        if ($from -eq $toIndex) { return }
        $this.View.Move($from, $toIndex)
    }
    [void] CommitReorder() {
        $this.Tiles.Clear()
        for ($i = 0; $i -lt $this.View.Count; $i++) {
            $tile = $this.View[$i]
            $tile.Order = $i
            $this.Tiles.Add($tile)
        }
        $this.Parser.Save($this.Tiles)
    }
    [void] ToggleTheme() {
        $newTheme = $this.Theme.Toggle($this.UI.Window)
        ($this.UI.Get('ThemeToggleButton')).Content = $this.Theme.ToggleIcon()
        $this.Factory.SetTheme($newTheme)
        foreach ($t in $this.Tiles) { $this.Factory.ApplyShades($t) }
        $this.OnSearch()
        $this.Parser.SetTheme($newTheme)
        $this.Parser.Save($this.Tiles)
    }
    [void] SaveWindowSize([double]$width, [double]$height) {
        $this.Parser.SetWindowSize($width, $height)
        $this.Parser.Save($this.Tiles)
    }
}
'@))
# --- END: src\Controller\AppController.ps1 ---


# --- Configuration ---
$config   = Import-PowerShellDataFile -Path "$root\config\AppConfig.psd1"  # Lecture du .psd1
$jsonPath = Join-Path $root $config.DataFile                              # Chemin des données de tuiles

# --- Instanciation des dépendances (injection dans le contrôleur) ---
$factory  = [TileFactory]::new($config.ShadeFactors, $config.DefaultColor)   # Fabrique
$parser   = [TileParser]::new($jsonPath, $factory)                           # Parseur
$launcher = [EdgeLauncher]::new($config.Edge)                                # Lanceur Edge
$ui       = [UIManager]::new((Join-Path $root $config.Views.Selector))       # Interface principale
$theme    = [ThemeManager]::new('Dark')                                      # Gestionnaire de thèmes (thème réel lu depuis les données)

# Création du contrôleur avec toutes ses dépendances.
$controller = [AppController]::new($ui, $parser, $factory, $launcher, $config, $root, $theme)

# --- Démarrage de l'application ---
Write-Host "Launching Edge profil Selector"
$controller.Initialize()  # Charge les tuiles et branche les évènements
$ui.Show()                # Affiche la fenêtre principale
