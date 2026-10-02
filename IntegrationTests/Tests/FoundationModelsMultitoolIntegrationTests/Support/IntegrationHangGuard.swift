// IntegrationHangGuard.swift
//
// The one `.timeLimit` value of the integration tests. Decided by the user on
// 2026-10-01 (card `^tm4x2hp`): no test checks the speed of the machine.

import Testing

/// The hang guard of each integration test.
enum IntegrationHangGuard {
    /// How many minutes an integration test can run before the guard stops it:
    /// thirty.
    ///
    /// The value is far above the slowest step seen on a busy machine: one
    /// model turn of 362 s, a model load of 359 s, and a full test of about
    /// 600 s.
    private static let minutes = 30

    /// The `.timeLimit` of each integration test.
    ///
    /// This is a hang guard, and not a speed check. It stops a test that
    /// cannot end. It must not fail a test that makes progress on a busy
    /// machine (card `^tm4x2hp`).
    static let timeLimit = TimeLimitTrait.Duration.minutes(minutes)
}
