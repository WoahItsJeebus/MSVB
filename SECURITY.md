# Security Policy

## Supported versions

Security fixes are applied to the latest released version of Vortex Launch Bridge.

| Version | Supported |
| --- | --- |
| Latest release | Yes |
| Older releases | No |

## Reporting a vulnerability

Do not include exploit details, local paths, launch arguments, profile data, or other sensitive information in a public issue.

Use GitHub's **Report a vulnerability** option on the repository's Security tab if private vulnerability reporting is available. If it is unavailable, open a minimal public issue asking the maintainer to establish a private contact channel; do not describe the vulnerability in that issue.

Please include:

- the affected plugin, Millennium, Vortex, Steam, and Windows versions;
- the smallest reproducible sequence;
- the expected and observed security impact;
- a sanitized proof of concept or log excerpt, if needed;
- any suggested mitigation.

The maintainer aims to acknowledge reports within seven days. Public disclosure should wait until a fix or mitigation is available.

## Scope

Reports are especially useful when they involve:

- validation bypasses across frontend/backend RPC boundaries;
- command-line or custom-executable handling;
- unsafe filesystem access;
- unintended Vortex state mutation;
- unredacted sensitive data;
- interception failures that can suppress or duplicate a Steam launch;
- unsafe behavior from the packaged process helper.

The project does not provide a bug bounty.
