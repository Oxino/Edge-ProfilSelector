@{
    DataFile     = 'AppData.json'
    Views        = @{
        Selector = 'views\TilesSelectorUI.xaml'
        AddTile  = 'views\TilesAddUI.xaml'
    }
    Edge         = @{
        ExePath   = 'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe'
        Arguments = '--profile-directory="{0}" {1}'
    }
    DefaultColor = '#0078D4'
    ShadeFactors = @{
        Lighter = 1.15
        Darker  = 0.78
    }
}