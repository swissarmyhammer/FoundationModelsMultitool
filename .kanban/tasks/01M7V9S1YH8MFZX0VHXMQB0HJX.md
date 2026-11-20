---
assignees:
- claude-code
position_column: todo
position_ordinal: '8180'
title: 'Endpoint: preferredFolder argument of importableSessions (D209)'
---
## Goal
A client can tell `importableSessions` which folder comes first, as `searchSessions` lets a client give the folder of its tab. Today only the agent path has a preferred folder (the folder of the caller session), so the app must read the folder of the tab first and then the other folders. Request from TestudoApp (testudoapp-9a).

## Change
- Add the optional argument `preferredFolder: String` to `Query.importableSessions` in `Capabilities/Sessions/SessionsGraphImport.swift`. It does not filter: the sessions of that folder come first, then the others. `~` expands. A path that is not absolute gives `INVALID_FOLDER`.
- Pass it as `ImportableSessionsRequest.preferredFolder`. For a call of the agent with no `preferredFolder`, the folder of the caller session stays the preferred folder. An explicit `preferredFolder` replaces it.
- Update the argument description, the doc comments at the top of the file and in `SessionsGraph.swift`, and add an alias (`preferred_folder`) in the alias table (D86).
- Re-record the golden SDL.

## Tests
- [ ] A client call with `preferredFolder` sends that folder to the fake importer as `preferredFolder`, and `folder` stays `nil`.
- [ ] A client call with no `preferredFolder` sends `nil`.
- [ ] An agent call with no `preferredFolder` sends the folder of the caller session; with one, it sends the argument.
- [ ] A relative `preferredFolder` gives `INVALID_FOLDER`.
- [ ] The golden SDL has the argument.