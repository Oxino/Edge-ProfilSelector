<#
.SYNOPSIS
    Gère le glisser-déposer (drag & drop) des tuiles dans la ListBox pour
    permettre leur repositionnement, avec réorganisation visuelle en direct.
.DESCRIPTION
    Branche les évènements souris de la ListBox. Pendant le survol (DragOver),
    la tuile déplacée est repositionnée en temps réel dans la vue observable :
    les autres tuiles s'écartent pour lui faire de la place. La tuile déplacée
    est rendue semi-transparente (effet "fantôme"). Au dépôt, le nouvel ordre
    est validé et persisté par le contrôleur.
#>
class DragDropManager {
    hidden [object] $TileList     # La ListBox contenant les tuiles
    hidden [object] $Controller   # Contrôleur (AppController) pour déléguer le réordonnancement
    hidden $StartPoint            # Point de départ du clic (pour le seuil de drag)
    hidden $DraggedItem           # Tuile en cours de déplacement (TileModel)
    hidden [bool] $IsDragStarted  # Vrai si un drag a réellement démarré (vs simple clic)
    hidden $DraggedContainer      # ListBoxItem de la tuile déplacée (pour l'estompage)

    <#
    .SYNOPSIS
        Initialise le gestionnaire avec la ListBox et le contrôleur.
    #>
    DragDropManager([object]$tileList, [object]$controller) {
        $this.TileList   = $tileList
        $this.Controller = $controller
    }

    <#
    .SYNOPSIS
        Active le drag & drop en branchant les évènements souris sur la ListBox.
    #>
    [void] Enable() {
        $mgr = $this                       # Capture pour les closures
        $this.TileList.AllowDrop = $true   # Autorise la ListBox à recevoir un drop

        # Mémorise la position et la tuile au moment du clic gauche
        $this.TileList.Add_PreviewMouseLeftButtonDown({
            param($s, $e) $mgr.OnMouseDown($e)
        }.GetNewClosure())

        # Démarre le drag dès que la souris se déplace suffisamment
        $this.TileList.Add_PreviewMouseMove({
            param($s, $e) $mgr.OnMouseMove($e)
        }.GetNewClosure())

        # Bouton relâché : si aucun drag n'a eu lieu, c'est un vrai clic -> lancement
        $this.TileList.Add_PreviewMouseLeftButtonUp({
            param($s, $e) $mgr.OnMouseUp($e)
        }.GetNewClosure())

        # Pendant le survol : réorganise les tuiles en direct (aperçu animé)
        $this.TileList.Add_DragOver({
            param($s, $e) $mgr.OnDragOver($e)
        }.GetNewClosure())

        # Traite le dépôt (validation et persistance du nouvel ordre)
        $this.TileList.Add_Drop({
            param($s, $e) $mgr.OnDrop($e)
        }.GetNewClosure())
    }

    <#
    .SYNOPSIS
        Mémorise le point de départ et la tuile sous le curseur.
    #>
    hidden [void] OnMouseDown($e) {
        $this.StartPoint       = $e.GetPosition($null)
        $this.DraggedItem      = $this.GetTileFromPoint($e.OriginalSource)
        $this.DraggedContainer = $this.GetContainerFromPoint($e.OriginalSource)
        $this.IsDragStarted    = $false   # Réinitialise : aucun drag n'a encore eu lieu
    }

    <#
    .SYNOPSIS
        Démarre l'opération de drag si le bouton gauche est maintenu et que
        le seuil de déplacement système est franchi.
    #>
    hidden [void] OnMouseMove($e) {
        # Rien à faire si le bouton n'est pas maintenu ou si aucune tuile n'est visée
        if ($e.LeftButton -ne [System.Windows.Input.MouseButtonState]::Pressed) { return }
        if ($null -eq $this.DraggedItem) { return }
        if ($this.IsDragStarted) { return }   # Un drag est déjà en cours

        $pos = $e.GetPosition($null)
        $dx  = [Math]::Abs($pos.X - $this.StartPoint.X)
        $dy  = [Math]::Abs($pos.Y - $this.StartPoint.Y)

        # Seuil minimal (évite de déclencher un drag sur un simple clic)
        if ($dx -lt [System.Windows.SystemParameters]::MinimumHorizontalDragDistance -and
            $dy -lt [System.Windows.SystemParameters]::MinimumVerticalDragDistance) {
            return
        }

        # Un drag a réellement démarré (ce n'est pas un simple clic)
        $this.IsDragStarted = $true
        $this.Controller.SetDragging($true)   # Bloque le lancement d'Edge

        # Rend la tuile déplacée semi-transparente (effet "fantôme" en place)
        $this.SetDraggedOpacity(0.4)

        try {
            $data = New-Object System.Windows.DataObject('TileModel', $this.DraggedItem)
            [System.Windows.DragDrop]::DoDragDrop($this.TileList, $data, [System.Windows.DragDropEffects]::Move) | Out-Null
        }
        finally {
            # Restaure l'opacité et réactive le lancement d'Edge
            $this.SetDraggedOpacity(1.0)
            $this.Controller.SetDragging($false)
            $this.DraggedItem      = $null
            $this.DraggedContainer = $null
        }
    }

    <#
    .SYNOPSIS
        Gère le relâchement du bouton gauche : lance le profil uniquement s'il
        s'agit d'un vrai clic (aucun drag n'a démarré).
    .DESCRIPTION
        Pendant un drag, l'appel bloquant DoDragDrop consomme le relâchement du
        bouton : cette méthode n'est donc appelée que pour un clic simple.
    #>
    hidden [void] OnMouseUp($e) {
        # Si un drag a eu lieu, ce n'est pas un clic : on ne lance rien
        if ($this.IsDragStarted) { $this.IsDragStarted = $false; return }

        # Retrouve la tuile sous le curseur au moment du relâchement
        $tile = $this.GetTileFromPoint($e.OriginalSource)
        if ($null -ne $tile) {
            $this.Controller.LaunchTile($tile)
        }
    }

    <#
    .SYNOPSIS
        Réorganise les tuiles en direct pendant le survol : déplace la tuile
        tirée vers la position de la tuile survolée (les autres s'écartent).
    .PARAMETER e Arguments de l'évènement DragOver.
    #>
    hidden [void] OnDragOver($e) {
        $e.Effects = [System.Windows.DragDropEffects]::Move
        $e.Handled = $true
        if ($null -eq $this.DraggedItem) { return }

        # Tuile actuellement survolée
        $target = $this.GetTileFromPoint($e.OriginalSource)
        if ($null -eq $target -or $target -eq $this.DraggedItem) { return }

        # Index cible dans la vue observable
        $toIndex = $this.Controller.IndexOfInView($target)
        if ($toIndex -lt 0) { return }

        # Déplace la tuile tirée à cette position (la ListBox repositionne les autres)
        $this.Controller.MoveTileInView($this.DraggedItem, $toIndex)

        # WPF régénère le conteneur après un Move : on ré-applique la transparence
        $this.SetDraggedOpacity(0.4)
    }

    <#
    .SYNOPSIS
        Valide et persiste le nouvel ordre au moment du dépôt.
    #>
    hidden [void] OnDrop($e) {
        if (-not $e.Data.GetDataPresent('TileModel')) { return }
        $this.Controller.CommitReorder()   # Persistance de l'ordre affiché
        $e.Handled = $true
    }

    # =====================================================================
    #  Helpers
    # =====================================================================

    <#
    .SYNOPSIS
        Applique une opacité au conteneur (ListBoxItem) de la tuile déplacée,
        en récupérant le conteneur courant (régénéré par WPF après un Move).
    .PARAMETER opacity Opacité à appliquer (0..1).
    #>
    hidden [void] SetDraggedOpacity([double]$opacity) {
        if ($null -eq $this.DraggedItem) { return }
        $container = $this.TileList.ItemContainerGenerator.ContainerFromItem($this.DraggedItem)
        if ($null -ne $container) {
            $this.DraggedContainer = $container
            $container.Opacity = $opacity
        }
    }

    <#
    .SYNOPSIS
        Remonte l'arbre visuel depuis l'élément source pour retrouver la tuile
        (DataContext du ListBoxItem) située sous le curseur.
    .PARAMETER source Élément visuel d'origine de l'évènement.
    .OUTPUTS Le TileModel correspondant, ou $null si hors d'une tuile.
    #>
    hidden [object] GetTileFromPoint($source) {
        $container = $this.GetContainerFromPoint($source)
        if ($null -eq $container) { return $null }
        return $container.DataContext   # Le TileModel associé à ce conteneur
    }

    <#
    .SYNOPSIS
        Remonte l'arbre visuel pour retrouver le ListBoxItem sous le curseur.
    .PARAMETER source Élément visuel d'origine de l'évènement.
    .OUTPUTS Le ListBoxItem correspondant, ou $null si hors d'une tuile.
    #>
    hidden [object] GetContainerFromPoint($source) {
        $current = $source
        # Remonte tant qu'on n'a pas atteint un ListBoxItem (ou la racine)
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
