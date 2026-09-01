# Codex Advisor Privacy Policy (Draft)

> **Notice:** This document is a pre-release draft. All publisher-specific entries marked `OWNER-PROVIDED` must be populated by the repository owner prior to formal directory submission.

**Effective Date:** OWNER-PROVIDED effective date  
**Publisher / Controller:** OWNER-PROVIDED legal entity name  
**Contact Email:** OWNER-PROVIDED privacy contact email  
**Physical Address:** OWNER-PROVIDED physical mailing address  
**Website:** OWNER-PROVIDED website URL  

---

## 1. Overview and Core Privacy Principles

Codex Advisor is an open-source, skills-only plugin designed for local use within Codex CLI and Codex desktop.

- **Local Execution:** Codex Advisor operates entirely on your local machine with no hosted service and no remote backend infrastructure.
- **No Third-Party Transmission:** No user prompts, code snippets, project context, or consultation packets are transmitted to the maintainers, Zero Delta LLC, or any third-party infrastructure.
- **No External Telemetry or Analytics:** The plugin includes no telemetry, no analytics tracking, no crash reporting, and no MCP server.
- **Zero-Tool Sandboxing:** Advisor child processes execute in a forced read-only sandbox with zero tools enabled, preventing outbound network connections or unsolicited local file modifications.

## 2. Information Handled by the Plugin

### Local Consultation Context
When the root agent invokes a consultation, it compiles a bounded five-section packet containing:
- The technical decision question.
- Relevant code context, architectural options, and repository boundaries provided by the root agent.
- No credentials, secrets, personal data, or irrelevant conversation history.

This packet is processed locally by your authenticated Codex runtime through your existing OpenAI subscription. Communication with OpenAI's API is governed by your own OpenAI account agreement and OpenAI's Privacy Policy; Codex Advisor does not interpose any proxy, intermediate server, or hosted service.

### Local Session Data & Persisted Codex Session Logs
- Consultation activity, receipts (`ADVISOR CALL` and `ADVISOR RESULT`), and decisions are recorded locally within your persisted Codex session logs.
- Persisted Codex session logs remain on your local storage device under your user-configured Codex home directory (e.g., `~/.codex/sessions`).
- The plugin never uploads, copies, or shares persisted Codex session logs.

## 3. Local Audit and Diagnostic Script

The repository includes a local audit utility (`plugins/advisor/scripts/advisor-audit.sh`) for inspecting consultation metrics:
- The script operates strictly on local persisted Codex session logs.
- It calculates aggregate counts and statistics (such as consult/skip counts and token totals).
- The audit tool enforces strict data redaction: it never emits session content, user prompts, file paths, filenames, identifiers, contact information, secret-shaped patterns, or cost calculations.
- Audit output is displayed on local standard output and is not transmitted anywhere.

## 4. Authentication and Credentials

Codex Advisor relies exclusively on your existing local Codex host authentication:
- The plugin does not request, collect, store, transmit, or handle OpenAI API keys or login credentials.
- The plugin does not read or duplicate credential files from your local environment.

## 5. Third-Party Services and Surfaces

- **OpenAI Codex:** Consultation requests are executed via your local Codex installation communicating with OpenAI models (`gpt-5.6-terra` and `gpt-5.6-sol`). Data handling by OpenAI is governed by OpenAI's terms.
- **No MCP or Hosted Service:** Codex Advisor provides no MCP servers, no hosted services, and no background cloud services.

## 6. User Control and Data Deletion

Because all session data resides solely in local persisted Codex session logs on your own machine:
- You retain complete ownership and control over all consultation records.
- You may inspect, modify, archive, or delete your persisted Codex session logs at any time using standard local operating system tools.
- Removing or uninstalling the plugin removes the plugin files from your local environment without affecting your private repository data.

## 7. Changes to this Privacy Policy

Any updates to this policy will be published in the project repository with an updated effective date.

## 8. Contact Information

For inquiries regarding this Privacy Policy or the privacy practices of Codex Advisor, please contact:
- **Email:** OWNER-PROVIDED privacy contact email  
- **Postal Address:** OWNER-PROVIDED physical mailing address  
