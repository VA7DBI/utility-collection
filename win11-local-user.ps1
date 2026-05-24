# Simple script to automate the creation of a "passwordless" local user. 


param(
    [Parameter(Mandatory = $true)]
    [string]$Username,

    [switch]$Admin,
    [switch]$OnStart,
    [switch]$Kiosk,
    [switch]$Remove
)

# Ensure script is running as admin
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Error "This script must be run as Administrator."
    exit 1
}

# Logging
$LogFile = "$PSScriptRoot\CreateUser-$Username.log"
function Log {
    param([string]$Message)
    $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    "$timestamp  $Message" | Out-File -FilePath $LogFile -Append
    Write-Output $Message
}

Log "Script started for user '$Username'."

# ---------------------------------------------------------
# REMOVE MODE
# ---------------------------------------------------------
if ($Remove) {

    Log "Entering REMOVE mode for user '$Username'."

    # Remove kiosk mode if enabled
    try {
        Remove-AssignedAccess -UserName $Username -ErrorAction Stop
        Log "Kiosk mode removed for '$Username'."
    }
    catch {
        Log "Kiosk mode removal skipped or failed: $_"
    }

    # Remove autologin if this user was set
    try {
        $RegPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon"
        $DefaultUser = (Get-ItemProperty -Path $RegPath -Name "DefaultUserName" -ErrorAction SilentlyContinue).DefaultUserName

        if ($DefaultUser -eq $Username) {
            Set-ItemProperty -Path $RegPath -Name "AutoAdminLogon" -Value "0"
            Remove-ItemProperty -Path $RegPath -Name "DefaultUserName" -ErrorAction SilentlyContinue
            Remove-ItemProperty -Path $RegPath -Name "DefaultPassword" -ErrorAction SilentlyContinue
            Log "Autologin disabled for '$Username'."
        }
    }
    catch {
        Log "Autologin cleanup skipped or failed: $_"
    }

    # Remove user account
    try {
        Remove-LocalUser -Name $Username -ErrorAction Stop
        Log "User '$Username' removed successfully."
    }
    catch {
        Log "ERROR: Failed to remove user: $_"
    }

    # Remove home directory
    $HomeDir = "C:\Users\$Username"
    if (Test-Path $HomeDir) {
        try {
            Remove-Item -Path $HomeDir -Recurse -Force -ErrorAction Stop
            Log "Home directory '$HomeDir' deleted."
        }
        catch {
            Log "ERROR: Failed to delete home directory: $_"
        }
    }

    Log "REMOVE mode completed."
    exit 0
}

# ---------------------------------------------------------
# CREATE MODE
# ---------------------------------------------------------

Log "Entering CREATE mode for '$Username'."

# Create secure empty password
$SecureEmptyPassword = ConvertTo-SecureString "" -AsPlainText -Force

# Create the user
try {
    New-LocalUser -Name $Username `
                  -Password $SecureEmptyPassword `
                  -PasswordNeverExpires `
                  -UserMayNotChangePassword `
                  -AccountNeverExpires `
                  -ErrorAction Stop

    Log "User '$Username' created successfully."
}
catch {
    Log "ERROR: Failed to create user: $_"
    exit 1
}

# Add to Users group
try {
    Add-LocalGroupMember -Group "Users" -Member $Username -ErrorAction Stop
    Log "User '$Username' added to Users group."
}
catch {
    Log "ERROR: Failed to add user to Users group: $_"
}

# Optional admin membership
if ($Admin) {
    try {
        Add-LocalGroupMember -Group "Administrators" -Member $Username -ErrorAction Stop
        Log "User '$Username' added to Administrators group."
    }
    catch {
        Log "ERROR: Failed to add user to Administrators group: $_"
    }
}

# Create home directory
$HomeDir = "C:\Users\$Username"
if (-not (Test-Path $HomeDir)) {
    try {
        New-Item -ItemType Directory -Path $HomeDir -ErrorAction Stop | Out-Null
        Log "Home directory created at $HomeDir."
    }
    catch {
        Log "ERROR: Failed to create home directory: $_"
    }
}

# Set permissions
try {
    $acl = Get-Acl $HomeDir
    $rule = New-Object System.Security.AccessControl.FileSystemAccessRule("$Username","FullControl","ContainerInherit,ObjectInherit","None","Allow")
    $acl.SetAccessRule($rule)
    Set-Acl -Path $HomeDir -AclObject $acl
    Log "Permissions applied to home directory."
}
catch {
    Log "ERROR: Failed to set permissions: $_"
}

# Enable automatic login if requested
if ($OnStart) {
    try {
        $RegPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon"

        Set-ItemProperty -Path $RegPath -Name "AutoAdminLogon" -Value "1"
        Set-ItemProperty -Path $RegPath -Name "DefaultUserName" -Value $Username
        Set-ItemProperty -Path $RegPath -Name "DefaultPassword" -Value ""

        Log "Automatic login enabled for '$Username'."
    }
    catch {
        Log "ERROR: Failed to configure automatic login: $_"
    }
}

# Enable kiosk mode if requested
if ($Kiosk) {
    try {
        $AppUserModelId = "Microsoft.MicrosoftEdge_8wekyb3d8bbwe!App"
        Set-AssignedAccess -UserName $Username -AppUserModelId $AppUserModelId
        Log "Kiosk mode enabled for '$Username'."
    }
    catch {
        Log "ERROR: Failed to configure kiosk mode: $_"
    }
}

Log "CREATE mode completed."
