Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

class UIManager {
    [System.Windows.Window] $Window
    hidden [hashtable]      $Controls = @{}

    UIManager([string]$xamlPath) {
        # Lecture explicite en UTF-8 pour préserver les accents (é, è, à...)
        $xaml = [System.IO.File]::ReadAllText($xamlPath, [System.Text.Encoding]::UTF8)
        $reader = [System.Xml.XmlReader]::Create([System.IO.StringReader]$xaml)
        $this.Window = [System.Windows.Markup.XamlReader]::Load($reader)
        $reader.Close()

        if ($null -eq $this.Window) {
            throw "Echec du chargement du XAML : $xamlPath"
        }
    }

    [object] Get([string]$name) {
        if (-not $this.Controls.ContainsKey($name)) {
            $this.Controls[$name] = $this.Window.FindName($name)
        }
        return $this.Controls[$name]
    }

    [void] SetTiles([System.Collections.IEnumerable]$tiles) {
        ($this.Get('TileList')).ItemsSource = $tiles
    }

    [void] Show() {
        $this.Window.WindowStartupLocation = [System.Windows.WindowStartupLocation]::CenterScreen
        $this.Window.Topmost = $true
        $this.Window.ShowDialog() | Out-Null
        $this.Window.Topmost = $false
    }
}