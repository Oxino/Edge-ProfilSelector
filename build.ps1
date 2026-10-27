<#
.SYNOPSIS
    Génère un bundle mono-fichier de l'application (pour un lancement plus rapide).
.DESCRIPTION
    Lit le point d'entrée EdgeSelector.ps1 et remplace chaque ligne de
    dot-sourcing (. "$root\...ps1") par le contenu réel du fichier correspondant,
    encapsulé dans un ScriptBlock créé au runtime.

    IMPORTANT : les classes référencent des types WPF (System.Windows.*). Or,
    dans un fichier unique, PowerShell parse TOUT le fichier avant d'exécuter
    quoi que ce soit — donc avant le Add-Type des assemblies. Pour éviter les
    erreurs « Type introuvable » au parse-time, chaque classe inlinée est
    encapsulée dans [ScriptBlock]::Create(...) puis dot-sourcée : son parsing est
    ainsi différé au runtime, APRÈS le chargement des assemblies (exactement
    comme le dot-sourcing de fichiers séparés, mais sans I/O disque multiple).

    Les fichiers source restent séparés pour le développement ; seul le bundle
    est optimisé pour la production.
.EXAMPLE
    .\build.ps1
    Régénère EdgeSelector.Bundle.ps1 à partir des sources.
.EXAMPLE
    .\build.ps1 -Minify
    Régénère le bundle en retirant commentaires et lignes vides (plus léger).
#>
param(
    # Retire commentaires et lignes vides du code inliné (bundle minifié)
    [switch]$Minify
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot

<#
.SYNOPSIS
    Minifie du code PowerShell en retirant commentaires et lignes vides.
.DESCRIPTION
    Utilise le tokenizer officiel (PSParser) pour retirer UNIQUEMENT les
    véritables commentaires : les « # » situés dans des chaînes, des regex ou
    des here-strings sont préservés (une simple suppression textuelle les
    casserait). Les sauts de ligne sont conservés car ils servent de
    séparateurs d'instructions en PowerShell ; seules les lignes devenues vides
    (ex. lignes de commentaire supprimées) sont éliminées.
.PARAMETER code Code source à minifier.
#>
function Get-MinifiedCode {
    param([string]$code)

    $errors = $null
    $tokens = [System.Management.Automation.PSParser]::Tokenize($code, [ref]$errors)
    # Note : des « erreurs » de tokenisation surviennent car les classes
    # référencent des types WPF non résolus au moment du build. Elles sont
    # bénignes ici : le tokenizer identifie tout de même correctement les
    # commentaires (seule information dont on a besoin). On ne s'arrête donc pas.
    if ($null -eq $tokens -or $tokens.Count -eq 0) {
        return $code   # Sécurité : tokenisation totalement impossible
    }

    # Reconstruit le texte en sautant les tokens de type commentaire.
    $lines = $code -split "`r?`n"
    # Collecte les plages (ligne/colonne) des commentaires à retirer
    $comments = $tokens | Where-Object { $_.Type -eq 'Comment' }

    # Retire chaque commentaire de la ligne correspondante (commentaires mono-ligne)
    # en repartant de la fin pour ne pas décaler les indices.
    foreach ($c in ($comments | Sort-Object StartLine, Start -Descending)) {
        $idx = $c.StartLine - 1
        if ($idx -lt 0 -or $idx -ge $lines.Count) { continue }
        if ($c.StartLine -eq $c.EndLine) {
            # Commentaire sur une seule ligne : on coupe à partir de sa colonne
            $col = $c.StartColumn - 1
            if ($col -ge 0 -and $col -le $lines[$idx].Length) {
                $lines[$idx] = $lines[$idx].Substring(0, $col)
            }
        }
        else {
            # Commentaire bloc <# ... #> : on neutralise les lignes couvertes
            for ($l = $c.StartLine; $l -le $c.EndLine; $l++) {
                $li = $l - 1
                if ($li -ge 0 -and $li -lt $lines.Count) { $lines[$li] = '' }
            }
        }
    }

    # Supprime les espaces de fin et les lignes devenues vides
    $result = $lines |
        ForEach-Object { $_.TrimEnd() } |
        Where-Object { $_.Trim().Length -gt 0 }

    return ($result -join "`r`n")
}

$entry  = Join-Path $root 'EdgeSelector.ps1'
$output = Join-Path $root 'EdgeSelector.Bundle.ps1'

if (-not (Test-Path $entry)) {
    throw "Point d'entrée introuvable : $entry"
}

# Lit le script d'entrée en UTF-8
$lines = [System.IO.File]::ReadAllLines($entry, [System.Text.Encoding]::UTF8)

$sb = [System.Text.StringBuilder]::new()
[void]$sb.AppendLine('# ============================================================')
[void]$sb.AppendLine('#  FICHIER GÉNÉRÉ AUTOMATIQUEMENT PAR build.ps1 - NE PAS ÉDITER')
[void]$sb.AppendLine('#  Bundle mono-fichier pour un démarrage optimisé.')
[void]$sb.AppendLine("#  Généré le : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
[void]$sb.AppendLine('# ============================================================')
[void]$sb.AppendLine('')

# Regex détectant une ligne de dot-sourcing : . "$root\chemin\fichier.ps1"
$dotSource = '^\s*\.\s+"\$root\\(?<path>[^"]+\.ps1)"'
$inlined = 0

foreach ($line in $lines) {
    $m = [regex]::Match($line, $dotSource)
    if ($m.Success) {
        $relPath  = $m.Groups['path'].Value
        $filePath = Join-Path $root $relPath
        if (-not (Test-Path $filePath)) {
            throw "Fichier référencé introuvable : $filePath"
        }
        $content = [System.IO.File]::ReadAllText($filePath, [System.Text.Encoding]::UTF8).TrimEnd()

        # Minifie éventuellement le code inliné (retrait commentaires + lignes vides)
        if ($Minify) { $content = Get-MinifiedCode $content }

        # Encapsule le code dans un here-string littéral (@' ... '@) exécuté via
        # [ScriptBlock]::Create : le parsing des classes (et de leurs types WPF)
        # est différé au runtime, après le Add-Type. (Aucun fichier source ne
        # débute une ligne par la séquence de fin '@, le here-string est donc sûr.)
        [void]$sb.AppendLine("# --- INLINE: $relPath ---")
        [void]$sb.AppendLine('. ([ScriptBlock]::Create(@''')
        [void]$sb.AppendLine($content)
        [void]$sb.AppendLine('''@))')
        [void]$sb.AppendLine("# --- END: $relPath ---")
        [void]$sb.AppendLine('')
        $inlined++
    }
    else {
        [void]$sb.AppendLine($line)
    }
}

# Écriture du bundle en UTF-8 avec BOM (accents corrects sous PS 5.1)
$utf8Bom = [System.Text.UTF8Encoding]::new($true)
[System.IO.File]::WriteAllText($output, $sb.ToString(), $utf8Bom)

Write-Host "Bundle généré : $output" -ForegroundColor Green
Write-Host "  $inlined fichier(s) source inliné(s)." -ForegroundColor Green
