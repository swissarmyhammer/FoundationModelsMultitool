// `XXH3` — the 64-bit XXH3 hash, with seed 0 and the default secret.
//
// `utils/hash.rs` in `../swissarmyhammer/crates/swissarmyhammer-sem/src/`
// calls `xxhash_rust::xxh3::xxh3_64` for each content hash and a streaming
// `Xxh3` for each structural hash. This file ports the scalar path of that
// function from the `xxhash-rust` crate, version 0.8.15 (`src/xxh3.rs` and
// `src/xxh3_common.rs`). The crate has no Swift package, and CryptoKit has no
// XXH3. Thus the port is here, step by step, with the same constants.
//
// The seed is always 0, because `hash.rs` never gives a seed. Thus each term
// of the Rust code that adds or subtracts the seed is not here: a term of 0
// does not change the value.
//
// The streaming `Xxh3` of `structural_hash` gives the same digest as
// `xxh3_64` of all the bytes that it got. Thus `SemanticHash` collects the
// bytes and calls ``hash64(_:)`` one time.
//
// Golden vectors from the Rust crate pin each length path
// (`GitGoldens/semantic-hash-golden.json`, read by `SemanticHashTests`).

/// The 64-bit XXH3 hash of `xxhash-rust` 0.8.15, with seed 0 and the default
/// secret.
enum XXH3 {

    // MARK: Constants of `xxh32_common.rs`, `xxh64_common.rs`, and `xxh3_common.rs`

    /// `xxh32::PRIME_1`.
    private static let prime32First: UInt64 = 0x9E37_79B1
    /// `xxh32::PRIME_2`.
    private static let prime32Second: UInt64 = 0x85EB_CA77
    /// `xxh32::PRIME_3`.
    private static let prime32Third: UInt64 = 0xC2B2_AE3D
    /// `xxh64::PRIME_1`.
    private static let prime64First: UInt64 = 0x9E37_79B1_85EB_CA87
    /// `xxh64::PRIME_2`.
    private static let prime64Second: UInt64 = 0xC2B2_AE3D_27D4_EB4F
    /// `xxh64::PRIME_3`.
    private static let prime64Third: UInt64 = 0x1656_67B1_9E37_79F9
    /// `xxh64::PRIME_4`.
    private static let prime64Fourth: UInt64 = 0x85EB_CA77_C2B2_AE63
    /// `xxh64::PRIME_5`.
    private static let prime64Fifth: UInt64 = 0x27D4_EB2F_1656_67C5
    /// The multiplier of `avalanche` in `xxh3_common.rs`.
    private static let avalancheMultiplier: UInt64 = 0x1656_6791_9E37_79F9
    /// The multiplier of `strong_avalanche` in `xxh3_common.rs`.
    private static let strongAvalancheMultiplier: UInt64 = 0x9FB2_1C65_1E98_DF25

    /// `DEFAULT_SECRET` of `xxh3_common.rs`: 192 bytes.
    // Each byte is one row of the XXH3 secret table, copied from the Rust
    // crate. A byte of the table has no name of its own.
    // swiftlint:disable no_magic_numbers
    private static let defaultSecret: [UInt8] = [
        0xb8, 0xfe, 0x6c, 0x39, 0x23, 0xa4, 0x4b, 0xbe, 0x7c, 0x01, 0x81, 0x2c, 0xf7, 0x21, 0xad, 0x1c,
        0xde, 0xd4, 0x6d, 0xe9, 0x83, 0x90, 0x97, 0xdb, 0x72, 0x40, 0xa4, 0xa4, 0xb7, 0xb3, 0x67, 0x1f,
        0xcb, 0x79, 0xe6, 0x4e, 0xcc, 0xc0, 0xe5, 0x78, 0x82, 0x5a, 0xd0, 0x7d, 0xcc, 0xff, 0x72, 0x21,
        0xb8, 0x08, 0x46, 0x74, 0xf7, 0x43, 0x24, 0x8e, 0xe0, 0x35, 0x90, 0xe6, 0x81, 0x3a, 0x26, 0x4c,
        0x3c, 0x28, 0x52, 0xbb, 0x91, 0xc3, 0x00, 0xcb, 0x88, 0xd0, 0x65, 0x8b, 0x1b, 0x53, 0x2e, 0xa3,
        0x71, 0x64, 0x48, 0x97, 0xa2, 0x0d, 0xf9, 0x4e, 0x38, 0x19, 0xef, 0x46, 0xa9, 0xde, 0xac, 0xd8,
        0xa8, 0xfa, 0x76, 0x3f, 0xe3, 0x9c, 0x34, 0x3f, 0xf9, 0xdc, 0xbb, 0xc7, 0xc7, 0x0b, 0x4f, 0x1d,
        0x8a, 0x51, 0xe0, 0x4b, 0xcd, 0xb4, 0x59, 0x31, 0xc8, 0x9f, 0x7e, 0xc9, 0xd9, 0x78, 0x73, 0x64,
        0xea, 0xc5, 0xac, 0x83, 0x34, 0xd3, 0xeb, 0xc3, 0xc5, 0x81, 0xa0, 0xff, 0xfa, 0x13, 0x63, 0xeb,
        0x17, 0x0d, 0xdd, 0x51, 0xb7, 0xf0, 0xda, 0x49, 0xd3, 0x16, 0x55, 0x26, 0x29, 0xd4, 0x68, 0x9e,
        0x2b, 0x16, 0xbe, 0x58, 0x7d, 0x47, 0xa1, 0xfc, 0x8f, 0xf8, 0xb8, 0xd1, 0x7a, 0xd0, 0x31, 0xce,
        0x45, 0xcb, 0x3a, 0x8f, 0x95, 0x16, 0x04, 0x28, 0xaf, 0xd7, 0xfb, 0xca, 0xbb, 0x4b, 0x40, 0x7e,
    ]
    // swiftlint:enable no_magic_numbers

    /// `INITIAL_ACC` of `xxh3.rs`: the eight accumulators of the long path.
    private static let initialAccumulators: [UInt64] = [
        prime32Third, prime64First, prime64Second, prime64Third,
        prime64Fourth, prime32Second, prime64Fifth, prime32First,
    ]

    /// The length in bytes of one 64-bit word.
    private static let wordLength = MemoryLayout<UInt64>.size
    /// The length in bytes of one 32-bit word.
    private static let halfWordLength = MemoryLayout<UInt32>.size
    /// The length in bytes of the block that `mix16_b` reads.
    private static let mixBlockLength = 16
    /// `STRIPE_LEN`: the length in bytes of one stripe of the long path.
    private static let stripeLength = 64
    /// `SECRET_CONSUME_RATE`: the secret step from one stripe to the next.
    private static let secretConsumeRate = 8
    /// `SECRET_MERGEACCS_START`: the secret offset of the last merge.
    private static let secretMergeAccumulatorsStart = 11
    /// `SECRET_LASTACC_START`: the secret offset back from the end for the
    /// last stripe.
    private static let secretLastAccumulatorStart = 7
    /// `MID_SIZE_MAX`: the longest input of the 129-to-240 path.
    private static let midSizeMax = 240
    /// `SECRET_SIZE_MIN`: the smallest secret that XXH3 accepts.
    private static let secretSizeMin = 136
    /// `START_OFFSET` of `xxh3_64_129to240`.
    private static let midSizeStartOffset = 3
    /// `LAST_OFFSET` of `xxh3_64_129to240`.
    private static let midSizeLastOffset = 17
    /// The number of `mix16_b` rounds before the first avalanche of
    /// `xxh3_64_129to240`.
    private static let midSizeFirstRounds = 8
    /// The longest input of the 1-to-3 path.
    private static let tinyInputMax = 3
    /// The longest input of the 4-to-8 path.
    private static let smallInputMax = 8
    /// The longest input of the 0-to-16 paths.
    private static let shortInputMax = 16
    /// The longest input of the 17-to-128 path.
    private static let mediumInputMax = 128
    /// The input length that each step of the 17-to-128 path adds: two
    /// blocks of `mix16_b`, one from the start and one from the end.
    private static let mediumStepLength = 32
    /// The secret offset of the empty-input path (`xxh3_64_0to16`).
    private static let emptyInputSecretOffset = 56
    /// The secret offset of the 4-to-8 path.
    private static let smallInputSecretOffset = 8
    /// The secret offset of the 9-to-16 path.
    private static let shortInputSecretOffset = 24
    /// The first left rotation of `strong_avalanche`.
    private static let strongAvalancheFirstRotation = 49
    /// The second left rotation of `strong_avalanche`.
    private static let strongAvalancheSecondRotation = 24
    /// The number of accumulators that one `mix_two_accs` of `merge_accs`
    /// reads.
    private static let accumulatorsPerMix = 2

    // MARK: Hash

    /// The XXH3-64 hash of `bytes`, the same value as `xxh3_64` of
    /// `xxhash-rust` (`src/xxh3.rs`, `xxh3_64`).
    ///
    /// - Parameter bytes: The input.
    /// - Returns: The 64-bit hash.
    static func hash64(_ bytes: [UInt8]) -> UInt64 {
        bytes.withUnsafeBytes { input in
            defaultSecret.withUnsafeBytes { secret in
                hash64(input, secret: secret)
            }
        }
    }

    /// `xxh3_64_internal`: selects the path for the length of `input`.
    private static func hash64(_ input: UnsafeRawBufferPointer, secret: UnsafeRawBufferPointer) -> UInt64 {
        switch input.count {
        case 0: emptyInput(secret: secret)
        case ...tinyInputMax: tinyInput(input, secret: secret)
        case ...smallInputMax: smallInput(input, secret: secret)
        case ...shortInputMax: shortInput(input, secret: secret)
        case ...mediumInputMax: mediumInput(input, secret: secret)
        case ...midSizeMax: midSizeInput(input, secret: secret)
        default: longInput(input, secret: secret)
        }
    }

    // MARK: Short paths

    /// The empty input: the last branch of `xxh3_64_0to16`.
    private static func emptyInput(secret: UnsafeRawBufferPointer) -> UInt64 {
        xxh64Avalanche(
            readLE64(secret, emptyInputSecretOffset) ^ readLE64(secret, emptyInputSecretOffset + wordLength))
    }

    /// `xxh3_64_1to3`.
    private static func tinyInput(_ input: UnsafeRawBufferPointer, secret: UnsafeRawBufferPointer) -> UInt64 {
        let length = input.count
        let first = UInt32(input[0])
        let middle = UInt32(input[length >> 1])
        let last = UInt32(input[length - 1])
        let combined = (first << 16) | (middle << 24) | last | (UInt32(length) << 8)
        let flip = UInt64(readLE32(secret, 0) ^ readLE32(secret, halfWordLength))
        return xxh64Avalanche(UInt64(combined) ^ flip)
    }

    /// `xxh3_64_4to8`.
    private static func smallInput(_ input: UnsafeRawBufferPointer, secret: UnsafeRawBufferPointer) -> UInt64 {
        let length = input.count
        let head = UInt64(readLE32(input, 0))
        let tail = UInt64(readLE32(input, length - halfWordLength))
        let flip =
            readLE64(secret, smallInputSecretOffset) ^ readLE64(secret, smallInputSecretOffset + wordLength)
        let combined = tail &+ (head << 32)
        return strongAvalanche(combined ^ flip, length: UInt64(length))
    }

    /// `xxh3_64_9to16`.
    private static func shortInput(_ input: UnsafeRawBufferPointer, secret: UnsafeRawBufferPointer) -> UInt64 {
        let length = input.count
        let highOffset = shortInputSecretOffset + mixBlockLength
        let flipLow = readLE64(secret, shortInputSecretOffset) ^ readLE64(secret, shortInputSecretOffset + wordLength)
        let flipHigh = readLE64(secret, highOffset) ^ readLE64(secret, highOffset + wordLength)
        let low = readLE64(input, 0) ^ flipLow
        let high = readLE64(input, length - wordLength) ^ flipHigh
        let accumulator = UInt64(length) &+ low.byteSwapped &+ high &+ multiplyFold(low, high)
        return avalanche(accumulator)
    }

    // MARK: Medium paths

    /// `xxh3_64_7to128` (the 17-to-128 path). The Rust code nests three
    /// `if` blocks. Each step `step` of this loop is one of those blocks: it
    /// mixes the 16-byte block `step` from the start with the 16-byte secret
    /// block `2 * step`, and the block `step` from the end with the secret
    /// block `2 * step + 1`. The sum is the same, because the order of a
    /// wrapping add does not change its value.
    private static func mediumInput(_ input: UnsafeRawBufferPointer, secret: UnsafeRawBufferPointer) -> UInt64 {
        let length = input.count
        var accumulator = UInt64(length) &* prime64First
        for step in 0...((length - 1) / mediumStepLength) {
            let secretOffset = step * mediumStepLength
            accumulator &+= mix16B(input, at: step * mixBlockLength, secret: secret, at: secretOffset)
            accumulator &+= mix16B(
                input, at: length - (step + 1) * mixBlockLength, secret: secret, at: secretOffset + mixBlockLength)
        }
        return avalanche(accumulator)
    }

    /// `xxh3_64_129to240`.
    private static func midSizeInput(_ input: UnsafeRawBufferPointer, secret: UnsafeRawBufferPointer) -> UInt64 {
        let length = input.count
        let rounds = length / mixBlockLength
        var accumulator = UInt64(length) &* prime64First
        for round in 0..<midSizeFirstRounds {
            accumulator &+= mix16B(input, at: mixBlockLength * round, secret: secret, at: mixBlockLength * round)
        }
        accumulator = avalanche(accumulator)
        for round in midSizeFirstRounds..<rounds {
            let secretOffset = mixBlockLength * (round - midSizeFirstRounds) + midSizeStartOffset
            accumulator &+= mix16B(input, at: mixBlockLength * round, secret: secret, at: secretOffset)
        }
        accumulator &+= mix16B(
            input, at: length - mixBlockLength, secret: secret, at: secretSizeMin - midSizeLastOffset)
        return avalanche(accumulator)
    }

    /// `mix16_b` with seed 0.
    private static func mix16B(
        _ input: UnsafeRawBufferPointer, at inputOffset: Int, secret: UnsafeRawBufferPointer, at secretOffset: Int
    ) -> UInt64 {
        let low = readLE64(input, inputOffset) ^ readLE64(secret, secretOffset)
        let high = readLE64(input, inputOffset + wordLength) ^ readLE64(secret, secretOffset + wordLength)
        return multiplyFold(low, high)
    }

    // MARK: Long path

    /// `xxh3_64_long_impl` with `hash_long_internal_loop`.
    private static func longInput(_ input: UnsafeRawBufferPointer, secret: UnsafeRawBufferPointer) -> UInt64 {
        let length = input.count
        let stripesPerBlock = (secret.count - stripeLength) / secretConsumeRate
        let blockLength = stripeLength * stripesPerBlock
        let blocks = (length - 1) / blockLength
        var accumulators = initialAccumulators
        for block in 0..<blocks {
            accumulateStripes(&accumulators, input, at: block * blockLength, secret: secret, count: stripesPerBlock)
            scramble(&accumulators, secret: secret, at: secret.count - stripeLength)
        }
        let lastStripes = ((length - 1) - blockLength * blocks) / stripeLength
        accumulateStripes(&accumulators, input, at: blocks * blockLength, secret: secret, count: lastStripes)
        accumulate512(
            &accumulators, input, at: length - stripeLength,
            secret: secret, at: secret.count - stripeLength - secretLastAccumulatorStart)
        return mergeAccumulators(
            accumulators, secret: secret, at: secretMergeAccumulatorsStart, start: UInt64(length) &* prime64First)
    }

    /// `accumulate_loop`: accumulates `count` stripes from `inputOffset`.
    private static func accumulateStripes(
        _ accumulators: inout [UInt64], _ input: UnsafeRawBufferPointer, at inputOffset: Int,
        secret: UnsafeRawBufferPointer, count: Int
    ) {
        for stripe in 0..<count {
            accumulate512(
                &accumulators, input, at: inputOffset + stripe * stripeLength,
                secret: secret, at: stripe * secretConsumeRate)
        }
    }

    /// `accumulate_512_scalar`: accumulates one stripe.
    private static func accumulate512(
        _ accumulators: inout [UInt64], _ input: UnsafeRawBufferPointer, at inputOffset: Int,
        secret: UnsafeRawBufferPointer, at secretOffset: Int
    ) {
        for lane in accumulators.indices {
            let value = readLE64(input, inputOffset + lane * wordLength)
            let key = value ^ readLE64(secret, secretOffset + lane * wordLength)
            accumulators[lane ^ 1] &+= value
            accumulators[lane] &+= UInt64(UInt32(truncatingIfNeeded: key)) &* (key >> 32)
        }
    }

    /// `scramble_acc_scalar`.
    private static func scramble(
        _ accumulators: inout [UInt64], secret: UnsafeRawBufferPointer, at secretOffset: Int
    ) {
        for lane in accumulators.indices {
            let key = readLE64(secret, secretOffset + lane * wordLength)
            let value = accumulators[lane] ^ (accumulators[lane] >> 47)
            accumulators[lane] = (value ^ key) &* prime32First
        }
    }

    /// `merge_accs` with `mix_two_accs`.
    private static func mergeAccumulators(
        _ accumulators: [UInt64], secret: UnsafeRawBufferPointer, at secretOffset: Int, start: UInt64
    ) -> UInt64 {
        var result = start
        for pair in stride(from: 0, to: accumulators.count, by: accumulatorsPerMix) {
            let pairOffset = secretOffset + pair * wordLength
            result &+= multiplyFold(
                accumulators[pair] ^ readLE64(secret, pairOffset),
                accumulators[pair + 1] ^ readLE64(secret, pairOffset + wordLength))
        }
        return avalanche(result)
    }

    // MARK: Mixers

    /// `avalanche` of `xxh3_common.rs`.
    private static func avalanche(_ value: UInt64) -> UInt64 {
        let shifted = (value ^ (value >> 37)) &* avalancheMultiplier
        return shifted ^ (shifted >> 32)
    }

    /// `strong_avalanche` of `xxh3_common.rs`.
    private static func strongAvalanche(_ value: UInt64, length: UInt64) -> UInt64 {
        var mixed =
            value ^ rotateLeft(value, by: strongAvalancheFirstRotation)
            ^ rotateLeft(value, by: strongAvalancheSecondRotation)
        mixed = mixed &* strongAvalancheMultiplier
        mixed ^= (mixed >> 35) &+ length
        mixed = mixed &* strongAvalancheMultiplier
        return mixed ^ (mixed >> 28)
    }

    /// `avalanche` of `xxh64_common.rs`.
    private static func xxh64Avalanche(_ value: UInt64) -> UInt64 {
        var mixed = value ^ (value >> 33)
        mixed = mixed &* prime64Second
        mixed ^= (mixed >> 29)
        mixed = mixed &* prime64Third
        return mixed ^ (mixed >> 32)
    }

    /// `mul128_fold64`: the 128-bit product of the two values, with its low
    /// and high halves combined by XOR.
    private static func multiplyFold(_ left: UInt64, _ right: UInt64) -> UInt64 {
        let product = left.multipliedFullWidth(by: right)
        return product.low ^ product.high
    }

    /// `u64::rotate_left`.
    private static func rotateLeft(_ value: UInt64, by count: Int) -> UInt64 {
        (value << count) | (value >> (UInt64.bitWidth - count))
    }

    // MARK: Reads

    /// The little-endian 64-bit word at `offset`.
    private static func readLE64(_ bytes: UnsafeRawBufferPointer, _ offset: Int) -> UInt64 {
        UInt64(littleEndian: bytes.loadUnaligned(fromByteOffset: offset, as: UInt64.self))
    }

    /// The little-endian 32-bit word at `offset`.
    private static func readLE32(_ bytes: UnsafeRawBufferPointer, _ offset: Int) -> UInt32 {
        UInt32(littleEndian: bytes.loadUnaligned(fromByteOffset: offset, as: UInt32.self))
    }
}
