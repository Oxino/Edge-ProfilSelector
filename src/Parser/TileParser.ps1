class TileParser {
    hidden [string]      $JsonPath
    hidden [TileFactory] $Factory
    hidden [string]      $Theme      # Thème persisté ('Dark' / 'Light')
    hidden [double]      $WinWidth   # Largeur de fenêtre persistée (0 = non défini)
    hidden [double]      $WinHeight  # Hauteur de fenêtre persistée (0 = non défini)

    TileParser([string]$jsonPath, [TileFactory]$factory) {
        $this.JsonPath  = $jsonPath
        $this.Factory   = $factory
        $this.Theme     = 'Dark'
        $this.WinWidth  = 0
        $this.WinHeight = 0
    }

    <#
    .SYNOPSIS
        Charge les tuiles depuis le fichier et mémorise le thème enregistré.
    .DESCRIPTION
        Prend en charge le nouveau format { Theme, Tiles } ainsi que l'ancien
        format (simple tableau de tuiles) pour la rétro-compatibilité.
    #>
    [System.Collections.Generic.List[TileModel]] Load() {
        $tiles = [System.Collections.Generic.List[TileModel]]::new()

        if (-not (Test-Path $this.JsonPath)) { return $tiles }

        $raw = Get-Content -Path $this.JsonPath -Raw | ConvertFrom-Json

        # Détermine la source des tuiles selon le format lu
        $items = $null
        if ($raw -is [System.Array]) {
            # Ancien format : tableau de tuiles directement
            $items = $raw
        }
        elseif ($null -ne $raw.PSObject.Properties['Tiles']) {
            # Nouveau format : objet { Theme, Tiles }
            $items = $raw.Tiles
            if ($raw.Theme) { $this.Theme = $raw.Theme }
            # Taille de fenêtre persistée (optionnelle)
            if ($raw.PSObject.Properties['WindowWidth']  -and $raw.WindowWidth)  { $this.WinWidth  = [double]$raw.WindowWidth }
            if ($raw.PSObject.Properties['WindowHeight'] -and $raw.WindowHeight) { $this.WinHeight = [double]$raw.WindowHeight }
        }
        else {
            # Objet unique (une seule tuile) -> on l'encapsule
            $items = @($raw)
        }

        $i = 0
        foreach ($item in $items) {
            $tiles.Add($this.Factory.CreateFromJson($item, $i))
            $i++
        }
        return $tiles
    }

    <#
    .SYNOPSIS Retourne le thème mémorisé lors du dernier chargement.
    #>
    [string] GetTheme() { return $this.Theme }

    <#
    .SYNOPSIS Met à jour le thème à persister (au prochain Save).
    #>
    [void] SetTheme([string]$theme) { $this.Theme = $theme }

    <#
    .SYNOPSIS Retourne la largeur de fenêtre persistée (0 si non définie).
    #>
    [double] GetWindowWidth() { return $this.WinWidth }

    <#
    .SYNOPSIS Retourne la hauteur de fenêtre persistée (0 si non définie).
    #>
    [double] GetWindowHeight() { return $this.WinHeight }

    <#
    .SYNOPSIS Met à jour la taille de fenêtre à persister (au prochain Save).
    #>
    [void] SetWindowSize([double]$width, [double]$height) {
        $this.WinWidth  = $width
        $this.WinHeight = $height
    }

    <#
    .SYNOPSIS
        Enregistre le thème courant, la taille de fenêtre et les tuiles (JSON).
    #>
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