import Foundation
@testable import PadelCore

/// Deterministic generator (SplitMix64) so seeded tests are reproducible.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

func makePlayers(_ count: Int) -> [Player] {
    (0..<count).map { Player(name: "P\($0 + 1)") }
}

func completedMatch(
    _ tournamentId: UUID, round: Int, _ team1: [Player], _ team2: [Player], _ score1: Int, _ score2: Int
) -> Match {
    Match(
        tournamentId: tournamentId, round: round,
        team1: team1.map(\.id), team2: team2.map(\.id),
        score1: score1, score2: score2, status: .completed
    )
}
