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