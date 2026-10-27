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
. "$root\src\UI\ColorHelper.ps1"          # Utilitaires de couleur
. "$root\src\UI\ThemeManager.ps1"         # Gestionnaire de thèmes Dark/Light
. "$root\src\Models\TileModel.ps1"        # Modèle de données d'une tuile
. "$root\src\Factory\TileFactory.ps1"     # Fabrique de tuiles
. "$root\src\Parser\TileParser.ps1"       # Chargement / sauvegarde JSON
. "$root\src\Services\EdgeLauncher.ps1"   # Lancement des profils Edge
. "$root\src\UI\UIManager.ps1"            # Gestionnaire d'interface WPF
. "$root\src\Features\DragDropManager.ps1" # Glisser-déposer des tuiles
. "$root\src\Controller\AppController.ps1" # Contrôleur principal

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