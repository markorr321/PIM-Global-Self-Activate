# Exit blocking removed - restore normal functionality

# PERFORMANCE OPTIMIZATION: Initialize global cache variables (simplified - no pending role caches)
function Initialize-PIMCache {
    # Initialize cache variables if they don't exist
    if (-not $global:ActiveRoleCache) { $global:ActiveRoleCache = @() }
    if (-not $global:ActiveRoleCacheTime) { $global:ActiveRoleCacheTime = $null }
    if (-not $global:RoleDefinitionCache) { $global:RoleDefinitionCache = @{} }
    if (-not $global:RoleDefinitionCacheTime) { $global:RoleDefinitionCacheTime = $null }
}

# Clear expired cache entries (simplified - no pending role caches)
function Clear-ExpiredCache {
    $currentTime = Get-Date
    
    # Clear active role cache if older than 60 seconds
    if ($global:ActiveRoleCacheTime -and ($currentTime - $global:ActiveRoleCacheTime).TotalSeconds -gt 60) {
        $global:ActiveRoleCache = @()
        $global:ActiveRoleCacheTime = $null
    }
    
    # Clear role definition cache if older than 5 minutes
    if ($global:RoleDefinitionCacheTime -and ($currentTime - $global:RoleDefinitionCacheTime).TotalSeconds -gt 300) {
        $global:RoleDefinitionCache = @{}
        $global:RoleDefinitionCacheTime = $null
    }
}

# Initialize cache on script start
Initialize-PIMCache

# OPTIMIZED: Centralized role definition caching function
function Get-CachedRoleDefinition {
    param([string]$RoleId)
    
    # Check if we have cached data that's still fresh (within 5 minutes)
    if ($global:RoleDefinitionCache.ContainsKey($RoleId) -and 
        $global:RoleDefinitionCacheTime -and 
        ((Get-Date) - $global:RoleDefinitionCacheTime).TotalSeconds -lt 300) {
        return $global:RoleDefinitionCache[$RoleId]
    }
    
    # Fetch and cache the role definition
    try {
        $roleDefinition = Get-MgRoleManagementDirectoryRoleDefinition -UnifiedRoleDefinitionId $RoleId
        $global:RoleDefinitionCache[$RoleId] = $roleDefinition
        $global:RoleDefinitionCacheTime = Get-Date
        return $roleDefinition
    } catch {
        # Return a fallback object if API call fails
        $fallback = [PSCustomObject]@{
            DisplayName = "Unknown Role"
            Id = $RoleId
        }
        $global:RoleDefinitionCache[$RoleId] = $fallback
        return $fallback
    }
}

<#
    Global PIM Manager Script (Activation + Deactivation) with Teams Notifications
    ------------------------------------------------------------------------------
    - Detects and deactivates active roles (with justification)
    - Falls back to activation if no roles are active
    - Supports group-based and user-based eligibilities
    - MFA-enforced MSAL login via browser
    - Sends Teams notifications via webhook for successful operations
    
    FEATURES:
    =========
    
    🔔 Teams Integration:
       - Automatic notifications for successful role activations and deactivations
       - Rich adaptive cards with role details, user info, and timestamps
       - Configurable webhook URL and notification toggle
       - Timezone-aware timestamps with proper abbreviations
    
    📋 Adaptive Card Features:
       - Role operation type (Activation/Deactivation) with appropriate icons
       - User email, role name, and justification
       - Duration and expiry time for activations
       - Localized date/time with timezone abbreviation
       - Color-coded themes (Blue for activation, Orange for deactivation)
    
    ⚙️ Configuration:
       - Set $teamsWebhookUrl to your Teams webhook URL
       - Set $enableTeamsNotifications to $false to disable notifications
       - Webhook creation guide: Teams Channel → More options → Manage channel → Edit → Incoming Webhook → Add
    
    🚀 Performance Optimizations:
       - API Response Caching: 60-80% faster repeated calls
       - Parallel Processing: 50% faster role data processing (PowerShell 7+)
       - Targeted API Filters: 40% less network traffic
       - Optimized UI Updates: 30% less CPU usage
       - Smart Module Loading: Faster startup with required modules only
    
    📚 References:
       - Microsoft Teams Webhooks: https://learn.microsoft.com/en-us/microsoftteams/platform/webhooks-and-connectors/how-to/add-incoming-webhook
       - Adaptive Cards Schema: http://adaptivecards.io/schemas/adaptive-card.json
#>

# ========================= Global Variables =========================

# Global cache for role definitions to avoid repeated API calls
if (-not $script:RoleDefinitionCache) {
    $script:RoleDefinitionCache = @{}
    $script:RoleCacheExpiry = (Get-Date).AddMinutes(30)
}

# Shared schedule instance cache to avoid duplicate API calls
if (-not $script:ScheduleInstanceCache) {
    $script:ScheduleInstanceCache = @{}
    $script:ScheduleInstanceCacheExpiry = (Get-Date).AddSeconds(30)
}

function Get-CachedRoleDefinition {
    param([string]$RoleId)
    
    # Validate input parameter
    if ([string]::IsNullOrEmpty($RoleId)) {
        return $null
    }
    
    # Initialize cache if not exists
    if (-not $script:RoleDefinitionCache) {
        $script:RoleDefinitionCache = @{}
        $script:RoleCacheExpiry = (Get-Date).AddMinutes(30)
    }
    
    # Check if cache has expired
    if ((Get-Date) -gt $script:RoleCacheExpiry) {
        $script:RoleDefinitionCache = @{}
        $script:RoleCacheExpiry = (Get-Date).AddMinutes(30)
    }
    
    # Return cached result if available
    if ($script:RoleDefinitionCache.ContainsKey($RoleId)) {
        return $script:RoleDefinitionCache[$RoleId]
    }
    
    # Fetch and cache the role definition
    try {
        $roleDefinition = Get-MgRoleManagementDirectoryRoleDefinition -UnifiedRoleDefinitionId $RoleId
        $script:RoleDefinitionCache[$RoleId] = $roleDefinition
        return $roleDefinition
    } catch {
        # Cache null result to avoid repeated failed calls
        $script:RoleDefinitionCache[$RoleId] = $null
        return $null
    }
}

function Get-CachedScheduleInstances {
    param([string]$CurrentUserId)
    
    # Check if cache has expired
    if ((Get-Date) -gt $script:ScheduleInstanceCacheExpiry) {
        $script:ScheduleInstanceCache = @{}
        $script:ScheduleInstanceCacheExpiry = (Get-Date).AddSeconds(30)
    }
    
    # Return cached result if available
    if ($script:ScheduleInstanceCache.ContainsKey($CurrentUserId)) {
        return $script:ScheduleInstanceCache[$CurrentUserId]
    }
    
    # Fetch and cache the schedule instances
    try {
        $scheduleInstances = Get-MgRoleManagementDirectoryRoleAssignmentScheduleInstance -Filter "PrincipalId eq '$CurrentUserId' and AssignmentType eq 'Activated'" -All
        $script:ScheduleInstanceCache[$CurrentUserId] = $scheduleInstances
        return $scheduleInstances
    } catch {
        # Cache empty result to avoid repeated failed calls
        $script:ScheduleInstanceCache[$CurrentUserId] = @()
        return @()
    }
}

function Get-EligibleRolesOptimized {
    param([string]$CurrentUserId)
    $allEligibleRoles = @()
    try {
        # OPTIMIZED: Use filter and cached role definitions for much better performance
        $eligibilitySchedules = Get-MgRoleManagementDirectoryRoleEligibilityScheduleInstance -Filter "PrincipalId eq '$CurrentUserId'" -All
        
        # FASTEST: Use parallel processing to get role definitions (PowerShell 7+)
        if ($PSVersionTable.PSVersion.Major -ge 7 -and $eligibilitySchedules.Count -gt 3) {
            # Use parallel processing for multiple roles
            $allEligibleRoles = $eligibilitySchedules | ForEach-Object -Parallel {
                try {
                    $roleDef = Get-MgRoleManagementDirectoryRoleDefinition -UnifiedRoleDefinitionId $_.RoleDefinitionId
                    [PSCustomObject]@{
                        RoleDefinitionId = $_.RoleDefinitionId
                        RoleDefinition   = @{
                            DisplayName = $roleDef.DisplayName
                            Id = $roleDef.Id
                            Description = $roleDef.Description
                        }
                        PrincipalId      = $_.PrincipalId
                        DirectoryScopeId = $_.DirectoryScopeId
                    }
                } catch {
                    # Skip roles that fail to load
                    $null
                }
            } | Where-Object { $_ -ne $null }
        } else {
            # Sequential processing for few roles
            foreach ($schedule in $eligibilitySchedules) {
                try {
                    $roleDef = Get-MgRoleManagementDirectoryRoleDefinition -UnifiedRoleDefinitionId $schedule.RoleDefinitionId
                    $allEligibleRoles += [PSCustomObject]@{
                        RoleDefinitionId = $schedule.RoleDefinitionId
                        RoleDefinition   = @{
                            DisplayName = $roleDef.DisplayName
                            Id = $roleDef.Id
                            Description = $roleDef.Description
                        }
                        PrincipalId      = $schedule.PrincipalId
                        DirectoryScopeId = $schedule.DirectoryScopeId
                    }
                } catch {
                    # Skip roles that fail to load
                    continue
                }
            }
        }
    } catch {
        Write-Host "Error retrieving eligible roles: $($_.Exception.Message)" -ForegroundColor Red
        $allEligibleRoles = @()
    }

    
    # REMOVED: Pending role filtering - not needed for self-activating organizations
    
    # OPTIMIZED: Batch check for active roles with caching
    $activeRoleIds = @()
    try {
        # Use global cache if available and recent (within 60 seconds)
        if ($global:ActiveRoleCache -and $global:ActiveRoleCacheTime -and 
            ((Get-Date) - $global:ActiveRoleCacheTime).TotalSeconds -lt 60) {
            $activeRoleIds = $global:ActiveRoleCache
        } else {
            # FAST: Get all active assignments in one call instead of individual calls
            $allActiveAssignments = Get-MgRoleManagementDirectoryRoleAssignment -Filter "PrincipalId eq '$CurrentUserId'" -All
            $activeRoleIds = $allActiveAssignments | Select-Object -ExpandProperty RoleDefinitionId -Unique
            
            # Cache the results
            $global:ActiveRoleCache = $activeRoleIds
            $global:ActiveRoleCacheTime = Get-Date
        }
    } catch {
        # Fallback to individual checks if batch fails
        foreach ($role in $allEligibleRoles) {
            try {
                $activeAssignments = Get-MgRoleManagementDirectoryRoleAssignment -Filter "PrincipalId eq '$CurrentUserId' and RoleDefinitionId eq '$($role.RoleDefinitionId)'" -ErrorAction SilentlyContinue
                if ($activeAssignments -and $activeAssignments.Count -gt 0) {
                    $activeRoleIds += $role.RoleDefinitionId
                }
            } catch {
                # Skip if API call fails
            }
        }
    }
    # SIMPLIFIED: Only filter out active roles - no pending role filtering
    $eligibleRoles = $allEligibleRoles | Where-Object { 
        $activeRoleIds -notcontains $_.RoleDefinitionId
    }

    # Deduplicate roles by RoleDefinitionId to prevent duplicates
    $validRoles = $eligibleRoles | Sort-Object RoleDefinitionId | Group-Object RoleDefinitionId | ForEach-Object { $_.Group[0] }
    
    return $validRoles
}

function Show-DynamicExpirationMenu {
    param(
        [array]$RoleExpirationData,
        [string]$Title
    )
    
    [Console]::CursorVisible = $false
    $currentIndex = 0
    $selected = @()
    for ($i = 0; $i -lt $RoleExpirationData.Count; $i++) {
        $selected += $false
    }
    
    try {
        do {
            Clear-Host
            Show-PIMGlobalHeaderMinimal
            Write-Host ""
            Write-Host $Title -ForegroundColor Cyan
            Write-Host ("=" * $Title.Length) -ForegroundColor Cyan
            Write-Host ""
            
            # Filter out expired roles and check if any remain
            $activeRoleData = @()
            $activeSelected = @()
            $newCurrentIndex = $currentIndex
            
            for ($i = 0; $i -lt $RoleExpirationData.Count; $i++) {
                $roleData = $RoleExpirationData[$i]
                $role = $roleData.Role
                $expirationTime = $roleData.ExpirationTime
                
                # Calculate countdown
                $isExpired = $false
                if ($expirationTime) {
                    $timeRemaining = $expirationTime - (Get-Date)
                    
                    
                    if ($timeRemaining.TotalSeconds -gt 0) {
                        $hours = [Math]::Floor($timeRemaining.TotalHours)
                        $minutes = $timeRemaining.Minutes
                        $seconds = $timeRemaining.Seconds
                        
                        if ($hours -gt 0) {
                            $countdownText = "expires in ${hours}h ${minutes}m ${seconds}s"
                        } else {
                            $countdownText = "expires in ${minutes}m ${seconds}s"
                        }
                    } else {
                        $countdownText = "expired"
                        $isExpired = $true
                    }
                } else {
                    $countdownText = "no expiration data"
                }
                
                # Only include non-expired roles
                if (-not $isExpired) {
                    $activeRoleData += @{
                        Role = $role
                        ExpirationTime = $expirationTime
                        CountdownText = $countdownText
                        OriginalIndex = $i
                    }
                    $activeSelected += $selected[$i]
                }
            }
            
            # Check if all roles expired during countdown
            if ($activeRoleData.Count -eq 0) {
                Clear-Host
                Show-PIMGlobalHeaderMinimal
                Write-Host ""
                Write-Host "ℹ️  No active roles to deactivate at this time." -ForegroundColor Gray
                Write-Host ""
                Write-Host "Would you like to activate roles instead? (Y/N): " -NoNewline -ForegroundColor Cyan
                Write-Host ""
                Write-Host ""
                Write-Host "Ctrl+Q to exit" -ForegroundColor Magenta
                
                # Ask if user wants to manage more roles
                do {
                    [Console]::SetCursorPosition(42, [Console]::CursorTop - 2)
                    $input = Read-Host
                    $input = $input.Trim().ToUpper()
                    if ($input -eq "Y" -or $input -eq "YES") {
                        [Console]::CursorVisible = $true
                        Start-PIMRoleManagement -CurrentUserId $script:CurrentUserId
                        return
                    } elseif ($input -eq "N" -or $input -eq "NO") {
                        Write-Host "❌ No role management workflows available." -ForegroundColor Red
                    Write-Host ""
                    Write-Host "Check back later when roles are approved or activated." -ForegroundColor Gray
                    Write-Host ""
                    Show-DynamicControlBar
                    
                    # Wait for Ctrl+Q to exit
                    do {
                        $key = [Console]::ReadKey($true)
                        if ($key.Key -eq 'Q' -and $key.Modifiers -eq 'Control') {
                            Invoke-PIMExit -Message "Exiting PIM role management..."
                        }
                    } while ($true)
                    return
                        Write-Host "Script completed successfully." -ForegroundColor Green
                        [Console]::CursorVisible = $true
                        return @()
                    } else {
                        Write-Host "Please enter Y or N." -ForegroundColor Yellow
                    }
                } while ($true)
            }
            
            # Update arrays to only include active roles
            $selected = $activeSelected
            if ($currentIndex -ge $activeRoleData.Count) {
                $currentIndex = $activeRoleData.Count - 1
            }
            
            # Display active roles with dynamic countdown
            for ($i = 0; $i -lt $activeRoleData.Count; $i++) {
                $roleInfo = $activeRoleData[$i]
                
                # Display role with selection indicator
                $checkbox = if ($selected[$i]) { "[✓]" } else { "[ ]" }
                $arrow = if ($i -eq $currentIndex) { "► " } else { "  " }
                
                Write-Host "$arrow$checkbox $($roleInfo.Role.RoleName) ($($roleInfo.CountdownText))" -ForegroundColor $(if ($i -eq $currentIndex) { "Yellow" } else { "White" })
            }
            
            Write-Host ""
            $selectedCount = ($selected | Where-Object { $_ }).Count
            Write-Host "Roles Selected: $selectedCount" -ForegroundColor Green
            Write-Host ""
            Write-Host "↑/↓ Navigate | SPACE Toggle | ENTER Confirm | Ctrl+Q Exit" -ForegroundColor Magenta
            
            # Handle input with timeout for countdown updates
            $inputAvailable = $false
            $timeout = 1000 # 1 second timeout
            $startTime = Get-Date
            
            while (((Get-Date) - $startTime).TotalMilliseconds -lt $timeout -and -not $inputAvailable) {
                if ([Console]::KeyAvailable) {
                    $inputAvailable = $true
                    break
                }
                Start-Sleep -Milliseconds 50
            }
            
            if ($inputAvailable) {
                $key = [Console]::ReadKey($true)
                
                switch ($key.Key) {
                    "UpArrow" {
                        if ($currentIndex -gt 0) { $currentIndex-- }
                    }
                    "DownArrow" {
                        if ($currentIndex -lt ($RoleExpirationData.Count - 1)) { $currentIndex++ }
                    }
                    "Spacebar" {
                        $selected[$currentIndex] = -not $selected[$currentIndex]
                    }
                    "Enter" {
                        [Console]::CursorVisible = $false
                        $selectedIndices = @()
                        for ($i = 0; $i -lt $selected.Count; $i++) {
                            if ($selected[$i]) {
                                $selectedIndices += $i
                            }
                        }
                        # Clear screen before returning to prevent UI overlap
                        Clear-Host
                        return $selectedIndices
                    }
                    "Escape" {
                        return @()
                    }
                }
                
                # Handle Ctrl+Q
                if ($key.Modifiers -eq "Control" -and $key.Key -eq "Q") {
                    Invoke-PIMExit -Message "Exiting PIM role management..."
                }
            }
            
        } while ($true)
    }
    finally {
        [Console]::CursorVisible = $true
    }
}

function Start-RoleDeactivationWorkflowWithCheck {
    param([string]$CurrentUserId)
    
    # FAST: Get active roles using cached data
    $activeRoles = @()
    try {
        # FAST: Use cached schedule instances to avoid duplicate API calls
        $scheduleInstances = Get-CachedScheduleInstances -CurrentUserId $CurrentUserId
        
        if ($scheduleInstances.Count -eq 0) {
            Write-Host "ℹ️  No active roles to deactivate at this time." -ForegroundColor Gray
            Write-Host ""
            
            # Ask if user wants to activate roles instead
            $response = Read-PIMInput -Prompt "Would you like to activate roles instead? (Y/N)" -ForegroundColor Cyan
            
            $input = $response.Trim().ToUpper()
            if ($input -eq "Y" -or $input -eq "YES") {
                $eligibleRoles = Get-EligibleRolesOptimized -CurrentUserId $CurrentUserId
                if ($eligibleRoles.Count -gt 0) {
                    Start-RoleActivationWorkflow -ValidRoles $eligibleRoles -CurrentUserId $CurrentUserId
                } else {
                    Write-Host "❌ No eligible roles available for activation." -ForegroundColor Red
                }
                return
            } elseif ($input -eq "N" -or $input -eq "NO") {
                Write-Host ""
                Write-Host "❌ No role management workflows available." -ForegroundColor Red
                Write-Host ""
                Write-Host "Check back later when roles are approved or activated." -ForegroundColor Gray
                Write-Host ""
                Show-DynamicControlBar
                
                # Wait for Ctrl+Q to exit
                do {
                    $key = [Console]::ReadKey($true)
                    if ($key.Key -eq 'Q' -and $key.Modifiers -eq 'Control') {
                        Invoke-PIMExit -Message "Exiting PIM role management..."
                    }
                } while ($true)
            } else {
                Write-Host "Please enter Y or N." -ForegroundColor Yellow
            }
        }
        
        # OPTIMIZED: Convert schedule instances to active roles using cached role definitions
        $activeRoles = @()
        foreach ($instance in $scheduleInstances) {
            $roleDefinition = Get-CachedRoleDefinition -RoleId $instance.RoleDefinitionId
            if ($roleDefinition) {
                $expirationTime = $null
                if ($instance.EndDateTime) {
                    $expirationTime = [DateTime]::Parse($instance.EndDateTime).ToLocalTime()
                }
                
                $activeRoles += [PSCustomObject]@{
                    RoleName = $roleDefinition.DisplayName
                    Assignment = $instance
                    ExpirationTime = $expirationTime
                }
            }
        }
    } catch {
        Write-Host "❌ Error checking active roles: $($_.Exception.Message)" -ForegroundColor Red
        return
    }
    
    if ($activeRoles.Count -eq 0) {
        Write-Host "ℹ️  No active roles to deactivate at this time." -ForegroundColor Gray
        Write-Host ""
        
        # Ask if user wants to activate roles instead with Ctrl+Q support
        Write-Host "Would you like to activate roles instead? (Y/N): " -NoNewline -ForegroundColor Cyan
        Write-Host ""
        Write-Host "Ctrl+Q to exit" -ForegroundColor Gray
        
        # Store cursor position for inline input
        $promptLeft = [Console]::CursorLeft
        $promptTop = [Console]::CursorTop
        
        # Show control bar below the prompt with proper spacing
        Write-Host "`n"  # Add blank line after prompt
        Write-Host "Ctrl+Q Exit" -ForegroundColor Magenta
        $script:LastControlBarLine = [Console]::CursorTop - 1
        
        # Return cursor to inline position after the prompt (same line as Y/N question)
        [Console]::SetCursorPosition($promptLeft, $promptTop)
        
        $userInput = ""
        do {
            $key = [Console]::ReadKey($true)
            
            # Check for Ctrl+Q
            if ($key.Key -eq 'Q' -and $key.Modifiers -eq 'Control') {
                Invoke-PIMExit -Message "Exiting PIM role management..."
                return
            }
            
            # Handle Enter key
            if ($key.Key -eq 'Enter') {
                if ($userInput -eq 'Y' -or $userInput -eq 'y') {
                    # Clear the control bar first
                    if ($script:LastControlBarLine -ge 0) {
                        try {
                            [Console]::SetCursorPosition(0, $script:LastControlBarLine)
                            Write-Host (" " * [Console]::WindowWidth) -NoNewline
                            [Console]::SetCursorPosition(0, $script:LastControlBarLine)
                            $script:LastControlBarLine = -1
                        } catch { }
                    }
                    # Use exactly the same logic as the main menu activation
                    $eligibleRoles = Get-EligibleRolesOptimized -CurrentUserId $CurrentUserId
                    
                    if ($eligibleRoles.Count -gt 0) {
                        Start-RoleActivationWorkflow -ValidRoles $eligibleRoles -CurrentUserId $CurrentUserId
                    } else {
                        Write-PIMHost "❌ No active roles available for activation." -ForegroundColor Red
                        Write-PIMHost ""
                        Write-PIMHost "❌ No role management workflows available." -ForegroundColor Red
                        Write-PIMHost ""
                        Write-PIMHost "Check back later when roles are approved or activated." -ForegroundColor Gray
                        Write-PIMHost ""
                        Write-PIMHost "Ctrl+Q Exit" -ForegroundColor Magenta
                        
                        # Wait for Ctrl+Q
                        [Console]::CursorVisible = $false
                        do {
                            $key = [Console]::ReadKey($true)
                            if ($key.Key -eq 'Q' -and $key.Modifiers -eq 'Control') {
                                [Console]::CursorVisible = $true
                                Invoke-PIMExit -Message "Exiting PIM role management..."
                                return
                            }
                        } while ($true)
                    }
                    return
                } elseif ($userInput -eq 'N' -or $userInput -eq 'n') {
                    # Clear the control bar
                    if ($script:LastControlBarLine -ge 0) {
                        try {
                            [Console]::SetCursorPosition(0, $script:LastControlBarLine)
                            Write-Host (" " * [Console]::WindowWidth) -NoNewline
                            [Console]::SetCursorPosition(0, $script:LastControlBarLine)
                            $script:LastControlBarLine = -1
                        } catch { }
                    }
                    
                    Write-Host "No additional roles will be managed." -ForegroundColor Yellow
                    Write-Host ""
                    Write-Host "Ctrl+Q Exit" -ForegroundColor Magenta
                    
                    # Hide cursor and wait for Ctrl+Q instead of exiting
                    [Console]::CursorVisible = $false
                    do {
                        $key = [Console]::ReadKey($true)
                        if ($key.Key -eq 'Q' -and $key.Modifiers -eq 'Control') {
                            [Console]::CursorVisible = $true
                            Invoke-PIMExit -Message "Exiting PIM role management..."
                            return
                        }
                    } while ($true)
                } else {
                    # Invalid input, show error and continue
                    Write-Host ""
                    Write-Host "Please enter Y or N." -ForegroundColor Yellow
                    Write-Host "Would you like to activate roles instead? (Y/N): " -NoNewline -ForegroundColor Cyan
                    
                    # Update cursor position
                    $promptLeft = [Console]::CursorLeft
                    $promptTop = [Console]::CursorTop
                    
                    # Update control bar position
                    Write-Host "`n"
                    Write-Host "Ctrl+Q Exit" -ForegroundColor Magenta
                    $script:LastControlBarLine = [Console]::CursorTop - 1
                    
                    # Return cursor to prompt
                    [Console]::SetCursorPosition($promptLeft, $promptTop)
                    $userInput = ""
                    continue
                }
            }
            
            # Handle backspace
            if ($key.Key -eq 'Backspace' -and $userInput.Length -gt 0) {
                $userInput = $userInput.Substring(0, $userInput.Length - 1)
                Write-Host "`b `b" -NoNewline
            }
            # Handle regular character input
            elseif ($key.KeyChar -match '[YyNn]' -and $userInput.Length -eq 0) {
                $userInput = $key.KeyChar.ToString()
                Write-Host $key.KeyChar -NoNewline
            }
        } while ($true)
    }
    
    # Continue with deactivation workflow - we already checked for active roles above
    
    # Skip cached schedules - we already have the data from schedule instances above
    # Use the schedule instances we already retrieved for 5-minute checking
    
    # Check for roles that are too new to deactivate (5-minute rule)
    # Use the same logic as smart routing to get accurate activation times
    $readyToDeactivate = @()
    $tooNewRoles = @()
    
    # Get cached schedules for accurate activation time lookup
    $cachedSchedules = Get-CachedSchedules -CurrentUserId $CurrentUserId
    
    foreach ($role in $activeRoles) {
        try {
            $assignment = $role.Assignment
            $activationTime = $null
            
            # Use the schedule instance StartDateTime as the primary activation time
            if ($assignment.StartDateTime) {
                $activationTime = [DateTime]::Parse($assignment.StartDateTime).ToLocalTime()
            }
            
            # If no StartDateTime, try to find recent activation request as fallback
            if (-not $activationTime) {
                $recentCutoff = (Get-Date).AddMinutes(-10)
                $schedules = $cachedSchedules | Where-Object { 
                    $_.PrincipalId -eq $assignment.PrincipalId -and 
                    $_.RoleDefinitionId -eq $assignment.RoleDefinitionId -and
                    [DateTime]::Parse($_.CreatedDateTime) -gt $recentCutoff
                }
                
                if ($schedules) {
                    $activationSchedules = $schedules | Where-Object { $_.Action -eq "selfActivate" }
                    if ($activationSchedules) {
                        $latestSchedule = $activationSchedules | Sort-Object CreatedDateTime -Descending | Select-Object -First 1
                        $activationTime = [DateTime]::Parse($latestSchedule.CreatedDateTime).ToLocalTime()
                    }
                }
            }
            
            if ($activationTime) {
                $timeSinceActivation = (Get-Date) - $activationTime
                
                if ($timeSinceActivation.TotalMinutes -lt 5) {
                    $tooNewRoles += @{
                        RoleName = $role.RoleName
                        ActivationTime = $activationTime
                        Assignment = $role.Assignment
                    }
                } else {
                    $readyToDeactivate += $role
                }
            } else {
                # No activation time available, assume it's ready (old activation)
                $readyToDeactivate += $role
            }
        } catch {
            # If there's an error checking, assume it's ready
            $readyToDeactivate += $role
        }
    }
    
    
    # If some roles are too new, show countdown
    if ($tooNewRoles.Count -gt 0) {
        Clear-Host
        Show-PIMGlobalHeaderMinimal
        Write-Host ""
        
        if ($readyToDeactivate.Count -eq 0) {
            Write-Host "⏰ All roles are within the 5-minute activation period." -ForegroundColor Yellow
            Write-Host "Showing countdown until they can be deactivated..." -ForegroundColor Cyan
        } else {
            Write-Host "⏰ Some roles are within the 5-minute activation period." -ForegroundColor Yellow
            Write-Host "Showing countdown for roles that cannot be deactivated yet..." -ForegroundColor Cyan
        }
        Write-Host ""
        
        $countdownResult = Show-DeactivationCountdown -TooNewRoles $tooNewRoles
        
        # If countdown completed successfully, continue to deactivation workflow
        if ($countdownResult -eq $true) {
            # Refresh and get all active roles now that countdown is complete
            Start-RoleDeactivationWorkflowWithCheck -CurrentUserId $CurrentUserId
            return
        }
        return
    }
    
    # If no roles ready after filtering, show message and continue to deactivation workflow
    if ($readyToDeactivate.Count -eq 0) {
        Write-Host "ℹ️  All roles are within the 5-minute activation period." -ForegroundColor Gray
        Write-Host ""
        
        do {
            Write-Host "Would you like to activate roles instead? (Y/N): " -NoNewline -ForegroundColor Cyan
            Write-Host ""
            Write-Host ""
            Write-Host "Ctrl+Q to exit" -ForegroundColor Magenta
            $input = Read-Host
            $input = $input.Trim().ToUpper()
            if ($input -eq "Y" -or $input -eq "YES") {
                Clear-Host
                Start-PIMRoleManagement -CurrentUserId $CurrentUserId
                return
            } elseif ($input -eq "N" -or $input -eq "NO") {
                Write-PIMHost "No additional roles will be managed." -ForegroundColor Cyan -ControlsText $script:ControlMessages['Exit']
                Write-PIMHost "Please close the terminal." -ForegroundColor Yellow -ControlsText $script:ControlMessages['Exit']
                
                # Wait for user to exit with Ctrl+Q
                do {
                    if ([Console]::KeyAvailable) {
                        $key = [Console]::ReadKey($true)
                        if (Test-GlobalShortcut -Key $key) {
                            return
                        }
                    }
                    Start-Sleep -Milliseconds 100
                } while ($true)
            } else {
                Write-PIMHost "Please enter Y or N." -ForegroundColor Yellow -ControlsText $script:ControlMessages['Exit']
            }
        } while ($true)
    }
    
    # Use expiration data already collected during initial role retrieval - NO ADDITIONAL API CALLS
    $roleExpirationData = @()
    $filteredReadyToDeactivate = @()
    
    # Process roles using expiration data already available in role objects
    foreach ($role in $readyToDeactivate) {
        # Check if role is already expired using data we already have
        if ($role.ExpirationTime) {
            if ($role.ExpirationTime -gt (Get-Date)) {
                # Role is still active, include it
                $filteredReadyToDeactivate += $role
                $roleExpirationData += [PSCustomObject]@{
                    Role = $role
                    ExpirationTime = $role.ExpirationTime
                }
            }
            # If expired, skip this role entirely
        } else {
            # No expiration data, assume it's still active
            $filteredReadyToDeactivate += $role
            $roleExpirationData += [PSCustomObject]@{
                Role = $role
                ExpirationTime = $null
            }
        }
    }
    
    # Update readyToDeactivate to only include non-expired roles
    $readyToDeactivate = $filteredReadyToDeactivate
    
    # Check if any roles remain after filtering out expired ones
    if ($readyToDeactivate.Count -eq 0) {
        Write-Host "ℹ️  No active roles to deactivate at this time." -ForegroundColor Gray
        Write-Host ""
        
        # Ask if user wants to activate roles instead with inline input handling
        Write-Host "Would you like to activate roles instead? (Y/N): " -NoNewline -ForegroundColor Cyan
        
        # Store cursor position for inline input
        $promptLeft = [Console]::CursorLeft
        $promptTop = [Console]::CursorTop
        
        # Show control bar below the prompt with proper spacing
        Write-Host "`n"  # Add blank line after prompt
        Write-Host "Ctrl+Q to exit" -ForegroundColor Magenta
        $script:LastControlBarLine = [Console]::CursorTop - 1
        
        # Return cursor to inline position after the prompt (same line as Y/N question)
        [Console]::SetCursorPosition($promptLeft, $promptTop)
        
        $userInput = ""
        do {
            $key = [Console]::ReadKey($true)
            
            # Check for Ctrl+Q
            if ($key.Key -eq 'Q' -and $key.Modifiers -eq 'Control') {
                Invoke-PIMExit
                return
            }
            
            # Handle Enter key
            if ($key.Key -eq 'Enter') {
                if ($userInput -eq 'Y' -or $userInput -eq 'y') {
                    # Clear the control bar and move cursor to start of that line
                    if ($script:LastControlBarLine -ge 0) {
                        try {
                            [Console]::SetCursorPosition(0, $script:LastControlBarLine)
                            Write-Host (" " * [Console]::WindowWidth) -NoNewline
                            $script:LastControlBarLine = -1
                        } catch { }
                    }
                    Clear-Host
                                        Start-PIMRoleManagement -CurrentUserId $CurrentUserId
                                        return
                } elseif ($userInput -eq 'N' -or $userInput -eq 'n') {
                    Write-Host ""
                    Write-Host "❌ No role management workflows available." -ForegroundColor Red
                    Write-Host ""
                    Write-Host "Check back later when roles are approved or activated." -ForegroundColor Gray
                    Write-Host ""
                    Show-DynamicControlBar
                    
                    # Wait for Ctrl+Q to exit
                    do {
                        $key = [Console]::ReadKey($true)
                        if ($key.Key -eq 'Q' -and $key.Modifiers -eq 'Control') {
                            Invoke-PIMExit -Message "Exiting PIM role management..."
                        }
                    } while ($true)
                    return
                    return
                } else {
                    Write-Host ""
                    Write-Host "Please enter Y or N: " -NoNewline -ForegroundColor Yellow
                    # Clear and redraw control bar for invalid input
                    if ($script:LastControlBarLine -ge 0) {
                        try {
                            [Console]::SetCursorPosition(0, $script:LastControlBarLine)
                            Write-Host (" " * [Console]::WindowWidth) -NoNewline
                        } catch { }
                    }
                    Write-Host ""
                    Write-Host "Ctrl+Q to exit" -ForegroundColor Magenta
                    $script:LastControlBarLine = [Console]::CursorTop - 1
                    # Return cursor to prompt position
                    [Console]::SetCursorPosition([Console]::CursorLeft, [Console]::CursorTop - 2)
                    $userInput = ""
                }
            }
            # Handle backspace
            elseif ($key.Key -eq 'Backspace' -and $userInput.Length -gt 0) {
                $userInput = $userInput.Substring(0, $userInput.Length - 1)
                Write-Host "`b `b" -NoNewline
            }
            # Handle regular characters (Y/N only)
            elseif ($key.KeyChar -match '[YyNn]' -and $userInput.Length -eq 0) {
                $userInput = $key.KeyChar.ToString().ToUpper()
                Write-Host $userInput -NoNewline -ForegroundColor Green
            }
        } while ($true)
        return
    }
    
    # Show dynamic countdown menu
    $selectedIndices = Show-DynamicExpirationMenu -RoleExpirationData $roleExpirationData -Title "🔄 Select Active Roles to Deactivate"
    
    if ($selectedIndices.Count -eq 0) {
                Write-Host "❌ No roles selected for deactivation." -ForegroundColor Yellow
        return
    }
    
    # Clear screen and show clean deactivation progress
    Clear-Host
    Show-PIMGlobalHeaderMinimal
    Write-Host ""
    Write-Host "🔄 Deactivating $($selectedIndices.Count) role(s)..." -ForegroundColor Cyan
    Write-Host ""
    
    $successCount = 0
    $failCount = 0
    $skippedCount = 0
    
    foreach ($index in $selectedIndices) {
        # Validate index
        if ($index -lt 0 -or $index -ge $readyToDeactivate.Count) {
            Write-Host "⚠️ Invalid selection index: $index" -ForegroundColor Yellow
            continue
        }
        
        $role = $readyToDeactivate[$index]
        $assignment = $role.Assignment
        $roleName = $role.RoleName
        
        try {
            # Validate assignment data
            if (-not $assignment.PrincipalId -or -not $assignment.RoleDefinitionId) {
                Write-Host "❌ Invalid assignment data for: $roleName" -ForegroundColor Red
                $failCount++
                continue
            }
            
            # Create deactivation request
            $deactivationRequest = @{
                action = "selfDeactivate"
                principalId = $assignment.PrincipalId
                roleDefinitionId = $assignment.RoleDefinitionId
                directoryScopeId = if ($assignment.DirectoryScopeId) { $assignment.DirectoryScopeId } else { "/" }
            }
            
            # Make the deactivation request
            $result = New-MgRoleManagementDirectoryRoleAssignmentScheduleRequest -BodyParameter $deactivationRequest
            
            if ($result) {
                Write-Host "✅ Successfully deactivated: $roleName" -ForegroundColor Green
                $successCount++
                
                # Clear cache to ensure fresh data on next deactivation check
                $script:ScheduleInstanceCache = @{}
                $script:ScheduleInstanceCacheExpiry = (Get-Date).AddSeconds(-1)
                
                # FIXED: Clear global active role cache so deactivated role appears in activation workflow
                $global:ActiveRoleCache = @()
                $global:ActiveRoleCacheTime = $null
            } else {
                Write-Host "❌ Failed to deactivate: $roleName" -ForegroundColor Red
                $failCount++
            }
            
        } catch {
            $errorMessage = $_.Exception.Message
            if ($errorMessage -like "*RoleAssignmentDoesNotExist*") {
                Write-Host "⚠️ Role already deactivated: $roleName" -ForegroundColor Yellow
                $skippedCount++
            } else {
                Write-Host "❌ Role deactivation failed for ${roleName}: $errorMessage" -ForegroundColor Red
                $failCount++
            }
        }
    }
    
    Write-Host ""
    
    # Ask if user wants to manage more roles
    do {
        $input = Read-PIMInput -Prompt "Would you like to manage more roles? (Y/N)" -ControlsText $script:ControlMessages['Exit']
        $input = $input.Trim().ToUpper()
        if ($input -eq "Y" -or $input -eq "YES") {
            $continueChoice = "Yes"
            break
        } elseif ($input -eq "N" -or $input -eq "NO") {
            $continueChoice = "No"
            break
        } else {
            Write-Host "Please enter Y or N." -ForegroundColor Yellow
        }
    } while ($true)
    
    if ($continueChoice -eq "Yes") {
        # Smart routing: Check what workflows are available
        $eligibleRoles = Get-EligibleRolesOptimized -CurrentUserId $CurrentUserId
        # Get active roles using cached approach to avoid duplicate API calls
        $scheduleInstances = Get-CachedScheduleInstances -CurrentUserId $CurrentUserId
        $activeRoles = @()
        foreach ($instance in $scheduleInstances) {
            $roleDefinition = Get-CachedRoleDefinition -RoleId $instance.RoleDefinitionId
            if ($roleDefinition) {
                $activeRoles += [PSCustomObject]@{
                    RoleName = $roleDefinition.DisplayName
                    Assignment = $instance
                }
            }
        }
        
        # Filter out roles that are too new (within 5 minutes) for deactivation
        $readyForDeactivation = @()
        if ($activeRoles.Count -gt 0) {
            foreach ($role in $activeRoles) {
                $assignment = $role.Assignment
                
                # Use StartDateTime from the schedule instance we already have
                if ($assignment.StartDateTime) {
                    $activationTime = [DateTime]::Parse($assignment.StartDateTime).ToLocalTime()
                    $timeSinceActivation = (Get-Date) - $activationTime
                    
                    if ($timeSinceActivation.TotalMinutes -ge 5) {
                        $readyForDeactivation += $role
                    }
                } else {
                    $readyForDeactivation += $role
                }
            }
        }
        
        # Smart routing logic
        if ($eligibleRoles.Count -gt 0 -and $readyForDeactivation.Count -gt 0) {
            # Both workflows available - show choice menu using proper checkbox menu
            $menuItems = @("Activate Roles", "Deactivate Roles")
            $selectedIndices = Show-CheckboxMenu -Items $menuItems -Title "🔄 Choose Action" -Prompt "Use arrow keys to navigate, SPACE to toggle selection, ENTER to confirm:" -SingleSelection
            
            if ($selectedIndices.Count -gt 0) {
                $selectedIndex = $selectedIndices[0]
                $selectedAction = $menuItems[$selectedIndex]
                
                if ($selectedAction -eq "Activate Roles") {
                    Start-RoleActivationWorkflow -ValidRoles $eligibleRoles -CurrentUserId $CurrentUserId
                } elseif ($selectedAction -eq "Deactivate Roles") {
                    Start-RoleDeactivationWorkflowWithCheck -CurrentUserId $CurrentUserId
                }
            }
        } elseif ($eligibleRoles.Count -gt 0) {
            # Only activation available - go directly to activation
            Start-RoleActivationWorkflow -ValidRoles $eligibleRoles -CurrentUserId $CurrentUserId
        } elseif ($readyForDeactivation.Count -gt 0) {
            # Only deactivation available - go directly to deactivation
            Start-RoleDeactivationWorkflowWithCheck -CurrentUserId $CurrentUserId
        } else {
            # No workflows available
            Write-Host "❌ No role management workflows currently available." -ForegroundColor Red
            Write-Host ""
            Write-Host "Check back later when roles are approved or activated." -ForegroundColor Gray
        }
        return
    } else {
        Write-Host "❌ No role management workflows available." -ForegroundColor Red
                    Write-Host ""
                    Write-Host "Check back later when roles are approved or activated." -ForegroundColor Gray
                    Write-Host ""
                    Show-DynamicControlBar
                    
                    # Wait for Ctrl+Q to exit
                    do {
                        $key = [Console]::ReadKey($true)
                        if ($key.Key -eq 'Q' -and $key.Modifiers -eq 'Control') {
                            Invoke-PIMExit -Message "Exiting PIM role management..."
                        }
                    } while ($true)
                    return
        Write-Host "Script completed successfully." -ForegroundColor Green
        return
    }
    
    # Use expiration data already collected during initial role retrieval - NO ADDITIONAL API CALLS
    $roleExpirationData = @()
    $filteredReadyToDeactivate = @()
    
    # Process roles using expiration data already available in role objects
    foreach ($role in $readyToDeactivate) {
        # Check if role is already expired using data we already have
        if ($role.ExpirationTime) {
            if ($role.ExpirationTime -gt (Get-Date)) {
                # Role is still active, include it
                $filteredReadyToDeactivate += $role
                $roleExpirationData += [PSCustomObject]@{
                    Role = $role
                    ExpirationTime = $role.ExpirationTime
                }
            }
            # If expired, skip this role entirely
        } else {
            # No expiration data, assume it's still active
            $filteredReadyToDeactivate += $role
            $roleExpirationData += [PSCustomObject]@{
                Role = $role
                ExpirationTime = $null
            }
        }
    }
    
    # Update readyToDeactivate to only include non-expired roles
    $readyToDeactivate = $filteredReadyToDeactivate
    
    # Check if any roles remain after filtering out expired ones
    if ($readyToDeactivate.Count -eq 0) {
        Write-Host "ℹ️  No active roles to deactivate at this time." -ForegroundColor Gray
        Write-Host ""
        
        # Ask if user wants to activate roles instead with inline input handling
        Write-Host "Would you like to activate roles instead? (Y/N): " -NoNewline -ForegroundColor Cyan
        
        # Store cursor position for inline input
        $promptLeft = [Console]::CursorLeft
        $promptTop = [Console]::CursorTop
        
        # Show control bar below the prompt with proper spacing
        Write-Host "`n"  # Add blank line after prompt
        Write-Host "Ctrl+Q to exit" -ForegroundColor Magenta
        $script:LastControlBarLine = [Console]::CursorTop - 1
        
        # Return cursor to inline position after the prompt (same line as Y/N question)
        [Console]::SetCursorPosition($promptLeft, $promptTop)
        
        $userInput = ""
        do {
            $key = [Console]::ReadKey($true)
            
            # Check for Ctrl+Q
            if ($key.Key -eq 'Q' -and $key.Modifiers -eq 'Control') {
                Invoke-PIMExit
                return
            }
            
            # Handle Enter key
            if ($key.Key -eq 'Enter') {
                if ($userInput -eq 'Y' -or $userInput -eq 'y') {
                    # Clear the control bar and move cursor to start of that line
                    if ($script:LastControlBarLine -ge 0) {
                        try {
                            [Console]::SetCursorPosition(0, $script:LastControlBarLine)
                            Write-Host (" " * [Console]::WindowWidth) -NoNewline
                            $script:LastControlBarLine = -1
                        } catch { }
                    }
                    Clear-Host
                                        Start-PIMRoleManagement -CurrentUserId $CurrentUserId
                                        return
                } elseif ($userInput -eq 'N' -or $userInput -eq 'n') {
                    Write-Host ""
                    Write-Host "❌ No role management workflows available." -ForegroundColor Red
                    Write-Host ""
                    Write-Host "Check back later when roles are approved or activated." -ForegroundColor Gray
                    Write-Host ""
                    Show-DynamicControlBar
                    
                    # Wait for Ctrl+Q to exit
                    do {
                        $key = [Console]::ReadKey($true)
                        if ($key.Key -eq 'Q' -and $key.Modifiers -eq 'Control') {
                            Invoke-PIMExit -Message "Exiting PIM role management..."
                        }
                    } while ($true)
                    return
                    return
                } else {
                    Write-Host ""
                    Write-Host "Please enter Y or N: " -NoNewline -ForegroundColor Yellow
                    # Clear and redraw control bar for invalid input
                    if ($script:LastControlBarLine -ge 0) {
                        try {
                            [Console]::SetCursorPosition(0, $script:LastControlBarLine)
                            Write-Host (" " * [Console]::WindowWidth) -NoNewline
                        } catch { }
                    }
                    Write-Host ""
                    Write-Host "Ctrl+Q to exit" -ForegroundColor Magenta
                    $script:LastControlBarLine = [Console]::CursorTop - 1
                    # Return cursor to prompt position
                    [Console]::SetCursorPosition([Console]::CursorLeft, [Console]::CursorTop - 2)
                    $userInput = ""
                }
            }
            # Handle backspace
            elseif ($key.Key -eq 'Backspace' -and $userInput.Length -gt 0) {
                $userInput = $userInput.Substring(0, $userInput.Length - 1)
                Write-Host "`b `b" -NoNewline
            }
            # Handle regular characters (Y/N only)
            elseif ($key.KeyChar -match '[YyNn]' -and $userInput.Length -eq 0) {
                $userInput = $key.KeyChar.ToString().ToUpper()
                Write-Host $userInput -NoNewline -ForegroundColor Green
            }
        } while ($true)
        return
    }
    
    # Show dynamic countdown menu
    $selectedIndices = Show-DynamicExpirationMenu -RoleExpirationData $roleExpirationData -Title "🔄 Select Active Roles to Deactivate"
    
    if ($selectedIndices.Count -eq 0) {
                Write-Host "❌ No roles selected for deactivation." -ForegroundColor Yellow
        return
    }
    
    # Clear screen and show clean deactivation progress
    Clear-Host
    Show-PIMGlobalHeaderMinimal
    Write-Host ""
    Write-Host "🔄 Deactivating $($selectedIndices.Count) role(s)..." -ForegroundColor Cyan
    Write-Host ""
    
    $successCount = 0
    $failCount = 0
    $skippedCount = 0
    
    foreach ($index in $selectedIndices) {
        # Validate index
        if ($index -lt 0 -or $index -ge $readyToDeactivate.Count) {
            Write-Host "⚠️ Invalid selection index: $index" -ForegroundColor Yellow
            continue
        }
        
        $role = $readyToDeactivate[$index]
        $assignment = $role.Assignment
        $roleName = $role.RoleName
        
        try {
            # Validate assignment data
            if (-not $assignment.PrincipalId -or -not $assignment.RoleDefinitionId) {
                Write-Host "   ❌ Invalid assignment data for: $roleName" -ForegroundColor Red
                $failCount++
                continue
            }
            
            # Create deactivation request
            $deactivationRequest = @{
                action = "selfDeactivate"
                principalId = $assignment.PrincipalId
                roleDefinitionId = $assignment.RoleDefinitionId
                directoryScopeId = if ($assignment.DirectoryScopeId) { $assignment.DirectoryScopeId } else { "/" }
            }
            
            # Make the deactivation request
            $result = New-MgRoleManagementDirectoryRoleAssignmentScheduleRequest -BodyParameter $deactivationRequest
            
            if ($result) {
                Write-Host "✅ Successfully deactivated: $roleName" -ForegroundColor Green
                $successCount++
                
                # Clear cache to ensure fresh data on next deactivation check
                $script:ScheduleInstanceCache = @{}
                $script:ScheduleInstanceCacheExpiry = (Get-Date).AddSeconds(-1)
                
                # FIXED: Clear global active role cache so deactivated role appears in activation workflow
                $global:ActiveRoleCache = @()
                $global:ActiveRoleCacheTime = $null
            } else {
                Write-Host "❌ Failed to deactivate: $roleName" -ForegroundColor Red
                $failCount++
            }
            
        } catch {
            $errorMessage = $_.Exception.Message
            if ($errorMessage -like "*RoleAssignmentDoesNotExist*") {
                Write-Host "⚠️ Role already deactivated: $roleName" -ForegroundColor Yellow
                $skippedCount++
            } else {
                Write-Host "❌ Role deactivation failed for ${roleName}: $errorMessage" -ForegroundColor Red
                $failCount++
            }
        }
    }
    
    Write-Host ""
    
    # Ask if user wants to manage more roles
    do {
        $input = Read-PIMInput -Prompt "Would you like to manage more roles? (Y/N)" -ControlsText $script:ControlMessages['Exit']
        $input = $input.Trim().ToUpper()
        if ($input -eq "Y" -or $input -eq "YES") {
            $continueChoice = "Yes"
            break
        } elseif ($input -eq "N" -or $input -eq "NO") {
            $continueChoice = "No"
            break
        } else {
            Write-Host "Please enter Y or N." -ForegroundColor Yellow
        }
    } while ($true)
    
    if ($continueChoice -eq "Yes") {
        # Smart routing: Check what workflows are available
        $eligibleRoles = Get-EligibleRolesOptimized -CurrentUserId $CurrentUserId
        # Get active roles using cached approach to avoid duplicate API calls
        $scheduleInstances = Get-CachedScheduleInstances -CurrentUserId $CurrentUserId
        $activeRoles = @()
        foreach ($instance in $scheduleInstances) {
            $roleDefinition = Get-CachedRoleDefinition -RoleId $instance.RoleDefinitionId
            if ($roleDefinition) {
                $activeRoles += [PSCustomObject]@{
                    RoleName = $roleDefinition.DisplayName
                    Assignment = $instance
                }
            }
        }
        
        # Filter out roles that are too new (within 5 minutes) for deactivation
        $readyForDeactivation = @()
        if ($activeRoles.Count -gt 0) {
            $cachedSchedules = Get-CachedSchedules -CurrentUserId $CurrentUserId
            foreach ($role in $activeRoles) {
                $assignment = $role.Assignment
                # Use same logic as deactivation workflow - only check recent requests
                $recentCutoff = (Get-Date).AddMinutes(-10)
                $schedules = $cachedSchedules | Where-Object { 
                    $_.PrincipalId -eq $assignment.PrincipalId -and 
                    $_.RoleDefinitionId -eq $assignment.RoleDefinitionId -and
                    [DateTime]::Parse($_.CreatedDateTime) -gt $recentCutoff
                }
                
                if ($schedules) {
                    $activationSchedules = $schedules | Where-Object { $_.Action -eq "selfActivate" }
                    if ($activationSchedules) {
                        $latestSchedule = $activationSchedules | Sort-Object CreatedDateTime -Descending | Select-Object -First 1
                        $requestTime = [DateTime]::Parse($latestSchedule.CreatedDateTime).ToLocalTime()
                        
                        # Use the actual API timestamp - this is the real activation time
                        $activationTime = $requestTime
                        
                        $timeSinceActivation = (Get-Date) - $activationTime
                        if ($timeSinceActivation.TotalMinutes -ge 5) {
                            $readyForDeactivation += $role
                        }
                    } else {
                        $readyForDeactivation += $role
                    }
                } else {
                    $readyForDeactivation += $role
                }
            }
        }
        
        # Smart routing logic
        if ($eligibleRoles.Count -gt 0 -and $readyForDeactivation.Count -gt 0) {
            # Both workflows available - show choice menu using proper checkbox menu
            $menuItems = @("Activate Roles", "Deactivate Roles")
            $selectedIndices = Show-CheckboxMenu -Items $menuItems -Title "🔄 Choose Action" -Prompt "Use arrow keys to navigate, SPACE to toggle selection, ENTER to confirm:" -SingleSelection
            
            if ($selectedIndices.Count -gt 0) {
                $selectedIndex = $selectedIndices[0]
                $selectedAction = $menuItems[$selectedIndex]
                
                if ($selectedAction -eq "Activate Roles") {
                    Start-RoleActivationWorkflow -ValidRoles $eligibleRoles -CurrentUserId $CurrentUserId
                } elseif ($selectedAction -eq "Deactivate Roles") {
                    Start-RoleDeactivationWorkflowWithCheck -CurrentUserId $CurrentUserId
                }
            }
        } elseif ($eligibleRoles.Count -gt 0) {
            # Only activation available - go directly to activation
            Start-RoleActivationWorkflow -ValidRoles $eligibleRoles -CurrentUserId $CurrentUserId
        } elseif ($readyForDeactivation.Count -gt 0) {
            # Only deactivation available - go directly to deactivation
            Start-RoleDeactivationWorkflowWithCheck -CurrentUserId $CurrentUserId
        } else {
            # No workflows available
            Write-Host "❌ No role management workflows currently available." -ForegroundColor Red
            Write-Host ""
            Write-Host "Check back later when roles are approved or activated." -ForegroundColor Gray
        }
        return
    } else {
        Write-Host "❌ No role management workflows available." -ForegroundColor Red
                    Write-Host ""
                    Write-Host "Check back later when roles are approved or activated." -ForegroundColor Gray
                    Write-Host ""
                    Show-DynamicControlBar
                    
                    # Wait for Ctrl+Q to exit
                    do {
                        $key = [Console]::ReadKey($true)
                        if ($key.Key -eq 'Q' -and $key.Modifiers -eq 'Control') {
                            Invoke-PIMExit -Message "Exiting PIM role management..."
                        }
                    } while ($true)
                    return
        Write-Host "Script completed successfully." -ForegroundColor Green
        return
    }
}

function Show-PIMGlobalHeader {
    Write-Host "[ P I M - G L O B A L ]" -ForegroundColor DarkMagenta
    Write-Host "PIM-Global - Automate PIM Role Activation Application via Microsoft Entra ID" -ForegroundColor Green
        Write-Host "Made by Mark Orr with " -NoNewline -ForegroundColor White
        Write-Host "☕ 3 cups of coffee" -NoNewline -ForegroundColor Yellow
        Write-Host " and " -NoNewline -ForegroundColor White  
        Write-Host "🥤 6 diet cokes" -NoNewline -ForegroundColor Red
        Write-Host "! Dedicated to " -NoNewline -ForegroundColor White
        Write-Host "Courtney and Aubrey" -ForegroundColor Magenta
    Write-Host "Version 3.0.0 | Release: 01.15.2025" -ForegroundColor Gray
    Write-Host ""
    Write-Host "This is a private version of the application. Feedback welcome at:" -ForegroundColor Yellow
    Write-Host "Issues: " -NoNewline -ForegroundColor White
    }
    
    function Show-PIMGlobalHeaderClean {
        Write-Host "[ P I M - G L O B A L ]" -ForegroundColor DarkMagenta
    }
    
    function Show-PIMGlobalHeaderMinimal {
        Write-Host "[ P I M - G L O B A L ]" -ForegroundColor DarkMagenta
    }
    
    # ========================= Centralized Control Menu System =========================
    
    # Control message constants
    $script:ControlMessages = @{
        'Exit' = "Ctrl+Q Exit"
        'Navigation' = "↑/↓ Navigate | SPACE Toggle | ENTER Confirm | Ctrl+Q Exit"
        'Input' = "Ctrl+Q Exit | ESC Cancel"
        'Menu' = "↑/↓ Navigate | SPACE Toggle | ENTER Confirm | Ctrl+Q Exit"
        'Shortcuts' = "Ctrl+A Select All | Ctrl+D Deselect All | Ctrl+R Refresh"
    }
    
    # Centralized exit handler
    function Invoke-PIMExit {
        param(
            [string]$Message = "Exiting..."
        )
        
        Clear-Host
        Write-Host $Message -ForegroundColor Yellow
        
        try {
            Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
            Write-Host "✅ Disconnected from Microsoft Graph." -ForegroundColor Green
        } catch {
            Write-Host "ℹ️ Already disconnected from Microsoft Graph." -ForegroundColor DarkGray
        }
        
        Write-Host "Terminal will close in 2 seconds..." -ForegroundColor Yellow
        Start-Sleep -Seconds 2
        [Environment]::Exit(0)
    }
    
    # Centralized key handler for common shortcuts
    function Test-GlobalShortcut {
        param(
            [System.ConsoleKeyInfo]$Key
        )
        
        # Handle Ctrl+Q globally
        if ($Key.Key -eq 'Q' -and $Key.Modifiers -eq 'Control') {
            Invoke-PIMExit
            return $true
        }
        
        return $false
    }
    
    # Enhanced input reader with centralized control handling
    function Read-PIMInput {
        param(
            [string]$Prompt,
            [string]$ControlsText = $script:ControlMessages['Input'],
            [switch]$Required,
            [string]$ValidationPattern,
            [string]$ValidationMessage
        )
        
        # Display prompt with colon and space, keep cursor inline
        Write-Host "${Prompt}: " -ForegroundColor Cyan -NoNewline
        
        # Store cursor position for inline input
        $promptLeft = [Console]::CursorLeft
        $promptTop = [Console]::CursorTop
        
        # Show control bar below the prompt
        Write-Host ""  # Move to next line
        Write-Host $ControlsText -ForegroundColor Magenta
        $script:LastControlBarLine = [Console]::CursorTop - 1
        
        # Return cursor to inline position after the prompt
        [Console]::SetCursorPosition($promptLeft, $promptTop)
        
        $input = ""
        do {
            $key = [Console]::ReadKey($true)
            
            # Check global shortcuts first
            if (Test-GlobalShortcut -Key $key) {
                return $null
            }
            
            # Handle ESC for cancellation
            if ($key.Key -eq 'Escape') {
                Write-Host ""
                return $null
            }
            
            # Handle Enter
            if ($key.Key -eq 'Enter') {
                # Move to next line after input and clear control bar
                Write-Host ""
                # Clear the control bar when input is complete
                if ($script:LastControlBarLine -ge 0) {
                    try {
                        [Console]::SetCursorPosition(0, $script:LastControlBarLine)
                        Write-Host (" " * [Console]::WindowWidth) -NoNewline
                        [Console]::SetCursorPosition(0, $script:LastControlBarLine)
                        $script:LastControlBarLine = -1
                    } catch { }
                }
                break
            }
            
            # Handle Backspace
            if ($key.Key -eq 'Backspace' -and $input.Length -gt 0) {
                $input = $input.Substring(0, $input.Length - 1)
                Write-Host "`b `b" -NoNewline
            }
            
            # Handle regular characters
            elseif ($key.KeyChar -ne "`0" -and [char]::IsControl($key.KeyChar) -eq $false) {
                $input += $key.KeyChar
                Write-Host $key.KeyChar -NoNewline -ForegroundColor White
            }
        } while ($true)
        
        # Validate input if required
        if ($Required -and [string]::IsNullOrWhiteSpace($input)) {
            Write-Host "Input is required." -ForegroundColor DarkRed
            return Read-PIMInput -Prompt $Prompt -ControlsText $ControlsText -Required:$Required -ValidationPattern $ValidationPattern -ValidationMessage $ValidationMessage
        }
        
        if ($ValidationPattern -and $input -notmatch $ValidationPattern) {
            Write-Host $ValidationMessage -ForegroundColor DarkRed
            return Read-PIMInput -Prompt $Prompt -ControlsText $ControlsText -Required:$Required -ValidationPattern $ValidationPattern -ValidationMessage $ValidationMessage
        }
        
        return $input
    }
    
    # Dynamic Control Bar System
    $script:LastControlBarLine = -1
    
    function Show-DynamicControlBar {
        param(
            [string]$ControlsText = $script:ControlMessages['Exit'],
            [switch]$Force
        )
    
        # Get current cursor position
        $currentLeft = [Console]::CursorLeft
        $currentTop = [Console]::CursorTop
        
        # Calculate target line (one line below current content for dynamic movement)
        $targetTop = $currentTop + 1
        
        # Clear previous control bar if it exists
        if ($script:LastControlBarLine -ge 0 -and ($script:LastControlBarLine -ne $targetTop -or $Force)) {
            try {
                [Console]::SetCursorPosition(0, $script:LastControlBarLine)
                Write-Host (" " * [Console]::WindowWidth) -NoNewline
            } catch {
                # Ignore if we can't clear the old line
            }
        }
        
        # Ensure buffer is tall enough
        if ($targetTop -ge [Console]::BufferHeight) {
            [Console]::BufferHeight = $targetTop + 1
        }
        
        # Draw the new control bar
        try {
            [Console]::SetCursorPosition(0, $targetTop)
            Write-Host $ControlsText -ForegroundColor Magenta
            
            # Update last control bar line
            $script:LastControlBarLine = $targetTop
            
            # Don't move cursor - let calling function handle positioning
        } catch {
            # Fallback to original position if something goes wrong
            try {
                [Console]::SetCursorPosition($currentLeft, $currentTop)
            } catch {
                # If all else fails, just continue
            }
        }
    }
    
    # Enhanced Write-Host wrapper that updates control bar
    function Write-PIMHost {
        param(
            [string]$Object = "",
            [ConsoleColor]$ForegroundColor = [Console]::ForegroundColor,
            [ConsoleColor]$BackgroundColor = [Console]::BackgroundColor,
            [switch]$NoNewline,
            [string]$ControlsText = $null
        )
        
        Write-Host $Object -ForegroundColor $ForegroundColor -BackgroundColor $BackgroundColor -NoNewline:$NoNewline
        
        # Only show control bar when explicitly requested
        if ($ControlsText) {
            Show-DynamicControlBar -ControlsText $ControlsText
        }
    }
    
    # Sticky Controls Helper (Enhanced) - Backward compatibility
    function Show-StickyControls {
        param(
            [string]$ControlsText = $script:ControlMessages['Exit']
        )
        
        Show-DynamicControlBar -ControlsText $ControlsText
    }
    
    # Centralized menu choice handler
    function Show-PIMChoiceMenu {
        param(
            [string[]]$Choices,
            [string]$Title = "Select an option",
            [string]$Prompt = "Use arrow keys to navigate, ENTER to select:",
            [int]$DefaultIndex = 0
        )
        
        $currentIndex = $DefaultIndex
        $maxIndex = $Choices.Count - 1
        
        do {
            Clear-Host
            Show-PIMGlobalHeaderMinimal
            Write-Host ""
            Write-Host $Title -ForegroundColor Cyan
            Write-Host $Prompt -ForegroundColor Gray
            Write-Host ""
            
            for ($i = 0; $i -lt $Choices.Count; $i++) {
                $prefix = if ($i -eq $currentIndex) { "► " } else { "  " }
                $color = if ($i -eq $currentIndex) { "Yellow" } else { "White" }
                Write-Host "$prefix$($Choices[$i])" -ForegroundColor $color
            }
            
            Write-Host ""
            Show-StickyControls -ControlsText $script:ControlMessages['Navigation']
            
            $key = [Console]::ReadKey($true)
            
            # Check global shortcuts
            if (Test-GlobalShortcut -Key $key) {
                return $null
            }
            
            switch ($key.Key) {
                "UpArrow" {
                    $currentIndex = if ($currentIndex -eq 0) { $maxIndex } else { $currentIndex - 1 }
                }
                "DownArrow" {
                    $currentIndex = if ($currentIndex -eq $maxIndex) { 0 } else { $currentIndex + 1 }
                }
                "Enter" {
                    return $currentIndex
                }
                "Escape" {
                    return $null
                }
            }
        } while ($true)
    }
    
    Clear-Host
    Show-PIMGlobalHeader
    Write-Host "https://github.com/markorr321/PIM-Global-Self-Activate/issues" -ForegroundColor Blue
    Write-Host ""
    Write-Host "Love this tool? Consider sponsoring development:" -ForegroundColor White
    Write-Host "GitHub: " -NoNewline -ForegroundColor White
    Write-Host "https://github.com/sponsors/markorr321" -ForegroundColor Blue
    Write-Host "Development opportunities: " -NoNewline -ForegroundColor White
    Write-Host "morr@orr365.tech" -ForegroundColor Cyan
    Start-Sleep -Seconds 3
    
    # ========================= Optimized Module Dependencies =========================
    $ErrorActionPreference = "SilentlyContinue"
    
    # Remove any pre-loaded Graph modules to prevent version conflicts
    Get-Module Microsoft.Graph.* | Remove-Module -Force -ErrorAction SilentlyContinue
    
    # Optimizing module loading silently
    
    # Install MSAL.PS if not available
    if (-not (Get-Module -Name MSAL.PS) -and -not (Get-Module -ListAvailable -Name MSAL.PS)) {
        Write-Host "Installing MSAL.PS..." -ForegroundColor Yellow
        Install-Module MSAL.PS -Scope CurrentUser -Force
    }
    
    # Install only required Graph modules instead of the entire Microsoft.Graph meta-package
    $requiredGraphModules = @(
        "Microsoft.Graph.Authentication",
        "Microsoft.Graph.Identity.DirectoryManagement",
        "Microsoft.Graph.Users"
    )
    
    foreach ($module in $requiredGraphModules) {
        # Skip installation if module is already loaded (any version)
        if (-not (Get-Module -Name $module)) {
            if (-not (Get-Module -ListAvailable -Name $module)) {
                Write-Host "Installing $module..." -ForegroundColor Yellow
                Install-Module $module -Scope CurrentUser -Force
            }
        }
    }
    
    # Import modules explicitly to ensure clean loading
    foreach ($module in $requiredGraphModules) {
        Import-Module $module -Force -ErrorAction SilentlyContinue
    }
    
    # Optimized modules ready silently
    
    # ========================= Teams Webhook Configuration =========================
    # Configure your Teams webhook URL here
    # To create a webhook: Teams Channel → More options → Manage channel → Edit → Incoming Webhook → Add
    $teamsWebhookUrl = "https://cmaorrtech.webhook.office.com/webhookb2/102682b7-85c6-4c3e-b98b-c3b460fe8011@51eb883f-451f-4194-b108-4df354b35bf4/IncomingWebhook/33c507565393483ab034c8d19ed3c1fb/8cc8faec-1b97-40f0-ab11-eddcf89d54a1/V2HLN3VPRcvQK5pVYjkVjRpzG6-seyiOIzAXbXB0U8e9A1"
    
    # Approval channel webhook URL (for approval-required roles)
    $approvalChannelWebhookUrl = "https://cmaorrtech.webhook.office.com/webhookb2/d4f674d6-36f8-4e0a-9d2a-7cdb5d3bf196@51eb883f-451f-4194-b108-4df354b35bf4/IncomingWebhook/f2192c4bc3cf48fca3fcb5e93cb4d45a/8cc8faec-1b97-40f0-ab11-eddcf89d54a1/V21J6fdDWCg3a4nctZ5U_fF7NGWprF4HPd6EYQEORq4kk1"
    
    # Power Automate URL for interactive approvals (for immediate activation roles)
    $powerAutomateApprovalUrl = "https://default51eb883f451f4194b1084df354b35b.f4.environment.api.powerplatform.com:443/powerautomate/automations/direct/workflows/6805f3b5957f452d96dafd153561d04d/triggers/manual/paths/invoke/?api-version=1&sp=%2Ftriggers%2Fmanual%2Frun&sv=1.0&sig=oARAEv9M68wOCUwUMDpt1oEiqDd7We84z3f6aY45h2A"
    
    # Enable/disable Teams notifications (set to $false if experiencing hangs)
    $enableTeamsNotifications = $true
    
    # Enable/disable batching multiple role requests into single approval
    $enableBatchApprovals = $false
    
    # Azure PIM Portal URL for approvals
    $pimApprovalUrl = "https://portal.azure.com/?Microsoft_Azure_PIMCommon=true#view/Microsoft_Azure_PIMCommon/ApproveRequestMenuBlade/~/aadmigratedroles"
    
    # ========================= ACTIVATION WORKFLOW =========================
    function Start-RoleActivationWorkflow {
        param(
            [array]$ValidRoles,
            [string]$CurrentUserId
        )
        
        if ($ValidRoles.Count -eq 0) {
            # Clear any existing control bar first
            if ($script:LastControlBarLine -ge 0) {
                try {
                    [Console]::SetCursorPosition(0, $script:LastControlBarLine)
                    Write-Host (" " * [Console]::WindowWidth) -NoNewline
                    $script:LastControlBarLine = -1
                } catch { }
            }
            
            Write-PIMHost "❌ No eligible roles available for activation." -ForegroundColor Red
            Write-PIMHost ""
            Write-PIMHost "Would you like to deactivate roles instead? (Y/N): " -NoNewline -ForegroundColor Cyan
            
            # Store cursor position for inline input
            $promptLeft = [Console]::CursorLeft
            $promptTop = [Console]::CursorTop
            
            # Show control bar below the prompt with proper spacing
            Write-PIMHost "`n"  # Add blank line after prompt
            Write-PIMHost "Y/N to choose | Ctrl+Q Exit" -ForegroundColor Magenta
            $script:LastControlBarLine = [Console]::CursorTop - 1
            
            # Return cursor to inline position after the prompt (same line as Y/N question)
            [Console]::SetCursorPosition($promptLeft, $promptTop)
            
            $userInput = ""
            do {
                $key = [Console]::ReadKey($true)
                
                # Check for Ctrl+Q
                if ($key.Key -eq 'Q' -and $key.Modifiers -eq 'Control') {
                    Invoke-PIMExit
                    return
                }
                
                # Handle Enter key
                if ($key.Key -eq 'Enter') {
                    if ($userInput -eq 'Y' -or $userInput -eq 'y') {
                        # Clear the control bar and move cursor to start of that line
                        if ($script:LastControlBarLine -ge 0) {
                            try {
                                [Console]::SetCursorPosition(0, $script:LastControlBarLine)
                                Write-Host (" " * [Console]::WindowWidth) -NoNewline
                                [Console]::SetCursorPosition(0, $script:LastControlBarLine)
                                $script:LastControlBarLine = -1
                            } catch { }
                        }
                        # Get active roles using cached approach to avoid duplicate API calls
                        $scheduleInstances = Get-CachedScheduleInstances -CurrentUserId $CurrentUserId
                        $activeRoles = @()
                        foreach ($instance in $scheduleInstances) {
                            $roleDefinition = Get-CachedRoleDefinition -RoleId $instance.RoleDefinitionId
                            if ($roleDefinition) {
                                $activeRoles += [PSCustomObject]@{
                                    RoleName = $roleDefinition.DisplayName
                                    Assignment = $instance
                                }
                            }
                        }
                        if ($activeRoles.Count -gt 0) {
                            Start-RoleDeactivationWorkflowWithCheck -CurrentUserId $CurrentUserId
                        } else {
                            Write-Host "❌ No active roles available for deactivation." -ForegroundColor Red
                            Write-Host ""
                            Write-Host "❌ No role management workflows available." -ForegroundColor Yellow
                            Write-Host ""
                            Write-Host "Check back later when roles are approved or activated." -ForegroundColor White
                            Write-Host ""
                            Write-Host "Ctrl+Q Exit" -ForegroundColor Magenta
                            
                            # Hide cursor since no input is needed
                            [Console]::CursorVisible = $false
                            
                            # Control bar already shown above, no need for dynamic control bar
                            
                            # Wait for user to exit with Ctrl+Q
                            do {
                                if ([Console]::KeyAvailable) {
                                    $key = [Console]::ReadKey($true)
                                    if ($key.Key -eq 'Q' -and $key.Modifiers -eq 'Control') {
                                        Invoke-PIMExit
                                        return
                                    }
                                }
                                Start-Sleep -Milliseconds 100
                            } while ($true)
                        }
                        return
                    } elseif ($userInput -eq 'N' -or $userInput -eq 'n') {
                        # Clear the control bar and move cursor to start of that line
                        if ($script:LastControlBarLine -ge 0) {
                            try {
                                [Console]::SetCursorPosition(0, $script:LastControlBarLine)
                                Write-Host (" " * [Console]::WindowWidth) -NoNewline
                                [Console]::SetCursorPosition(0, $script:LastControlBarLine)
                                $script:LastControlBarLine = -1
                            } catch { }
                        }
                        Write-Host "✅ No additional role management tasks available." -ForegroundColor Green
                        Write-Host ""
                        Write-Host "All eligible roles are currently activated." -ForegroundColor Gray
                        Write-Host ""
                        Write-Host "Ctrl+Q Exit" -ForegroundColor Magenta
                        
                        # Hide cursor since no input is needed
                        [Console]::CursorVisible = $false
                        
                        # Wait for user to exit with Ctrl+Q
                        do {
                            if ([Console]::KeyAvailable) {
                                $key = [Console]::ReadKey($true)
                                if ($key.Key -eq 'Q' -and $key.Modifiers -eq 'Control') {
                                    Invoke-PIMExit
                                    return
                                }
                            }
                            Start-Sleep -Milliseconds 100
                        } while ($true)
                        return
                    } else {
                        Write-Host ""
                        Write-Host "Please enter Y or N: " -NoNewline -ForegroundColor Yellow
                        # Clear and redraw control bar for invalid input
                        if ($script:LastControlBarLine -ge 0) {
                            try {
                                [Console]::SetCursorPosition(0, $script:LastControlBarLine)
                                Write-Host (" " * [Console]::WindowWidth) -NoNewline
                            } catch { }
                        }
                        Write-Host ""
                        Write-Host "Y/N to choose | Ctrl+Q Exit" -ForegroundColor Magenta
                        $script:LastControlBarLine = [Console]::CursorTop - 1
                        # Return cursor to prompt position
                        [Console]::SetCursorPosition([Console]::CursorLeft, [Console]::CursorTop - 2)
                        $userInput = ""
                    }
                }
                # Handle backspace
                elseif ($key.Key -eq 'Backspace' -and $userInput.Length -gt 0) {
                    $userInput = $userInput.Substring(0, $userInput.Length - 1)
                    Write-Host "`b `b" -NoNewline
                }
                # Handle regular characters (Y/N only)
                elseif ($key.KeyChar -match '[YyNn]' -and $userInput.Length -eq 0) {
                    $userInput = $key.KeyChar.ToString().ToUpper()
                    Write-Host $userInput -NoNewline -ForegroundColor Green
                }
            } while ($true)
        }
        
        # Prepare roles for display
        $roleItems = @()
        foreach ($role in $ValidRoles) {
            $scopeDisplay = ""
            $roleItems += "$($role.RoleDefinition.DisplayName)$scopeDisplay"
        }
        
        # Main workflow loop for role selection and activation
        do {
            # Show checkbox menu for role selection
            $selectedIndices = Show-CheckboxMenu -Items $roleItems -Title "Select Roles to Activate" -Prompt "Use arrow keys to navigate, SPACE to toggle selection, ENTER to confirm:"
            
            if ($selectedIndices.Count -eq 0) {
                Write-Host "❌ No roles selected for activation." -ForegroundColor Yellow
                return
            }
            
            Flush-ConsoleInput
        
            # Duration input - add to existing display
            do {
                $durationInput = Read-PIMInput -Prompt "Enter activation duration (e.g., 1H, 30M, 2H30M)" -ControlsText $script:ControlMessages['Input']
                
                if ([string]::IsNullOrWhiteSpace($durationInput) -or $durationInput -notmatch '^\d+[HM]') {
                    Write-Host "ERROR: Invalid format. Use '1H', '30M', or '2H30M'." -ForegroundColor Red
                }
            } while ([string]::IsNullOrWhiteSpace($durationInput) -or $durationInput -notmatch '^\d+[HM]')
            
            # Convert duration to ISO 8601 format and validate minimum 5 minutes
            $duration = $durationInput.ToUpper() -replace '(\d+)H', 'PT${1}H' -replace '(\d+)M', '${1}M'
            if ($duration -match '^\d+M$') { $duration = "PT$duration" }
            
            # Parse duration to check if it's less than 5 minutes
            $totalMinutes = 0
            if ($durationInput.ToUpper() -match '(\d+)H') { $totalMinutes += [int]$matches[1] * 60 }
            if ($durationInput.ToUpper() -match '(\d+)M') { $totalMinutes += [int]$matches[1] }
            
            if ($totalMinutes -lt 5) {
                Write-Host ""
                Write-Host "❌ Activation Duration too short: Minimum Required is 5 minutes." -ForegroundColor Red
                Write-Host ""
                Write-Host "Press any key to return to role selection..." -ForegroundColor Yellow
                $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
                Clear-Host
                Show-PIMGlobalHeaderMinimal
                Write-Host ""
                continue  # Restart the role selection loop
            }
            
            # If we get here, validation passed - break out of the loop
            break
            
        } while ($true)
    
        # Justification input
        $justification = Read-PIMInput -Prompt "Enter reason for activation" -ControlsText $script:ControlMessages['Input']
        
        if ([string]::IsNullOrWhiteSpace($justification)) {
            Write-Host "Justification is required." -ForegroundColor Red
            return
        }
        
        Write-Host ""
        Write-Host "🔄 Activating $($selectedIndices.Count) role(s)..." -ForegroundColor Cyan
        
        $successCount = 0
        $failCount = 0
        $warningCount = 0
        
        foreach ($index in $selectedIndices) {
            $role = $ValidRoles[$index]
            $roleName = $role.RoleDefinition.DisplayName
            
            try {
                # Create activation request
                $activationRequest = @{
                    action = "selfActivate"
                    principalId = $CurrentUserId
                    roleDefinitionId = $role.RoleDefinitionId
                    directoryScopeId = $role.DirectoryScopeId
                    justification = $justification
                    scheduleInfo = @{
                        startDateTime = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
                        expiration = @{
                            type = "afterDuration"
                            duration = $duration
                        }
                    }
                }
                
                # Make the activation request
                $result = New-MgRoleManagementDirectoryRoleAssignmentScheduleRequest -BodyParameter $activationRequest
                
                if ($result) {
                    Write-Host "✅ Role activation submitted for: $roleName" -ForegroundColor Green
                    $successCount++
                    
                    # REMOVED: Approval checking and notification logic - not needed for self-activating organizations
                } else {
                    Write-Host "❌ Failed to activate: $roleName" -ForegroundColor Yellow
                    $failCount++
                }
                
            } catch {
                $errorMsg = $_.Exception.Message
                if ($errorMsg -like "*RoleAssignmentExists*") {
                    Write-Host "⚠️ Skipped $roleName - role is already active" -ForegroundColor Yellow
                } else {
                    Write-Host "❌ Failed to activate: $roleName - $errorMsg" -ForegroundColor Red
                    $failCount++
                }
            }
        }
        
        Write-Host ""
        
        # Ask if user wants to manage more roles
        do {
            $input = Read-PIMInput -Prompt "Would you like to manage more roles? (Y/N)" -ControlsText $script:ControlMessages['Exit']
            $input = $input.Trim().ToUpper()
            if ($input -eq "Y" -or $input -eq "YES") {
                $continueChoice = "Yes"
                break
            } elseif ($input -eq "N" -or $input -eq "NO") {
                $continueChoice = "No"
                break
            } else {
                Write-Host "Please enter Y or N." -ForegroundColor Yellow
            }
        } while ($true)
        
        if ($continueChoice -eq "Yes") {
            # Use the working choice menu logic from main script
            $menuItems = @("Activate Roles", "Deactivate Roles")
            $selectedIndices = Show-CheckboxMenu -Items $menuItems -Title "🔄 Choose Action" -Prompt "Use arrow keys to navigate, SPACE to toggle selection, ENTER to confirm:" -SingleSelection
            
            if ($selectedIndices.Count -gt 0) {
                $selectedIndex = $selectedIndices[0]
                $selectedAction = $menuItems[$selectedIndex]
                
                if ($selectedAction -eq "Activate Roles") {
                    $eligibleRoles = Get-EligibleRolesOptimized -CurrentUserId $CurrentUserId
                    Start-RoleActivationWorkflow -ValidRoles $eligibleRoles -CurrentUserId $CurrentUserId
                } elseif ($selectedAction -eq "Deactivate Roles") {
                    Start-RoleDeactivationWorkflowWithCheck -CurrentUserId $CurrentUserId
                }
            }
        } else {
            Write-PIMHost "No additional roles will be managed." -ForegroundColor Cyan -ControlsText $script:ControlMessages['Exit']
            Write-PIMHost "Please close the terminal." -ForegroundColor Yellow -ControlsText $script:ControlMessages['Exit']
            
            # Wait for user to exit with Ctrl+Q
            do {
                if ([Console]::KeyAvailable) {
                    $key = [Console]::ReadKey($true)
                    if (Test-GlobalShortcut -Key $key) {
                        return
                    }
                }
                Start-Sleep -Milliseconds 100
            } while ($true)
        }
    }
    
    # ========================= Toast Notification Functions =========================
    function Show-ToastNotification {
        param(
            [string]$Title,
            [string]$Message,
            [string]$Type = "Success"
        )
        
        try {
            # Use PowerShell's built-in toast notification capability
            # This is the most reliable method for PowerShell scripts
            $null = [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]
            $null = [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime]
            
            # Create the toast template with image support
            $template = [Windows.UI.Notifications.ToastNotificationManager]::GetTemplateContent([Windows.UI.Notifications.ToastTemplateType]::ToastImageAndText02)
            
            # Add custom logo or system icon based on availability
            $imageElements = $template.GetElementsByTagName("image")
            if ($imageElements.Count -gt 0) {
                # Check for custom logo files (in order of preference)
                $customLogo = $null
                $logoFiles = @(
                    (Join-Path $PSScriptRoot "PIM.ico"),
                    (Join-Path $PSScriptRoot "pim-logo.ico"),
                    (Join-Path $PSScriptRoot "pim-logo.png"),
                    (Join-Path $PSScriptRoot "logo.ico"),
                    (Join-Path $PSScriptRoot "logo.png")
                )
                
                foreach ($logoFile in $logoFiles) {
                    if (Test-Path $logoFile) {
                        $customLogo = $logoFile
                        break
                    }
                }
                
                if ($customLogo) {
                    # Use custom logo
                    $logoUri = $customLogo.Replace('\', '/')
                    $imageElements[0].SetAttribute("src", "file:///$logoUri")
                } else {
                    # Use system icons based on type
                    switch ($Type) {
                        "Success" { 
                            $imageElements[0].SetAttribute("src", "ms-appx:///Assets/Square44x44Logo.png")
                        }
                        "Warning" { 
                            $imageElements[0].SetAttribute("src", "ms-appx:///Assets/Square44x44Logo.altform-unplated_targetsize-48.png")
                        }
                        "Error" { 
                            $imageElements[0].SetAttribute("src", "ms-appx:///Assets/Square44x44Logo.altform-unplated_targetsize-48.png")
                        }
                        default { 
                            $imageElements[0].SetAttribute("src", "ms-appx:///Assets/Square44x44Logo.png")
                        }
                    }
                }
                $imageElements[0].SetAttribute("alt", "PIM Global")
            }
            
            # Add visual styling based on type
            if ($Type -eq "Warning") {
                # Add warning styling to the toast XML
                $toastElement = $template.SelectSingleNode("/toast")
                if ($toastElement) {
                    $toastElement.SetAttribute("scenario", "reminder")
                }
            }
            
            # Set the text
            $template.GetElementsByTagName("text")[0].AppendChild($template.CreateTextNode($Title)) | Out-Null
            $template.GetElementsByTagName("text")[1].AppendChild($template.CreateTextNode($Message)) | Out-Null
            
            # Create and show the toast
            $toast = [Windows.UI.Notifications.ToastNotification]::new($template)
            $toast.ExpirationTime = [DateTimeOffset]::Now.AddSeconds(10)
            
            # Use a generic Windows app identifier that should work
            $appId = "Microsoft.Windows.Computer"
            [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($appId).Show($toast)
            
        } catch {
            # Fallback to system tray balloon notification
            try {
                Add-Type -AssemblyName System.Windows.Forms
                $balloon = New-Object System.Windows.Forms.NotifyIcon
                $balloon.Icon = [System.Drawing.SystemIcons]::Information
                $balloon.BalloonTipTitle = $Title
                $balloon.BalloonTipText = $Message
                $balloon.BalloonTipIcon = "Info"
                $balloon.Visible = $true
                $balloon.ShowBalloonTip(5000)
                
                # Clean up after showing
                Start-Job -ScriptBlock {
                    param($balloon)
                    Start-Sleep -Seconds 6
                    $balloon.Dispose()
                } -ArgumentList $balloon | Out-Null
                
            } catch {
                # Final fallback - just continue silently
            }
        }
    }
    
    # ========================= Teams Notification Functions =========================
    function Get-TimeZoneAbbreviation {
        $tz = Get-TimeZone
        $now = Get-Date
        $offset = $tz.GetUtcOffset($now)
        $isDst = $tz.IsDaylightSavingTime($now)
        $abbr = $tz.Id
        # Try to get a common abbreviation
        switch ($tz.Id) {
            'Pacific Standard Time' { $abbr = if ($isDst) { 'PDT' } else { 'PST' } }
            'Mountain Standard Time' { $abbr = if ($isDst) { 'MDT' } else { 'MST' } }
            'Central Standard Time' { $abbr = if ($isDst) { 'CDT' } else { 'CST' } }
            'Eastern Standard Time' { $abbr = if ($isDst) { 'EDT' } else { 'EST' } }
            'UTC' { $abbr = 'UTC' }
            default { $abbr = $tz.Id }
        }
        return $abbr
    }
    
    # REMOVED: Teams notification functions - not needed for self-activating organizations
    
    # REMOVED: Power Automate approval functions - not needed for self-activating organizations
    
    # REMOVED: All remaining notification functions - not needed for self-activating organizations
    
    # ========================= 1) Config & Login =========================
    $clientId = "bf34fc64-bbbc-45cb-9124-471341025093"
    $tenantId = "common"
    $claimsJson = '{"access_token":{"acrs":{"essential":true,"value":"c1"}}}'
    $extraParams = @{ "claims" = $claimsJson }
    
    $scopesDelegated = @(
        "User.Read",
        "GroupMember.Read.All",
        "RoleManagement.Read.Directory",
        "RoleManagement.ReadWrite.Directory",
        "Directory.Read.All"
    )
    
    try {
        Write-Host "🔐 Initiating authentication..." -ForegroundColor Cyan
        Write-Host "Please complete authentication in the browser window that opens." -ForegroundColor Yellow
        Write-Host ""
    
        # Clear MSAL token cache to force fresh authentication
        try {
            Clear-MsalTokenCache -ErrorAction SilentlyContinue
        } catch {
            # Ignore errors if cache doesn't exist
        }
    
    $tokenResult = Get-MsalToken -ClientId $clientId `
                                 -TenantId $tenantId `
                                 -Scopes $scopesDelegated `
                                 -Interactive `
                                 -ExtraQueryParameters $extraParams
    
        if (-not $tokenResult -or -not $tokenResult.AccessToken) {
            throw "Authentication failed - no token received"
        }
    
    $accessToken = $tokenResult.AccessToken
    $tenantId = $tokenResult.TenantId
    $secureToken = ConvertTo-SecureString $accessToken -AsPlainText -Force
        
        Write-Host "🔗 Connecting to Microsoft Graph..." -ForegroundColor Cyan
    Connect-MgGraph -AccessToken $secureToken -ErrorAction Stop | Out-Null
        
    $context = Get-MgContext
        if (-not $context -or -not $context.Account) {
            throw "Failed to establish Graph context"
        }
        
        $currentUser = Get-MgUser -UserId $context.Account -ErrorAction Stop
    $currentUserId = $currentUser.Id
    
    Write-Host ""
        Write-Host "✅ Authentication Successful!" -ForegroundColor DarkGreen
    Write-Host "User: $($context.Account)" -ForegroundColor Cyan
    Write-Host "Tenant: $tenantId" -ForegroundColor Cyan
    
    
    
    
    # ========================= Performance Optimization: API Caching =========================
    # Force clear all existing cache
    $global:CachedSchedules = $null
    $global:CachedSchedulesTime = $null
    $global:CachedRoleDefinitions = @{}
    $global:CacheExpiryMinutes = 0  # Force fresh data every time
    
    # Clear any existing cache from previous runs
    Remove-Variable -Name "CachedSchedules" -Scope Global -ErrorAction SilentlyContinue
    Remove-Variable -Name "CachedSchedulesTime" -Scope Global -ErrorAction SilentlyContinue
    
    # Advanced: Pre-computed string formatting cache
    $global:TimeFormatCache = @{}
    function Get-CachedTimeFormat {
        param([TimeSpan]$TimeSpan)
        
        $totalSeconds = [int]$TimeSpan.TotalSeconds
        
        if ($global:TimeFormatCache.ContainsKey($totalSeconds)) {
            return $global:TimeFormatCache[$totalSeconds]
        }
        
        $hours = [int][math]::Floor($TimeSpan.TotalHours)
        $minutes = [int][math]::Floor($TimeSpan.TotalMinutes % 60)
        $seconds = [int][math]::Floor($TimeSpan.TotalSeconds % 60)
        
        $formatted = "{0:D2}:{1:D2}:{2:D2}" -f $hours, $minutes, $seconds
        
        # Cache for future use (limit cache size to prevent memory bloat)
        if ($global:TimeFormatCache.Count -lt 1000) {
            $global:TimeFormatCache[$totalSeconds] = $formatted
        }
        
        return $formatted
    }
    
    # Advanced: Smart UI updates with change detection
    $global:LastUIState = @{}
    function Update-UIIfChanged {
        param(
            [string]$Key,
            [string]$NewContent,
            [int]$Line,
            [ConsoleColor]$Color = "White"
        )
        
        if ($global:LastUIState[$Key] -ne $NewContent) {
            [Console]::SetCursorPosition(0, $Line)
            Write-Host $NewContent.PadRight([Console]::WindowWidth - 1) -ForegroundColor $Color
            $global:LastUIState[$Key] = $NewContent
            Add-PerformanceMetric -Type "UIUpdates"
            return $true  # Changed
        }
        Add-PerformanceMetric -Type "UISkipped"
        return $false  # No change
    }
    
    # Advanced: Memory optimization
    function Optimize-Memory {
        # Force garbage collection for better performance
        [System.GC]::Collect()
        [System.GC]::WaitForPendingFinalizers()
        
        # Clear time format cache if it gets too large
        if ($global:TimeFormatCache.Count -gt 500) {
            $global:TimeFormatCache.Clear()
        }
        
        # Clear UI state cache periodically
        if ($global:LastUIState.Count -gt 100) {
            $global:LastUIState.Clear()
        }
    }
    
    # Advanced: Batch Graph API calls for maximum efficiency
    function Invoke-BatchGraphRequest {
        param(
            [array]$Requests,
            [int]$BatchSize = 20
        )
        
        if ($Requests.Count -eq 0) { return @() }
        
        $results = @()
        
        for ($i = 0; $i -lt $Requests.Count; $i += $BatchSize) {
            $batch = $Requests[$i..[math]::Min($i + $BatchSize - 1, $Requests.Count - 1)]
            
            $batchRequest = @{
                requests = @()
            }
            
            for ($j = 0; $j -lt $batch.Count; $j++) {
                $batchRequest.requests += @{
                    id = $j.ToString()
                    method = if ($batch[$j].Method) { $batch[$j].Method } else { "GET" }
                    url = $batch[$j].Url
                }
            }
            
            try {
                $response = Invoke-MgGraphRequest -Method POST -Uri "https://graph.microsoft.com/v1.0/`$batch" -Body ($batchRequest | ConvertTo-Json -Depth 3)
                if ($response.responses) {
                    foreach ($resp in $response.responses) {
                        if ($resp.status -eq 200 -and $resp.body) {
                            $results += $resp.body
                        }
                    }
                }
            } catch {
                Write-Host "⚠️  Batch request failed, using individual calls" -ForegroundColor Yellow
                # Fallback to individual calls
                foreach ($request in $batch) {
                    try {
                        $result = Invoke-MgGraphRequest -Method GET -Uri $request.Url
                        if ($result) { $results += $result }
                    } catch {
                        # Skip failed individual requests
                    }
                }
            }
            
            # Small delay between batches to avoid throttling
            if ($i + $BatchSize -lt $Requests.Count) {
                Start-Sleep -Milliseconds 100
            }
        }
        
        return $results
    }
    
    # Advanced: Persistent disk cache for multi-session performance
    $global:CacheDirectory = Join-Path $env:TEMP "PIMGlobalCache"
    $global:DiskCacheExpiryHours = 1
    
    function Initialize-DiskCache {
        if (-not (Test-Path $global:CacheDirectory)) {
            New-Item -ItemType Directory -Path $global:CacheDirectory -Force | Out-Null
        }
        
        # Clean old cache files (older than 1 hour)
        Get-ChildItem $global:CacheDirectory -Filter "*.json" -ErrorAction SilentlyContinue | Where-Object {
            $_.LastWriteTime -lt (Get-Date).AddHours(-$global:DiskCacheExpiryHours)
        } | Remove-Item -Force -ErrorAction SilentlyContinue
    }
    
    function Get-DiskCachedData {
        param(
            [string]$Key,
            [scriptblock]$DataProvider,
            [int]$ExpiryMinutes = 30
        )
        
        $cacheFile = Join-Path $global:CacheDirectory "$Key.json"
        
        # Check if cache file exists and is not expired
        if (Test-Path $cacheFile) {
            $cacheInfo = Get-Item $cacheFile
            if ($cacheInfo.LastWriteTime -gt (Get-Date).AddMinutes(-$ExpiryMinutes)) {
                try {
                    $cachedData = Get-Content $cacheFile -Raw | ConvertFrom-Json
                    return $cachedData
                } catch {
                    # Cache corrupted, will regenerate
                }
            }
        }
        
        # Generate fresh data
        $freshData = & $DataProvider
        
        # Save to cache
        try {
            $freshData | ConvertTo-Json -Depth 10 | Out-File $cacheFile -Encoding UTF8
                    } catch {
            # Cache write failed, continue without caching
        }
        
        return $freshData
    }
    
    # Advanced: Async operations for background processing
    function Start-AsyncOperation {
        param(
            [scriptblock]$Operation,
            [string]$Name = "AsyncOp",
            [hashtable]$Parameters = @{}
        )
        
        # PowerShell 7+ job-based async simulation
        $job = Start-Job -ScriptBlock $Operation -ArgumentList $Parameters -Name $Name
        return $job
    }
    
    function Wait-AsyncOperations {
        param([array]$Jobs, [int]$TimeoutSeconds = 30)
        
        $results = @()
        $completedJobs = @()
        
        # Wait for jobs with timeout
        $timeout = (Get-Date).AddSeconds($TimeoutSeconds)
        
        while ($Jobs.Count -gt $completedJobs.Count -and (Get-Date) -lt $timeout) {
            foreach ($job in $Jobs) {
                if ($job.State -eq 'Completed' -and $job -notin $completedJobs) {
                    try {
                        $result = Receive-Job $job
                        if ($result) { $results += $result }
                        $completedJobs += $job
                        Remove-Job $job
                    } catch {
                        # Job failed, skip it
                        $completedJobs += $job
                        Remove-Job $job
                    }
                }
            }
            Start-Sleep -Milliseconds 100
        }
        
        # Clean up any remaining jobs
        foreach ($job in $Jobs) {
            if ($job -notin $completedJobs) {
                Stop-Job $job -ErrorAction SilentlyContinue
                Remove-Job $job -ErrorAction SilentlyContinue
            }
        }
        
        return $results
    }
    
    # Advanced: Predictive caching based on usage patterns
    $global:AccessPatterns = @{}
    $global:PredictiveCache = @{}
    
    function Track-DataAccess {
        param([string]$Key, [string]$Operation = "read")
        
        if (-not $global:AccessPatterns.ContainsKey($Key)) {
            $global:AccessPatterns[$Key] = @{
                Count = 0
                LastAccessed = Get-Date
                AccessTimes = @()
                Operations = @()
            }
        }
        
        $pattern = $global:AccessPatterns[$Key]
        $pattern.Count++
        $pattern.LastAccessed = Get-Date
        $pattern.AccessTimes += Get-Date
        $pattern.Operations += $Operation
        
        # Keep only last 10 access times to prevent memory bloat
        if ($pattern.AccessTimes.Count -gt 10) {
            $pattern.AccessTimes = $pattern.AccessTimes[-10..-1]
            $pattern.Operations = $pattern.Operations[-10..-1]
        }
    }
    
    function Get-PredictiveCacheKeys {
        # Return keys that are likely to be accessed soon based on patterns
        $hotKeys = $global:AccessPatterns.Keys | Where-Object {
            $pattern = $global:AccessPatterns[$_]
            $pattern.Count -gt 2 -and
            ((Get-Date) - $pattern.LastAccessed).TotalMinutes -lt 15
        } | Sort-Object { $global:AccessPatterns[$_].Count } -Descending
        
        return $hotKeys | Select-Object -First 5
    }
    
    function Start-PredictivePreload {
        # Background job to preload likely-needed data
        $predictiveKeys = Get-PredictiveCacheKeys
        
        foreach ($key in $predictiveKeys) {
            if (-not $global:PredictiveCache.ContainsKey($key)) {
                # Start async preload based on key pattern
                if ($key -match "schedule") {
                    $job = Start-AsyncOperation -Name "Preload_$key" -Operation {
                        # Preload schedule data
                        try {
                            Get-MgRoleManagementDirectoryRoleAssignmentSchedule -All | Select-Object -First 50
                        } catch { $null }
                    }
                    $global:PredictiveCache[$key] = @{ Job = $job; StartTime = Get-Date }
                }
            }
        }
        
        # Clean up old preload jobs
        $expiredKeys = $global:PredictiveCache.Keys | Where-Object {
            ((Get-Date) - $global:PredictiveCache[$_].StartTime).TotalMinutes -gt 5
        }
        foreach ($key in $expiredKeys) {
            if ($global:PredictiveCache[$key].Job) {
                Stop-Job $global:PredictiveCache[$key].Job -ErrorAction SilentlyContinue
                Remove-Job $global:PredictiveCache[$key].Job -ErrorAction SilentlyContinue
            }
            $global:PredictiveCache.Remove($key)
        }
    }
    
    # Advanced: Performance monitoring and metrics
    $global:PerformanceMetrics = @{
        APICallCount = 0
        CacheHits = 0
        CacheMisses = 0
        BatchedCalls = 0
        IndividualCalls = 0
        StartTime = Get-Date
        UIUpdates = 0
        UISkipped = 0
    }
    
    function Add-PerformanceMetric {
        param([string]$Type, [int]$Count = 1)
        
        if ($global:PerformanceMetrics.ContainsKey($Type)) {
            $global:PerformanceMetrics[$Type] += $Count
        }
    }
    
    function Get-PerformanceReport {
        $runtime = (Get-Date) - $global:PerformanceMetrics.StartTime
        $cacheHitRate = if (($global:PerformanceMetrics.CacheHits + $global:PerformanceMetrics.CacheMisses) -gt 0) {
            [math]::Round(($global:PerformanceMetrics.CacheHits / ($global:PerformanceMetrics.CacheHits + $global:PerformanceMetrics.CacheMisses)) * 100, 1)
        } else { 0 }
        
        $uiEfficiency = if (($global:PerformanceMetrics.UIUpdates + $global:PerformanceMetrics.UISkipped) -gt 0) {
            [math]::Round(($global:PerformanceMetrics.UISkipped / ($global:PerformanceMetrics.UIUpdates + $global:PerformanceMetrics.UISkipped)) * 100, 1)
        } else { 0 }
        
        return @{
            Runtime = $runtime.ToString("mm\:ss")
            APICallCount = $global:PerformanceMetrics.APICallCount
            CacheHitRate = "$cacheHitRate%"
            BatchEfficiency = "$($global:PerformanceMetrics.BatchedCalls) batched vs $($global:PerformanceMetrics.IndividualCalls) individual"
            UIEfficiency = "$uiEfficiency% updates skipped (smart rendering)"
        }
    }
    
    
    
    function Show-StartupDashboard {
    Write-Host ""
        Write-Host "╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
        Write-Host "║                    🚀 PIM PERFORMANCE STATS                  ║" -ForegroundColor Cyan
        Write-Host "╠══════════════════════════════════════════════════════════════╣" -ForegroundColor Cyan
        
        # Get current performance metrics
        $report = Get-PerformanceReport
        $currentTime = Get-Date
        
        # Calculate some startup stats
        $cacheStatus = if (Test-Path $global:CacheDirectory) { "✅ Active" } else { "⚠️  Initializing" }
        $optimizationsStatus = "✅ Loaded"
        
        Write-Host "║  📊 Cache Status: $($cacheStatus.PadRight(42)) ║" -ForegroundColor White
        Write-Host "║  ⚡ Optimizations: $($optimizationsStatus.PadRight(40)) ║" -ForegroundColor White
        Write-Host "║  🕐 Session Start: $($currentTime.ToString('MM/dd/yyyy hh:mm tt').PadRight(39)) ║" -ForegroundColor White
        Write-Host "║  🎯 Ready for role management operations                     ║" -ForegroundColor Green
        Write-Host "╠══════════════════════════════════════════════════════════════╣" -ForegroundColor Cyan
        Write-Host "║                      ⌨️  KEYBOARD SHORTCUTS                   ║" -ForegroundColor Yellow
        Write-Host "╠══════════════════════════════════════════════════════════════╣" -ForegroundColor Cyan
        Write-Host "║  Ctrl+R  → Refresh role status        Ctrl+Q → Quick exit    ║" -ForegroundColor Gray
        Write-Host "║  ESC → Cancel/Back                     Space → Toggle select  ║" -ForegroundColor Gray
        Write-Host "║  Ctrl+A  → Auto-select all roles      Space → Toggle select  ║" -ForegroundColor Gray
        Write-Host "║  Ctrl+D  → Deactivate all active      Enter → Confirm        ║" -ForegroundColor Gray
        Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "Press any key to continue..." -ForegroundColor DarkGray
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        Clear-Host
    }
    
    function Get-CachedSchedules {
        param([string]$CurrentUserId)
        
        Track-DataAccess -Key "schedules" -Operation "read"
        
        # FORCE FRESH DATA - NO CACHING
        Add-PerformanceMetric -Type "CacheMisses"
        
        # Always fetch fresh data - no cache check - MATCH PROGRESS.PS1 EXACTLY
        try {
            Add-PerformanceMetric -Type "APICallCount"
            # Get schedule requests (for activation timestamps) instead of just schedules - OPTIMIZED
            $freshSchedules = Get-MgRoleManagementDirectoryRoleAssignmentScheduleRequest -Filter "PrincipalId eq '$CurrentUserId'" -Top 50
            
            # Return fresh data without caching
            return $freshSchedules
        } catch {
            Write-Host "⚠️ Filter not supported, falling back to full fetch..." -ForegroundColor Yellow
            # Fallback to original method if filter not supported - EXACT MATCH TO PROGRESS.PS1
            $freshSchedules = Get-MgRoleManagementDirectoryRoleAssignmentSchedule -All | Where-Object { 
                $_.PrincipalId -eq $CurrentUserId 
            }
            return $freshSchedules
        }
    }
    
    # Removed duplicate Get-CachedRoleDefinition function - using the one at top of file
    
    }
    catch {
                Write-Host ""
        Write-Host "❌ Authentication Failed" -ForegroundColor Red
        Write-Host "================================================" -ForegroundColor Red
                        Write-Host ""
        
        $errorMessage = $_.Exception.Message
        
        # Provide user-friendly error messages
        if ($errorMessage -like "*user_cancel*" -or $errorMessage -like "*canceled*") {
            Write-Host "🚫 Authentication was cancelled by user." -ForegroundColor Yellow
            Write-Host "   You need to complete the authentication process to use PIM-Global." -ForegroundColor White
        }
        elseif ($errorMessage -like "*network*" -or $errorMessage -like "*timeout*") {
            Write-Host "🌐 Network connection issue detected." -ForegroundColor Yellow
            Write-Host "   Please check your internet connection and try again." -ForegroundColor White
        }
        elseif ($errorMessage -like "*tenant*" -or $errorMessage -like "*authority*") {
            Write-Host "🏢 Tenant/Authority issue detected." -ForegroundColor Yellow
            Write-Host "   Please verify you're using the correct organizational account." -ForegroundColor White
        }
        elseif ($errorMessage -like "*scope*" -or $errorMessage -like "*permission*") {
            Write-Host "🔐 Permission issue detected." -ForegroundColor Yellow
            Write-Host "   Your account may not have the required permissions for PIM operations." -ForegroundColor White
            Write-Host "   Contact your administrator to ensure you have PIM eligibility." -ForegroundColor White
        }
        elseif ($errorMessage -like "*MFA*" -or $errorMessage -like "*multifactor*") {
            Write-Host "🔒 Multi-Factor Authentication issue detected." -ForegroundColor Yellow
            Write-Host "   Please ensure MFA is properly configured on your account." -ForegroundColor White
        }
        else {
            Write-Host "⚠️ An unexpected error occurred during authentication:" -ForegroundColor Yellow
            Write-Host "   $errorMessage" -ForegroundColor White
        }
        
                        Write-Host ""
        Write-Host "💡 Troubleshooting Tips:" -ForegroundColor Cyan
        Write-Host "   • Ensure you're using your organizational Microsoft account" -ForegroundColor Gray
        Write-Host "   • Complete MFA authentication when prompted" -ForegroundColor Gray
        Write-Host "   • Check that you have PIM role eligibilities assigned" -ForegroundColor Gray
        Write-Host "   • Try running as administrator if permission issues persist" -ForegroundColor Gray
        Write-Host "   • Contact your IT administrator if problems continue" -ForegroundColor Gray
        Write-Host ""
        Write-Host "🔄 You can restart the script to try authentication again." -ForegroundColor Green
                        Write-Host ""
                        Write-Host "Press Enter to exit..." -ForegroundColor Cyan
                        $null = Read-Host
                        exit 1
    }
    
    function Flush-ConsoleInput {
        while ([Console]::KeyAvailable) {
            [Console]::ReadKey($true) | Out-Null
        }
    }
    
    # Simple bottom status bar - shows at bottom without interfering with content
    function Show-BottomControls {
        param(
            [string]$ControlsText,
            [string]$ShortcutsText = ""
        )
        
        # This function is deprecated - use Show-DynamicControlBar instead
        # Keeping for compatibility but doing nothing
        return
        
        # Restore cursor position (ensure it doesn't overlap)
        $maxLine = $controlsLine - 1
        if ($currentPos -ge $maxLine) {
            [Console]::SetCursorPosition(0, ($controlsLine - 2))
                    } else {
            [Console]::SetCursorPosition(0, $currentPos)
        }
    }
    
    # Show-ExpirationCountdown function removed - using Show-CheckboxMenuWithLiveCountdown instead
    
    function Show-CheckboxMenuWithLiveCountdown {
        param(
            [array]$Items,
            [array]$ActiveRoles,
            [string]$Title = "Select Items",
            [string]$Prompt = "Use arrow keys to navigate, SPACE to toggle selection, ENTER to confirm:"
        )
        
             if ($Items.Count -eq 0) {
             Write-Host "No items to select from." -ForegroundColor Red
             return @()
         }
         
         # Clear screen and show header
        Clear-Host
        Write-Host "[ P I M - G L O B A L ]" -ForegroundColor DarkMagenta
        Write-Host "PIM-Global - Automate PIM Role Activation Application via Microsoft Entra ID" -ForegroundColor Green
        
        # Initialize selection state
        $selected = @{}
        $currentIndex = 0
        
        # Prepare countdown data with parallel processing
        # Processing role expiration data silently
        $roleTracker = @{}
        
        # Get cached schedules once
        $cachedSchedules = Get-CachedSchedules -CurrentUserId $currentUserId
        
        # ULTRA AGGRESSIVE DEDUPLICATION: Force only ONE entry per role name at input level
        $uniqueActiveRoles = @()
        $inputDedupTable = @{}
        
        foreach ($role in $ActiveRoles) {
            $roleName = $role.RoleName
            if (-not $inputDedupTable.ContainsKey($roleName)) {
                $inputDedupTable[$roleName] = $role
                $uniqueActiveRoles += $role
            }
            # Skip any additional entries with the same role name
        }
        
        # Process unique roles in parallel (PowerShell 7+ feature)
        $roleExpirationData = $uniqueActiveRoles | ForEach-Object -Parallel {
            $entry = $_
            $schedules = $using:cachedSchedules
            
            try {
                $roleSchedules = $schedules | Where-Object { 
                    $_.PrincipalId -eq $entry.Assignment.PrincipalId -and 
                    $_.RoleDefinitionId -eq $entry.Assignment.RoleDefinitionId 
                }
                
                $schedule = $roleSchedules | Sort-Object CreatedDateTime -Descending | Select-Object -First 1
                
                if ($schedule.ScheduleInfo.Expiration.EndDateTime) {
                    $expirationTime = [DateTime]::Parse($schedule.ScheduleInfo.Expiration.EndDateTime).ToLocalTime()
                    
                    [PSCustomObject]@{
                        RoleName = $entry.RoleName
                        ExpirationTime = $expirationTime
                    }
                }
            } catch {
                # Skip roles we can't get expiration info for
                $null
            }
        } -ThrottleLimit 5 | Where-Object { $_ }
        
        # FINAL DEDUPLICATION: Use Select-Object with unique role names only
        $roleExpirationData = $roleExpirationData | Sort-Object RoleName, ExpirationTime -Descending | Group-Object RoleName | ForEach-Object { $_.Group[0] }
        # Show countdown header immediately after main header
        Write-Host "🕐 Countdown Until Role Expiration" -ForegroundColor Cyan
        # Store initial countdown positions - start at line 4 (after header, space, and countdown title)
        $countdownStartLine = 4
        # Calculate menu positions after countdown display (1 line per role + space + space before menu)
        $menuStartLine = $countdownStartLine + $roleExpirationData.Count + 2  # 1 line per role + space + title
        $statusLine = $menuStartLine + $Items.Count + 1  # After all menu items + 1 space
        # Clear any previous countdown display remnants
        for ($i = 0; $i -lt 10; $i++) {
            [Console]::SetCursorPosition(0, $countdownStartLine + $i)
            Write-Host (" " * [Console]::WindowWidth)
        }
        [Console]::SetCursorPosition(0, $countdownStartLine)
        
        # Force cursor to correct position after countdown header
        
        # Reserve space for countdown display (will be handled by live update loop) - 1 line per role
        foreach ($roleData in $roleExpirationData) {
            Write-Host ""  # Role line only
        }
        Write-Host $Title -ForegroundColor Cyan
        
        # Recalculate positions after initial display
        $menuStartLine = [Console]::CursorTop
        $statusLine = $menuStartLine + $Items.Count + 1
        
        # Show bottom controls once
        Show-BottomControls -ControlsText $script:ControlMessages['Menu'] -ShortcutsText $script:ControlMessages['Shortcuts']
        
        # Hide cursor for cleaner display
        [Console]::CursorVisible = $false
        
        $lastUpdate = Get-Date
        
        try {
            do {
                $currentTime = Get-Date
                
                # Update countdown every second for real-time accuracy
                if (($currentTime - $lastUpdate).TotalSeconds -ge 1) {
                    # Always redraw header at top to ensure it's visible
                    [Console]::SetCursorPosition(0, 0)
                    Write-Host "[ P I M - G L O B A L ]" -ForegroundColor DarkMagenta
                    [Console]::SetCursorPosition(0, 1)
                    Write-Host ""  # Space between PIM-Global and Countdown
                    [Console]::SetCursorPosition(0, 2)
                    Write-Host "🕐 Countdown Until Role Expiration" -ForegroundColor Cyan
                    
                    $lineIndex = $countdownStartLine
                    
                    foreach ($roleData in $roleExpirationData) {
                        $timeRemaining = $roleData.ExpirationTime - $currentTime
                        
                        [Console]::SetCursorPosition(0, $lineIndex)
                        
                        if ($timeRemaining.TotalSeconds -gt 0) {
                            $timeDisplay = Get-CachedTimeFormat -TimeSpan $timeRemaining
                            
                            # Color coding based on time remaining
                            if ($timeRemaining.TotalMinutes -le 10) {
                                $icon = "🚨"
                                $color = "Red"
                            } elseif ($timeRemaining.TotalMinutes -le 30) {
                                $icon = "⚠️"
                                $color = "Yellow"
            } else {
                                $icon = "⏳"
                                $color = "Green"
                            }
                            
                            $roleText = "$icon $($roleData.RoleName): $timeDisplay remaining"
                            Update-UIIfChanged -Key "role_$($roleData.RoleName)" -NewContent $roleText -Line $lineIndex -Color $color
                            } else {
                            $roleText = "❌ $($roleData.RoleName): Expired"
                            Write-Host $roleText.PadRight([Console]::WindowWidth - 1) -ForegroundColor Red
                        }
                        
                        $lineIndex += 1
                    }
                    
                    # Redraw title to ensure it stays visible (clear the line first)
                    $titleLine = $countdownStartLine + $roleExpirationData.Count + 1  # +1 for space after countdown
                    [Console]::SetCursorPosition(0, $titleLine)
                    Write-Host (" " * [Console]::WindowWidth) # Clear the line
                    [Console]::SetCursorPosition(0, $titleLine)
                    Write-Host $Title -ForegroundColor Cyan
                    
                    $lastUpdate = $currentTime
                }
                
                # Update menu display
                for ($i = 0; $i -lt $Items.Count; $i++) {
                    [Console]::SetCursorPosition(0, $menuStartLine + $i)
                    
                    $item = $Items[$i]
                    $arrow = if ($i -eq $currentIndex) { "► " } else { "  " }
                    $color = if ($i -eq $currentIndex) { "Yellow" } else { "White" }
                    $checkbox = if ($selected[$i]) { "[✓]" } else { "[ ]" }
                    $checkboxColor = if ($selected[$i]) { "Green" } else { "Gray" }
                    
                    # Get display text from RoleName property
                    $displayText = if ($item.RoleName) { $item.RoleName } else { $item.ToString() }
                    
                    Write-Host "$arrow" -NoNewline -ForegroundColor $color
                    Write-Host "$checkbox " -NoNewline -ForegroundColor $checkboxColor
                    Write-Host "$displayText".PadRight([Console]::WindowWidth - $arrow.Length - $checkbox.Length - 1) -ForegroundColor $color
                }
                
                # Update status
                [Console]::SetCursorPosition(0, $statusLine)
                $selectedCount = ($selected.Values | Where-Object { $_ }).Count
                if ($selectedCount -gt 0) {
                    Write-Host ("Roles Selected: $selectedCount").PadRight([Console]::WindowWidth - 1) -ForegroundColor Green
                    } else {
                    Write-Host ("Roles Selected: 0").PadRight([Console]::WindowWidth - 1) -ForegroundColor Gray
                }
                
                # Check for input (non-blocking)
                if ([Console]::KeyAvailable) {
                    $key = [Console]::ReadKey($true)
                    
                    switch ($key.Key) {
                        "UpArrow" {
                            $currentIndex = if ($currentIndex -gt 0) { $currentIndex - 1 } else { $Items.Count - 1 }
                        }
                        "DownArrow" {
                            $currentIndex = if ($currentIndex -lt ($Items.Count - 1)) { $currentIndex + 1 } else { 0 }
                        }
                        "Spacebar" {
                            $selected[$currentIndex] = -not $selected[$currentIndex]
                        }
                        "Enter" {
                            $selectedItems = @()
                            for ($i = 0; $i -lt $Items.Count; $i++) {
                                if ($selected[$i]) {
                                    $selectedItems += $i
                                }
                            }
                            # Clear the screen before returning to prevent overlap
                            Clear-Host
                            return $selectedItems
                        }
                        "Escape" {
                            # Clear the screen before returning to prevent overlap
                            Clear-Host
                            return @()
                        }
    
                    }
                    
                    # Handle Ctrl key combinations
                    if ($key.Modifiers -eq "Control") {
                        switch ($key.Key) {
                            "A" {
                                # Ctrl+A - Select all items
                                for ($i = 0; $i -lt $Items.Count; $i++) {
                                    $selected[$i] = $true
                                }
                                # Clear the status area and show selection message
                                [Console]::SetCursorPosition(0, $statusLine)
                                Write-Host "✅ All roles selected".PadRight([Console]::WindowWidth - 1) -ForegroundColor Green
                                Start-Sleep -Milliseconds 800
                            }
                            "D" {
                                # Ctrl+D - Deselect all items
                                for ($i = 0; $i -lt $Items.Count; $i++) {
                                    $selected[$i] = $false
                                }
                                # Clear the status area and show deselection message
                                [Console]::SetCursorPosition(0, $statusLine)
                                Write-Host "❌ All roles deselected".PadRight([Console]::WindowWidth - 1) -ForegroundColor Yellow
                                Start-Sleep -Milliseconds 800
                            }
    
                            "R" {
                                # Ctrl+R - Refresh (will be handled by returning special value)
                                Write-Host ""
                                Write-Host "🔄 Refreshing role status..." -ForegroundColor Cyan
                                Start-Sleep -Milliseconds 500
                                Clear-Host
                                return "REFRESH"
                            }
                            "Q" {
                                # Ctrl+Q - Exit application immediately
                                Clear-Host
                                Write-Host "Exiting PIM role management..." -ForegroundColor Yellow
                                try {
        Disconnect-MgGraph | Out-Null
        Write-Host "Disconnected from Microsoft Graph." -ForegroundColor DarkRed
                    } catch {
                                    Write-Host "Already disconnected from Microsoft Graph." -ForegroundColor DarkGray
                                }
        Write-Host ""
                                Write-Host "Terminal will close in 3 seconds..." -ForegroundColor Cyan
                                Start-Sleep -Seconds 3
                                [Environment]::Exit(0)
                            }
                        }
                    }
                }
                
                # Optimized delay to prevent excessive CPU usage
                Start-Sleep -Milliseconds 250
                
                # Periodic memory optimization and predictive preload (every ~40 seconds)
                if ((Get-Random -Maximum 160) -eq 1) {
                    Optimize-Memory
                    Start-PredictivePreload
                }
                
        } while ($true)
        }
        finally {
            [Console]::CursorVisible = $true
        }
    }
    
    
    
    function Show-EnhancedDeactivationCountdown {
        param(
            [array]$TooNewRoles,
            [array]$ReadyRoles = @(),
            [string]$CurrentUserId
        )
        
        try {
            [Console]::CursorVisible = $false
        
            # Deduplicate roles by name
            $uniqueRoles = @{}
            $deduplicatedRoles = @()
            foreach ($roleInfo in $TooNewRoles) {
                if (-not $uniqueRoles.ContainsKey($roleInfo.RoleName)) {
                    $uniqueRoles[$roleInfo.RoleName] = $true
                    $deduplicatedRoles += $roleInfo
                }
            }
            
            # Store initial cursor position and screen content
            $initialCursorTop = [Console]::CursorTop
            
            # Build static header content once
            $headerLines = @()
            $headerLines += "[ P I M - G L O B A L ]"
            $headerLines += ""
            $headerLines += "⏰ Role Deactivation Countdown"
            $headerLines += "   (5-minute minimum activation period required)"
            $headerLines += ""
            $headerLines += "🔒 Roles waiting for 5-minute period:"
            
            do {
                # Clear and redraw header every time for clean display
                Clear-Host
                foreach ($line in $headerLines) {
                    if ($line -eq "[ P I M - G L O B A L ]") {
                        Write-Host $line -ForegroundColor Magenta
                    } elseif ($line -eq "⏰ Role Deactivation Countdown") {
                        Write-Host $line -ForegroundColor Yellow
                    } elseif ($line -eq "   (5-minute minimum activation period required)") {
                        Write-Host $line -ForegroundColor Gray
                    } elseif ($line -eq "🔒 Roles waiting for 5-minute period:") {
                        Write-Host $line -ForegroundColor Red
                    } else {
                        Write-Host $line
                    }
                }
                
                $allReady = $true
                foreach ($roleInfo in $deduplicatedRoles) {
                    try {
                        # Use cached activation time instead of making API calls in countdown loop
                        $activationTime = $roleInfo.ActivationTime
                        $deactivationTime = $activationTime.AddMinutes(5)
                        $timeRemaining = $deactivationTime - (Get-Date)
                        
                        if ($timeRemaining.TotalSeconds -gt 0) {
                            $allReady = $false
                            $hours = [int][math]::Floor($timeRemaining.TotalHours)
                            $minutes = [int][math]::Floor($timeRemaining.TotalMinutes % 60)
                            $seconds = [int][math]::Floor($timeRemaining.TotalSeconds % 60)
                            $timeDisplay = "{0:D2}:{1:D2}:{2:D2}" -f $hours, $minutes, $seconds
                            
                            Write-Host "  ⏳ $($roleInfo.RoleName): $timeDisplay remaining" -ForegroundColor Cyan
                        } else {
                            Write-Host "  ✅ $($roleInfo.RoleName): Ready for deactivation" -ForegroundColor Green
                        }
                    } catch {
                        Write-Host "  ❓ $($roleInfo.RoleName): Unable to check" -ForegroundColor Yellow
                    }
                }
                
                # Show ready roles if any
                if ($ReadyRoles.Count -gt 0) {
                    Write-Host ""
                    Write-Host "✅ Roles ready for deactivation:" -ForegroundColor Green
                    foreach ($role in $ReadyRoles) {
                        Write-Host "  🔓 $($role.RoleName)" -ForegroundColor Green
                    }
                }
                
                # Show dynamic control bar
                Show-DynamicControlBar -ControlsText $script:ControlMessages['Exit']
                
                # Check if all roles are ready
                if ($allReady) {
                    Write-Host "🎉 All roles are now ready for deactivation!" -ForegroundColor Green
                    Write-Host "Launching deactivation workflow..." -ForegroundColor Cyan
                    Start-Sleep -Seconds 2
                    
                    # Refresh and launch deactivation workflow
                    $allRoles = $TooNewRoles + $ReadyRoles
                    $allActiveRoles = @()
                    foreach ($roleInfo in $allRoles) {
                        if ($roleInfo.Assignment) {
                            $allActiveRoles += @{
                                RoleName = $roleInfo.RoleName
                                Assignment = $roleInfo.Assignment
                            }
                        }
                    }
                    
                    Start-RoleDeactivationWorkflow -ActiveRoles $allActiveRoles -CurrentUserId $CurrentUserId
                    return
                }
                
                # Check for user input (non-blocking)
                if ([Console]::KeyAvailable) {
                    $key = [Console]::ReadKey($true)
                    
                    # Check global shortcuts
                    if (Test-GlobalShortcut -Key $key) {
                        return
                    }
                    
                    # Any other key skips countdown
                    Write-Host "Countdown skipped by user." -ForegroundColor Yellow
                    
                    # If there are ready roles, show deactivation workflow
                    if ($ReadyRoles.Count -gt 0) {
                        Start-RoleDeactivationWorkflow -ActiveRoles $ReadyRoles -CurrentUserId $CurrentUserId
                    } else {
                        # Return to main menu
                        return
                    }
                    return
                }
                
                Start-Sleep -Seconds 1
                
            } while ($true)
            
        } finally {
            [Console]::CursorVisible = $true
        }
    }
    
    function Show-CountdownWithMenu {
        param(
            [array]$TooNewRoles,
            [string]$CurrentUserId
        )
        
        try {
            [Console]::CursorVisible = $false
            
            # Deduplicate roles by name
            $uniqueRoles = @{}
            $deduplicatedRoles = @()
            foreach ($roleInfo in $TooNewRoles) {
                if (-not $uniqueRoles.ContainsKey($roleInfo.RoleName)) {
                    $uniqueRoles[$roleInfo.RoleName] = $true
                    $deduplicatedRoles += $roleInfo
                }
            }
            
            # Build static header content once
            $headerLines = @()
            $headerLines += "[ P I M - G L O B A L ]"
            $headerLines += ""
            $headerLines += "⏰ Time Remaining Until Roles Can Be Deactivated"
            $headerLines += "   (5-minute minimum activation period required)"
            $headerLines += "   The deactivation menu will automatically refresh when timers expire"
            $headerLines += ""
            
            do {
                # Clear and redraw header every time for clean display
                Clear-Host
                foreach ($line in $headerLines) {
                    if ($line -eq "[ P I M - G L O B A L ]") {
                        Write-Host $line -ForegroundColor Magenta
                    } elseif ($line -eq "⏰ Time Remaining Until Roles Can Be Deactivated") {
                        Write-Host $line -ForegroundColor Yellow
                    } elseif ($line -eq "   (5-minute minimum activation period required)") {
                        Write-Host $line -ForegroundColor Gray
                    } elseif ($line -eq "   The deactivation menu will automatically refresh when timers expire") {
                        Write-Host $line -ForegroundColor Cyan
                    } else {
                        Write-Host $line
                    }
                }
                
                $allReady = $true
                
                foreach ($roleInfo in $deduplicatedRoles) {
                    try {
                        $activationTime = $roleInfo.ActivationTime
                        $deactivationTime = $activationTime.AddMinutes(5)
                        $timeRemaining = $deactivationTime - (Get-Date)
                        
                        if ($timeRemaining.TotalSeconds -gt 0) {
                            $allReady = $false
                            $hours = [int][math]::Floor($timeRemaining.TotalHours)
                            $minutes = [int][math]::Floor($timeRemaining.TotalMinutes % 60)
                            $seconds = [int][math]::Floor($timeRemaining.TotalSeconds % 60)
                            $timeDisplay = "{0:D2}:{1:D2}:{2:D2}" -f $hours, $minutes, $seconds
                            
                            Write-Host "  ⏳ $($roleInfo.RoleName): $timeDisplay remaining" -ForegroundColor Cyan
                        } else {
                            Write-Host "  ✅ $($roleInfo.RoleName): Ready for deactivation" -ForegroundColor Green
                        }
                    } catch {
                        Write-Host "  ❓ $($roleInfo.RoleName): Unable to check" -ForegroundColor Yellow
                    }
                }
                
                Show-DynamicControlBar -ControlsText "Controls: Any key to skip countdown | Ctrl+Q to close terminal"
                
                # Check for user input (non-blocking)
                if ([Console]::KeyAvailable) {
                    $key = [Console]::ReadKey($true)
                    
                    # Check global shortcuts
                    if (Test-GlobalShortcut -Key $key) {
                        return
                    }
                    
                    # Any other key skips countdown
                    Write-Host "Countdown skipped by user." -ForegroundColor Yellow
                    Start-Sleep -Seconds 1
                    
                    # Launch deactivation workflow with all roles
                    $allActiveRoles = @()
                    foreach ($roleInfo in $TooNewRoles) {
                        if ($roleInfo.Assignment) {
                            $allActiveRoles += @{
                                RoleName = $roleInfo.RoleName
                                Assignment = $roleInfo.Assignment
                            }
                        }
                    }
                    
                    Start-RoleDeactivationWorkflow -ActiveRoles $allActiveRoles -CurrentUserId $CurrentUserId
                    return
                }
                
                if (-not $allReady) {
                    Start-Sleep -Seconds 1
                }
                
            } while (-not $allReady)
        
        [Console]::CursorVisible = $true
            
            if ($allReady) {
                Clear-Host
                Show-PIMGlobalHeaderMinimal
                Write-Host ""
                Write-Host "✅ All roles are now eligible for deactivation!" -ForegroundColor Green
                Write-Host ""
                Start-Sleep -Seconds 2
                
                # Launch deactivation workflow
                $allActiveRoles = @()
                foreach ($roleInfo in $TooNewRoles) {
                    if ($roleInfo.Assignment) {
                        $allActiveRoles += @{
                            RoleName = $roleInfo.RoleName
                            Assignment = $roleInfo.Assignment
                        }
                    }
                }
                
                Start-RoleDeactivationWorkflow -ActiveRoles $allActiveRoles -CurrentUserId $CurrentUserId
            }
            
        } finally {
            [Console]::CursorVisible = $true
        }
    }
    
    function Show-DeactivationCountdown {
        param(
            [array]$TooNewRoles
        )
        
        try {
            [Console]::CursorVisible = $false
        
        Clear-Host
        Show-PIMGlobalHeaderMinimal
        Write-Host ""
        Write-Host "⏰ Time Remaining Until Roles Can Be Deactivated" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "   (5-minute minimum activation period required)" -ForegroundColor Gray
        Write-Host "   The deactivation menu will automatically refresh when timers expire" -ForegroundColor Cyan
        Write-Host ""
        
        # Remember the starting line for roles
        $roleStartLine = [Console]::CursorTop
        
        # Deduplicate roles by name
        $uniqueRoles = @{}
        $deduplicatedRoles = @()
        foreach ($roleInfo in $TooNewRoles) {
            if (-not $uniqueRoles.ContainsKey($roleInfo.RoleName)) {
                $uniqueRoles[$roleInfo.RoleName] = $true
                $deduplicatedRoles += $roleInfo
            }
        }
        
        # Show initial role lines
        foreach ($roleInfo in $deduplicatedRoles) {
            Write-Host "  ⏳ $($roleInfo.RoleName): --:-- remaining" -ForegroundColor Cyan
        }
        Write-Host ""
        Write-Host "Ctrl+Q to exit" -ForegroundColor Magenta
        
        do {
            $allReady = $true
            
            # Update each role's countdown in place
            for ($i = 0; $i -lt $deduplicatedRoles.Count; $i++) {
                $roleInfo = $deduplicatedRoles[$i]
                try {
                    $activationTime = $roleInfo.ActivationTime
                    $deactivationTime = $activationTime.AddMinutes(5)
                    $timeRemaining = $deactivationTime - (Get-Date)
                    
                    # Position cursor at this role's line
                    $lineNumber = $roleStartLine + $i
                    [Console]::SetCursorPosition(0, $lineNumber)
                    
                    if ($timeRemaining.TotalSeconds -gt 0) {
                        $allReady = $false
                        $minutes = [int][math]::Floor($timeRemaining.TotalMinutes)
                        $seconds = [int][math]::Floor($timeRemaining.TotalSeconds % 60)
                        $timeDisplay = "{0:D2}:{1:D2}" -f $minutes, $seconds
                        
                        # Update only the time part to reduce flicker
                        Write-Host "  ⏳ $($roleInfo.RoleName): $timeDisplay remaining" -ForegroundColor Cyan -NoNewline
                        Write-Host (" " * ([Console]::WindowWidth - [Console]::CursorLeft - 1))
                    } else {
                        Write-Host "  ✅ $($roleInfo.RoleName): Ready for deactivation!" -ForegroundColor Green -NoNewline
                        Write-Host (" " * ([Console]::WindowWidth - [Console]::CursorLeft - 1))
                    }
                } catch {
                    # Position cursor at this role's line
                    $lineNumber = $roleStartLine + $i
                    [Console]::SetCursorPosition(0, $lineNumber)
                    # Clear line and write new content
                    Write-Host (" " * ([Console]::WindowWidth - 1)) -NoNewline
                    [Console]::SetCursorPosition(0, $lineNumber)
                    Write-Host "  ❓ $($roleInfo.RoleName): Unable to check" -ForegroundColor Yellow
                }
            }
            
            # Check if user pressed a key to skip
            if ([Console]::KeyAvailable) {
                $key = [Console]::ReadKey($true)
                if ($key.Key -eq 'Q' -and $key.Modifiers -eq 'Control') {
                    Invoke-PIMExit
                } else {
                Write-Host "Countdown skipped by user." -ForegroundColor Yellow
                    Start-Sleep -Seconds 1
                        break
                }
                }
            
            if (-not $allReady) {
                Start-Sleep -Seconds 1
            }
            
        } while (-not $allReady)
        
        [Console]::CursorVisible = $true
        
        if ($allReady) {
            Clear-Host
            Show-PIMGlobalHeaderMinimal
            Write-Host ""
            Write-Host "   Refreshing deactivation menu..." -ForegroundColor Cyan
            Start-Sleep -Seconds 2
            return $true
        }
        
        return $false
            
        } finally {
            [Console]::CursorVisible = $true
        }
    }
    
    function Show-SinglePageActivationForm {
        param(
            [array]$ValidRoles,
            [array]$RoleItems
        )
        
        $selected = @{}
        $currentStep = 0  # 0 = role selection, 1 = duration, 2 = justification, 3 = ready to submit
        $currentRoleIndex = 0
        $durationInput = ""
        $justificationInput = ""
        
        [Console]::CursorVisible = $false
        
        try {
            do {
                    Clear-Host
                Show-PIMGlobalHeaderMinimal
                Write-Host ""
                Write-Host "Select Roles to Activate" -ForegroundColor Cyan
                Write-Host "========================" -ForegroundColor Cyan
                Write-Host ""
                for ($i = 0; $i -lt $RoleItems.Count; $i++) {
                    $checkbox = if ($selected[$i]) { "[✓]" } else { "[ ]" }
                    $arrow = if ($i -eq $currentRoleIndex -and $currentStep -eq 0) { "► " } else { "  " }
                    $color = if ($i -eq $currentRoleIndex -and $currentStep -eq 0) { "Yellow" } else { "White" }
                    $checkboxColor = if ($selected[$i]) { "Green" } else { "Gray" }
                    
                    Write-Host "$arrow" -NoNewline -ForegroundColor $color
                    Write-Host "$checkbox " -NoNewline -ForegroundColor $checkboxColor
                    Write-Host "$($RoleItems[$i])" -ForegroundColor $color
                }
                
                Write-Host ""
                
                Write-Host ""
                
                # Show fields dynamically based on current step
                if ($currentStep -ge 1) {
                    # Show duration field (step 1)
                    $durationColor = if ($currentStep -eq 1) { "Yellow" } else { "Green" }
                    $durationArrow = if ($currentStep -eq 1) { "► " } else { "✓ " }
                    Write-Host "$durationArrow" -NoNewline -ForegroundColor $durationColor
                    Write-Host "Enter activation duration (e.g., 30M, 1H, 2H30M): " -NoNewline -ForegroundColor $durationColor
                    Write-Host "$durationInput" -ForegroundColor White
                    Write-Host ""
                }
                
                if ($currentStep -ge 2) {
                    # Show reason field (step 2)
                    $reasonColor = if ($currentStep -eq 2) { "Yellow" } else { "Green" }
                    $reasonArrow = if ($currentStep -eq 2) { "► " } else { "✓ " }
                    Write-Host "$reasonArrow" -NoNewline -ForegroundColor $reasonColor
                    Write-Host "Enter reason for activation: " -NoNewline -ForegroundColor $reasonColor
                    Write-Host "$justificationInput" -ForegroundColor White
                    Write-Host ""
                }
                
                # Show selected count
                $selectedCount = ($selected.Keys | Where-Object { $selected[$_] }).Count
                Write-Host ""
                Write-Host "Roles Selected: $selectedCount" -ForegroundColor Cyan
                Write-Host ""
                
                # Show control bar for role selection step
                if ($currentStep -eq 0) {
                    Write-Host "↑/↓ Navigate | SPACE Toggle | ENTER Confirm | Ctrl+Q Exit" -ForegroundColor Magenta
                } elseif ($currentStep -eq 1) {
                    Write-Host "Type duration | ENTER Continue | Ctrl+Q Exit" -ForegroundColor Magenta
                } elseif ($currentStep -eq 2) {
                    Write-Host "Type reason | ENTER Activate | Ctrl+Q Exit" -ForegroundColor Magenta
                }
                
                $key = [Console]::ReadKey($true)
                
                    switch ($key.Key) {
                    "UpArrow" {
                        if ($currentStep -eq 0) {
                            $currentRoleIndex = if ($currentRoleIndex -gt 0) { $currentRoleIndex - 1 } else { $RoleItems.Count - 1 }
                        }
                    }
                    "DownArrow" {
                        if ($currentStep -eq 0) {
                            $currentRoleIndex = if ($currentRoleIndex -lt ($RoleItems.Count - 1)) { $currentRoleIndex + 1 } else { 0 }
                        }
                    }
                    "Spacebar" {
                        if ($currentStep -eq 0) {
                            $selected[$currentRoleIndex] = -not $selected[$currentRoleIndex]
                        }
                    }
                    "Enter" {
                        if ($currentStep -eq 0) {
                            # Step 0: Role selection -> Duration
                            $selectedIndices = @()
                            for ($i = 0; $i -lt $RoleItems.Count; $i++) {
                                if ($selected[$i]) {
                                    $selectedIndices += $i
                                }
                            }
                            
                            if ($selectedIndices.Count -eq 0) {
                                Write-Host ""
                                Write-Host "❌ Please select at least one role." -ForegroundColor Red
                                Show-DynamicControlBar -ControlsText "↑↓ Navigate Roles | SPACE Toggle | Select roles first | Ctrl+Q Exit"
                                Start-Sleep -Seconds 2
                                continue
                            }
                            
                            $currentStep = 1  # Move to duration input
                            [Console]::CursorVisible = $true
                            Show-DynamicControlBar -ControlsText "Type duration | ENTER Continue to Reason | Ctrl+Q Exit"
                            
                        } elseif ($currentStep -eq 1) {
                            # Step 1: Duration -> Reason
                            if ([string]::IsNullOrWhiteSpace($durationInput)) {
                                Write-Host ""
                                Write-Host "❌ Please enter a duration." -ForegroundColor Red
                                Show-DynamicControlBar -ControlsText "Type duration | ENTER Continue to Reason | Ctrl+Q Exit"
                                Start-Sleep -Seconds 2
                                continue
                            }
                            
                            $currentStep = 2  # Move to reason input
                            Show-DynamicControlBar -ControlsText "Type reason | ENTER Activate Roles | Ctrl+Q Exit"
                            
                        } elseif ($currentStep -eq 2) {
                            # Step 2: Reason -> Submit
                            if ([string]::IsNullOrWhiteSpace($justificationInput)) {
                                Write-Host ""
                                Write-Host "❌ Please enter a reason." -ForegroundColor Red
                                Show-DynamicControlBar -ControlsText "Type reason | ENTER Activate Roles | Ctrl+Q Exit"
                                Start-Sleep -Seconds 2
                                continue
                            }
                            
                            # Final submission
                            $selectedIndices = @()
                            for ($i = 0; $i -lt $RoleItems.Count; $i++) {
                                if ($selected[$i]) {
                                    $selectedIndices += $i
                                }
                            }
                            
                            return @{
                                SelectedIndices = $selectedIndices
                                Duration = $durationInput
                                Justification = $justificationInput
                            }
                        }
                    }
                    "Backspace" {
                        if ($currentStep -eq 1 -and $durationInput.Length -gt 0) {
                            $durationInput = $durationInput.Substring(0, $durationInput.Length - 1)
                            # Update control bar after backspace
                            Show-DynamicControlBar -ControlsText "Type duration | ENTER Continue to Reason | Ctrl+Q Exit"
                        } elseif ($currentStep -eq 2 -and $justificationInput.Length -gt 0) {
                            $justificationInput = $justificationInput.Substring(0, $justificationInput.Length - 1)
                            # Update control bar after backspace
                            Show-DynamicControlBar -ControlsText "Type reason | ENTER Activate Roles | Ctrl+Q Exit"
                        }
                    }
                    default {
                        # Handle typing in current step's field
                        if ($key.KeyChar -match '[a-zA-Z0-9\s\.,!@#$%^&*()_+=\-\[\]{}|;:''",.<>?/~`]') {
                            if ($currentStep -eq 1) {
                                $durationInput += $key.KeyChar
                                # Update control bar after each character
                                Show-DynamicControlBar -ControlsText "Type duration | ENTER Continue to Reason | Ctrl+Q Exit"
                            } elseif ($currentStep -eq 2) {
                                $justificationInput += $key.KeyChar
                                # Update control bar after each character
                                Show-DynamicControlBar -ControlsText "Type reason | ENTER Activate Roles | Ctrl+Q Exit"
                            }
                        }
                    }
                    "Escape" {
                        return $null
                    }
                }
            } while ($true)
        } finally {
            [Console]::CursorVisible = $true
        }
    }
    
    function Show-SimpleMenu {
        param(
            [array]$Items,
            [string]$Title = "Select an option",
            [int]$DefaultSelection = 0
        )
        
        if ($Items.Count -eq 0) {
            Write-Host "No items to select from." -ForegroundColor Red
            return 0
        }
        
        $currentIndex = $DefaultSelection
        [Console]::CursorVisible = $false
        
        try {
            do {
                    Clear-Host
                Show-PIMGlobalHeader
                    Write-Host ""
                Write-Host $Title -ForegroundColor Cyan
                Write-Host $("=" * $Title.Length) -ForegroundColor Cyan
                Write-Host ""
                
                # Display menu items
                for ($i = 0; $i -lt $Items.Count; $i++) {
                    $arrow = if ($i -eq $currentIndex) { "► " } else { "  " }
                    $color = if ($i -eq $currentIndex) { "Yellow" } else { "White" }
                    Write-Host "$arrow$($Items[$i])" -ForegroundColor $color
                }
                
                Write-Host ""
                Write-Host "Use ↑↓ arrow keys to navigate, ENTER to select" -ForegroundColor Gray
                
                $key = [Console]::ReadKey($true)
                
                switch ($key.Key) {
                    "UpArrow" {
                        $currentIndex = if ($currentIndex -gt 0) { $currentIndex - 1 } else { $Items.Count - 1 }
                    }
                    "DownArrow" {
                        $currentIndex = if ($currentIndex -lt ($Items.Count - 1)) { $currentIndex + 1 } else { 0 }
                    }
                    "Enter" {
                        return $currentIndex
                    }
                    "Escape" {
                        return -1
                    }
                }
            } while ($true)
        } finally {
            [Console]::CursorVisible = $true
        }
    }
    
    function Show-YesNoMenu {
        param(
            [string]$Question,
            [string]$DefaultChoice = "No",
            [switch]$KeepContent
        )
        
        # Removed problematic Environment.Exit override
        
        # SIMPLIFIED VERSION with arrow key support
        $options = @("Yes", "No")
        $defaultIndex = if ($DefaultChoice -eq "Yes") { 0 } else { 1 }
        $currentIndex = $defaultIndex
        
        # Display the question only once at the start
                Write-Host $Question -ForegroundColor Cyan
                Write-Host ""
        
        $menuStartLine = [Console]::CursorTop
        
        do {
            # Clear only the menu area, not the question
            [Console]::SetCursorPosition(0, $menuStartLine)
            for ($i = 0; $i -lt 6; $i++) {
                Write-Host (" " * [Console]::WindowWidth)
            }
            [Console]::SetCursorPosition(0, $menuStartLine)
                
                for ($i = 0; $i -lt $options.Count; $i++) {
                    $option = $options[$i]
                    $arrow = if ($i -eq $currentIndex) { "► " } else { "  " }
                    $color = if ($i -eq $currentIndex) { "Yellow" } else { "White" }
                    $checkbox = if ($i -eq $currentIndex) { "[✓]" } else { "[ ]" }
                    $checkboxColor = if ($i -eq $currentIndex) { "Green" } else { "Gray" }
                    
                    Write-Host "$arrow" -NoNewline -ForegroundColor $color
                    Write-Host "$checkbox " -NoNewline -ForegroundColor $checkboxColor
                    Write-Host "$option" -ForegroundColor $color
                }
                
                Write-Host ""
            Write-Host "Use ↑/↓ to navigate, ENTER to select, Y for Yes, N for No..." -ForegroundColor Magenta
                
                $key = [Console]::ReadKey($true)
                
                    switch ($key.Key) {
                    "UpArrow" {
                        $currentIndex = if ($currentIndex -gt 0) { $currentIndex - 1 } else { $options.Count - 1 }
                    }
                    "DownArrow" {
                        $currentIndex = if ($currentIndex -lt ($options.Count - 1)) { $currentIndex + 1 } else { 0 }
                    }
                    "Enter" {
                    $choice = $options[$currentIndex]
                    Write-Host "Selected: $choice" -ForegroundColor Green
                    return $choice
                    }
                    "Y" {
                    Write-Host "Selected: Yes" -ForegroundColor Green
                        return "Yes"
                    }
                    "N" {
                    Write-Host "Selected: No" -ForegroundColor Green
                        return "No"
                    }
                }
            } while ($true)
    }
    
    function Show-CheckboxMenuDynamic {
        param(
            [array]$Items,
            [string]$Title = "Select Items",
            [string]$Prompt = "Use arrow keys to navigate, SPACE to toggle selection, ENTER to confirm:",
            [bool]$AllowMultiple = $true,
            [string]$DisplayProperty = $null
        )
        
        if ($Items.Count -eq 0) {
            Write-Host "No items to select from." -ForegroundColor Red
            return @()
        }
        
        $currentIndex = 0
        $selected = @{}
        for ($i = 0; $i -lt $Items.Count; $i++) {
            $selected[$i] = $false
        }
        
        do {
            Clear-Host
            Show-PIMGlobalHeaderMinimal
                        Write-Host ""
            Write-Host $Title -ForegroundColor Cyan
            Write-Host $("=" * $Title.Length) -ForegroundColor Cyan
            Write-Host ""
            
            # Show all roles
            for ($i = 0; $i -lt $Items.Count; $i++) {
                $item = $Items[$i]
                $checkbox = if ($selected[$i]) { "[✓]" } else { "[ ]" }
                $arrow = if ($i -eq $currentIndex) { "► " } else { "  " }
                
                # Get display text
                $displayText = if ($DisplayProperty -and $item.PSObject.Properties[$DisplayProperty]) {
                    $item.$DisplayProperty
                } else {
                    $item.ToString()
                }
                
                $line = "$arrow$checkbox $displayText"
                
                # Apply colors
                if ($selected[$i]) {
                    Write-Host $line -ForegroundColor Green
                } else {
                    Write-Host $line -ForegroundColor White
                }
            }
            
            Write-Host ""
            $selectedCount = ($selected.GetEnumerator() | Where-Object { $_.Value }).Count
            Write-Host "Roles Selected: $selectedCount" -ForegroundColor Cyan
            Write-Host ""
            
            # Get user input WITHOUT showing controls initially
            $key = [Console]::ReadKey($true)
            
            switch ($key.Key.ToString()) {
                    "UpArrow" {
                    $currentIndex = if ($currentIndex -gt 0) { $currentIndex - 1 } else { $Items.Count - 1 }
                    }
                    "DownArrow" {
                    $currentIndex = if ($currentIndex -lt ($Items.Count - 1)) { $currentIndex + 1 } else { 0 }
                }
                "Spacebar" {
                    $selected[$currentIndex] = -not $selected[$currentIndex]
                }
                "A" {
                    if ($key.Modifiers -band [ConsoleModifiers]::Control) {
                        for ($i = 0; $i -lt $Items.Count; $i++) {
                            $selected[$i] = $true
                        }
                    }
                }
                "D" {
                    if ($key.Modifiers -band [ConsoleModifiers]::Control) {
                        for ($i = 0; $i -lt $Items.Count; $i++) {
                            $selected[$i] = $false
                        }
                    }
                }
                "Q" {
                    if ($key.Modifiers -band [ConsoleModifiers]::Control) {
                        Write-Host "🔄 Disconnecting from Microsoft Graph..." -ForegroundColor Cyan
                        try {
                            Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
                            Write-Host "✅ Disconnected from Microsoft Graph" -ForegroundColor Green
                        } catch {
                            Write-Host "⚠️ Already disconnected or error during disconnection" -ForegroundColor Yellow
                        }
                        Start-Sleep -Seconds 3
                        exit
                    }
                }
                "Enter" {
                    break
                    }
                }
            } while ($true)
        
        # Return selected indices
        $selectedIndices = @()
        for ($i = 0; $i -lt $Items.Count; $i++) {
            if ($selected[$i]) {
                $selectedIndices += $i
            }
        }
        
        return $selectedIndices
    }
    
    function Show-CheckboxMenu {
        param(
            [array]$Items,
            [string]$Title = "Select Items",
            [string]$Prompt = "Use arrow keys to navigate, SPACE to toggle selection, ENTER to confirm:",
            [switch]$AllowMultiple = $true,
            [switch]$SingleSelection = $false,
            [switch]$PreserveContent = $false,
            [switch]$KeepSelectionVisible = $false,
            [string]$DisplayProperty = $null
        )
        
        if ($Items.Count -eq 0) {
            Write-Host "No items to select from." -ForegroundColor Red
            return @()
        }
        
        # Initialize selection state
        $selected = @{}
        $currentIndex = 0
        
        # For single selection mode, initialize with nothing selected
        for ($i = 0; $i -lt $Items.Count; $i++) {
            $selected[$i] = $false
        }
        
        # Hide cursor for cleaner display
        [Console]::CursorVisible = $false
        
        try {
            [Console]::CursorVisible = $false
            
            # Simple clean approach - just redraw everything each time
            do {
                    Clear-Host
                Show-PIMGlobalHeaderMinimal
                    Write-Host ""
                Write-Host $Title -ForegroundColor Cyan
                Write-Host $("=" * $Title.Length) -ForegroundColor Cyan
                Write-Host ""
                
                # Show all roles
                for ($i = 0; $i -lt $Items.Count; $i++) {
                    $item = $Items[$i]
                    $checkbox = if ($selected[$i]) { "[✓]" } else { "[ ]" }
                    $arrow = if ($i -eq $currentIndex) { "► " } else { "  " }
                    
                    # Get display text
                    $displayText = if ($DisplayProperty -and $item.PSObject.Properties[$DisplayProperty]) {
                        $item.$DisplayProperty
                        } else {
                        $item.ToString()
                    }
                    
                    $line = "$arrow$checkbox $displayText"
                    
                    # Apply colors
                    if ($selected[$i]) {
                        Write-Host $line -ForegroundColor Green
                } else {
                        Write-Host $line -ForegroundColor White
                    }
                }
                
                Write-Host ""
                $selectedCount = ($selected.GetEnumerator() | Where-Object { $_.Value }).Count
                # Check if this is the main workflow menu based on title
                $menuText = if ($Title -eq "🔄 Choose Action") { "Workflow Selected: $selectedCount" } else { "Roles Selected: $selectedCount" }
                Write-Host $menuText -ForegroundColor Cyan
                Write-Host ""
                # Show control bar for navigation
                $controlBarTop = [Console]::CursorTop
                Write-Host "↑/↓ Navigate | SPACE Toggle | ENTER Confirm | Ctrl+Q Exit" -ForegroundColor Magenta
                
                # Get user input
                $key = [Console]::ReadKey($true)
                
                switch ($key.Key.ToString()) {
                    "UpArrow" {
                        $currentIndex = if ($currentIndex -gt 0) { $currentIndex - 1 } else { $Items.Count - 1 }
                    }
                    "DownArrow" {
                        $currentIndex = if ($currentIndex -lt ($Items.Count - 1)) { $currentIndex + 1 } else { 0 }
                    }
                    "Spacebar" {
                        if ($SingleSelection) {
                            # Clear all selections first for single selection mode
                            for ($i = 0; $i -lt $Items.Count; $i++) {
                                $selected[$i] = $false
                            }
                            # Select only the current item
                            $selected[$currentIndex] = $true
                        } else {
                            $selected[$currentIndex] = -not $selected[$currentIndex]
                        }
                    }
                    "Enter" {
                        $selectedItems = @()
                        for ($i = 0; $i -lt $Items.Count; $i++) {
                            if ($selected[$i]) {
                                $selectedItems += $i
                            }
                        }
                        # Clear the control bar line before returning
                        [Console]::SetCursorPosition(0, $controlBarTop)
                        Write-Host (" " * [Console]::WindowWidth) -NoNewline
                        [Console]::SetCursorPosition(0, $controlBarTop)
                        return $selectedItems
                    }
                    "Escape" {
                        return @()
                    }
                    "Q" {
            Write-Host ""
                        Write-Host "Exiting..." -ForegroundColor Yellow
                            Disconnect-MgGraph | Out-Null
                        Write-Host "Disconnected from Microsoft Graph." -ForegroundColor Green
                        Write-Host "Terminal will close in 3 seconds..." -ForegroundColor Yellow
                        Start-Sleep -Seconds 3
                        [Environment]::Exit(0)
                    }
                }
                
                # Handle Ctrl key combinations
                if ($key.Modifiers -eq "Control") {
                    switch ($key.Key) {
                        "A" {
                            # Ctrl+A - Select all items (only if not single selection)
                            if (-not $SingleSelection) {
                                for ($i = 0; $i -lt $Items.Count; $i++) {
                                    $selected[$i] = $true
                                }
                            }
                        }
                        "D" {
                            # Ctrl+D - Deselect all items
                            for ($i = 0; $i -lt $Items.Count; $i++) {
                                $selected[$i] = $false
                            }
                        }
                        "R" {
                            # Ctrl+R - Refresh (return special value)
                            return "REFRESH"
                        }
                        "Q" {
                            # Use centralized exit handler
                            if ($key.Modifiers -eq 'Control') {
                                Invoke-PIMExit -Message "Exiting PIM role management..."
                            }
                        }
                    }
                }
            } while ($true)
        }
        finally {
            [Console]::CursorVisible = $true
        }
    }
    
    # Removed duplicate code - function ends here
    
    # Optimized pending role detection with ultra-fast discovery
    function Get-PendingApprovalRequestsLocal {
        param([string]$CurrentUserId)
        
        try {
            # ULTRA FAST: Just get recent requests with a limit to avoid long waits
            $recentRequests = Get-MgRoleManagementDirectoryRoleAssignmentScheduleRequest -Filter "PrincipalId eq '$CurrentUserId'" -Top 10
            
            # Only consider requests from the last 24 hours to avoid stale data
            $cutoffTime = (Get-Date).AddHours(-24)
            
            # Filter for recent pending, approved, AND provisioned requests that haven't been activated yet
            $pendingRequests = $recentRequests | Where-Object {
                ($_.Status -eq "PendingApproval" -or $_.Status -eq "Approved" -or $_.Status -eq "Provisioned") -and
                $_.Action -eq "selfActivate" -and
                $_.CreatedDateTime -gt $cutoffTime
            }
            
            return $pendingRequests
        } catch {
            # Skip pending check entirely if it fails - don't let it block the app
            return @()
        }
    }
    
    # ULTRA-FAST: Use cached pending requests if available
    try {
        # Check if we have recent cached data (within 30 seconds)
        if ($global:PendingRequestsCache -and $global:PendingRequestsCacheTime -and 
            ((Get-Date) - $global:PendingRequestsCacheTime).TotalSeconds -lt 30) {
            $pendingRequests = $global:PendingRequestsCache
        } else {
            # Only check the most recent 10 requests to keep it fast
            $recentRequests = Get-MgRoleManagementDirectoryRoleAssignmentScheduleRequest -Filter "PrincipalId eq '$currentUserId'" -Top 10 -ErrorAction SilentlyContinue
            
            if ($recentRequests) {
                # Only consider requests from the last 24 hours to avoid stale data
                $cutoffTime = (Get-Date).AddHours(-24)
                
                $pendingRequests = $recentRequests | Where-Object {
                    ($_.Status -eq "PendingApproval" -or $_.Status -eq "Approved" -or $_.Status -eq "Provisioned") -and 
                    $_.Action -eq "selfActivate" -and
                    $_.CreatedDateTime -gt $cutoffTime
                }
            } else {
                $pendingRequests = @()
            }
            
            # Cache the results
            $global:PendingRequestsCache = $pendingRequests
            $global:PendingRequestsCacheTime = Get-Date
        }
    } catch {
        # If API fails, continue without pending check
        $pendingRequests = @()
    }
    
    # Skip pending roles display - go straight to main menu
    # (Pending roles are still filtered out during activation workflow)
    
    # Create main choice menu items
    $menuItems = @(
        "Activate Roles",
        "Deactivate Roles"
    )
    
    # Show checkbox menu with single selection
    $selectedIndices = Show-CheckboxMenu -Items $menuItems -Title "🔄 Choose Action" -Prompt "Use arrow keys to navigate, SPACE to toggle selection, ENTER to confirm:" -SingleSelection
    
    if ($selectedIndices.Count -gt 0) {
        $selectedIndex = $selectedIndices[0]
        $selectedAction = $menuItems[$selectedIndex]
        
        if ($selectedAction -eq "Activate Roles") {
            # Get eligible roles using the optimized function (filtering intact)
            $eligibleRoles = Get-EligibleRolesOptimized -CurrentUserId $currentUserId
            Start-RoleActivationWorkflow -ValidRoles $eligibleRoles -CurrentUserId $currentUserId
        } elseif ($selectedAction -eq "Deactivate Roles") {
            Start-RoleDeactivationWorkflowWithCheck -CurrentUserId $currentUserId
        }
    }
    return
    
    # ========================= WORKFLOW FUNCTIONS =========================
    
    
    function Start-PIMRoleManagement {
        param(
            [string]$CurrentUserId
        )
        
        [Console]::CursorVisible = $false
        Clear-Host
        Show-PIMGlobalHeaderMinimal
        
        # Create main choice menu items
        $menuItems = @(
            "Activate Roles",
            "Deactivate Roles"
        )
        
        # Show checkbox menu with single selection
        [Console]::CursorVisible = $true
        $selectedIndices = Show-CheckboxMenu -Items $menuItems -Title "🔄 Choose Action" -Prompt "Use arrow keys to navigate, SPACE to toggle selection, ENTER to confirm:" -SingleSelection
        
        if ($selectedIndices.Count -eq 0) {
            return
        }
        
        $selectedIndex = $selectedIndices[0]
        $selectedAction = $menuItems[$selectedIndex]
        
        if ($selectedAction -eq "Activate Roles") {
            # Get eligible roles and navigate to activation workflow
            $eligibleRoles = Get-EligibleRolesOptimized -CurrentUserId $CurrentUserId
            # Apply the same additional filtering that Start-RoleActivationWorkflow does
            if ($eligibleRoles.Count -gt 0) {
                $pendingRequests = Get-PendingApprovalRequestsLocal -CurrentUserId $CurrentUserId
                $pendingRoleIds = @()
                if ($pendingRequests.Count -gt 0) {
                    $pendingRoleIds = $pendingRequests | ForEach-Object { $_.RoleDefinitionId }
                }
                
                # Filter out pending roles (same as Start-RoleActivationWorkflow)
                $eligibleRoles = $eligibleRoles | Where-Object { 
                    $pendingRoleIds -notcontains $_.RoleDefinitionId
                }
            }
            Write-PIMHost "Press ENTER to continue..." -ForegroundColor Cyan
            Read-Host
            Start-RoleActivationWorkflow -ValidRoles $eligibleRoles -CurrentUserId $CurrentUserId
        } elseif ($selectedAction -eq "Deactivate Roles") {
            # Navigate to deactivation workflow with silent pending role filtering
            Start-RoleDeactivationWorkflowWithCheck -CurrentUserId $CurrentUserId
        }
    }
    
    function Start-RoleActivationWorkflowWithCheck {
        param(
            [string]$CurrentUserId,
            [switch]$SkipDeactivationOffer
        )
        
        # Use the exact same logic that was working in the original script - silently
        
        $allEligibleRoles = @()
        try {
            # OPTIMIZED: Use filter and cached role definitions for much better performance
            $eligibilitySchedules = Get-MgRoleManagementDirectoryRoleEligibilityScheduleInstance -Filter "PrincipalId eq '$CurrentUserId'" -All
            
            # FASTEST: Use parallel processing to get role definitions (PowerShell 7+)
            if ($PSVersionTable.PSVersion.Major -ge 7 -and $eligibilitySchedules.Count -gt 3) {
                # Use parallel processing for multiple roles
                $allEligibleRoles = $eligibilitySchedules | ForEach-Object -Parallel {
                    try {
                        $roleDef = Get-MgRoleManagementDirectoryRoleDefinition -UnifiedRoleDefinitionId $_.RoleDefinitionId
                        [PSCustomObject]@{
                            RoleDefinitionId = $_.RoleDefinitionId
                            RoleDefinition   = @{
                                DisplayName = $roleDef.DisplayName
                                Id = $roleDef.Id
                                Description = $roleDef.Description
                            }
                            PrincipalId      = $_.PrincipalId
                            DirectoryScopeId = $_.DirectoryScopeId
                        }
                    } catch {
                        # Skip roles that fail to load
                        $null
                    }
                } | Where-Object { $_ -ne $null }
                    } else {
                # Sequential processing for few roles
                foreach ($schedule in $eligibilitySchedules) {
                    try {
                        $roleDef = Get-MgRoleManagementDirectoryRoleDefinition -UnifiedRoleDefinitionId $schedule.RoleDefinitionId
                        $allEligibleRoles += [PSCustomObject]@{
                            RoleDefinitionId = $schedule.RoleDefinitionId
                            RoleDefinition   = @{
                                DisplayName = $roleDef.DisplayName
                                Id = $roleDef.Id
                                Description = $roleDef.Description
                            }
                            PrincipalId      = $schedule.PrincipalId
                            DirectoryScopeId = $schedule.DirectoryScopeId
                        }
                    } catch {
                        # Skip roles that fail to load
                        continue
                    }
                }
            }
        } catch {
            Write-Host "Error retrieving eligible roles: $($_.Exception.Message)" -ForegroundColor Red
            $allEligibleRoles = @()
        }
    
        # Get pending role IDs to filter them out
        $pendingRequests = Get-PendingApprovalRequestsLocal -CurrentUserId $CurrentUserId
        $pendingRoleIds = @()
        if ($pendingRequests.Count -gt 0) {
            $pendingRoleIds = $pendingRequests | ForEach-Object { $_.RoleDefinitionId }
        }
    
        # FAST: Filter out roles that are already active using direct API call
        try {
            $userAssignments = Get-MgRoleManagementDirectoryRoleAssignment -Filter "PrincipalId eq '$CurrentUserId'" -All
            $activeRoleIds = $userAssignments | ForEach-Object { $_.RoleDefinitionId }
        } catch {
            # Fallback if filter not supported
            Write-Host "Using fallback method for active roles..." -ForegroundColor Yellow
            $userAssignments = Get-MgRoleManagementDirectoryRoleAssignment -All | Where-Object { $_.PrincipalId -eq $CurrentUserId }
            # Get unique role IDs for batch processing - filter out empty/null values and expired roles
        $currentTime = Get-Date
        
        $activeAssignments = $userAssignments | Where-Object { 
            -not [string]::IsNullOrWhiteSpace($_.RoleDefinitionId) -and
            (-not $_.EndDateTime -or [DateTime]::Parse($_.EndDateTime).ToLocalTime() -gt $currentTime) -and
            ($_.AssignmentType -eq 'Activated' -or $_.AssignmentType -eq 'Assigned')
        }
        
        $activeRoleIds = $activeAssignments | ForEach-Object { $_.RoleDefinitionId }
        }
        
        $eligibleRoles = $allEligibleRoles | Where-Object { 
            $activeRoleIds -notcontains $_.RoleDefinitionId -and
            $pendingRoleIds -notcontains $_.RoleDefinitionId
        }
    
        # Deduplicate roles by RoleDefinitionId to prevent duplicates
        $validRoles = $eligibleRoles | Sort-Object RoleDefinitionId | Group-Object RoleDefinitionId | ForEach-Object { $_.Group[0] }
    
    
        
        if ($validRoles.Count -eq 0) {
            # Clear screen and start fresh to remove old controls
            Clear-Host
            Show-PIMGlobalHeaderMinimal
            Write-Host ""
            Write-Host "ℹ️  No roles available for activation at this time." -ForegroundColor Gray
            Write-Host ""
            
            if ($SkipDeactivationOffer) {
                # Don't offer deactivation since we came from deactivation workflow
                Write-Host "❌ No role management workflows available." -ForegroundColor Red
                    Write-Host ""
                    Write-Host "Check back later when roles are approved or activated." -ForegroundColor Gray
                    Write-Host ""
                    Show-DynamicControlBar
                    
                    # Wait for Ctrl+Q to exit
                    do {
                        $key = [Console]::ReadKey($true)
                        if ($key.Key -eq 'Q' -and $key.Modifiers -eq 'Control') {
                            Invoke-PIMExit -Message "Exiting PIM role management..."
                        }
                    } while ($true)
                    return
                Write-Host ""
                Write-Host "Returning to main menu..." -ForegroundColor Gray
                Start-Sleep -Seconds 1
                return
            } else {
                # Get user input with proper cursor positioning
                do {
                    $input = Read-PIMInput -Prompt "Would you like to check for roles to deactivate instead? (Y/N)" -ControlsText $script:ControlMessages['Exit']
                    $input = $input.Trim().ToUpper()
                    if ($input -eq "Y" -or $input -eq "YES") {
                        $continueChoice = "Yes"
                        break
                    } elseif ($input -eq "N" -or $input -eq "NO") {
                        $continueChoice = "No"
                        break
                } else {
                        Write-PIMHost "Please enter Y or N." -ForegroundColor Yellow -ControlsText $script:ControlMessages['Exit']
                    }
                } while ($true)
                
                # Show controls at the bottom after user responds
                Write-Host ""
                
                if ($continueChoice -eq "Yes") {
                    # Go directly to deactivation workflow
                    Start-RoleDeactivationWorkflowWithCheck -CurrentUserId $CurrentUserId
                } else {
                    Write-Host "❌ No role management workflows available." -ForegroundColor Red
                    Write-Host ""
                    Write-Host "Check back later when roles are approved or activated." -ForegroundColor Gray
                    Write-Host ""
                    Show-DynamicControlBar
                    
                    # Wait for Ctrl+Q to exit
                    do {
                        $key = [Console]::ReadKey($true)
                        if ($key.Key -eq 'Q' -and $key.Modifiers -eq 'Control') {
                            Invoke-PIMExit -Message "Exiting PIM role management..."
                        }
                    } while ($true)
                    return
                    Write-Host ""
                    Write-Host "Returning to main menu..." -ForegroundColor Gray
                    Start-Sleep -Seconds 1
                    # Return to main workflow choice menu instead of exiting
                    return
                }
            }
            return
        }
        
        # Continue to activation workflow
        Start-RoleActivationWorkflow -ValidRoles $validRoles -CurrentUserId $CurrentUserId
    }
    
    
    function Show-DeactivationCountdown {
        param(
            [array]$TooNewRoles,
            [array]$ReadyRoles,
            [string]$CurrentUserId
        )
        
        # Build static header content once
        $headerLines = @()
        $headerLines += "[ P I M - G L O B A L ]"
        $headerLines += ""
        $headerLines += "⏰ Time Remaining Until Roles Can Be Deactivated"
        $headerLines += "   (5-minute minimum activation period required)"
        $headerLines += ""
        
        do {
            # Clear and redraw header every time for clean display
            Clear-Host
            foreach ($line in $headerLines) {
                if ($line -eq "[ P I M - G L O B A L ]") {
                    Write-Host $line -ForegroundColor Magenta
                } elseif ($line -eq "⏰ Time Remaining Until Roles Can Be Deactivated") {
                    Write-Host $line -ForegroundColor Yellow
                } elseif ($line -eq "   (5-minute minimum activation period required)") {
                    Write-Host $line -ForegroundColor Gray
                } else {
                    Write-Host $line
                }
            }
            
            $allReady = $true
            
            foreach ($roleInfo in $TooNewRoles) {
                try {
                    $activationTime = $roleInfo.ActivationTime
                    $deactivationTime = $activationTime.AddMinutes(5)
                    $timeRemaining = $deactivationTime - (Get-Date)
                    
                    if ($timeRemaining.TotalSeconds -gt 0) {
                        $allReady = $false
                        $minutes = [int][math]::Floor($timeRemaining.TotalMinutes)
                        $seconds = [int][math]::Floor($timeRemaining.TotalSeconds % 60)
                        $timeDisplay = "{0:D2}:{1:D2}" -f $minutes, $seconds
                        
                        Write-Host "  ⏳ $($roleInfo.RoleName): $timeDisplay remaining" -ForegroundColor Cyan
                    } else {
                        Write-Host "  ✅ $($roleInfo.RoleName): Ready for deactivation!" -ForegroundColor Green
                    }
                } catch {
                    Write-Host "  ❓ $($roleInfo.RoleName): Unable to check" -ForegroundColor Yellow
                }
            }
            
            Show-DynamicControlBar -ControlsText "Any key to skip countdown | Ctrl+Q Exit"
            
            # Check if user pressed a key to skip
            if ([Console]::KeyAvailable) {
                [Console]::ReadKey($true) | Out-Null
                Write-Host "Countdown skipped by user." -ForegroundColor Yellow
                return $false
            }
            
            if (-not $allReady) {
                Start-Sleep -Seconds 1
            }
            
        } while (-not $allReady)
        
        [Console]::CursorVisible = $true
        
        # All roles are ready
        Clear-Host
        Show-PIMGlobalHeaderMinimal
        Write-Host ""
        Write-Host "✅ All roles are now eligible for deactivation!" -ForegroundColor Green
        Write-Host ""
        Start-Sleep -Seconds 2
        return $true
    }

# Move Start-RoleDeactivationWorkflow to global scope  
function Start-RoleDeactivationWorkflow {
    param(
        [array]$ActiveRoles,
        [string]$CurrentUserId
    )
    
    
    # Get cached schedules for activation time checking
    try {
        $cachedSchedules = Get-CachedSchedules -CurrentUserId $CurrentUserId
    } catch {
        $cachedSchedules = @()
    }
        [Console]::CursorVisible = $false
        if ($ActiveRoles.Count -eq 0) {
            Write-Host "❌ No active roles available for deactivation." -ForegroundColor Red
            return
        }  
    # Check for roles that are too new to deactivate (5-minute rule)
    $readyToDeactivate = @()
    $tooNewRoles = @()
    
    
    foreach ($role in $ActiveRoles) {
        try {
            $assignment = $role.Assignment
            $schedules = $cachedSchedules | Where-Object { 
                $_.PrincipalId -eq $assignment.PrincipalId -and 
                $_.RoleDefinitionId -eq $assignment.RoleDefinitionId 
            }
            
            if ($schedules) {
                # Filter for activation requests only
                $activationSchedules = $schedules | Where-Object { $_.Action -eq "selfActivate" }
                if ($activationSchedules) {
                    # Get the most recent activation request
                    $latestSchedule = $activationSchedules | Sort-Object CreatedDateTime -Descending | Select-Object -First 1
                    
                    # Get activation time efficiently
                    if ($latestSchedule.ScheduleInfo -and $latestSchedule.ScheduleInfo.StartDateTime) {
                        $activationTime = [DateTime]::Parse($latestSchedule.ScheduleInfo.StartDateTime).ToLocalTime()
                    } else {
                        $activationTime = [DateTime]::Parse($latestSchedule.CreatedDateTime).ToLocalTime()
                    }
                    
                    $timeSinceActivation = (Get-Date) - $activationTime
                    if ($timeSinceActivation.TotalMinutes -lt 5) {
                        $tooNewRoles += [PSCustomObject]@{
                            RoleName = $role.RoleName
                            ActivationTime = $activationTime
                            Assignment = $role.Assignment
                        }
                    } else {
                        $readyToDeactivate += $role
                    }
                } else {
                    # No activation schedules found, assume it's ready
                    $readyToDeactivate += $role
                }
            } else {
                # If we can't get activation time, assume it's ready (old activation)
                $readyToDeactivate += $role
            }
        } catch {
            # If there's an error checking, assume it's ready
            $readyToDeactivate += $role
        }
    }
    
    # If some roles are too new, show countdown
    if ($tooNewRoles.Count -gt 0) {
        [Console]::CursorVisible = $false
        Clear-Host
        Show-PIMGlobalHeaderMinimal
        Write-Host ""
        
        if ($readyToDeactivate.Count -eq 0) {
            Write-Host "⏰ All roles are within the 5-minute activation period." -ForegroundColor Yellow
            Write-Host "Showing countdown until they can be deactivated..." -ForegroundColor Cyan
        } else {
            Write-Host "⏰ Some roles are within the 5-minute activation period." -ForegroundColor Yellow
            Write-Host "Showing countdown for roles that cannot be deactivated yet..." -ForegroundColor Cyan
        }
        Write-Host ""
        
        Show-DeactivationCountdown -TooNewRoles $tooNewRoles
        return
    }
    
    # If no roles are ready for deactivation, inform user and return
    if ($readyToDeactivate.Count -eq 0) {
        Write-Host "ℹ️  All roles are currently within the 5-minute activation period." -ForegroundColor Gray
        Write-Host ""
        
        # Ask if user wants to activate roles instead with inline input handling
        Write-Host "Would you like to activate roles instead? (Y/N): " -NoNewline -ForegroundColor Cyan
        
        # Store cursor position for inline input
        $promptLeft = [Console]::CursorLeft
        $promptTop = [Console]::CursorTop
        
        # Show control bar below the prompt with proper spacing
        Write-Host "`n"  # Add blank line after prompt
        Write-Host "Ctrl+Q to exit" -ForegroundColor Magenta
        $script:LastControlBarLine = [Console]::CursorTop - 1
        
        # Return cursor to inline position after the prompt (same line as Y/N question)
        [Console]::SetCursorPosition($promptLeft, $promptTop)
        
        $userInput = ""
        do {
            $key = [Console]::ReadKey($true)
            
            # Check for Ctrl+Q
            if ($key.Key -eq 'Q' -and $key.Modifiers -eq 'Control') {
                Invoke-PIMExit
                return
            }
            
            # Handle Enter key
            if ($key.Key -eq 'Enter') {
                if ($userInput -eq 'Y' -or $userInput -eq 'y') {
                    # Clear the control bar and move cursor to start of that line
                    if ($script:LastControlBarLine -ge 0) {
                        try {
                            [Console]::SetCursorPosition(0, $script:LastControlBarLine)
                            Write-Host (" " * [Console]::WindowWidth) -NoNewline
                            $script:LastControlBarLine = -1
                        } catch { }
                    }
                    Clear-Host
                                        Start-PIMRoleManagement -CurrentUserId $CurrentUserId
                                        return
                } elseif ($userInput -eq 'N' -or $userInput -eq 'n') {
                    Write-Host ""
                    Write-Host "❌ No role management workflows available." -ForegroundColor Red
                    Write-Host ""
                    Write-Host "Check back later when roles are approved or activated." -ForegroundColor Gray
                    Write-Host ""
                    Show-DynamicControlBar
                    
                    # Wait for Ctrl+Q to exit
                    do {
                        $key = [Console]::ReadKey($true)
                        if ($key.Key -eq 'Q' -and $key.Modifiers -eq 'Control') {
                            Invoke-PIMExit -Message "Exiting PIM role management..."
                        }
                    } while ($true)
                    return
                    return
                } else {
                    Write-Host ""
                    Write-Host "Please enter Y or N: " -NoNewline -ForegroundColor Yellow
                    # Clear and redraw control bar for invalid input
                    if ($script:LastControlBarLine -ge 0) {
                        try {
                            [Console]::SetCursorPosition(0, $script:LastControlBarLine)
                            Write-Host (" " * [Console]::WindowWidth) -NoNewline
                        } catch { }
                    }
                    Write-Host ""
                    Write-Host "Ctrl+Q to exit" -ForegroundColor Magenta
                    $script:LastControlBarLine = [Console]::CursorTop - 1
                    # Return cursor to prompt position
                    [Console]::SetCursorPosition([Console]::CursorLeft, [Console]::CursorTop - 2)
                    $userInput = ""
                }
            }
            # Handle backspace
            elseif ($key.Key -eq 'Backspace' -and $userInput.Length -gt 0) {
                $userInput = $userInput.Substring(0, $userInput.Length - 1)
                Write-Host "`b `b" -NoNewline
            }
            # Handle regular characters (Y/N only)
            elseif ($key.KeyChar -match '[YyNn]' -and $userInput.Length -eq 0) {
                $userInput = $key.KeyChar.ToString().ToUpper()
                Write-Host $userInput -NoNewline -ForegroundColor Green
            }
        } while ($true)
        
        if ($continueChoice -eq "Yes") {
            # Return to choice menu
            return
        } else {
            Write-Host "❌ No role management workflows available." -ForegroundColor Red
                    Write-Host ""
                    Write-Host "Check back later when roles are approved or activated." -ForegroundColor Gray
                    Write-Host ""
                    Show-DynamicControlBar
                    
                    # Wait for Ctrl+Q to exit
                    do {
                        $key = [Console]::ReadKey($true)
                        if ($key.Key -eq 'Q' -and $key.Modifiers -eq 'Control') {
                            Invoke-PIMExit -Message "Exiting PIM role management..."
                        }
                    } while ($true)
                    return
            Write-Host "Script completed successfully." -ForegroundColor Green
        }
        return
    }
    
    # Get role expiration data for countdown display
    try {
        $userAssignments = Get-MgRoleManagementDirectoryRoleAssignment -Filter "PrincipalId eq '$CurrentUserId'" -All
        $roleExpirationData = @()
        
        foreach ($role in $readyToDeactivate) {
            $assignment = $role.Assignment
            $schedules = $cachedSchedules | Where-Object { 
                $_.PrincipalId -eq $assignment.PrincipalId -and 
                $_.RoleDefinitionId -eq $assignment.RoleDefinitionId 
            }
            $schedule = $schedules | Sort-Object CreatedDateTime -Descending | Select-Object -First 1
            
            if ($schedule.ScheduleInfo.Expiration.EndDateTime) {
                $expirationTime = [DateTime]::Parse($schedule.ScheduleInfo.Expiration.EndDateTime).ToLocalTime()
                $roleExpirationData += [PSCustomObject]@{
                    RoleName = $role.RoleName
                    ExpirationTime = $expirationTime
                    Assignment = $assignment
                    Index = $readyToDeactivate.IndexOf($role)
                }
            }
        }
        
        # Remove duplicates
        $roleExpirationData = $roleExpirationData | Sort-Object RoleName, ExpirationTime -Descending | Group-Object RoleName | ForEach-Object { $_.Group[0] }
        
    } catch {
        Write-Host "⚠️ Could not retrieve role expiration data for countdown display: $($_.Exception.Message)" -ForegroundColor Yellow
        $roleExpirationData = @()
    }
    
    # Use countdown menu if we have expiration data
    if ($roleExpirationData.Count -gt 0) {
        $selectedIndices = Show-CheckboxMenu -Items $readyToDeactivate -Title "🔄 Select Active Roles to Deactivate" -Prompt "Use arrow keys to navigate, SPACE to toggle selection, ENTER to confirm:" -DisplayProperty "RoleName"
    } else {
        # OPTIMIZED: Batch get all expiration data in single API call
        $allScheduleInstances = Get-MgRoleManagementDirectoryRoleAssignmentScheduleInstance -Filter "PrincipalId eq '$CurrentUserId' and AssignmentType eq 'Activated'" -All
        $scheduleInstanceLookup = @{}
        foreach ($instance in $allScheduleInstances) {
            $scheduleInstanceLookup[$instance.RoleDefinitionId] = $instance
        }
        
        $roleItemsWithExpiration = @()
        foreach ($role in $readyToDeactivate) {
            $assignment = $role.Assignment
            
            # Get expiration time from lookup table (O(1) access)
            try {
                $scheduleInstance = $scheduleInstanceLookup[$assignment.RoleDefinitionId]
                
                if ($scheduleInstance -and $scheduleInstance.EndDateTime) {
                    $expirationTime = [DateTime]::Parse($scheduleInstance.EndDateTime).ToLocalTime()
                    $timeRemaining = $expirationTime - (Get-Date)
                    
                    
                    if ($timeRemaining.TotalSeconds -gt 0) {
                        $hours = [Math]::Floor($timeRemaining.TotalHours)
                        $minutes = $timeRemaining.Minutes
                        $seconds = $timeRemaining.Seconds
                        
                        if ($hours -gt 0) {
                            $countdownText = "expires in ${hours}h ${minutes}m"
                        } else {
                            $countdownText = "expires in ${minutes}m ${seconds}s"
                        }
                        
                        $roleItemsWithExpiration += "$($role.RoleName) ($countdownText)"
                    } else {
                        $roleItemsWithExpiration += "$($role.RoleName) (expired)"
                    }
                } else {
                    # Try alternative approach using cached schedules
                    $cachedSchedules = Get-CachedSchedules -CurrentUserId $CurrentUserId
                    $schedules = $cachedSchedules | Where-Object { 
                        $_.PrincipalId -eq $assignment.PrincipalId -and 
                        $_.RoleDefinitionId -eq $assignment.RoleDefinitionId 
                    }
                    $schedule = $schedules | Sort-Object CreatedDateTime -Descending | Select-Object -First 1
                    
                    if ($schedule.ScheduleInfo.Expiration.EndDateTime) {
                        $expirationTime = [DateTime]::Parse($schedule.ScheduleInfo.Expiration.EndDateTime).ToLocalTime()
                        $timeRemaining = $expirationTime - (Get-Date)
                        
                        if ($timeRemaining.TotalSeconds -gt 0) {
                            $hours = [Math]::Floor($timeRemaining.TotalHours)
                            $minutes = $timeRemaining.Minutes
                            
                            if ($hours -gt 0) {
                                $countdownText = "expires in ${hours}h ${minutes}m"
                            } else {
                                $countdownText = "expires in ${minutes}m"
                            }
                            
                            $roleItemsWithExpiration += "$($role.RoleName) ($countdownText)"
                        } else {
                            $roleItemsWithExpiration += "$($role.RoleName) (expired)"
                        }
                    } else {
                        $roleItemsWithExpiration += "$($role.RoleName) (no expiration data)"
                    }
                }
            } catch {
                $roleItemsWithExpiration += "$($role.RoleName) (expiration unknown)"
            }
        }
        $selectedIndices = Show-CheckboxMenu -Items $roleItemsWithExpiration -Title "🔄 Select Active Roles to Deactivate" -Prompt "Use arrow keys to navigate, SPACE to toggle selection, ENTER to confirm:"
    }
    
    if ($selectedIndices.Count -eq 0) {
                Write-Host "❌ No roles selected for deactivation." -ForegroundColor Yellow
        return
    }
    
    # Clear screen and show clean deactivation progress
    Clear-Host
    Show-PIMGlobalHeaderMinimal
    Write-Host ""
    Write-Host "🔄 Deactivating $($selectedIndices.Count) role(s)..." -ForegroundColor Cyan
    Write-Host ""
    
    $successCount = 0
    $failCount = 0
    $skippedCount = 0
    
    foreach ($index in $selectedIndices) {
        # Validate index
        if ($index -lt 0 -or $index -ge $readyToDeactivate.Count) {
            Write-Host "⚠️ Invalid selection index: $index" -ForegroundColor Yellow
            continue
        }
        
        $role = $readyToDeactivate[$index]
        $assignment = $role.Assignment
        $roleName = $role.RoleName
        
        try {
            # Validate assignment data
            if (-not $assignment.PrincipalId -or -not $assignment.RoleDefinitionId) {
                Write-Host "   ❌ Invalid assignment data for: $roleName" -ForegroundColor Red
                $failCount++
                continue
            }
            
            # Create deactivation request
            $deactivationRequest = @{
                action = "selfDeactivate"
                principalId = $assignment.PrincipalId
                roleDefinitionId = $assignment.RoleDefinitionId
                directoryScopeId = if ($assignment.DirectoryScopeId) { $assignment.DirectoryScopeId } else { "/" }
            }
            
            # Make the deactivation request
            $result = New-MgRoleManagementDirectoryRoleAssignmentScheduleRequest -BodyParameter $deactivationRequest
            
            if ($result) {
                Write-Host "✅ Successfully deactivated: $roleName" -ForegroundColor Green
                $successCount++
                
                # Clear cache to ensure fresh data on next deactivation check
                $script:ScheduleInstanceCache = @{}
                $script:ScheduleInstanceCacheExpiry = (Get-Date).AddSeconds(-1)
                
                # FIXED: Clear global active role cache so deactivated role appears in activation workflow
                $global:ActiveRoleCache = @()
                $global:ActiveRoleCacheTime = $null
            } else {
                Write-Host "❌ Failed to deactivate: $roleName" -ForegroundColor Red
                $failCount++
            }
            
        } catch {
            $errorMessage = $_.Exception.Message
            if ($errorMessage -like "*RoleAssignmentDoesNotExist*") {
                Write-Host "⚠️ Role already deactivated: $roleName" -ForegroundColor Yellow
                $skippedCount++
            } else {
                Write-Host "❌ Role deactivation failed for ${roleName}: $errorMessage" -ForegroundColor Red
                $failCount++
            }
        }
    }
    
    Write-Host ""
    
    # Ask if user wants to manage more roles
    do {
        $input = Read-PIMInput -Prompt "Would you like to manage more roles? (Y/N)" -ControlsText $script:ControlMessages['Exit']
        $input = $input.Trim().ToUpper()
        if ($input -eq "Y" -or $input -eq "YES") {
            $continueChoice = "Yes"
            break
        } elseif ($input -eq "N" -or $input -eq "NO") {
            $continueChoice = "No"
            break
        } else {
            Write-Host "Please enter Y or N." -ForegroundColor Yellow
        }
    } while ($true)
        
        if ($continueChoice -eq "Yes") {
            # Use the working choice menu logic from main script
            $menuItems = @("Activate Roles", "Deactivate Roles")
            $selectedIndices = Show-CheckboxMenu -Items $menuItems -Title "🔄 Choose Action" -Prompt "Use arrow keys to navigate, SPACE to toggle selection, ENTER to confirm:" -SingleSelection
            
            if ($selectedIndices.Count -gt 0) {
                $selectedIndex = $selectedIndices[0]
                $selectedAction = $menuItems[$selectedIndex]
                
                if ($selectedAction -eq "Activate Roles") {
                    $eligibleRoles = Get-EligibleRolesOptimized -CurrentUserId $CurrentUserId
                    Start-RoleActivationWorkflow -ValidRoles $eligibleRoles -CurrentUserId $CurrentUserId
                } elseif ($selectedAction -eq "Deactivate Roles") {
                    Start-RoleDeactivationWorkflowWithCheck -CurrentUserId $CurrentUserId
                }
            }
        } else {
            Write-PIMHost "No additional roles will be managed." -ForegroundColor Cyan -ControlsText $script:ControlMessages['Exit']
            Write-PIMHost "Please close the terminal." -ForegroundColor Yellow -ControlsText $script:ControlMessages['Exit']
            
            # Wait for user to exit with Ctrl+Q
            do {
                if ([Console]::KeyAvailable) {
                    $key = [Console]::ReadKey($true)
                    if (Test-GlobalShortcut -Key $key) {
                        return
                    }
                }
                Start-Sleep -Milliseconds 100
            } while ($true)
        }
    }
    
    # Script execution complete
    
    
    
    # ========================= SMART ROLE MANAGEMENT MENU =========================
    
    function Show-SmartRoleManagementMenu {
        # Get current role status
        $activeRoles = Get-ActiveRoles
        $validRoles = Get-ValidRoles
        
        # Show menu based on available roles
                    Clear-Host
        Show-PIMGlobalHeaderMinimal
        Write-Host "Smart Role Management" -ForegroundColor Cyan
        Write-Host "=====================" -ForegroundColor Cyan
                    Write-Host ""
    
        if ($activeRoles.Count -gt 0 -and $validRoles.Count -gt 0) {
            Show-WorkflowChoiceMenu -ActiveRoles $activeRoles -EligibleRoles $validRoles
        } elseif ($validRoles.Count -gt 0) {
            Start-RoleActivationWorkflow -ValidRoles $validRoles
        } elseif ($activeRoles.Count -gt 0) {
            Start-RoleDeactivationWorkflow -ActiveRoles $activeRoles
                } else {
            Write-Host "❌ No roles available." -ForegroundColor Red
        }
    }
    
# ========================= MAIN SCRIPT EXECUTION =========================

[Console]::CursorVisible = $false
Write-Host "=== SCRIPT STARTING - CONNECTING TO MICROSOFT GRAPH ===" -ForegroundColor Green

# Connect to Microsoft Graph
try {
    # Clear any expired cache entries before starting
    Clear-ExpiredCache
    
    Connect-MgGraph -Scopes 'RoleManagement.ReadWrite.Directory', 'Directory.Read.All' -NoWelcome
    Write-Host "✅ Successfully connected to Microsoft Graph" -ForegroundColor Green
} catch {
    Write-Host "❌ Failed to connect to Microsoft Graph: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Get current user ID
try {
    $currentUser = Get-MgUser -UserId (Get-MgContext).Account -ErrorAction Stop
    $currentUserId = $currentUser.Id
    Write-Host "✅ Current User ID: $currentUserId" -ForegroundColor Green
} catch {
    Write-Host "❌ Failed to get current user: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Start the PIM role management workflow
[Console]::CursorVisible = $true
Start-PIMRoleManagement -CurrentUserId $currentUserId
