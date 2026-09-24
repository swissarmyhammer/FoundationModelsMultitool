---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m3a8vdwpqgdjc6y2psy1hkd3
  text: |-
    Research:
    - The project has no `IPAddress` type. Network.framework has a protocol with that name, but the project does not import Network. This task adds a module type `IPAddress` (family and bytes) in `WebAddressGuard.swift`. It uses `inet_pton` and `inet_ntop` from Darwin. `Darwin` is already imported in `PathGuard.swift` and `FileWalker.swift`. The package is macOS only.
    - `CorrectiveFailure` is internal, in `Capabilities/Files/CorrectiveResult.swift`. `WebGuardRefusal` conforms to it.
    - Rules to obey: no force unwrap in Sources; swiftlint `no_magic_numbers` allows only 0, 1, -1 and 100. Thus the blocked ranges are CIDR strings in a table, and bit widths come from `UInt8.bitWidth` and `MemoryLayout`. Periphery counts test callers, so the default `SystemHostResolver` gets a test that uses a numeric host only (no DNS query, no network).
    - Case: the scheme and the host are compared in lower case. A trailing dot on the host is removed. The brackets on an IPv6 literal host are removed.
    - The default resolver runs the blocking `getaddrinfo` on a global dispatch queue. Thus it does not block a thread of the Swift concurrency pool.
  timestamp: 2026-09-24T17:54:12.502789+00:00
- actor: claude-code
  id: 01m3a95dqsry2bax9sygfhye24
  text: |-
    Implementation landed (TDD).
    - RED: the new suite did not compile (the types were missing). Then a skeleton API with empty bodies made 63 issues in 21 tests. GREEN: 21 tests in `WebAddressGuardTests` pass. `swift test`: 1573 tests in 126 suites pass.
    - Design: `IPAddress` keeps the family and the bytes in network order. `AddressBlock` parses a CIDR text and does one prefix match for IPv4 and IPv6. `BlockedAddresses.ranges` is the ordered table; `255.255.255.255/32` comes before `240/4`, thus broadcast has its own message. An IPv4-mapped address is checked through `::ffff:0.0.0.0/96` as IPv4.
    - The name checks (blocklist, suffix) come before the literal IP check. Thus `http://127.0.0.1/` gives "the host 127.0.0.1 is on the blocklist". A literal IP that is not on the list (`http://10.0.0.1/`) gives "10.0.0.1 is a private address" with no resolver call.
    - A resolver error or an empty answer gives the refusal "<host> does not resolve" (fail closed).
    - The user-info refusal names the host but does not show the user or the password.
    - What did not work: `parts.count == 2` in the CIDR parser gave a swiftlint `no_magic_numbers` finding. The parser now splits at the index of the slash.
    - Discovery: `swift build` shows `warning: missing creator for mutated node: ... mlx-swift_Cmlx.bundle`. That warning is from SwiftPM and the mlx dependency. It was there before this change.

    ### implement — changed
    - evidence: 2 files — Sources/FoundationModelsMultitool/Capabilities/Web/WebAddressGuard.swift, Tests/FoundationModelsMultitoolTests/WebAddressGuardTests.swift; `swift test --filter WebAddressGuardTests` 21 passed; `swift test` 1573 passed, 0 failed
    - next: /review
  timestamp: 2026-09-24T17:59:40.025824+00:00
- actor: claude-code
  id: 01m3a9vzzv344sfbycxmcv8q46
  text: |
    ### test — green

    - Command: `swift test`. Result: 1573 tests in 126 suites pass. 0 fail. 0 skip.
    - Command: `swift package clean` then `swift build`. Result: 0 errors. The only warning is from the mlx-swift dependency, not from this project's code. This warning was present before this task.
    - Command: `swiftlint lint` on the new files. First result: 15 findings in the two new files (`WebAddressGuard.swift`, `WebAddressGuardTests.swift`).
    - Actions taken to clear the findings:
      - Removed each trailing comma in a collection literal (the `trailing_comma` rule).
      - Moved one opening brace to the line of the function signature (the `opening_brace` rule).
      - Renamed the enum cases `v4` and `v6` to `ipv4` and `ipv6` (the `identifier_name` rule: a case name must have 3 to 40 characters).
      - Changed `String(decoding: utf8, as: UTF8.self)` to `String(bytes: utf8, encoding: .ascii) ?? ""` (the `optional_data_string_conversion` rule).
      - Split `WebAddressGuard.swift` into 4 files, each under the 400-line limit (the `file_length` rule):
        - `Sources/FoundationModelsMultitool/Capabilities/Web/IPAddress.swift` — the `IPAddress` type.
        - `Sources/FoundationModelsMultitool/Capabilities/Web/BlockedAddresses.swift` — the blocked ranges.
        - `Sources/FoundationModelsMultitool/Capabilities/Web/HostResolver.swift` — the resolver protocol and the default resolver.
        - `Sources/FoundationModelsMultitool/Capabilities/Web/WebAddressGuard.swift` — the guard itself (`WebGuardRefusal`, `WebAddressGuard`).
    - Command: `swiftlint lint` on all 5 files after the changes. Result: 0 findings.
    - Note, not a blocker: `swiftformat --lint` on the same 5 files shows findings. Its `trailingCommas` rule wants a trailing comma back on the same lines where swiftlint's `trailing_comma` rule wants it removed. This is a direct conflict between the two tools' default rules. The wider repo (295 of 335 files) does not pass a default `swiftformat --lint` run, and no `.swiftformat` file and no CI step select `swiftformat` for this project. This finding is pre-existing and outside the scope of the files this task changed, so it was not actioned here.
    - After the split, `swift test` still shows 1573 tests in 126 suites pass. The `WebAddressGuardTests` suite alone shows 21 tests pass.
    - No commit was made, as directed.
    - Files changed: `Sources/FoundationModelsMultitool/Capabilities/Web/WebAddressGuard.swift`, `Sources/FoundationModelsMultitool/Capabilities/Web/IPAddress.swift`, `Sources/FoundationModelsMultitool/Capabilities/Web/BlockedAddresses.swift`, `Sources/FoundationModelsMultitool/Capabilities/Web/HostResolver.swift`, `Tests/FoundationModelsMultitoolTests/WebAddressGuardTests.swift`.
    - Next: `/review`.
  timestamp: 2026-09-24T18:11:59.611903+00:00
position_column: doing
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
- [x] Each blocked host, suffix, IPv4 range, and IPv6 class is refused, with a message that names the host and the address.
- [x] A host that resolves to one public and one private address is refused.
- [x] `https://example.com` with a stub resolver that gives a public address is allowed.
- [x] No network is used in the tests (the resolver is a stub).

## Tests
- [x] Create `Tests/FoundationModelsMultitoolTests/WebAddressGuardTests.swift`: a parameterized test for each blocked host, suffix, range, and IPv6 class; user info; `ftp:` and `file:` schemes; the many-address case; IPv4-mapped IPv6.
- [x] Run `swift test --filter WebAddressGuardTests`. All pass.
- [x] Run `swift test`. All pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #web