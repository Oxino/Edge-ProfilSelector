<# ################################
#Check profil path at edge://profile-internals/
        edge://version/
        
BackgroundColor at [System.Drawing.Color]::
        https://learn.microsoft.com/en-us/dotnet/api/system.drawing.color



https://www.cloudappie.nl/create-configure-edge-profiles-powershell/

################################ #>


Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

Set-Location $PSScriptRoot
$xaml = Get-Content -Path .\TilesSelectorUI.xaml -Raw

# Load XAML
$reader = [System.Xml.XmlReader]::Create([System.IO.StringReader] $xaml)
$window = [System.Windows.Markup.XamlReader]::Load($reader)
$reader.Close()

# Verify window was loaded correctly
if ($null -eq $window) {
    Write-Error "Failed to load XAML. Window is null."
    exit 1
}

# Elements
$searchBox = $window.FindName("SearchBox")
$tileList = $window.FindName("TileList")
$placeholderText = $window.FindName("PlaceholderText")
$clearButton = $window.FindName("ClearButton")
$addButton = $window.FindName("AddTileButton")

# Load data from JSON file
$jsonPath = Join-Path $PSScriptRoot "TilesData.json"
$jsonData = Get-Content -Path $jsonPath -Raw | ConvertFrom-Json

# Ensure it's always an array
if ($jsonData -is [System.Management.Automation.PSCustomObject]) {
    $jsonData = @($jsonData)
}

#Parsing Item JSON
$data = @()
foreach ($item in $jsonData) {
    # helper to compute shade (factor >1 = lighter, <1 = darker)
    function Get-Shade($hex, $factor) {
        try {
            $h = $hex.TrimStart('#')
            if ($h.Length -eq 3) { $h = ($h.ToCharArray() | ForEach-Object { "$_$_" }) -join '' }
            $r = [Convert]::ToInt32($h.Substring(0,2),16)
            $g = [Convert]::ToInt32($h.Substring(2,2),16)
            $b = [Convert]::ToInt32($h.Substring(4,2),16)
            $nr = [math]::Round([math]::Min(255, [math]::Max(0, $r * $factor)))
            $ng = [math]::Round([math]::Min(255, [math]::Max(0, $g * $factor)))
            $nb = [math]::Round([math]::Min(255, [math]::Max(0, $b * $factor)))
            return ('#{0:X2}{1:X2}{2:X2}' -f $nr, $ng, $nb)
        }
        catch { return $hex }
    }

    $primary = $item.Couleur
    $lighter = Get-Shade $primary 1.15
    $darker  = Get-Shade $primary 0.78

    $data += [PSCustomObject]@{
        Title = $item.Titre
        Image = $item.Image
        Profil = $item.Profil
		Url = $item.Url
        Couleur = $primary
        Color1 = $lighter
        Color2 = $darker
    }
}

# Initial Load
$tileList.ItemsSource = $data

# Auto-focus on search box
$searchBox.Focus() | Out-Null

# Handle window drag move
$window.Add_MouseLeftButtonDown({
    try {
        if ($_.OriginalSource -ne $tileList -and $_.OriginalSource -ne $searchBox) {
            $window.DragMove()
        }
    }
    catch {
        # Ignore drag move errors
    }
})

# Focus search box on click outside tiles
$tileList.Add_PreviewMouseDown({
    # Only prevent focus if clicking on the list itself, not on items
    if ($_.OriginalSource -eq $tileList -or $_.OriginalSource.GetType().Name -eq "ListBoxItem") {
        $searchBox.Focus()
        $_.Handled = $false
    }
})

# Add tile button handler - open add dialog
$addButton.Add_Click({
    $addXaml = Get-Content -Path (Join-Path $PSScriptRoot "TilesAddUI.xaml") -Raw
    $r = [System.Xml.XmlReader]::Create([System.IO.StringReader] $addXaml)
    $addWindow = [System.Windows.Markup.XamlReader]::Load($r)
    $r.Close()

    $titleBox = $addWindow.FindName('TitleBox')
    $imageBox = $addWindow.FindName('ImageBox')
    $profilBox = $addWindow.FindName('ProfilBox')
    $colorBox = $addWindow.FindName('ColorBox')
    $pickColor = $addWindow.FindName('PickColorButton')
    $browseImage = $addWindow.FindName('BrowseImageButton')
    $saveBtn = $addWindow.FindName('SaveAddButton')
    $cancelBtn = $addWindow.FindName('CancelAddButton')

    Add-Type -AssemblyName System.Windows.Forms

    $pickColor.Add_Click({
        $cd = New-Object System.Windows.Forms.ColorDialog
        if ($cd.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $sel = $cd.Color
            $hex = ('#{0:X2}{1:X2}{2:X2}' -f $sel.R, $sel.G, $sel.B)
            $colorBox.Text = $hex
        }
    })

    $browseImage.Add_Click({
        $ofd = New-Object System.Windows.Forms.OpenFileDialog
        $ofd.Filter = 'Images|*.png;*.jpg;*.jpeg;*.bmp;*.gif'
        if ($ofd.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $imageBox.Text = $ofd.FileName
        }
    })

    # Save handler
    $saveBtn.Add_Click({
        $t = $titleBox.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($t)) {
            [System.Windows.MessageBox]::Show('Le titre est requis','Erreur',[System.Windows.MessageBoxButton]::OK,[System.Windows.MessageBoxImage]::Warning) | Out-Null
            return
        }
        $img = $imageBox.Text.Trim()
        $prof = $profilBox.Text.Trim()
        $col = $colorBox.Text.Trim()
        if (-not $col) { $col = '#0078D4' }

        # Load existing JSON and append
        $jsonPathLocal = Join-Path $PSScriptRoot 'TilesData.json'
        $j = Get-Content -Path $jsonPathLocal -Raw | ConvertFrom-Json
        if ($j -is [System.Management.Automation.PSCustomObject]) { $j = @($j) }
        $new = [PSCustomObject]@{ Titre = $t; Image = $img; Profil = $prof; Couleur = $col }
        $j += $new
        $j | ConvertTo-Json -Depth 4 | Set-Content -Path $jsonPathLocal -Encoding UTF8

        # Update in-memory $data (compute shades)
        function Get-ShadeLocal($hex, $factor) {
            try {
                $h = $hex.TrimStart('#')
                if ($h.Length -eq 3) { $h = ($h.ToCharArray() | ForEach-Object { "$_$_" }) -join '' }
                $r = [Convert]::ToInt32($h.Substring(0,2),16)
                $g = [Convert]::ToInt32($h.Substring(2,2),16)
                $b = [Convert]::ToInt32($h.Substring(4,2),16)
                $nr = [math]::Round([math]::Min(255, [math]::Max(0, $r * $factor)))
                $ng = [math]::Round([math]::Min(255, [math]::Max(0, $g * $factor)))
                $nb = [math]::Round([math]::Min(255, [math]::Max(0, $b * $factor)))
                return ('#{0:X2}{1:X2}{2:X2}' -f $nr, $ng, $nb)
            } catch { return $hex }
        }

        $primary = $col
        $lighter = Get-ShadeLocal $primary 1.15
        $darker = Get-ShadeLocal $primary 0.78

        $newObj = [PSCustomObject]@{
            Title = $t
            Image = $img
            Profil = $prof
            Couleur = $primary
            Color1 = $lighter
            Color2 = $darker
        }
        $data = $data + ,$newObj

        $tileList.ItemsSource = $data
        try { $addWindow.Close() } catch { }
    })

    $cancelBtn.Add_Click({ try { $addWindow.Close() } catch { } })

    $addWindow.Owner = $window
    $addWindow.ShowDialog() | Out-Null
})

# Search Logic
$searchBox.Add_TextChanged({
    $filter = $searchBox.Text.ToLower()
    
    # Show/Hide placeholder and clear button based on text
    if ([string]::IsNullOrWhiteSpace($searchBox.Text)) {
        $placeholderText.Visibility = [System.Windows.Visibility]::Visible
        $clearButton.Visibility = [System.Windows.Visibility]::Hidden
    } else {
        $placeholderText.Visibility = [System.Windows.Visibility]::Hidden
        $clearButton.Visibility = [System.Windows.Visibility]::Visible
    }
    
    # Filter tiles
    if ([string]::IsNullOrWhiteSpace($filter)) {
        $tileList.ItemsSource = $data
    } else {
        $filtered = @($data | Where-Object { $_.Title.ToLower().Contains($filter) })
        $tileList.ItemsSource = $filtered
    }
})

# Clear button click handler
$clearButton.Add_Click({
    $searchBox.Clear()
    $searchBox.Focus()
})

# Enter Key Handler
$searchBox.Add_KeyDown({
    if ($_.Key -eq [System.Windows.Input.Key]::Return) {
        if ($tileList.Items.Count -gt 0) {
            $tileList.SelectedIndex = 0
            $tileList.Focus()
        }
        $_.Handled = $true
    }
})

# Escape Key Handler - clear search and restore items
$searchBox.Add_KeyDown({
    if ($_.Key -eq [System.Windows.Input.Key]::Escape) {
        if ([string]::IsNullOrWhiteSpace($searchBox.Text)) {
            # If search is empty, close the window
            try { $window.Close() } catch { }
        }
        else {
            # Otherwise clear the search and restore items
            $searchBox.Clear()
            $placeholderText.Visibility = [System.Windows.Visibility]::Visible
            $clearButton.Visibility = [System.Windows.Visibility]::Hidden
            $tileList.ItemsSource = $data
            $searchBox.Focus()
        }
        $_.Handled = $true
    }
})
# Selection Logic
$tileList.Add_SelectionChanged({
    if ($tileList.SelectedItem) {
        Write-Host "Selected: $($tileList.SelectedItem.Title)"
        #$tileList.ItemsSource
        
        try { 
           $profil= Search-EdgeProfil -source $tileList.ItemsSource -title $tileList.SelectedItem.Title     
           
           Launch-EdgePorfil -profil $profil

           $window.Close()
         } catch { }
    }
})


function Launch-EdgePorfil($profil) {
    Write-Host "Launch edge profile ! $($profil.Title)"
    #$tileCong = Search-TileConfig -InternalName $InternalName
    #"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe" --profile-directory="Profile 13"
    #edge flag : https://peter.sh/experiments/chromium-command-line-switches/
    
	
	
    Start-Process -FilePath "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe" -ArgumentList "--profile-directory=`"$($profil.Profil)`" $($profil.Url)"#--no-first-run --no-default-browser-check --flag-switches-begin --flag-switches-end --site-per-process"
    
    #$Global:form.Dispose()
    #$Global:form.Close()
}
function Search-EdgeProfil($source,$title) {
    return $source | ? { $_.Title -eq $title } | select -First 1 
}



# Display Window and bring to foreground
Write-Host "Launching Edge profil Selector"

# Force window to foreground
$window.WindowStartupLocation = [System.Windows.WindowStartupLocation]::CenterScreen
$window.Topmost = $true
$window.ShowDialog() | Out-Null
$window.Topmost = $false
