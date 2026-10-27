<#using namespace System.Windows
using namespace System.Windows.Input
using module ..\UI\UIManager.psm1
using module ..\Parser\TileParser.psm1
using module ..\Factory\TileFactory.psm1
using module ..\Launcher\EdgeLauncher.psm1
using module ..\Model\TileModel.psm1
#>

<#
.SYNOPSIS
    Contrôleur principal de l'application Edge Profil Selector.
.DESCRIPTION
    Orchestre l'interface (UIManager), le chargement/enregistrement des tuiles
    (TileParser), leur création (TileFactory) et le lancement des profils Edge
    (EdgeLauncher). Gère également les évènements utilisateur (recherche,
    sélection, ajout de tuile).
#>
class AppController {
    # --- Dépendances injectées ---
    hidden [UIManager]    $UI        # Gestionnaire d'interface (fenêtre principale)
    hidden [TileParser]   $Parser    # Chargement / sauvegarde des tuiles (JSON)
    hidden [TileFactory]  $Factory   # Fabrique de nouvelles tuiles
    hidden [EdgeLauncher] $Launcher  # Lancement des profils Edge
    hidden [hashtable]    $Config    # Configuration de l'application
    hidden [string]       $Root      # Répertoire racine du projet
    hidden [ThemeManager] $Theme     # Gestionnaire de thèmes Dark/Light
    hidden [System.Collections.Generic.List[TileModel]] $Tiles  # Collection maître (ordre de référence)
    hidden [System.Collections.ObjectModel.ObservableCollection[TileModel]] $View  # Vue liée à la ListBox (réordonnancement en direct)
    hidden [DragDropManager] $DragDrop   # Gestionnaire de glisser-déposer des tuiles
    hidden [bool]            $IsDragging # Vrai pendant un drag (bloque le lancement d'Edge)

    <#
    .SYNOPSIS
        Initialise le contrôleur avec ses dépendances.
    .PARAMETER ui       Gestionnaire d'interface.
    .PARAMETER parser   Parseur de tuiles.
    .PARAMETER factory  Fabrique de tuiles.
    .PARAMETER launcher Lanceur de profils Edge.
    .PARAMETER config   Table de configuration.
    .PARAMETER root     Répertoire racine du projet.
    #>
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

    <#
    .SYNOPSIS
        Point d'entrée : charge les tuiles, les affiche et branche les évènements.
    #>
    [void] Initialize() {
        $this.Tiles = $this.Parser.Load()        # Chargement des tuiles depuis la source
        # Synchronise la fabrique sur le thème persisté AVANT tout calcul de teintes
        $this.Factory.SetTheme($this.Parser.GetTheme())
        # Recalcule les teintes des tuiles déjà chargées selon le thème persisté
        foreach ($t in $this.Tiles) { $this.Factory.ApplyShades($t) }
        # Applique le thème persisté (lu depuis le fichier de données par le parser)
        $this.Theme.Apply($this.UI.Window, $this.Parser.GetTheme())
        # Restaure la taille de fenêtre sauvegardée (si présente et valide)
        $w = $this.Parser.GetWindowWidth()
        $h = $this.Parser.GetWindowHeight()
        if ($w -ge $this.UI.Window.MinWidth)  { $this.UI.Window.Width  = $w }
        if ($h -ge $this.UI.Window.MinHeight) { $this.UI.Window.Height = $h }
        # Vue observable liée UNE SEULE FOIS à la ListBox : ses Move sont
        # répercutés (et animés) par WPF -> réorganisation visuelle en direct.
        $this.View = [System.Collections.ObjectModel.ObservableCollection[TileModel]]::new()
        $this.UI.SetTiles($this.View)
        $this.RefreshTiles($this.Tiles)          # Affichage initial
        $this.BindEvents()                       # Abonnement aux évènements UI
        ($this.UI.Get('SearchBox')).Focus() | Out-Null  # Focus sur la recherche
    }

    <#
    .SYNOPSIS
        Met à jour la liste des tuiles affichées dans l'interface.
    .DESCRIPTION
        Remplit la vue observable SANS changer sa référence (indispensable pour
        conserver la liaison et les animations de la ListBox).
    .PARAMETER tiles Collection de tuiles à afficher.
    #>
    hidden [void] RefreshTiles([System.Collections.IEnumerable]$tiles) {
        $this.View.Clear()
        foreach ($t in $tiles) { $this.View.Add($t) }
    }

    <#
    .SYNOPSIS
        Abonne les gestionnaires d'évènements aux contrôles de l'interface.
    #>
    hidden [void] BindEvents() {
        # Capture des références pour les closures (les scriptblocks WPF perdent $this)
        $ctrl      = $this
        $win       = $this.UI.Window
        $searchBox = $this.UI.Get('SearchBox')
        $tileList  = $this.UI.Get('TileList')

        # Déplacement de la fenêtre depuis N'IMPORTE OÙ (fond, titre, marges...),
        # SAUF depuis les zones interactives : boutons, tuiles (repositionnables),
        # champ de recherche. On remonte l'arbre visuel depuis l'élément cliqué :
        # si on rencontre un contrôle interactif, on laisse passer le clic ;
        # sinon on démarre le déplacement de la fenêtre.
        $win.Add_MouseLeftButtonDown({
            param($s, $e)
            $node = $e.OriginalSource
            while ($null -ne $node) {
                if ($node -is [System.Windows.Controls.Primitives.ButtonBase] -or
                    $node -is [System.Windows.Controls.Primitives.Thumb] -or
                    $node -is [System.Windows.Controls.ListBoxItem] -or
                    $node -is [System.Windows.Controls.TextBox] -or
                    $node -is [System.Windows.Controls.Primitives.ScrollBar]) {
                    return   # Zone interactive : ne pas déplacer la fenêtre
                }
                if ($node -is [System.Windows.Media.Visual] -or
                    $node -is [System.Windows.Media.Media3D.Visual3D]) {
                    $node = [System.Windows.Media.VisualTreeHelper]::GetParent($node)
                } else { break }
            }
            try { $win.DragMove() } catch {}
        }.GetNewClosure())

        # Bouton Réduire : minimise la fenêtre
        ($this.UI.Get('MinimizeButton')).Add_Click({
            $win.WindowState = [System.Windows.WindowState]::Minimized
        }.GetNewClosure())

        # Bouton Fermer : ferme l'application
        ($this.UI.Get('CloseButton')).Add_Click({ $win.Close() }.GetNewClosure())

        # À la fermeture : persiste la taille courante de la fenêtre (si elle est
        # dans un état normal, pas minimisée/maximisée).
        $win.Add_Closing({
            param($s, $e)
            try {
                if ($win.WindowState -eq [System.Windows.WindowState]::Normal) {
                    $ctrl.SaveWindowSize($win.Width, $win.Height)
                }
            } catch {}
        }.GetNewClosure())

        # Filtrage en temps réel lors de la saisie
        $searchBox.Add_TextChanged({ $ctrl.OnSearch() }.GetNewClosure())

        # Bouton d'effacement de la recherche
        ($this.UI.Get('ClearButton')).Add_Click({
            $searchBox.Clear(); $searchBox.Focus()
        }.GetNewClosure())

        # Gestion des touches (Entrée / Échap) dans la recherche
        $searchBox.Add_KeyDown({ param($s, $e) $ctrl.OnSearchKeyDown($e) }.GetNewClosure())
        # NB : le lancement du profil n'est PAS branché sur SelectionChanged
        # (qui se déclenche dès l'enfoncement du bouton) mais sur un vrai clic
        # détecté par le DragDropManager (voir OnMouseUp -> LaunchTile).
        # Ouverture de la boîte de dialogue d'ajout
        ($this.UI.Get('AddTileButton')).Add_Click({ $ctrl.OpenAddDialog() }.GetNewClosure())

        # Bouton de bascule de thème (Dark <-> Light) : met à jour l'icône
        $themeBtn = $this.UI.Get('ThemeToggleButton')
        $themeBtn.Content = $this.Theme.ToggleIcon()
        $themeBtn.Add_Click({ $ctrl.ToggleTheme() }.GetNewClosure())

        # Active le glisser-déposer pour repositionner les tuiles
        $this.DragDrop = [DragDropManager]::new($tileList, $this)
        $this.DragDrop.Enable()

        # Menu contextuel des tuiles (clic droit) : Modifier / Supprimer.
        # Le ContextMenu est une ressource partagée : on lit la tuile ciblée via
        # PlacementTarget.DataContext au moment du clic sur un élément du menu.
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

    <#
    .SYNOPSIS
        Filtre les tuiles en fonction du texte saisi dans la recherche.
    #>
    hidden [void] OnSearch() {
        $searchBox       = $this.UI.Get('SearchBox')
        $placeholderText = $this.UI.Get('PlaceholderText')
        $clearButton     = $this.UI.Get('ClearButton')
        $text            = $searchBox.Text

        # Affiche le placeholder et masque le bouton "clear" si la zone est vide
        $empty = [string]::IsNullOrWhiteSpace($text)
        $placeholderText.Visibility = if ($empty) { 'Visible' } else { 'Hidden' }
        $clearButton.Visibility     = if ($empty) { 'Hidden' }  else { 'Visible' }

        if ($empty) {
            $this.RefreshTiles($this.Tiles)   # Aucune recherche : on affiche tout
        } else {
            # Filtrage insensible à la casse sur le titre
            $filter = $text.ToLower()
            $filtered = @($this.Tiles | Where-Object { $_.Title.ToLower().Contains($filter) })
            $this.RefreshTiles($filtered)
        }
    }

    <#
    .SYNOPSIS
        Gère les touches Entrée et Échap dans la zone de recherche.
    .PARAMETER e Arguments de l'évènement clavier.
    #>
    hidden [void] OnSearchKeyDown([System.Windows.Input.KeyEventArgs]$e) {
        $searchBox = $this.UI.Get('SearchBox')
        $tileList  = $this.UI.Get('TileList')

        switch ($e.Key) {
            'Return' {
                # Entrée : sélectionne la première tuile de la liste
                if ($tileList.Items.Count -gt 0) {
                    $tileList.SelectedIndex = 0
                    $tileList.Focus()
                }
                $e.Handled = $true
            }
            'Escape' {
                # Échap : vide la recherche, ou ferme la fenêtre si déjà vide
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

    <#
    .SYNOPSIS
        Lance le profil Edge associé à une tuile puis ferme la fenêtre.
    .DESCRIPTION
        Appelé par le DragDropManager uniquement sur un vrai clic (bouton relâché
        au même endroit, sans déplacement), pas sur l'enfoncement du bouton.
    .PARAMETER tile Tuile (TileModel) dont le profil doit être lancé.
    #>
    [void] LaunchTile([object]$tile) {
        # Pendant un drag, on ne doit jamais lancer Edge
        if ($this.IsDragging) { return }
        if ($null -eq $tile)  { return }

        try {
            $this.Launcher.Launch($tile)   # Ouvre Edge avec le profil
            $this.UI.Window.Close()        # Fermeture uniquement si le lancement a réussi
        }
        catch {
            # Informe l'utilisateur et laisse la fenêtre ouverte pour réessayer
            [System.Windows.MessageBox]::Show(
                $_.Exception.Message, 'Lancement impossible',
                [System.Windows.MessageBoxButton]::OK,
                [System.Windows.MessageBoxImage]::Error) | Out-Null
        }
    }

    <#
    .SYNOPSIS
        Ouvre la boîte de dialogue d'ajout d'une nouvelle tuile.
    #>
    hidden [void] OpenAddDialog() {
        $this.ShowTileDialog($null)
    }

    <#
    .SYNOPSIS
        Ouvre la boîte de dialogue d'édition d'une tuile existante.
    .PARAMETER tile Tuile (TileModel) à modifier.
    #>
    [void] OpenEditDialog([object]$tile) {
        $this.ShowTileDialog($tile)
    }

    <#
    .SYNOPSIS
        Affiche la boîte de dialogue d'ajout ou d'édition d'une tuile.
    .DESCRIPTION
        Si $tile vaut $null, la boîte fonctionne en mode « ajout ». Sinon elle
        est pré-remplie avec les valeurs de la tuile et fonctionne en mode
        « édition » (le bouton enregistre les modifications sur place).
    .PARAMETER tile Tuile à modifier, ou $null pour un ajout.
    #>
    hidden [void] ShowTileDialog([object]$tile) {
        $ctrl     = $this
        $isEdit   = ($null -ne $tile)
        $xamlPath = Join-Path $this.Root $this.Config.Views.AddTile
        $addUI    = New-Object UIManager -ArgumentList $xamlPath

        # Applique le thème courant à la boîte de dialogue (cohérence visuelle)
        $this.Theme.Apply($addUI.Window, $this.Theme.GetCurrent())

        # Fenêtre sans bordure (WindowStyle=None) : on la déplace en glissant
        # sur la barre de titre personnalisée.
        $addWin   = $addUI.Window
        $titleBar = $addUI.Get('TitleBar')
        $titleBar.Add_MouseLeftButtonDown({
            param($s, $e)
            # Ne pas déplacer si le clic vient d'un bouton (ex : la croix),
            # sinon DragMove capture la souris et le Click du bouton n'a pas lieu.
            $node = $e.OriginalSource
            while ($null -ne $node -and $node -ne $s) {
                if ($node -is [System.Windows.Controls.Button]) { return }
                if ($node -is [System.Windows.Media.Visual]) {
                    $node = [System.Windows.Media.VisualTreeHelper]::GetParent($node)
                } else { break }
            }
            try { $addWin.DragMove() } catch {}
        }.GetNewClosure())

        # Adapte les libellés et pré-remplit les champs en mode édition
        if ($isEdit) {
            ($addUI.Get('DialogTitle')).Text = 'Modifier le profil'
            ($addUI.Get('SaveAddButton')).Content = 'Enregistrer'
            ($addUI.Get('TitleBox')).Text  = $tile.Title
            ($addUI.Get('ImageBox')).Text  = $tile.Image
            ($addUI.Get('ProfilBox')).Text = $tile.Profil
            ($addUI.Get('ColorBox')).Text  = $tile.Couleur
        }

        # Bouton de fermeture (croix) de la barre de titre
        ($addUI.Get('CloseButton')).Add_Click({ $addWin.Close() }.GetNewClosure())

        Add-Type -AssemblyName System.Windows.Forms

        # Sélecteur de couleur : ouvre un ColorDialog et écrit la valeur hex
        ($addUI.Get('PickColorButton')).Add_Click({
            $cd = New-Object System.Windows.Forms.ColorDialog
            # Comparaison par nom d'enum ('OK') pour éviter un littéral de type
            # résolu au parse-time (System.Windows.Forms n'est chargé qu'ici).
            if ($cd.ShowDialog() -eq 'OK') {
                ($addUI.Get('ColorBox')).Text = ('#{0:X2}{1:X2}{2:X2}' -f $cd.Color.R, $cd.Color.G, $cd.Color.B)
            }
        }.GetNewClosure())

        # Sélecteur d'image : ouvre un OpenFileDialog filtré sur les images
        ($addUI.Get('BrowseImageButton')).Add_Click({
            $ofd = New-Object System.Windows.Forms.OpenFileDialog
            $ofd.Filter = 'Images|*.png;*.jpg;*.jpeg;*.bmp;*.gif'
            if ($ofd.ShowDialog() -eq 'OK') {
                ($addUI.Get('ImageBox')).Text = $ofd.FileName
            }
        }.GetNewClosure())

        # Bouton "Enregistrer" : valide puis crée ou met à jour la tuile
        ($addUI.Get('SaveAddButton')).Add_Click({
            $title = ($addUI.Get('TitleBox')).Text.Trim()
            # Le titre est obligatoire
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

        # Bouton "Annuler" : ferme sans enregistrer
        ($addUI.Get('CancelAddButton')).Add_Click({ $addUI.Window.Close() }.GetNewClosure())

        # Lien "edge://profile-internals/" : gras au survol, copie + animation au clic
        $urlLink = $addUI.Get('ProfileUrlLink')
        $urlLink.Add_MouseEnter({ param($s, $e) $s.FontWeight = [System.Windows.FontWeights]::Bold }.GetNewClosure())
        $urlLink.Add_MouseLeave({ param($s, $e) $s.FontWeight = [System.Windows.FontWeights]::Normal }.GetNewClosure())
        $urlLink.Add_MouseLeftButtonUp({
            param($s, $e)
            # Animation d'abord (réactivité immédiate), puis copie du texte
            $ctrl.PlayCopyAnimation($addUI)
            $s.Dispatcher.BeginInvoke([System.Windows.Threading.DispatcherPriority]::Background,
                [action]{ try { [System.Windows.Clipboard]::SetText($s.Text) } catch {} }) | Out-Null
        }.GetNewClosure())

        # Affichage modal centré sur la fenêtre principale
        $addUI.Window.Owner = $this.UI.Window
        $addUI.Window.ShowDialog() | Out-Null
    }

    <#
    .SYNOPSIS
        Joue l'animation "copié" : une disquette apparaît (petit rebond) puis
        explose en particules qui se dispersent avant de disparaître.
    .PARAMETER addUI Gestionnaire d'interface de la boîte de dialogue.
    #>
    hidden [void] PlayCopyAnimation([object]$addUI) {
        $icon      = $addUI.Get('CopyIcon')
        $iconScale = $addUI.Window.FindName('CopyIconScale')
        if ($null -eq $icon) { return }

        # Fonctions d'accès rapides
        $ms = { param($n) [System.Windows.Duration]::new([timespan]::FromMilliseconds($n)) }

        # --- Phase 1 : apparition immédiate de l'icône avec un petit rebond ---
        $fadeIn = [System.Windows.Media.Animation.DoubleAnimation]::new(0, 1, (& $ms 90))
        $icon.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $fadeIn)

        if ($null -ne $iconScale) {
            $pop = [System.Windows.Media.Animation.DoubleAnimation]::new(0.3, 1.0, (& $ms 130))
            $pop.EasingFunction = [System.Windows.Media.Animation.BackEase]@{ EasingMode = 'EaseOut'; Amplitude = 0.6 }
            $iconScale.BeginAnimation([System.Windows.Media.ScaleTransform]::ScaleXProperty, $pop)
            $iconScale.BeginAnimation([System.Windows.Media.ScaleTransform]::ScaleYProperty, $pop)
        }

        # --- Phase 2 : explosion en particules (juste après l'apparition) ---
        # Positions de dispersion (dx, dy) pour les 6 particules, en éventail
        $dirs = @(
            @(-14, -10), @(14, -10), @(-16, 2),
            @(16, 2),   @(-8, 12),  @(8, 12)
        )

        # Court délai pour laisser voir la disquette avant qu'elle n'explose
        $timer = [System.Windows.Threading.DispatcherTimer]::new()
        $timer.Interval = [timespan]::FromMilliseconds(650)
        $win = $addUI.Window
        $timer.Add_Tick({
            $timer.Stop()

            # L'icône disparaît en rétrécissant (comme si elle éclatait)
            $iconOut = [System.Windows.Media.Animation.DoubleAnimation]::new(1, 0, (& $ms 250))
            $icon.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $iconOut)
            if ($null -ne $iconScale) {
                $shrink = [System.Windows.Media.Animation.DoubleAnimation]::new(1.0, 1.6, (& $ms 250))
                $iconScale.BeginAnimation([System.Windows.Media.ScaleTransform]::ScaleXProperty, $shrink)
                $iconScale.BeginAnimation([System.Windows.Media.ScaleTransform]::ScaleYProperty, $shrink)
            }

            # Les particules jaillissent puis s'effacent
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

                # Apparition rapide puis disparition (flash) via keyframes d'opacité
                $op = [System.Windows.Media.Animation.DoubleAnimationUsingKeyFrames]::new()
                $op.Duration = (& $ms 350)
                $op.KeyFrames.Add([System.Windows.Media.Animation.LinearDoubleKeyFrame]::new(1, [System.Windows.Media.Animation.KeyTime]::FromPercent(0.1))) | Out-Null
                $op.KeyFrames.Add([System.Windows.Media.Animation.LinearDoubleKeyFrame]::new(0, [System.Windows.Media.Animation.KeyTime]::FromPercent(1.0))) | Out-Null
                $p.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $op)
            }
        }.GetNewClosure())
        $timer.Start()
    }

    <#
    .SYNOPSIS
        Crée, ajoute et persiste une nouvelle tuile.
    .PARAMETER title  Titre de la tuile.
    .PARAMETER image  Chemin de l'image.
    .PARAMETER profil Nom du profil Edge.
    .PARAMETER color  Couleur au format hexadécimal.
    #>
    [void] AddTile([string]$title, [string]$image, [string]$profil, [string]$color) {
        # Crée la tuile via la fabrique (index = position en fin de liste)
        $tile = $this.Factory.CreateNew($title, $image, $profil, $color, $null, $this.Tiles.Count)
        $this.Tiles.Add($tile)          # Ajout en mémoire
        $this.Parser.Save($this.Tiles)  # Persistance sur disque
        $this.RefreshTiles($this.Tiles) # Rafraîchissement de l'affichage
    }

    <#
    .SYNOPSIS
        Met à jour une tuile existante et persiste les modifications.
    .PARAMETER tile   Tuile (TileModel) à modifier.
    .PARAMETER title  Nouveau titre.
    .PARAMETER image  Nouveau chemin d'image.
    .PARAMETER profil Nouveau nom de profil Edge.
    .PARAMETER color  Nouvelle couleur au format hexadécimal.
    #>
    [void] UpdateTile([object]$tile, [string]$title, [string]$image, [string]$profil, [string]$color) {
        if ($null -eq $tile) { return }

        # Recrée une tuile à partir des nouvelles valeurs (recalcule les nuances)
        # en conservant l'ordre et l'URL d'origine.
        $updated = $this.Factory.CreateNew($title, $image, $profil, $color, $tile.Url, $tile.Order)

        # Remplace la tuile dans la liste maître (même position)
        $idx = $this.Tiles.IndexOf($tile)
        if ($idx -ge 0) { $this.Tiles[$idx] = $updated } else { $this.Tiles.Add($updated) }

        $this.Parser.Save($this.Tiles)   # Persistance sur disque
        $this.OnSearch()                 # Rafraîchit en respectant la recherche courante
    }

    <#
    .SYNOPSIS
        Supprime une tuile après confirmation et persiste la nouvelle liste.
    .PARAMETER tile Tuile (TileModel) à supprimer.
    #>
    [void] RemoveTile([object]$tile) {
        if ($null -eq $tile) { return }

        # Demande de confirmation avant suppression
        $answer = [System.Windows.MessageBox]::Show(
            "Supprimer la tuile « $($tile.Title) » ?", 'Confirmation',
            [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Question)
        if ($answer -ne [System.Windows.MessageBoxResult]::Yes) { return }

        $this.Tiles.Remove($tile) | Out-Null   # Retrait de la liste maître

        # Renumérote l'ordre pour rester contigu
        for ($i = 0; $i -lt $this.Tiles.Count; $i++) { $this.Tiles[$i].Order = $i }

        $this.Parser.Save($this.Tiles)   # Persistance sur disque
        $this.OnSearch()                 # Rafraîchit en respectant la recherche courante
    }

    <#
    .SYNOPSIS
        Active ou désactive l'état "drag en cours".
    .DESCRIPTION
        Appelé par le DragDropManager pour empêcher OnTileSelected de lancer
        Edge (et fermer la fenêtre) pendant un glisser-déposer.
    .PARAMETER value Vrai au début du drag, faux à la fin.
    #>
    [void] SetDragging([bool]$value) {
        $this.IsDragging = $value
    }

    <#
    .SYNOPSIS
        Retourne l'index d'une tuile dans la vue observable (ou -1).
    #>
    [int] IndexOfInView([object]$item) {
        return $this.View.IndexOf($item)
    }

    <#
    .SYNOPSIS
        Déplace une tuile dans la vue pendant le drag (aperçu animé en direct).
    .DESCRIPTION
        Utilise ObservableCollection.Move : la ListBox repositionne les tuiles
        en temps réel (les autres s'écartent). Rien n'est persisté ici.
    .PARAMETER item    Tuile déplacée.
    .PARAMETER toIndex Index de destination dans la vue.
    #>
    [void] MoveTileInView([object]$item, [int]$toIndex) {
        $from = $this.View.IndexOf($item)
        if ($from -lt 0) { return }
        if ($toIndex -lt 0) { $toIndex = 0 }
        if ($toIndex -ge $this.View.Count) { $toIndex = $this.View.Count - 1 }
        if ($from -eq $toIndex) { return }
        $this.View.Move($from, $toIndex)   # Déplacement répercuté par WPF
    }

    <#
    .SYNOPSIS
        Valide et persiste l'ordre courant de la vue (fin de drag).
    #>
    [void] CommitReorder() {
        # Réaligne la liste maître sur l'ordre affiché et renumérote Order
        $this.Tiles.Clear()
        for ($i = 0; $i -lt $this.View.Count; $i++) {
            $tile = $this.View[$i]
            $tile.Order = $i
            $this.Tiles.Add($tile)
        }
        $this.Parser.Save($this.Tiles)   # Persistance sur disque
    }

    <#
    .SYNOPSIS
        Bascule entre le thème sombre et le thème clair.
    .DESCRIPTION
        Applique le nouveau thème à la fenêtre principale (les brosses
        dynamiques mettent à jour toute l'interface instantanément) et actualise
        l'icône du bouton de bascule.
    #>
    [void] ToggleTheme() {
        $newTheme = $this.Theme.Toggle($this.UI.Window)
        ($this.UI.Get('ThemeToggleButton')).Content = $this.Theme.ToggleIcon()

        # Recalcule les teintes des tuiles pour qu'elles s'harmonisent au thème
        $this.Factory.SetTheme($newTheme)
        foreach ($t in $this.Tiles) { $this.Factory.ApplyShades($t) }
        # Régénère la vue pour forcer les bindings Color1/Color2 à se réévaluer
        $this.OnSearch()

        # Persiste le nouveau thème dans le fichier de données
        $this.Parser.SetTheme($newTheme)
        $this.Parser.Save($this.Tiles)
    }

    <#
    .SYNOPSIS
        Mémorise et persiste la taille courante de la fenêtre.
    .PARAMETER width  Largeur à sauvegarder.
    .PARAMETER height Hauteur à sauvegarder.
    #>
    [void] SaveWindowSize([double]$width, [double]$height) {
        $this.Parser.SetWindowSize($width, $height)
        $this.Parser.Save($this.Tiles)
    }
}