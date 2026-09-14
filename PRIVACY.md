# Privacy

nana is designed to run locally on your Mac.

## What nana reads

To display Codex quota information, nana starts the locally installed Codex
app-server and calls:

```text
account/rateLimits/read
```

Codex itself handles authentication using the account already signed in on
the user's computer.

To display the current model in the dropdown menu, nana may inspect local
Codex session/config metadata for fields such as the model name and reasoning
effort.

## What nana does not do

nana does not:

- ask for your OpenAI password
- ask for an API key
- directly collect authentication tokens
- upload quota information anywhere
- send analytics or telemetry
- run a project-owned server
- maintain a user database

## Network behavior

nana does not implement its own network client for a nana-operated service.

The Codex process it launches may communicate with OpenAI as part of normal
Codex operation. That communication is handled by Codex, not by nana.

## Data storage

The menu-bar edition does not need to store account-identifying information.

## Reporting concerns

If you discover a privacy or security issue, please open a GitHub issue
without including credentials, tokens, personal data, or private logs.
