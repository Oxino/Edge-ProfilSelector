<#
.SYNOPSIS
    Gestionnaire de thèmes (Dark / Light) de l'application.
.DESCRIPTION
    Définit deux palettes de couleurs (sombre et claire) et les applique à une
    fenêtre WPF en remplaçant un jeu de brosses nommées dans ses ressources.
    Les contrôles référencent ces brosses via {DynamicResource ...}, si bien que
    le simple remplacement des ressources bascule instantanément tout le thème,
    sans recharger l'interface.
#>
class ThemeManager {
    hidden [string] $Current   # Thème courant : 'Dark' ou 'Light'

    <#
    .SYNOPSIS
        Initialise le gestionnaire avec un thème de départ.
    .PARAMETER initial Nom du thème initial ('Dark' par défaut).
    #>
    ThemeManager([string]$initial) {
        $this.Current = if ($initial -eq 'Light') { 'Light' } else { 'Dark' }
    }

    <#
    .SYNOPSIS Retourne le nom du thème actuellement appliqué.
    #>
    [string] GetCurrent() { return $this.Current }

    # --- Helpers de construction de brosses -------------------------------

    hidden static [System.Windows.Media.Color] Col([string]$hex) {
        return [System.Windows.Media.ColorConverter]::ConvertFromString($hex)
    }

    # Brosse unie, avec opacité optionnelle (effet "verre")
    hidden static [System.Windows.Media.SolidColorBrush] Solid([string]$hex, [double]$opacity) {
        $b = [System.Windows.Media.SolidColorBrush]::new([ThemeManager]::Col($hex))
        $b.Opacity = $opacity
        $b.Freeze()
        return $b
    }

    # Dégradé diagonal à partir d'une liste de couleurs hexadécimales
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

    <#
    .SYNOPSIS
        Construit la palette (jeu de brosses) correspondant à un thème.
    .PARAMETER name 'Dark' ou 'Light'.
    #>
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
        # Thème sombre (par défaut)
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

    <#
    .SYNOPSIS
        Applique un thème à une fenêtre en remplaçant ses brosses nommées.
    .PARAMETER window Fenêtre WPF cible.
    .PARAMETER name   Thème à appliquer ('Dark' ou 'Light').
    #>
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

    <#
    .SYNOPSIS
        Bascule vers l'autre thème et l'applique.
    .PARAMETER window Fenêtre WPF à mettre à jour.
    .OUTPUTS Le nom du nouveau thème appliqué.
    #>
    [string] Toggle([System.Windows.Window]$window) {
        $next = if ($this.Current -eq 'Dark') { 'Light' } else { 'Dark' }
        $this.Apply($window, $next)
        return $next
    }

    <#
    .SYNOPSIS
        Retourne l'icône du bouton de bascule pour le thème courant.
    .DESCRIPTION
        En thème sombre on propose de passer au clair (soleil), et inversement
        (lune) en thème clair.
    #>
    [string] ToggleIcon() {
        if ($this.Current -eq 'Dark') { return [char]0x2600 }  # ☀ (aller vers clair)
        return [char]0x263E                                    # ☾ (aller vers sombre)
    }
}
