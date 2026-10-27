# Edge Profil Selector

Application Windows en PowerShell qui permet de choisir rapidement un profil
Microsoft Edge avant de l'ouvrir. Chaque profil est présenté sous forme de
tuile personnalisable.

## Fonctionnalités

- lancement d'un profil Edge et, si nécessaire, d'une URL associée ;
- recherche instantanée parmi les profils ;
- ajout, modification et suppression de tuiles ;
- réorganisation des tuiles par glisser-déposer ;
- menu contextuel sur chaque tuile ;
- thèmes sombre et clair, mémorisés entre les sessions ;
- mémorisation de la taille et de la position logique des tuiles ;
- lancement avec ou sans fenêtre PowerShell visible.

## Prérequis

- Windows avec PowerShell 5.1 ou une version compatible ;
- Microsoft Edge installé ;
- accès aux assemblies WPF fournies avec Windows.

Le chemin par défaut d'Edge est défini dans `config/AppConfig.psd1`. Adaptez
`Edge.ExePath` si Edge est installé dans un autre emplacement.

## Lancement

Depuis la racine du projet, deux modes sont disponibles :

### Mode développement

Lance directement les scripts source :

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\EdgeSelector.ps1
```

Ou double-cliquez sur `Launch.vbs` pour démarrer l'application sans fenêtre
console.

### Mode bundle

Le bundle regroupe les scripts PowerShell dans un seul fichier. Il est pratique
pour une utilisation quotidienne et limite les lectures de fichiers au démarrage.

```powershell
.\build.ps1
```

Puis lancez `Launch.Bundle.vbs`. Pour produire un bundle plus compact :

```powershell
.\build.ps1 -Minify
```

`EdgeSelector.Bundle.ps1` est généré automatiquement : ne le modifiez pas
directement. Régénérez-le après toute modification des fichiers de `src/` ou de
`EdgeSelector.ps1`.

## Configuration et données

- `config/AppConfig.psd1` contient le chemin d'Edge, les vues XAML, la couleur
	par défaut et les paramètres de génération des teintes ;
- `AppData.json` contient les tuiles, leur ordre, le thème et la taille de la
	fenêtre ;
- les chemins d'images enregistrés dans `AppData.json` doivent être valides sur
	la machine qui exécute l'application.

Une tuile contient notamment :

| Champ | Description |
| --- | --- |
| `Titre` | Nom affiché dans l'interface |
| `Image` | Chemin de l'image de la tuile |
| `Profil` | Répertoire du profil Edge, par exemple `Profile 7` |
| `Url` | URL ouverte avec le profil, facultative |
| `Couleur` | Couleur principale au format hexadécimal |
| `Order` | Position de la tuile |

## Structure du projet

```text
EdgeSelector.ps1          Point d'entrée source
EdgeSelector.Bundle.ps1   Point d'entrée généré pour la distribution
Launch.vbs                Lanceur silencieux du script source
Launch.Bundle.vbs         Lanceur silencieux du bundle
build.ps1                 Génération du bundle
AppData.json              Données et préférences utilisateur
config/                   Configuration générale
src/                      Modèles, contrôleur, services et gestionnaires UI
views/                    Interfaces WPF au format XAML
```

## Notes

Le projet est conçu pour Windows et dépend de l'interface WPF. Les fichiers
`.vbs` utilisent `ExecutionPolicy Bypass` uniquement pour ce lancement local ;
vérifiez les règles de sécurité de votre environnement avant de les distribuer.