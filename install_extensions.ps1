# GitHub repository information
$repoOwner = "DotNaos"
$repoName = "vscode-config"
$branch = "main"

# Base URL for raw content
$baseUrl = "https://raw.githubusercontent.com/$repoOwner/$repoName/$branch"

# Configuration
$configUrl = "$baseUrl/extensions-config.json"

# GitHub Personal Access Token (PAT) for authentication
$githubToken = $env:GITHUB_TOKEN

# Function to fetch JSON configuration from GitHub
function Get-Config {
    try {
        $config = Invoke-RestMethod -Uri $configUrl
        return $config
    }
    catch {
        Write-Error "Failed to fetch configuration from GitHub. Error: $_"
        exit 1
    }
}

# Function to update file content on GitHub
function Update-GitHubFile {
    param (
        [string]$Path,
        [string]$Content,
        [string]$Message
    )

    $apiUrl = "https://api.github.com/repos/$repoOwner/$repoName/contents/$Path"

    # Get the current file to retrieve its SHA
    $currentFile = Invoke-RestMethod -Uri $apiUrl -Headers @{
        Authorization = "token $githubToken"
    }

    $body = @{
        message = $Message
        content = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($Content))
        sha     = $currentFile.sha
    } | ConvertTo-Json

    try {
        Invoke-RestMethod -Method Put -Uri $apiUrl -Body $body -ContentType 'application/json' -Headers @{
            Authorization = "token $githubToken"
        }
        Write-Host "Successfully updated $Path on GitHub"
    }
    catch {
        Write-Error "Failed to update $Path on GitHub. Error: $_"
    }
}

# Function to fetch extension list from a file or URL
function Get-ExtensionList {
    param (
        [string]$Source
    )
    
    $fullUrl = if ($Source -match '^https?://') {
        $Source
    } else {
        "$baseUrl/extensions/$Source"
    }

    try {
        $extensions = Invoke-RestMethod -Uri $fullUrl
        return $extensions -split "`n" | Where-Object { $_ -match '\S' }
    }
    catch {
        Write-Error "Failed to fetch extension list from: $fullUrl. Error: $_"
        return $null
    }
}

# Function to install extensions
function Install-Extensions {
    param (
        [string[]]$Extensions
    )

    $vscodePath = (Get-Command code -ErrorAction SilentlyContinue).Source
    if (-not $vscodePath) {
        Write-Error "Visual Studio Code is not installed or not in the system PATH"
        return
    }

    foreach ($extension in $Extensions) {
        if (-not [string]::IsNullOrWhiteSpace($extension)) {
            Write-Host "Installing extension: $extension"
            & $vscodePath --install-extension $extension
        }
    }
}

# Function to get installed VSCode extensions
function Get-InstalledExtensions {
    $vscodePath = (Get-Command code -ErrorAction SilentlyContinue).Source
    if (-not $vscodePath) {
        Write-Error "Visual Studio Code is not installed or not in the system PATH"
        return $null
    }

    $extensions = & $vscodePath --list-extensions
    return $extensions
}

# Function to update source files based on installed extensions
function Update-SourceFiles {
    $config = Get-Config
    $installedExtensions = Get-InstalledExtensions

    if ($null -eq $installedExtensions) {
        Write-Error "Failed to retrieve installed extensions"
        return
    }

    # Get all remote extensions
    $remoteExtensions = $config.base + ($config.profiles.PSObject.Properties | ForEach-Object { Get-ExtensionList -Source $_.Value })

    # Find new extensions
    $newExtensions = $installedExtensions | Where-Object { $remoteExtensions -notcontains $_ }

    # If there are new extensions, prompt user for categorization
    if ($newExtensions) {
        Write-Host "New extensions detected:"
        $newExtensions | ForEach-Object { Write-Host "- $_" }
        Write-Host "`nLet's categorize these new extensions.`n"

        $profiles = @("Base") + $config.profiles.PSObject.Properties.Name
        foreach ($extension in $newExtensions) {
            Write-Host "For extension: $extension"
            for ($i = 0; $i -lt $profiles.Count; $i++) {
                Write-Host "$($i + 1). $($profiles[$i])"
            }
            $choice = Read-Host "Enter the number of the profile to add this extension to"

            if ($choice -match '^\d+$' -and [int]$choice -le $profiles.Count) {
                $profileName = $profiles[[int]$choice - 1]
                if ($profileName -eq "Base") {
                    $config.base += $extension
                } else {
                    $profileExtensions = Get-ExtensionList -Source $config.profiles.$profileName
                    $profileExtensions += $extension
                    Update-GitHubFile -Path "extensions/$($config.profiles.$profileName)" -Content ($profileExtensions -join "`n") -Message "Add $extension to $profileName profile"
                }
            } else {
                Write-Host "Invalid choice. Extension will not be categorized."
            }
        }

        # Update base extensions file
        Update-GitHubFile -Path "extensions/base.txt" -Content ($config.base -join "`n") -Message "Update base extensions"

        # Update config.json with new base extensions
        $updatedConfig = $config | ConvertTo-Json -Depth 10
        Update-GitHubFile -Path "config.json" -Content $updatedConfig -Message "Update config with new base extensions"
    } else {
        Write-Host "No new extensions detected."
    }

    Write-Host "Source files updated based on installed extensions"
}

# Main menu
function Show-MainMenu {
    $config = Get-Config
    while ($true) {
        Write-Host "`n=== VSCode Extension Manager ==="
        Write-Host "1. List Profiles"
        Write-Host "2. List Base Extensions"
        Write-Host "3. Install Extensions"
        Write-Host "4. Update Source Files from Installed Extensions"
        Write-Host "5. Exit"
        $choice = Read-Host "Enter your choice"

        switch ($choice) {
            "1" { List-Profiles $config }
            "2" { List-BaseExtensions $config }
            "3" { Install-ProfileExtensions $config }
            "4" { Update-SourceFiles }
            "5" { return }
            default { Write-Host "Invalid choice. Please try again." }
        }
    }
}

# List Profiles
function List-Profiles ($config) {
    Write-Host "`n=== Profiles ==="
    foreach ($profile in $config.profiles.PSObject.Properties) {
        Write-Host "$($profile.Name): $($profile.Value)"
    }
}

# List Base Extensions
function List-BaseExtensions ($config) {
    Write-Host "`n=== Base Extensions ==="
    $config.base | ForEach-Object { Write-Host $_ }
}

# Install extensions from profiles
function Install-ProfileExtensions ($config) {
    $profiles = @("Base") + $config.profiles.PSObject.Properties.Name
    Write-Host "`nAvailable Profiles:"
    for ($i = 0; $i -lt $profiles.Count; $i++) {
        Write-Host "$($i + 1). $($profiles[$i])"
    }
    $choice = Read-Host "Enter profile number (or 'all' for all profiles)"

    if ($choice -eq 'all') {
        $allExtensions = $config.base
        foreach ($profile in $config.profiles.PSObject.Properties) {
            $extensions = Get-ExtensionList -Source $profile.Value
            if ($extensions) {
                $allExtensions += $extensions
            }
        }
        Install-Extensions -Extensions ($allExtensions | Select-Object -Unique)
    }
    elseif ($choice -match '^\d+$' -and [int]$choice -le $profiles.Count) {
        $profileName = $profiles[[int]$choice - 1]
        if ($profileName -eq "Base") {
            Install-Extensions -Extensions $config.base
        } else {
            $source = $config.profiles.$profileName
            $extensions = Get-ExtensionList -Source $source
            if ($extensions) {
                Install-Extensions -Extensions ($config.base + $extensions | Select-Object -Unique)
            }
        }
    }
    else {
        Write-Host "Invalid choice."
    }
}

# Run the main menu
Show-MainMenu
