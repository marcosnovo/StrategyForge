# Coral — glosario es-ES (canonical UI vocabulary)

The Spanish UI strings live inline in `StrategyForge/Localization.swift` and the
`Localization+*.swift` feature tables (each entry is `(English, Spanish)`). To keep
the copy consistent — the backlog's "half-done is worse than not done" warning — new
strings must reuse these canonical terms rather than inventing synonyms.

## Two-noun taxonomy

The product has exactly two first-class nouns; don't blur them:

| Concept | English | Español | Notes |
|---|---|---|---|
| A conversation you run | **chat** | **chat** | Keep the loanword; don't translate to "conversación". |
| The group of agents behind a chat | **team** | **equipo** | Never "grupo". |
| One member of a team | **teammate** | **compañero** | Prefer over "agente" in team-management UI; "agente" stays for general/marketing copy ("equipo de agentes"). |
| The lead that delegates | **orchestrator** | **orquestador** | |

## Verb/noun glossary

| English | Español | Avoid |
|---|---|---|
| run (verb) | ejecutar | correr, lanzar |
| run (noun, a loop/chat execution) | ejecución | corrida |
| a single pass of a loop | pasada | |
| one interactive round | ronda | |
| merge (git) | fusionar / fusión | mergear, combinar, integrar |
| loop | bucle | |
| worktree | worktree | (keep the git term) |
| verifier | verificador | |
| turn (brake) | turno | |
| provider | proveedor | |

When in doubt, grep the Spanish side of `Localization*.swift` for an existing term
before coining a new one.
