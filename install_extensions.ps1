# GitHub repository information
$repoOwner = "DotNaos"
$repoName = "vscode-config"
$branch = "main"

# Base URL for raw content
$baseUrl = "https://raw.githubusercontent.com/$repoOwner/$repoName/$branch"

# Configuration
$configUrl = "$baseUrl/extensions-config.json"

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

# Function to save configuration back to GitHub (placeholder - requires GitHub API and authentication)
function Save-Config ($config) {
    Write-Host "Note: Saving configuration back to GitHub is not implemented in this version."
    Write-Host "Please manually update your config.json file in the GitHub repository."
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

# Main menu
function Show-MainMenu {
    $config = Get-Config
    while ($true) {
        Write-Host "`n=== VSCode Extension Manager ==="
        Write-Host "1. List Profiles"
        Write-Host "2. List Base Extensions"
        Write-Host "3. Install Extensions"
        Write-Host "4. Exit"
        $choice = Read-Host "Enter your choice"

        switch ($choice) {
            "1" { List-Profiles $config }
            "2" { List-BaseExtensions $config }
            "3" { Install-ProfileExtensions $config }
            "4" { return }
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
