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

    <#
    .SYNOPSIS
        Mélange deux couleurs hexadécimales selon un ratio.
    .PARAMETER hex     Couleur de base.
    .PARAMETER withHex Couleur avec laquelle mélanger.
    .PARAMETER ratio   Proportion de $withHex (0 = $hex, 1 = $withHex).
    #>
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

    <#
    .SYNOPSIS
        Génère les deux teintes de dégradé d'une tuile adaptées au thème.
    .DESCRIPTION
        - Thème sombre : teintes vives (couleur éclaircie puis assombrie) qui
          ressortent sur un fond foncé.
        - Thème clair : teintes pastel (couleur mélangée vers le blanc) plus
          douces et harmonieuses sur un fond clair.
    .PARAMETER hex     Couleur de référence de la tuile.
    .PARAMETER theme   'Dark' ou 'Light'.
    .PARAMETER lighter Facteur d'éclaircissement (thème sombre).
    .PARAMETER darker  Facteur d'assombrissement (thème sombre).
    .OUTPUTS Tableau [Color1, Color2].
    #>
    static [string[]] GetThemeShades([string]$hex, [string]$theme, [double]$lighter, [double]$darker) {
        if ($theme -eq 'Light') {
            # Version pastel : on rapproche la couleur du blanc pour l'adoucir
            $soft = [ColorHelper]::Mix($hex, '#FFFFFF', 0.55)
            return @(
                [ColorHelper]::GetShade($soft, 1.06),
                [ColorHelper]::GetShade($soft, 0.90)
            )
        }
        # Thème sombre : couleurs vives
        return @(
            [ColorHelper]::GetShade($hex, $lighter),
            [ColorHelper]::GetShade($hex, $darker)
        )
    }
}