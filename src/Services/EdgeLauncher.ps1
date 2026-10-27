class EdgeLauncher {
    hidden [string] $ExePath
    hidden [string] $ArgTemplate

    EdgeLauncher([hashtable]$edgeConfig) {
        $this.ArgTemplate = $edgeConfig.Arguments
        # Résout le chemin d'Edge : chemin configuré s'il existe, sinon détection auto
        $this.ExePath = $this.ResolveExePath($edgeConfig.ExePath)
    }

    <#
    .SYNOPSIS
        Détermine le chemin de l'exécutable Edge.
    .DESCRIPTION
        Utilise le chemin configuré s'il est valide. Sinon, recherche Edge dans
        les emplacements standards (Program Files / x86 / LocalAppData) puis dans
        le registre Windows (App Paths). Retourne $null si Edge est introuvable.
    .PARAMETER configured Chemin issu de la configuration.
    #>
    hidden [string] ResolveExePath([string]$configured) {
        # 1) Chemin configuré valide -> on le garde
        if (-not [string]::IsNullOrWhiteSpace($configured) -and (Test-Path $configured)) {
            return $configured
        }

        # 2) Emplacements standards d'installation
        $candidates = @(
            (Join-Path $env:ProgramFiles        'Microsoft\Edge\Application\msedge.exe'),
            (Join-Path ${env:ProgramFiles(x86)} 'Microsoft\Edge\Application\msedge.exe'),
            (Join-Path $env:LOCALAPPDATA        'Microsoft\Edge\Application\msedge.exe')
        )
        foreach ($c in $candidates) {
            if (-not [string]::IsNullOrWhiteSpace($c) -and (Test-Path $c)) { return $c }
        }

        # 3) Registre Windows (App Paths)
        $regPaths = @(
            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\msedge.exe',
            'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\App Paths\msedge.exe'
        )
        foreach ($rp in $regPaths) {
            try {
                $val = (Get-ItemProperty -Path $rp -ErrorAction Stop).'(default)'
                if (-not [string]::IsNullOrWhiteSpace($val) -and (Test-Path $val)) { return $val }
            } catch {}
        }

        # 4) Introuvable
        return $null
    }

    <#
    .SYNOPSIS Indique si un exécutable Edge valide a été trouvé.
    #>
    [bool] IsAvailable() {
        return (-not [string]::IsNullOrWhiteSpace($this.ExePath)) -and (Test-Path $this.ExePath)
    }

    <#
    .SYNOPSIS
        Lance Edge avec le profil de la tuile.
    .DESCRIPTION
        Valide la présence de l'exécutable et du profil avant de lancer. En cas
        de problème, lève une exception explicite (interceptée par l'appelant
        pour informer l'utilisateur).
    #>
    [void] Launch($tile) {
        if (-not $tile) { return }

        # Vérifie que l'exécutable Edge existe
        if (-not $this.IsAvailable()) {
            throw "Microsoft Edge est introuvable. Vérifiez le chemin dans la configuration (ExePath)."
        }
        # Vérifie qu'un profil est renseigné
        if ([string]::IsNullOrWhiteSpace($tile.Profil)) {
            throw "Aucun profil n'est défini pour la tuile « $($tile.Title) »."
        }

        Write-Host "Launch edge profile: $($tile.Title)"
        $arguments = $this.ArgTemplate -f $tile.Profil, $tile.Url
        Start-Process -FilePath $this.ExePath -ArgumentList $arguments
    }
}