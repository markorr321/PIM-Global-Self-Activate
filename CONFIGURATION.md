# PIM-Global-MST Configuration Guide

## Table of Contents
1. [First-Time Setup & Requirements](#first-time-setup--requirements)
2. [Microsoft Teams Integration Setup](#microsoft-teams-integration-setup)
3. [Power Automate Workflow Configuration](#power-automate-workflow-configuration)
4. [Advanced Configuration Options](#advanced-configuration-options)
5. [Troubleshooting](#troubleshooting)

---

## 🚀 Key Features

### **Advanced Authentication**
- ✅ **Handles Authentication Contexts seamlessly** - Automatically manages conditional access requirements
- 🔐 **Phishing-resistant passwordless MFA** support with both:
  - **Platform passkeys** (Windows Hello, Touch ID, Face ID)
  - **Portable passkeys** (FIDO2 security keys, mobile authenticators)

### **Enhanced PIM Management**
- 📋 **Dual-mode operation**: Role activation and deactivation in one unified script
- 🔍 **Active role detection**: Automatically identifies and filters currently active roles
- ⚡ **Multi-role operations**: Activate or deactivate multiple roles simultaneously
- 🔄 **Interactive session mode**: Perform multiple operations without re-authentication
- 🎨 **Color-coded output**: Enhanced visual feedback for better user experience
- 🛡️ **Improved error handling**: Comprehensive error messages and graceful failure recovery
- 🔄 **Real-time API sync**: Live synchronization with Azure AD PIM APIs

### **Script Evolution**
- 🆕 **PIM-Global-Teams-v2.ps1**: Latest version with full Teams integration and advanced features
- 🔄 **Backward compatibility**: Legacy PIM-Global.ps1 maintained for existing deployments

---

## First-Time Setup & Requirements

### System Requirements

#### **Mandatory Requirements**
- ✅ **Windows 10/11** (x64)
- ✅ **PowerShell 7+** - [Download here](https://github.com/PowerShell/PowerShell/releases)
- ✅ **Entra ID Premium P2** license (for PIM functionality)
- ✅ **Internet connectivity** for Microsoft Graph API calls
- ✅ **Eligible PIM roles** in your Azure AD tenant

#### **Optional Requirements (for Teams integration)**
- 🔹 **Microsoft Teams** access
- 🔹 **Teams channel management** permissions
- 🔹 **Power Automate Premium** license or **Power Platform** subscription (for approval workflows) 

### Initial Configuration Steps

#### **Step 1: Download and Extract**
1. Download `PIM-Global-SA.exe` from the [releases page](https://github.com/markorr321/PIM-Global-Self-Activate/releases)
2. Place the executable in a folder of your choice or pin it to your taskbar for daily use!
3. No installation required - it's a portable executable

#### **Step 2: Basic Configuration (Required)**
The tool works out-of-the-box for PIM functionality, but you need to configure Teams integration for notifications.

**Option A: Disable Teams Integration (Simplest)**
1. Extract the PowerShell script from the executable (run once to create temp files)
2. Edit `PIM-Global-Teams-v2.ps1` in the temp directory
3. Change line 80: `$enableTeamsNotifications = $false`

**Option B: Configure Teams Integration (Recommended)**
Continue to the Teams setup section below.

#### **Step 3: First Run**
1. Double-click `PIM-Global-SA.exe`
2. The tool will automatically install required PowerShell modules:
   - `MSAL.PS` (Microsoft Authentication Library)
   - `Microsoft.Graph` (Graph API PowerShell SDK)
3. Follow the browser authentication prompts
4. Grant the required permissions when prompted

#### **Step 4: Test Basic Functionality**
- The tool should display your eligible PIM roles
- You should be able to activate/deactivate roles
- If Teams is not configured, you'll see friendly warning messages (this is normal)

---

## Microsoft Teams Integration Setup

### Overview
Teams integration provides rich notifications for PIM role activations and approvals through adaptive cards.

### Step 1: Create Teams Webhooks

#### **Main Notification Channel (Required)**
1. **Open Microsoft Teams**
2. **Navigate to your desired channel** (e.g., "IT Operations", "Security")
3. **Click the three dots (...)** next to the channel name
4. **Select "Connectors"** or **"Manage channel"**
5. **Click "Edit"** if using the new Teams experience
6. **Find "Incoming Webhook"** and click **"Add"**
7. **Configure the webhook:**
   - **Name**: `PIM Role Notifications`
   - **Description**: `Automated notifications for PIM role activations`
   - **Upload image**: Optional (use your company logo)
8. **Copy the webhook URL** - it looks like:
   ```
   https://[tenant].webhook.office.com/webhookb2/[guid]/IncomingWebhook/[guid]/[guid]
   ```

#### **Approval Channel (Optional but Recommended)**
For roles requiring approval, create a separate webhook:
1. **Repeat the above steps** in your approval channel (e.g., "PIM Approvals")
2. **Name**: `PIM Approval Requests`
3. **Copy this webhook URL** as well

### Step 2: Configure Webhook URLs in Script

#### **Method 1: Edit the Executable's Embedded Script**
1. **Run the executable once** to extract files to temp directory
2. **Navigate to**: `%TEMP%\PIM-Global-MST\`
3. **Edit** `PIM-Global-Teams-v2.ps1`
4. **Update these lines** (around lines 71-74):

```powershell
# Main notifications webhook
$teamsWebhookUrl = "YOUR_MAIN_WEBHOOK_URL_HERE"

# Approval channel webhook (optional)
$approvalChannelWebhookUrl = "YOUR_APPROVAL_WEBHOOK_URL_HERE"
```

#### **Method 2: Modify Source and Rebuild (Advanced)**
If you have the source code:
1. Edit `PIM-Global-Teams-v2.ps1` in the project root
2. Update the webhook URLs
3. Rebuild the executable: `dotnet publish PIMGlobalMSTLauncher.csproj -c Release`

### Step 3: Test Teams Integration
1. **Run the executable**
2. **Activate a test role**
3. **Check your Teams channels** for notification cards
4. **Verify the cards display** correctly with role details

### Webhook URL Security
- ⚠️ **Keep webhook URLs secure** - they allow posting to your Teams channels
- 🔒 **Regenerate webhooks** if they're compromised
- 📝 **Document which channels** use which webhooks

---

## Power Automate Workflow Configuration

### Overview
Power Automate integration enables automated approval workflows and enhanced notifications for PIM role requests.

> **⚡ Important**: Power Automate workflows require a **Power Automate Premium** license or **Power Platform** subscription to function properly.

### Step 1: Create Power Automate Flow

#### **Flow Type: Instant Cloud Flow**
1. **Go to** [Power Automate](https://powerautomate.microsoft.com)
2. **Click "Create"** → **"Instant cloud flow"**
3. **Flow name**: `PIM Approval Workflow`
4. **Trigger**: **"When an HTTP request is received"**

#### **Step 2: Configure HTTP Trigger**
1. **Click "When an HTTP request is received"**
2. **Request Body JSON Schema**:
```json
{
    "type": "object",
    "properties": {
        "trackingId": {"type": "string"},
        "userEmail": {"type": "string"},
        "userDisplayName": {"type": "string"},
        "roleName": {"type": "string"},
        "roleNamesFormatted": {"type": "string"},
        "duration": {"type": "string"},
        "justification": {"type": "string"},
        "activationId": {"type": "string"},
        "expiryTime": {"type": "string"},
        "isBatch": {"type": "boolean"}
    }
}
```

#### **Step 3: Add Approval Actions**

**Option A: Simple Email Approval**
1. **Add action**: **"Start and wait for an approval"**
2. **Approval type**: **"Approve/Reject - First to respond"**
3. **Title**: `PIM Role Activation Request`
4. **Assigned to**: Your PIM approvers' emails
5. **Details**: 
   ```
   User: @{triggerBody()?['userDisplayName']} (@{triggerBody()?['userEmail']})
   Role: @{triggerBody()?['roleName']}
   Duration: @{triggerBody()?['duration']}
   Justification: @{triggerBody()?['justification']}
   Tracking ID: @{triggerBody()?['trackingId']}
   ```

**Option B: Teams Approval (Recommended)**
1. **Add action**: **"Post an Adaptive Card to a Teams channel and wait for a response"**
2. **Team**: Select your team
3. **Channel**: Select your approval channel
4. **Adaptive Card**:
```json
{
    "type": "AdaptiveCard",
    "version": "1.0",
    "body": [
        {
            "type": "TextBlock",
            "text": "🔐 PIM Role Activation Request",
            "weight": "Bolder",
            "size": "Medium"
        },
        {
            "type": "FactSet",
            "facts": [
                {"title": "User:", "value": "@{triggerBody()?['userDisplayName']}"},
                {"title": "Email:", "value": "@{triggerBody()?['userEmail']}"},
                {"title": "Role:", "value": "@{triggerBody()?['roleName']}"},
                {"title": "Duration:", "value": "@{triggerBody()?['duration']}"},
                {"title": "Justification:", "value": "@{triggerBody()?['justification']}"}
            ]
        }
    ],
    "actions": [
        {
            "type": "Action.Submit",
            "title": "✅ Approve",
            "data": {"action": "approve"}
        },
        {
            "type": "Action.Submit",
            "title": "❌ Deny",
            "data": {"action": "deny"}
        }
    ]
}
```

#### **Step 4: Handle Approval Response**
1. **Add condition**: **"Condition"**
2. **Left side**: `outputs('Post_an_Adaptive_Card_to_a_Teams_channel_and_wait_for_a_response')?['data']?['action']`
3. **Condition**: **"is equal to"**
4. **Right side**: `approve`

**If Approved:**
- Add action: **"Send an email (V2)"** to notify the user
- Add action: **"HTTP"** to call Azure PIM API for actual approval (advanced)

**If Denied:**
- Add action: **"Send an email (V2)"** to notify the user of denial

### Step 2: Configure Power Automate URL in Script

#### **Get the HTTP Trigger URL**
1. **Save your flow**
2. **Click on "When an HTTP request is received"**
3. **Copy the HTTP POST URL**

#### **Update the Script**
Edit `PIM-Global-Teams-v2.ps1` (line 77):
```powershell
$powerAutomateApprovalUrl = "YOUR_POWER_AUTOMATE_HTTP_TRIGGER_URL_HERE"
```

### Step 3: Test Power Automate Integration
1. **Run the executable**
2. **Activate a role that requires approval**
3. **Check that the approval request** appears in Teams/Email
4. **Test the approval/denial process**

---

## Advanced Configuration Options

### Configuration Variables (Lines 68-86)

```powershell
# ========================= Teams Webhook Configuration =========================
# Main notifications webhook URL
$teamsWebhookUrl = "YOUR_WEBHOOK_URL"

# Approval channel webhook URL (for approval-required roles)
$approvalChannelWebhookUrl = "YOUR_APPROVAL_WEBHOOK_URL"

# Power Automate URL for interactive approvals
$powerAutomateApprovalUrl = "YOUR_POWER_AUTOMATE_URL"

# Enable/disable Teams notifications
$enableTeamsNotifications = $true

# Enable/disable batching multiple role requests into single approval
$enableBatchApprovals = $false

# Azure PIM Portal URL for approvals
$pimApprovalUrl = "https://portal.azure.com/?Microsoft_Azure_PIMCommon=true#view/Microsoft_Azure_PIMCommon/ApproveRequestMenuBlade/~/aadmigratedroles"
```

### Customization Options

#### **Disable Teams Completely**
```powershell
$enableTeamsNotifications = $false
```

#### **Enable Batch Approvals**
```powershell
$enableBatchApprovals = $true
```
- Groups multiple role requests into single approval
- Reduces approval fatigue for bulk activations

#### **Custom PIM Portal URL**
Update `$pimApprovalUrl` if you use a different Azure portal URL or custom domain.

### Authentication Configuration (Lines 553-565)

```powershell
# Azure AD Application Configuration
$clientId = "bf34fc64-bbbc-45cb-9124-471341025093"  # Microsoft Graph PowerShell
$tenantId = "common"  # Works for all tenants
$claimsJson = '{"access_token":{"acrs":{"essential":true,"value":"c1"}}}'  # MFA enforcement

# Required Microsoft Graph Permissions
$scopesDelegated = @(
    "User.Read",
    "GroupMember.Read.All", 
    "RoleManagement.Read.Directory",
    "RoleManagement.ReadWrite.Directory",
    "Directory.Read.All"
)
```

---

## Troubleshooting

### Common Issues

#### **"Teams workflow not configured" Messages**
- **Cause**: Teams webhooks not configured or invalid
- **Solution**: Follow the Teams setup section above
- **Quick fix**: Set `$enableTeamsNotifications = $false` to disable

#### **"Power Automate workflow not configured" Messages**
- **Cause**: Power Automate URL not configured
- **Solution**: Follow the Power Automate setup section above
- **Quick fix**: These are warnings only - PIM functionality still works

#### **PowerShell Module Installation Fails**
- **Cause**: Network restrictions or permissions
- **Solution**: 
  ```powershell
  Install-Module MSAL.PS -Scope CurrentUser -Force
  Install-Module Microsoft.Graph -Scope CurrentUser -Force
  ```

#### **Authentication Failures**
- **Cause**: MFA not configured or conditional access policies
- **Solution**: Ensure your account has MFA enabled and meets all CA requirements

#### **No Eligible Roles Found**
- **Cause**: No PIM role assignments or roles already active
- **Solution**: Check Azure Portal → PIM → My Roles for eligible assignments

### Webhook Testing

#### **Test Webhook Manually**
```powershell
$webhookUrl = "YOUR_WEBHOOK_URL"
$testMessage = @{
    text = "Test message from PIM-Global-MST"
}
$json = $testMessage | ConvertTo-Json
Invoke-RestMethod -Uri $webhookUrl -Method Post -Body $json -ContentType 'application/json'
```

### Log Files and Debugging

#### **Enable Verbose Logging**
Add to the beginning of the script:
```powershell
$VerbosePreference = "Continue"
```

#### **Common Log Locations**
- PowerShell errors: Check the console output
- Teams webhook errors: Look for HTTP response codes
- Authentication issues: Browser developer tools

### Getting Help

#### **Support Channels**
- 🐛 **Bug Reports**: [GitHub Issues](https://github.com/markorr321/PIM-Global-Self-Activate/issues)
- 💬 **Questions**: [GitHub Discussions](https://github.com/markorr321/PIM-Global-Self-Activate/discussions)
- 📧 **Development**: morr@orr365.tech
- 💖 **Sponsorship**: [GitHub Sponsors](https://github.com/sponsors/markorr321)

#### **Information to Include in Support Requests**
- Operating system version
- PowerShell version (`$PSVersionTable`)
- Error messages (exact text)
- Steps to reproduce the issue
- Whether Teams integration is configured

---

## Security Best Practices

### Webhook Security
- 🔒 **Rotate webhook URLs** regularly
- 🚫 **Don't share webhook URLs** in public channels
- 📝 **Document webhook ownership** and purpose

### Script Security
- ✅ **Review script contents** before running
- 🔍 **Verify digital signatures** when available
- 🚫 **Don't run from untrusted sources**

### Permissions
- ⚡ **Use least-privilege** principle for PIM roles
- 🕐 **Use shortest duration** necessary for tasks
- 📋 **Provide clear justifications** for role activations

---

*This configuration guide covers PIM-Global-MST Version 3.0.0. For the latest updates, visit the [GitHub repository](https://github.com/markorr321/PIM-Global-Self-Activate).*
