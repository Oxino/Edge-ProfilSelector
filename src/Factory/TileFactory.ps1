class TileFactory {
    hidden [hashtable] $ShadeFactors
    hidden [string]    $DefaultColor
    hidden [string]    $Theme         # Thème courant ('Dark' / 'Light') pour le calcul des teintes

    TileFactory([hashtable]$shadeFactors, [string]$defaultColor) {
        $this.ShadeFactors = $shadeFactors
        $this.DefaultColor = $defaultColor
        $this.Theme        = 'Dark'
    }

    <#
    .SYNOPSIS Définit le thème utilisé pour générer les teintes des tuiles.
    #>
    [void] SetTheme([string]$theme) { $this.Theme = $theme }

    <#
    .SYNOPSIS
        (Re)calcule les teintes de dégradé (Color1/Color2) d'une tuile selon
        le thème courant, à partir de sa couleur de référence.
    #>
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
        $this.ApplyShades($tile)   # Teintes calculées selon le thème courant
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