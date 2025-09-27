# 🔐 PIM-Global-SelfActivate

Latest Release

> **Now available as a standalone `.exe`** in v4.0.0 – no PowerShell required, streamlined for self-activating organizations.

PIM-Global-SelfActivate is a lightweight, secure desktop utility designed to streamline Entra ID Privileged Identity Management (PIM) role activation and deactivation for organizations with self-activating PIM roles.

---

> 🚀 **Self-Activate Version Released!**  
> `PIM-Global-SelfActivate.ps1` now supports **phishing-resistant passwordless MFA**, **multi-role operations**, **active role detection**, and **streamlined workflows** for organizations with self-activating PIM roles.

## 🚀 Key Features

### **Advanced Authentication**
* 🔐 **Phishing-resistant passwordless MFA** with platform and portable passkeys
* 🔄 **Authentication Context handling** - seamless conditional access management
* 🌍 **Multi-tenant support** across global deployments
* 🛡️ **MSAL & Microsoft.Graph-based** secure authentication

### **Enhanced PIM Management**
* ✅ **Portable executable** — no script editing or PowerShell knowledge required
* 📋 **Dual-mode operation** — role activation and deactivation in one unified tool
* 🔍 **Active role detection** — automatically identifies currently active roles
* ⚡ **Multi-role operations** — activate or deactivate multiple roles simultaneously
* 🔄 **Interactive session mode** — multiple operations without re-authentication
* 🎨 **Color-coded output** — enhanced visual feedback and error handling
* 🛑 **Smart deactivation workflow** — safely deactivate roles with justification tracking

### **Streamlined Workflow**
* 🚀 **Self-activating focus** - optimized for organizations with immediate activation
* ⚡ **No approval delays** - instant role activation for eligible users
* 🎯 **Clean interface** - no complex workflow configurations needed
* 🔄 **Session continuity** - multiple operations without re-authentication

---

## 🔐 Permissions

When you run the tool for the first time, Microsoft will prompt you to sign in and approve access to Microsoft Graph permissions:

| Permission | Why It's Needed |
|------------|----------------|
| User.Read | To identify you and sign in securely |
| GroupMember.Read.All | To read group-based PIM role eligibilities |
| RoleManagement.Read.Directory | To view which PIM roles you're eligible for |
| RoleManagement.ReadWrite.Directory | To activate/deactivate eligible roles on your behalf |
| Directory.Read.All | To read directory information for role operations |

📌 These permissions are **delegated** meaning they only apply while you're signed in interactively using MFA.

👉 If you're the first person in your tenant to use the tool, Microsoft Entra may ask your admin to approve the requested permissions. This is a one-time step built into the Microsoft sign-in experience – no separate setup or consent URL is needed.

---

## ✅ Requirements

### **Mandatory**
* Windows 10/11 (x64)
* PowerShell 7+ (automatically detected)
* Entra ID Premium P2 license (for PIM functionality)
* Eligible PIM roles in your tenant

### **Optional**
* None - this version is designed for self-activating organizations with minimal configuration

### **Auto-installed Dependencies**
The tool automatically installs required PowerShell modules:
* `Microsoft.Graph` - Graph API PowerShell SDK
* `MSAL.PS` - Microsoft Authentication Library

---

## 🧑‍💻 Usage

### **Option A** — Download Portable Executable (Recommended)

1. **Download** `PIM-Global-SA.exe` from [releases](https://github.com/markorr321/PIM-Global-Self-Activate/releases)
2. **Run** the executable - no installation required
3. **Follow** the authentication prompts
4. **Start using** - no additional configuration needed for self-activating roles

### **Option B** — Run PowerShell Script Directly

**Clone and run locally (Recommended):**
```bash
git clone https://github.com/markorr321/PIM-Global-Self-Activate.git
cd PIM-Global-Self-Activate
.\PIM-Global-SelfActivate.ps1
```

**Quick Start Script:**
```powershell
# One-line installer and runner
irm https://github.com/markorr321/PIM-Global-Self-Activate/raw/main/install.ps1 | iex
```

---

## 🧠 Example Workflow

### 🟢 Launch the Tool
![Step 1 - Launch The Tool](/images/Activation%20Workflow/PIM-Global-SelfActivate%20-%20Step%201A%20-%20Launch-The-Tool.png)

### 👤 Account Selection
![Step 2 - Account Selection ](/images/Activation%20Workflow/PIM-Global-SelfActivate%20-%20Step%201%20-%20Account%20Selection.png)

### 🔑 Passkey Authentication
![Step 3 - Sign In with your passkey](/images/Activation%20Workflow/PIM-Global-SelfActivate%20-%20Step%202%20-%20Sign%20In%20with%20your%20passkey.png)

### 📷 QR Code Verification
![Step 4 - QR Code Scan](/images/Activation%20Workflow/PIM-Global-SelfActivate%20-%20Step%203%20-%20QR%20Code%20Scan.png)

### ✅ MFA Confirmation
![Step 5 - Device Connected! Continue on your device!](/images/Activation%20Workflow/PIM-Global-SelfActivate%20-%20Step%204%20-%20Device%20Connected!%20Continue%20on%20your%20device!.png)

### 🧭 Choose Action
![Step 6 - Choose Activation Menu](/images/Activation%20Workflow/PIM-Global-SelfActivate%20-%20Step%206%20-%20Choose%20Activation%20Menu.png)

### 🎭 Role Selection
![Step 7 - Role Selection Menu](/images/Activation%20Workflow/PIM-Global-SelfActivate%20-%20Step%207%20-%20Role%20Selection%20Menu.png)

### ⏳ Duration Selection
![Step 8 - Duration Entry](/images/Activation%20Workflow/PIM-Global-SelfActivate%20-%20Step%208%20-%20Duration%20Entry.png)

### 📝 Justification
![Step 9 - Reason for Activation](/images/Activation%20Workflow/PIM-Global-SelfActivate%20-%20Step%209%20-%20Reason%20for%20Activation.png)

### ⚡ Activating Role
![Step 10 - Role Activation Submission](/images/Activation%20Workflow/PIM-Global-SelfActivate%20-%20Step%2010%20-%20Role%20Activation%20Submission.png)

### 📭 No More Roles to Manage
![Step 11 - No More Role Management](/images/Activation%20Workflow/PIM-Global-SelfActivate%20-%20Step%2012%20-%20No%20More%20Role%20Management.png)

---

## 🛑 Deactivation Workflow

### **Intelligent Role Deactivation**
PIM-Global-MST automatically detects active roles and provides a streamlined deactivation process:

### **Key Features**
- **🔍 Active Role Detection** - Automatically scans and identifies currently active PIM roles
- **📋 Bulk Deactivation** - Deactivate multiple active roles simultaneously  
- **📝 Justification Tracking** - Required justification for all deactivation actions
- **📊 Audit Logging** - Complete justification and timestamp tracking
- **🔄 Session Continuity** - Deactivate roles without re-authentication in the same session
- **⚡ Smart Filtering** - Only shows roles that can be deactivated (excludes permanent assignments)



### 🧭 Workflow Selection
![Step 1 - Workflow Selection](/images/Deactivation%20Workflow/PIM-Global-SelfActivate%20-%20Step%202%20-%20Workflow%20Selection.png)

### 🛑 Role Selection (Deactivation)
![Step 2 - Role Selection (Deactivation)](/images/Deactivation%20Workflow/PIM-Global-SelfActivate%20-%20Step%201%20-%20Role%20Selection.png)

### ✔️ Role Deactivation Successful
![Step 3 - Role Deactivation Successful](/images/Deactivation%20Workflow/PIM-Global-SelfActivate%20-%20Step%203-%20Role%20Deactivaiton%20Sucessfull.png)

### 📭 No More Workflows Available
![Step 4 - No More Workflows Available](/images/Deactivation%20Workflow/PIM-Global-SelfActivate%20-%20Step%204%20-%20No%20More%20Workflows%20Available.png)


## 🔧 Configuration

### **Ready to Use**
This version is designed for self-activating organizations and works out-of-the-box:

✅ **No configuration required** - Just run and authenticate
✅ **No Teams setup needed** - Streamlined for direct PIM operations
✅ **No approval workflows** - Optimized for immediate activation roles

### **Optional Customization**
If you need to modify behavior, you can edit the PowerShell script:
- Adjust session timeouts
- Modify role display preferences
- Customize justification requirements

---

## 🔐 Security Features

This tool implements enterprise-grade security:

* **MSAL interactive login** with ACRS enforcement (`acrs=c1`)
* **Phishing-resistant MFA** support (passkeys, Windows Hello, FIDO2)
* **No passwords or secrets stored** - uses secure token-based authentication
* **Conditional Access compliance** - handles authentication contexts seamlessly
* **Temporary file cleanup** - no permanent files left on system
* **Delegated permissions only** - works within user's existing permissions

---

## 🛠️ Advanced Features

### **Multi-Role Operations**
- Activate or deactivate multiple roles in a single session
- Batch processing for efficient role management
- Smart role conflict detection

### **Interactive Session Mode**
- Perform multiple PIM operations without re-authentication
- Session state management across operations
- Automatic token refresh handling

### **Streamlined Operations**
- Direct PIM API integration for immediate results
- Clean console interface with color-coded feedback
- Session management for multiple operations
- Optimized for self-activating role environments

### **Error Handling & User Experience**
- Color-coded console output for better readability
- Comprehensive error messages with suggested solutions
- Streamlined interface with minimal configuration
- Real-time API synchronization with Azure PIM

---

## 📋 Troubleshooting

### Common Issues

**Authentication issues**
- Ensure you have the required permissions in your tenant
- Check that your account has eligible PIM roles assigned

**PowerShell 7+ not found**
- Download from [PowerShell releases](https://github.com/PowerShell/PowerShell/releases)
- The tool checks common installation paths automatically

**No eligible roles found**
- Verify you have PIM role assignments in Azure Portal → PIM → My Roles
- Check that roles aren't already active

📖 **[Full Troubleshooting Guide](CONFIGURATION.md#troubleshooting)**

---

## 📜 License

MIT License

---

## 🤝 Support & Contributing

### **Get Help**
* 🐛 **Bug Reports**: [GitHub Issues](https://github.com/markorr321/PIM-Global-Self-Activate/issues)
* 💬 **Questions**: [GitHub Discussions](https://github.com/markorr321/PIM-Global-Self-Activate/discussions)
* 📧 **Development Opportunities**: morr@orr365.tech
* 🐦 **Twitter**: [@MarkHunterOrr](https://twitter.com/MarkHunterOrr)

### **Sponsor Development**
* 💖 **GitHub Sponsors**: [Support this project](https://github.com/sponsors/markorr321)
* ⭐ **Star this repo** to show your support

---

## 🔗 Related Projects

* **[PIM-Global](https://github.com/markorr321/PIM-Global)** - Original PowerShell-only version
* **[PIM-Global-Self-Activate](https://github.com/markorr321/PIM-Global-Self-Activate)**

---

*Made with ☕ 3 cups of coffee and 🥤 6 diet cokes by [Mark Orr](https://github.com/markorr321)*  
*Dedicated to Courtney and Aubrey* 💜
