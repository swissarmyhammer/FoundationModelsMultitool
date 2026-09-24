---
assignees:
- claude-code
position_column: todo
position_ordinal: '80'
title: 'Web: add WebAddressGuard (URL and resolved-address checks)'
---
## What
Add the URL guard of the web capability. Design: `web.md` § "What we copy" (the URL guard lists) and § "Fetch / The pipeline", step 2.

Create `Sources/FoundationModelsMultitool/Capabilities/Web/WebAddressGuard.swift`:
- `struct WebAddressGuard: Sendable` with `func check(_ url: URL) async -> WebGuardRefusal?` (`nil` means the URL is allowed).
- Refuse: a scheme that is not `http` or `https`; a URL with user info (`user:pass@`); the host blocklist (`localhost`, `127.0.0.1`, `::1`, `0.0.0.0`, `169.254.169.254`, `metadata.google.internal`, `metadata.azure.com`, `instance-data.ec2.internal`); the suffixes `.local`, `.localhost`, `.internal`.
- Resolve the host through an injected resolver (`protocol HostResolver: Sendable { func addresses(for host: String) async throws -> [IPAddress] }`). The default implementation calls `getaddrinfo`. Check EACH address, not only the first. Block IPv4 `0/8`, `10/8`, `100.64/10`, `127/8`, `169.254/16`, `172.16/12`, `192.168/16`, `198.18/15`, `224/4`, `240/4`, and broadcast. Block IPv6 loopback, multicast, unspecified, unique local `fc00::/7`, link local `fe80::/10`. Check an IPv4-mapped IPv6 address as IPv4.
- `WebGuardRefusal` carries `correctiveMessage` text in the files vocabulary, for example `The address is not allowed: localtest.me resolves to 127.0.0.1, a loopback address.` Conform it to `CorrectiveFailure` (`Capabilities/Files/CorrectiveResult.swift:26`).
- A literal IP host is checked without a resolver call.

## Acceptance Criteria
- [ ] Each blocked host, suffix, IPv4 range, and IPv6 class is refused, with a message that names the host and the address.
- [ ] A host that resolves to one public and one private address is refused.
- [ ] `https://example.com` with a stub resolver that gives a public address is allowed.
- [ ] No network is used in the tests (the resolver is a stub).

## Tests
- [ ] Create `Tests/FoundationModelsMultitoolTests/WebAddressGuardTests.swift`: a parameterized test for each blocked host, suffix, range, and IPv6 class; user info; `ftp:` and `file:` schemes; the many-address case; IPv4-mapped IPv6.
- [ ] Run `swift test --filter WebAddressGuardTests`. All pass.
- [ ] Run `swift test`. All pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #web