import Foundation
import Testing
@testable import PadelCore

private let seeds: [UInt64] = [1, 2, 3, 4, 5, 6, 7, 8]

private func partnerKeys(_ matches: [Match]) -> Set<PairKey> {
    var keys = Set<PairKey>()
    for match in matches {
        keys.insert(PairKey(match.team1[0], match.team1[1]))
        keys.insert(PairKey(match.team2[0], match.team2[1]))
    }
    return keys
}

private func allPairs(_ players: [Player]) -> Set<PairKey> {
    var keys = Set<PairKey>()
    for i in 0..<players.count {
        for j in (i + 1)..<players.count { keys.insert(PairKey(players[i].id, players[j].id)) }
    }
    return keys
}

/// Every match has 4 distinct players, and nobody plays twice in the same round.
private func expectValidRounds(_ matches: [Match], courts: Int) {
    for match in matches {
        #expect(match.team1.count == 2)
        #expect(match.team2.count == 2)
        #expect(Set(match.team1 + match.team2).count == 4)
    }
    for (_, roundMatches) in Dictionary(grouping: matches, by: \.round) {
        let ids = roundMatches.flatMap { $0.team1 + $0.team2 }
        #expect(Set(ids).count == ids.count)
        #expect(roundMatches.count <= courts)
    }
}

struct AmericanoTests {
    let tid = UUID()

    @Test func fewerThanFourActivePlayersKeepsOnlyCompleted() {
        var rng = SeededGenerator(seed: 1)
        let players = makePlayers(3)
        let result = Matchmaking.generateRounds(
            players: players, existingMatches: [], tournamentId: tid,
            totalCourts: 2, format: .americano, using: &rng
        )
        #expect(result.isEmpty)
    }

    @Test(arguments: seeds)
    func eightPlayersCoverEveryPartnership(seed: UInt64) {
        var rng = SeededGenerator(seed: seed)
        let players = makePlayers(8)
        let result = Matchmaking.generateRounds(
            players: players, existingMatches: [], tournamentId: tid,
            totalCourts: 2, format: .americano, using: &rng
        )
        expectValidRounds(result, courts: 2)
        #expect(partnerKeys(result) == allPairs(players))
        #expect(result.allSatisfy { $0.status == .pending })
        #expect(result.map(\.round).min() == 1)
    }

    @Test(arguments: seeds)
    func oddPlayerCountStillCoversEveryPartnership(seed: UInt64) {
        var rng = SeededGenerator(seed: seed)
        let players = makePlayers(5)
        let result = Matchmaking.generateRounds(
            players: players, existingMatches: [], tournamentId: tid,
            totalCourts: 2, format: .americano, using: &rng
        )
        expectValidRounds(result, courts: 1)
        #expect(partnerKeys(result) == allPairs(players))
    }

    @Test func inactivePlayersAreExcluded() {
        var rng = SeededGenerator(seed: 3)
        var players = makePlayers(6)
        players[5].active = false
        let result = Matchmaking.generateRounds(
            players: players, existingMatches: [], tournamentId: tid,
            totalCourts: 2, format: .americano, using: &rng
        )
        let used = Set(result.flatMap { $0.team1 + $0.team2 })
        #expect(!used.contains(players[5].id))
        #expect(partnerKeys(result) == allPairs(Array(players.prefix(5))))
    }

    @Test func keepsCompletedAndDropsPending() {
        var rng = SeededGenerator(seed: 4)
        let players = makePlayers(8)
        let done = completedMatch(tid, round: 1, [players[0], players[1]], [players[2], players[3]], 21, 10)
        let stalePending = Match(
            tournamentId: tid, round: 2,
            team1: [players[0].id, players[2].id], team2: [players[1].id, players[3].id]
        )
        let result = Matchmaking.generateRounds(
            players: players, existingMatches: [done, stalePending], tournamentId: tid,
            totalCourts: 2, format: .americano, using: &rng
        )
        #expect(result.contains { $0.id == done.id })
        #expect(!result.contains { $0.id == stalePending.id })
        let regenerated = result.filter { $0.status == .pending }
        #expect(regenerated.allSatisfy { $0.round >= 2 })
        #expect(partnerKeys(result) == allPairs(players))
    }

    @Test func singleMatchHasFourDistinctActivePlayers() {
        var rng = SeededGenerator(seed: 5)
        var players = makePlayers(6)
        players[0].active = false
        let match = Matchmaking.generateSingleMatch(
            players: players, existingMatches: [], tournamentId: tid,
            format: .americano, using: &rng
        )
        let ids = (match?.team1 ?? []) + (match?.team2 ?? [])
        #expect(Set(ids).count == 4)
        #expect(!ids.contains(players[0].id))
        #expect(match?.round == 1)
    }

    @Test func singleMatchNeedsFourActivePlayers() {
        var rng = SeededGenerator(seed: 5)
        let match = Matchmaking.generateSingleMatch(
            players: makePlayers(3), existingMatches: [], tournamentId: tid,
            format: .americano, using: &rng
        )
        #expect(match == nil)
    }
}

struct MexicanoTests {
    let tid = UUID()

    @Test(arguments: seeds)
    func firstRoundUsesFloorOfPlayersDividedByFour(seed: UInt64) {
        var rng = SeededGenerator(seed: seed)
        let players = makePlayers(10)
        let result = Matchmaking.generateRounds(
            players: players, existingMatches: [], tournamentId: tid,
            totalCourts: 1, format: .mexicano, using: &rng
        )
        #expect(result.count == 2)
        #expect(result.allSatisfy { $0.round == 1 })
        expectValidRounds(result, courts: 2)
    }

    @Test func nextRoundStartsAfterLastCompletedRound() {
        var rng = SeededGenerator(seed: 2)
        let players = makePlayers(8)
        let done = [
            completedMatch(tid, round: 1, [players[0], players[1]], [players[2], players[3]], 21, 10),
            completedMatch(tid, round: 1, [players[4], players[5]], [players[6], players[7]], 15, 18),
        ]
        let result = Matchmaking.generateRounds(
            players: players, existingMatches: done, tournamentId: tid,
            totalCourts: 1, format: .mexicano, using: &rng
        )
        let next = result.filter { $0.status == .pending }
        #expect(result.count == 4)
        #expect(next.allSatisfy { $0.round == 2 })
        expectValidRounds(next, courts: 2)
    }

    @Test func avoidsRepeatingPartnersWhenAlternativesExist() {
        let players = makePlayers(4)
        // P1 and P2 already partnered once. The other two splits cost less, so they must be chosen.
        let done = [completedMatch(tid, round: 1, [players[0], players[1]], [players[2], players[3]], 21, 10)]
        for seed in seeds {
            var rng = SeededGenerator(seed: seed)
            let result = Matchmaking.generateRounds(
                players: players, existingMatches: done, tournamentId: tid,
                totalCourts: 1, format: .mexicano, using: &rng
            )
            let next = result.first { $0.status == .pending }!
            let keys = [PairKey(next.team1[0], next.team1[1]), PairKey(next.team2[0], next.team2[1])]
            #expect(!keys.contains(PairKey(players[0].id, players[1].id)))
            #expect(!keys.contains(PairKey(players[2].id, players[3].id)))
        }
    }

    @Test func singleMatchHasFourDistinctPlayers() {
        var rng = SeededGenerator(seed: 9)
        let match = Matchmaking.generateSingleMatch(
            players: makePlayers(7), existingMatches: [], tournamentId: tid,
            format: .mexicano, using: &rng
        )
        #expect(Set((match?.team1 ?? []) + (match?.team2 ?? [])).count == 4)
    }
}

struct FixedPartnerTests {
    let tid = UUID()

    private func makeTeams(_ count: Int) -> [FixedTeam] {
        let players = makePlayers(count * 2)
        return (0..<count).map { index in
            FixedTeam(name: "T\(index + 1)", playerIds: [players[index * 2].id, players[index * 2 + 1].id])
        }
    }

    @Test func fewerThanTwoPlayableTeamsKeepsOnlyCompleted() {
        let solo = FixedTeam(name: "Solo", playerIds: [UUID()])
        let result = Matchmaking.generateFixedMatches(
            teams: [makeTeams(1)[0], solo], existingMatches: [], tournamentId: tid, totalCourts: 2
        )
        #expect(result.isEmpty)
    }

    @Test func roundRobinPlaysEveryTeamPairExactlyOnce() {
        let teams = makeTeams(5)
        let result = Matchmaking.generateFixedMatches(
            teams: teams, existingMatches: [], tournamentId: tid, totalCourts: 2
        )
        #expect(result.count == 10)
        let pairs = Set(result.map { match -> PairKey in
            let a = teams.first { Set($0.playerIds) == Set(match.team1) }!
            let b = teams.first { Set($0.playerIds) == Set(match.team2) }!
            return PairKey(a.id, b.id)
        })
        #expect(pairs.count == 10)
    }

    @Test func aTeamNeverPlaysTwiceInTheSameRound() {
        let result = Matchmaking.generateFixedMatches(
            teams: makeTeams(4), existingMatches: [], tournamentId: tid, totalCourts: 3
        )
        for (_, roundMatches) in Dictionary(grouping: result, by: \.round) {
            let ids = roundMatches.flatMap { $0.team1 + $0.team2 }
            #expect(Set(ids).count == ids.count)
            #expect(roundMatches.count <= 2)
        }
    }

    @Test func manyTeamsOnOneCourtAreNotTruncated() {
        let result = Matchmaking.generateFixedMatches(
            teams: makeTeams(12), existingMatches: [], tournamentId: tid, totalCourts: 1
        )
        #expect(result.count == 66)
    }

    @Test func keepsCompletedMatchesAndSchedulesOnlyTheRest() {
        let teams = makeTeams(3)
        let done = Match(
            tournamentId: tid, round: 1, team1: teams[0].playerIds, team2: teams[1].playerIds,
            score1: 21, score2: 5, status: .completed
        )
        let result = Matchmaking.generateFixedMatches(
            teams: teams, existingMatches: [done], tournamentId: tid, totalCourts: 1
        )
        #expect(result.count == 3)
        #expect(result.contains { $0.id == done.id })
        #expect(result.filter { $0.status == .pending }.allSatisfy { $0.round >= 2 })
    }

    @Test func singleFixedMatchPrefersUnplayedPair() {
        let teams = makeTeams(3)
        let played = [
            Match(tournamentId: tid, round: 1, team1: teams[0].playerIds, team2: teams[1].playerIds),
            Match(tournamentId: tid, round: 1, team1: teams[0].playerIds, team2: teams[2].playerIds),
        ]
        for seed in seeds {
            var rng = SeededGenerator(seed: seed)
            let match = Matchmaking.generateSingleFixedMatch(
                teams: teams, existingMatches: played, tournamentId: tid, using: &rng
            )!
            #expect(Set(match.team1) == Set(teams[1].playerIds) || Set(match.team1) == Set(teams[2].playerIds))
            #expect(Set(match.team1 + match.team2) == Set(teams[1].playerIds + teams[2].playerIds))
        }
    }

    @Test func singleFixedMatchStillWorksWhenAllPairsPlayed() {
        var rng = SeededGenerator(seed: 1)
        let teams = makeTeams(2)
        let played = [Match(tournamentId: tid, round: 1, team1: teams[0].playerIds, team2: teams[1].playerIds)]
        let match = Matchmaking.generateSingleFixedMatch(
            teams: teams, existingMatches: played, tournamentId: tid, using: &rng
        )
        #expect(match != nil)
    }
}
