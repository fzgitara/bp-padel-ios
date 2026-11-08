import Foundation

/// Order-independent key for two UUIDs (a partnership, an opposition, or a team-vs-team pair).
struct PairKey: Hashable {
    let first: UUID
    let second: UUID

    init(_ a: UUID, _ b: UUID) {
        if a.uuidString <= b.uuidString {
            first = a
            second = b
        } else {
            first = b
            second = a
        }
    }
}

private struct Pairing {
    let team1: [UUID]
    let team2: [UUID]
}

private struct History {
    var partnerships: [PairKey: Int] = [:]
    var opponents: [PairKey: Int] = [:]
}

public enum Matchmaking {
    // MARK: - Public API

    /// Americano: pre-generates rounds until every pair of players has been partners once.
    /// Mexicano: generates only the next round, pairing players by current standings.
    /// Completed matches are kept as-is; pending matches are dropped and regenerated.
    public static func generateRounds<G: RandomNumberGenerator>(
        players: [Player],
        existingMatches: [Match],
        tournamentId: UUID,
        totalCourts: Int,
        format: TournamentFormat,
        using generator: inout G
    ) -> [Match] {
        let completed = existingMatches.filter { $0.status == .completed }
        let active = players.filter(\.active)
        guard active.count >= 4 else { return completed }

        let playerCount = active.count
        let activeIds = Set(active.map(\.id))
        let matchesPerRound = format == .mexicano
            ? playerCount / 4
            : min(totalCourts, playerCount / 4)
        guard matchesPerRound >= 1 else { return completed }

        let startRound = (completed.map(\.round).max() ?? 0) + 1

        switch format {
        case .mexicano:
            return completed + mexicanoRound(
                active: active, completed: completed, activeIds: activeIds,
                tournamentId: tournamentId, round: startRound, using: &generator
            )
        case .americano:
            return americanoSchedule(
                active: active, completed: completed, activeIds: activeIds,
                tournamentId: tournamentId, matchesPerRound: matchesPerRound,
                startRound: startRound, using: &generator
            )
        }
    }

    /// One extra pending match, for the "add match" action.
    public static func generateSingleMatch<G: RandomNumberGenerator>(
        players: [Player],
        existingMatches: [Match],
        tournamentId: UUID,
        format: TournamentFormat,
        using generator: inout G
    ) -> Match? {
        let active = players.filter(\.active)
        guard active.count >= 4 else { return nil }

        let activeIds = Set(active.map(\.id))
        let completed = existingMatches.filter { $0.status == .completed }
        let round = (completed.map(\.round).max() ?? 0) + 1

        let pairing: Pairing
        switch format {
        case .mexicano:
            let history = buildHistory(matches: existingMatches, activeIds: activeIds)
            let ranks = rankMap(players: active, matches: completed)
            let four = active
                .shuffled(using: &generator)
                .sorted { (ranks[$0.id] ?? 0) < (ranks[$1.id] ?? 0) }
                .prefix(4)
                .map(\.id)
            pairing = mexicanoPairing(four[0], four[1], four[2], four[3], history: history, using: &generator)

        case .americano:
            var covered = Set<PairKey>()
            for match in existingMatches {
                for team in [match.team1, match.team2] where isActivePair(team, activeIds) {
                    covered.insert(PairKey(team[0], team[1]))
                }
            }
            var completedCounts: [UUID: Int] = [:]
            var totalCounts: [UUID: Int] = [:]
            for player in active {
                completedCounts[player.id] = 0
                totalCounts[player.id] = 0
            }
            for match in existingMatches {
                for id in match.team1 + match.team2 where totalCounts[id] != nil {
                    totalCounts[id]! += 1
                    if match.status == .completed { completedCounts[id]! += 1 }
                }
            }
            let sorted = active.shuffled(using: &generator).sorted {
                if completedCounts[$0.id]! != completedCounts[$1.id]! {
                    return completedCounts[$0.id]! < completedCounts[$1.id]!
                }
                return totalCounts[$0.id]! < totalCounts[$1.id]!
            }
            let group = selectBestGroup(sorted, covered: covered)
            pairing = bestAmericanoPairing(group[0].id, group[1].id, group[2].id, group[3].id, covered: covered, using: &generator)
        }

        return Match(tournamentId: tournamentId, round: round, team1: pairing.team1, team2: pairing.team2)
    }

    /// Fixed partners: a round-robin where every team plays every other team once.
    /// Completed matches are kept; a team never plays two matches in the same round.
    public static func generateFixedMatches(
        teams: [FixedTeam],
        existingMatches: [Match],
        tournamentId: UUID,
        totalCourts: Int
    ) -> [Match] {
        let completed = existingMatches.filter { $0.status == .completed }
        let playable = teams.filter { $0.playerIds.count == 2 }
        guard playable.count >= 2 else { return completed }

        let target = playable.count * (playable.count - 1) / 2
        var played = Set<PairKey>()
        for match in completed {
            if let a = team(in: teams, players: match.team1), let b = team(in: teams, players: match.team2) {
                played.insert(PairKey(a.id, b.id))
            }
        }

        var result = completed
        var round = (completed.map(\.round).max() ?? 0) + 1

        while played.count < target {
            var roundMatches: [Match] = []
            var busy = Set<UUID>()

            for _ in 0..<totalCourts {
                guard let (a, b) = firstUnplayedPair(playable, played: played, busy: busy) else { break }
                roundMatches.append(Match(
                    tournamentId: tournamentId, round: round,
                    team1: a.playerIds, team2: b.playerIds
                ))
                played.insert(PairKey(a.id, b.id))
                busy.insert(a.id)
                busy.insert(b.id)
            }

            if roundMatches.isEmpty { break }
            result += roundMatches
            round += 1
        }

        return result
    }

    /// One extra pending match between two fixed teams, preferring a pair that has not played yet.
    public static func generateSingleFixedMatch<G: RandomNumberGenerator>(
        teams: [FixedTeam],
        existingMatches: [Match],
        tournamentId: UUID,
        using generator: inout G
    ) -> Match? {
        let playable = teams.filter { $0.playerIds.count == 2 }
        guard playable.count >= 2 else { return nil }

        var played = Set<PairKey>()
        for match in existingMatches {
            if let a = team(in: teams, players: match.team1), let b = team(in: teams, players: match.team2) {
                played.insert(PairKey(a.id, b.id))
            }
        }

        var candidates: [(FixedTeam, FixedTeam)] = []
        for i in 0..<playable.count {
            for j in (i + 1)..<playable.count where !played.contains(PairKey(playable[i].id, playable[j].id)) {
                candidates.append((playable[i], playable[j]))
            }
        }
        if candidates.isEmpty { candidates.append((playable[0], playable[1])) }

        let pick = candidates.randomElement(using: &generator)!
        let completed = existingMatches.filter { $0.status == .completed }
        let round = (completed.map(\.round).max() ?? 0) + 1
        return Match(tournamentId: tournamentId, round: round, team1: pick.0.playerIds, team2: pick.1.playerIds)
    }

    // MARK: - Mexicano

    private static func mexicanoRound<G: RandomNumberGenerator>(
        active: [Player], completed: [Match], activeIds: Set<UUID>,
        tournamentId: UUID, round: Int, using generator: inout G
    ) -> [Match] {
        let history = buildHistory(matches: completed, activeIds: activeIds)

        var playedCounts: [UUID: Int] = [:]
        for player in active { playedCounts[player.id] = 0 }
        for match in completed {
            for id in match.team1 + match.team2 where playedCounts[id] != nil { playedCounts[id]! += 1 }
        }

        let ranks = rankMap(players: active, matches: completed)
        var available = active.shuffled(using: &generator).sorted {
            if playedCounts[$0.id]! != playedCounts[$1.id]! { return playedCounts[$0.id]! < playedCounts[$1.id]! }
            return (ranks[$0.id] ?? 0) < (ranks[$1.id] ?? 0)
        }

        var matches: [Match] = []
        while available.count >= 4 {
            let four = available.prefix(4).map(\.id)
            available.removeFirst(4)
            let pairing = mexicanoPairing(four[0], four[1], four[2], four[3], history: history, using: &generator)
            matches.append(Match(tournamentId: tournamentId, round: round, team1: pairing.team1, team2: pairing.team2))
        }
        return matches
    }

    /// Picks the cheapest of the 3 ways to split 4 players into 2 teams.
    /// Cost: repeated partners count double, repeated opponents count once.
    /// Small biases prefer 1+3 vs 2+4 (the classic Mexicano pattern); ties are broken randomly.
    private static func mexicanoPairing<G: RandomNumberGenerator>(
        _ a: UUID, _ b: UUID, _ c: UUID, _ d: UUID,
        history: History, using generator: inout G
    ) -> Pairing {
        func partner(_ x: UUID, _ y: UUID) -> Double { Double(history.partnerships[PairKey(x, y), default: 0]) }
        func opponent(_ x: UUID, _ y: UUID) -> Double { Double(history.opponents[PairKey(x, y), default: 0]) }

        let options: [(pairing: Pairing, cost: Double)] = [
            (Pairing(team1: [a, b], team2: [c, d]),
             partner(a, b) * 2 + partner(c, d) * 2 + opponent(a, c) + opponent(a, d) + opponent(b, c) + opponent(b, d) + 0.2),
            (Pairing(team1: [a, c], team2: [b, d]),
             partner(a, c) * 2 + partner(b, d) * 2 + opponent(a, b) + opponent(a, d) + opponent(c, b) + opponent(c, d) + 0.0),
            (Pairing(team1: [a, d], team2: [b, c]),
             partner(a, d) * 2 + partner(b, c) * 2 + opponent(a, b) + opponent(a, c) + opponent(d, b) + opponent(d, c) + 0.1),
        ]

        let minCost = options.map(\.cost).min()!
        let tied = options.filter { abs($0.cost - minCost) <= 0.01 }
        return tied.randomElement(using: &generator)!.pairing
    }

    // MARK: - Americano

    private static func americanoSchedule<G: RandomNumberGenerator>(
        active: [Player], completed: [Match], activeIds: Set<UUID>,
        tournamentId: UUID, matchesPerRound: Int, startRound: Int, using generator: inout G
    ) -> [Match] {
        let playerCount = active.count
        let targetPairs = playerCount * (playerCount - 1) / 2

        var covered = Set<PairKey>()
        for match in completed {
            for team in [match.team1, match.team2] where isActivePair(team, activeIds) {
                covered.insert(PairKey(team[0], team[1]))
            }
        }

        var playedCounts: [UUID: Int] = [:]
        for player in active { playedCounts[player.id] = 0 }
        for match in completed {
            for id in match.team1 + match.team2 where playedCounts[id] != nil { playedCounts[id]! += 1 }
        }

        var result = completed
        let maxRound = startRound + max(50, playerCount * 4)

        for round in startRound...maxRound {
            if covered.count >= targetPairs { break }

            var roundMatches: [Match] = []
            var usedInRound = Set<UUID>()

            for _ in 0..<matchesPerRound {
                if covered.count >= targetPairs { break }

                let available = active
                    .shuffled(using: &generator)
                    .filter { !usedInRound.contains($0.id) }
                    .sorted { playedCounts[$0.id]! < playedCounts[$1.id]! }
                if available.count < 4 { break }

                let group = selectBestGroup(available, covered: covered)
                let pairing = bestAmericanoPairing(
                    group[0].id, group[1].id, group[2].id, group[3].id,
                    covered: covered, using: &generator
                )
                roundMatches.append(Match(tournamentId: tournamentId, round: round, team1: pairing.team1, team2: pairing.team2))

                for player in group {
                    usedInRound.insert(player.id)
                    playedCounts[player.id]! += 1
                }
                covered.insert(PairKey(pairing.team1[0], pairing.team1[1]))
                covered.insert(PairKey(pairing.team2[0], pairing.team2[1]))
            }

            if roundMatches.isEmpty { break }
            result += roundMatches
        }

        return result
    }

    /// Of the 3 ways to split 4 players, picks the one with the most partnerships not yet covered.
    private static func bestAmericanoPairing<G: RandomNumberGenerator>(
        _ a: UUID, _ b: UUID, _ c: UUID, _ d: UUID,
        covered: Set<PairKey>, using generator: inout G
    ) -> Pairing {
        func fresh(_ x: UUID, _ y: UUID) -> Int { covered.contains(PairKey(x, y)) ? 0 : 1 }

        let options: [(pairing: Pairing, score: Int)] = [
            (Pairing(team1: [a, b], team2: [c, d]), fresh(a, b) + fresh(c, d)),
            (Pairing(team1: [a, c], team2: [b, d]), fresh(a, c) + fresh(b, d)),
            (Pairing(team1: [a, d], team2: [b, c]), fresh(a, d) + fresh(b, c)),
        ]
        let best = options.map(\.score).max()!
        return options.filter { $0.score == best }.randomElement(using: &generator)!.pairing
    }

    /// From players sorted by fewest matches played, picks the 4 (out of the first 8)
    /// that can create the most new partnerships.
    private static func selectBestGroup(_ sorted: [Player], covered: Set<PairKey>) -> [Player] {
        let candidates = Array(sorted.prefix(8))
        var bestGroup = Array(candidates.prefix(4))
        var bestScore = -1

        func maxNewPairs(_ a: UUID, _ b: UUID, _ c: UUID, _ d: UUID) -> Int {
            func fresh(_ x: UUID, _ y: UUID) -> Int { covered.contains(PairKey(x, y)) ? 0 : 1 }
            return max(fresh(a, b) + fresh(c, d), fresh(a, c) + fresh(b, d), fresh(a, d) + fresh(b, c))
        }

        for i in 0..<candidates.count {
            for j in (i + 1)..<candidates.count {
                for k in (j + 1)..<candidates.count {
                    for l in (k + 1)..<candidates.count {
                        let score = maxNewPairs(candidates[i].id, candidates[j].id, candidates[k].id, candidates[l].id)
                        if score > bestScore {
                            bestScore = score
                            bestGroup = [candidates[i], candidates[j], candidates[k], candidates[l]]
                        }
                    }
                }
            }
        }
        return bestGroup
    }

    // MARK: - Shared helpers

    private static func isActivePair(_ team: [UUID], _ activeIds: Set<UUID>) -> Bool {
        team.count == 2 && activeIds.contains(team[0]) && activeIds.contains(team[1])
    }

    private static func buildHistory(matches: [Match], activeIds: Set<UUID>) -> History {
        var history = History()
        for match in matches {
            for team in [match.team1, match.team2] where isActivePair(team, activeIds) {
                history.partnerships[PairKey(team[0], team[1]), default: 0] += 1
            }
            for a in match.team1 {
                for b in match.team2 where activeIds.contains(a) && activeIds.contains(b) {
                    history.opponents[PairKey(a, b), default: 0] += 1
                }
            }
        }
        return history
    }

    private static func rankMap(players: [Player], matches: [Match]) -> [UUID: Int] {
        var ranks: [UUID: Int] = [:]
        for (index, entry) in Leaderboard.calculate(players: players, matches: matches).enumerated() {
            ranks[entry.player.id] = index
        }
        return ranks
    }

    // MARK: - Fixed-team helpers

    private static func team(in teams: [FixedTeam], players: [UUID]) -> FixedTeam? {
        guard players.count == 2 else { return nil }
        return teams.first { Set($0.playerIds) == Set(players) }
    }

    private static func firstUnplayedPair(
        _ teams: [FixedTeam], played: Set<PairKey>, busy: Set<UUID>
    ) -> (FixedTeam, FixedTeam)? {
        for i in 0..<teams.count where !busy.contains(teams[i].id) {
            for j in (i + 1)..<teams.count where !busy.contains(teams[j].id) {
                if !played.contains(PairKey(teams[i].id, teams[j].id)) {
                    return (teams[i], teams[j])
                }
            }
        }
        return nil
    }
}
