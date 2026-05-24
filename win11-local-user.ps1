# Simple script to automate the creation of a "passwordless" local user. 

param(
    [Parameter(Mandatory = $true)]
    [string]$Username,

    [switch]$Admin,
    [switch]$OnStart
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

Log "Starting user creation for '$Username'."

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

        Set-ItemProperty -Path $RegPath -Name "AutoAdminLogon" -Value "1" -Type String
        Set-ItemProperty -Path $RegPath -Name "DefaultUserName" -Value $Username -Type String
        Set-ItemProperty -Path $RegPath -Name "DefaultPassword" -Value "" -Type String

        Log "Automatic login enabled for user '$Username'."
    }
    catch {
        Log "ERROR: Failed to configure automatic login: $_"
    }
}

Log "User creation process completed."
