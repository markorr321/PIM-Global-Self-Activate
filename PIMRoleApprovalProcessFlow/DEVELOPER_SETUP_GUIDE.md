# PIM Role Approval Process Flow - Developer Setup Guide

## Overview
This Power Automate flow provides an automated approval workflow for Privileged Identity Management (PIM) role activations in Microsoft Entra ID (Azure AD). When imported into your tenant, several configuration updates are required to make it functional.

## Prerequisites
- **Microsoft Entra ID P2 license** (required for PIM functionality)
- **Power Automate Premium license** (for HTTP with Entra ID connector)
- **Global Administrator or Privileged Role Administrator** permissions
- **Microsoft Teams** access for approval notifications
- **Service account** with appropriate PIM permissions (recommended)

## Required Configuration Updates

### 1. Microsoft Teams Integration
**What to update:** Teams Group and Channel IDs for approval notifications

**Current sanitized values:**
```json
"groupId": "00000000-0000-0000-0000-000000000003"
"channelId": "19:EXAMPLE-CHANNEL-ID@thread.tacv2"
```

**How to find your values:**
1. Navigate to your Teams channel for PIM approvals
2. Click the three dots (...) next to the channel name
3. Select "Get link to channel"
4. Extract the Group ID and Channel ID from the URL:
   ```
   https://teams.microsoft.com/l/channel/{CHANNEL_ID}/General?groupId={GROUP_ID}&tenantId={TENANT_ID}
   ```

**Where to update:**
- Search for `00000000-0000-0000-0000-000000000003` in the flow definition
- Search for `19:EXAMPLE-CHANNEL-ID@thread.tacv2` in the flow definition
- Replace with your actual Teams identifiers

### 2. Service Account Configuration
**What to update:** Authentication account for Microsoft Graph API calls

**Current sanitized value:**
```json
"displayName": "service-account@example.com"
```

**Recommended setup:**
1. Create a dedicated service account (e.g., `svc-pim-approvals@yourdomain.com`)
2. Assign the following Entra ID roles:
   - **Privileged Role Administrator** (for PIM operations)
   - **User Administrator** (for user lookups)
3. Configure the HTTP with Entra ID connection to use this account

**Where to update:**
- Update the connection reference in the flow
- Ensure proper authentication is configured

### 3. User Account References
**What to update:** Replace placeholder email with actual approver account

**Current sanitized value:**
```json
"displayName": "user@example.com"
```

**How to configure:**
1. Identify the primary PIM approver account
2. Update the Teams connection to use this account
3. Ensure this account has access to the designated Teams channel

### 4. Flow Trigger Configuration
**What to update:** Configure the HTTP trigger endpoint

**Current setup:**
- Manual trigger with JSON schema for PIM requests
- No authentication required (configure as needed)

**Integration options:**
1. **Azure Logic Apps** - Call from another automation
2. **Power Platform** - Trigger from Power Apps or other flows
3. **Custom Application** - HTTP POST from your PIM integration
4. **Azure Function** - Serverless integration

**Required payload schema:**
```json
{
  "trackingId": "string",
  "userEmail": "string", 
  "userDisplayName": "string",
  "roleName": "string",
  "roleNamesFormatted": "string",
  "roles": [
    {
      "roleName": "string",
      "activationId": "string", 
      "expiryTime": "string",
      "requiresApproval": "boolean"
    }
  ],
  "duration": "string",
  "justification": "string", 
  "activationId": "string",
  "expiryTime": "string",
  "isBatch": "boolean"
}
```

### 5. Microsoft Graph API Permissions
**Required API permissions for the service account:**

**Microsoft Graph:**
- `RoleManagement.ReadWrite.Directory` (Application)
- `User.Read.All` (Application) 
- `Directory.Read.All` (Application)

**How to configure:**
1. Go to Azure portal > App registrations
2. Find your Power Automate app registration
3. Add the required API permissions
4. Grant admin consent

### 6. PIM Configuration Alignment
**Ensure your PIM settings support the flow:**

1. **Approval Requirements:**
   - Enable approval for target roles in PIM
   - Configure appropriate approval timeouts
   - Set up approval policies

2. **Role Settings:**
   - Configure maximum activation duration
   - Set justification requirements
   - Enable/disable MFA requirements as needed

## Testing the Flow

### 1. Test Payload Example
```json
{
  "trackingId": "PIM-APPROVAL-TEST-001",
  "userEmail": "testuser@yourdomain.com",
  "userDisplayName": "Test User", 
  "roleName": "Global Administrator",
  "roleNamesFormatted": "• Global Administrator",
  "roles": [
    {
      "roleName": "Global Administrator",
      "activationId": "12345678-1234-1234-1234-123456789012",
      "expiryTime": "2024-01-01T12:00:00Z",
      "requiresApproval": true
    }
  ],
  "duration": "2 hours",
  "justification": "Emergency access required for system maintenance",
  "activationId": "12345678-1234-1234-1234-123456789012", 
  "expiryTime": "2024-01-01T12:00:00Z",
  "isBatch": false
}
```

### 2. Validation Steps
1. **Connection Test:** Verify all connections are working
2. **Teams Integration:** Confirm adaptive cards appear in the correct channel
3. **Approval Flow:** Test both approve and reject scenarios
4. **Graph API:** Verify PIM API calls succeed
5. **User Notifications:** Confirm users receive appropriate messages

## Troubleshooting

### Common Issues:
1. **Authentication Failures:** Check service account permissions and connection configuration
2. **Teams Card Not Appearing:** Verify Group ID and Channel ID are correct
3. **Graph API Errors:** Ensure proper API permissions and admin consent
4. **Approval Not Processing:** Check PIM role configuration and activation IDs

### Debugging Tips:
1. Enable flow run history and check for errors
2. Test individual actions in isolation
3. Verify JSON payload structure matches schema
4. Check Azure AD audit logs for PIM operations

## Security Considerations

1. **Principle of Least Privilege:** Only grant necessary permissions to service accounts
2. **Secure Connections:** Use managed identity where possible
3. **Audit Logging:** Enable comprehensive logging for compliance
4. **Access Reviews:** Regularly review who can trigger the flow
5. **Network Security:** Consider IP restrictions if applicable

## Support and Maintenance

- **Monitor Flow Runs:** Set up alerts for failed executions
- **Regular Updates:** Keep connections and permissions current
- **Documentation:** Maintain records of customizations made
- **Backup:** Export flow definitions before major changes

---

## Quick Setup Checklist

- [ ] Update Teams Group ID and Channel ID
- [ ] Configure service account with proper permissions
- [ ] Set up Microsoft Graph API permissions
- [ ] Test HTTP trigger endpoint
- [ ] Validate adaptive card display in Teams
- [ ] Test approval and rejection workflows
- [ ] Verify PIM integration works correctly
- [ ] Set up monitoring and alerts

For additional support, refer to Microsoft's Power Automate and PIM documentation or contact your organization's IT administrator.
