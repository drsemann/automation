# 1. Make sure the Microsoft App Installer is installed:
#    https://www.microsoft.com/en-us/p/app-installer/9nblggh4nns1
# 2. Edit the list of apps to install.
# 3. Run this script as administrator.

Write-Output "Installing Apps"
$apps = @(
    @{name = "7zip.7zip" },
    @{name = "SumatraPDF.SumatraPDF" },
    @{name = "Brave.Brave" },
    @{name = "Skillbrains.Lightshot" },         
    @{name = "JGraph.Draw" },                     
    @{name = "Dropbox.Dropbox" },                    
    @{name = "Git.Git" },                    
    @{name = "Mozilla.Firefox" },
	@{name = "Bitwarden.Bitwarden" },
    @{name = "Insecure.Nmap" },                    
    @{name = "Notepad++.Notepad++" },    
    @{name = "ONLYOFFICE.DesktopEditors" },
    @{name = "MiniTool.PartitionWizard.Free" },
    @{name = "JimRadford.SuperPuTTY" },
    @{name = "angryziber.AngryIPScanner" },                          
    @{name = "qBittorrent.qBittorrent" },
    @{name = "WinSCP.WinSCP" },                                  
    @{name = "WiresharkFoundation.Wireshark" },
    @{name = "Telegram.TelegramDesktop" },      
    @{name = "RealVNC.VNCViewer" },           
    @{name = "WireGuard.WireGuard" },
    @{name = "Obsidian.Obsidian" },         
    @{name = "Mobatek.MobaXterm" },                  
    @{name = "OpenVPNTechnologies.OpenVPN" },
    @{name = "PuTTY.PuTTY" },
    @{name = "VideoLAN.VLC" },
    @{name = "ZeroTier.ZeroTierOne"},
	@{name = "Devolutions.RemoteDesktopManager"},
    @{name = "Python.Python.3.12" }
);
Foreach ($app in $apps) {
    $listApp = winget list --exact -q $app.name
    if (![String]::Join("", $listApp).Contains($app.name)) {
        Write-host "Installing: " $app.name
        winget install -e -h --accept-source-agreements --accept-package-agreements --id $app.name 
    }
    else {
        Write-host "Skipping: " $app.name " (already installed)"
    }
}
