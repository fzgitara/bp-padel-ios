import Foundation
import Testing
@testable import PadelCore

struct LeaderboardTests {
    let tid = UUID()
    let players = makePlayers(4)

    var matches: [Match] {
        let (a, b, c, d) = (players[0], players[1], players[2], players[3])
        return [
            completedMatch(tid, round: 1, [a, b], [c, d], 21, 10),
            completedMatch(tid, round: 2, [a, c], [b, d], 15, 15),
            Match(tournamentId: tid, round: 3, team1: [a.id, d.id], team2: [b.id, c.id]),
        ]
    }

    @Test func countsOnlyCompletedMatches() {
        let entries = Leaderboard.calculate(players: players, matches: matches)
        let a = entries.first { $0.player.id == players[0].id }!
        #expect(a.matchesPlayed == 2)
        #expect(a.wins == 1)
        #expect(a.losses == 0)
        #expect(a.totalPoints == 36)
        #expect(a.pointDiff == 11)

        let d = entries.first { $0.player.id == players[3].id }!
        #expect(d.matchesPlayed == 2)
        #expect(d.wins == 0)
        #expect(d.losses == 1)
        #expect(d.pointDiff == -11)
    }

    @Test func sortsByWinsThenDiffThenPoints() {
        let entries = Leaderboard.calculate(players: players, matches: matches, sortBy: .wins)
        #expect(entries.map(\.player.name) == ["P1", "P2", "P3", "P4"])
    }

    @Test func sortsByPointsAndByDiff() {
        let eight = makePlayers(8)
        let custom = [
            completedMatch(tid, round: 1, [eight[0], eight[1]], [eight[2], eight[3]], 40, 39),
            completedMatch(tid, round: 1, [eight[4], eight[5]], [eight[6], eight[7]], 21, 0),
        ]
        let byPoints = Leaderboard.calculate(players: eight, matches: custom, sortBy: .points)
        #expect(byPoints.first?.player.name == "P1")
        let byDiff = Leaderboard.calculate(players: eight, matches: custom, sortBy: .diff)
        #expect(byDiff.first?.player.name == "P5")
        let byWins = Leaderboard.calculate(players: eight, matches: custom, sortBy: .wins)
        #expect(byWins.first?.player.name == "P5")
    }

    @Test func listsPlayersWithoutMatches() {
        let entries = Leaderboard.calculate(players: players, matches: [])
        #expect(entries.count == 4)
        #expect(entries.allSatisfy { $0.matchesPlayed == 0 })
    }

    @Test func ignoresPlayersNotInTheList() {
        let stranger = Player(name: "X")
        let match = completedMatch(tid, round: 1, [players[0], stranger], [players[1], players[2]], 21, 5)
        let entries = Leaderboard.calculate(players: players, matches: [match])
        #expect(entries.count == 4)
        #expect(entries.first { $0.player.id == players[0].id }!.wins == 1)
    }

    @Test func teamLeaderboardUsesFirstMembersRecord() {
        let (a, b, c, d) = (players[0], players[1], players[2], players[3])
        let teamAB = FixedTeam(name: "AB", playerIds: [a.id, b.id])
        let teamCD = FixedTeam(name: "CD", playerIds: [c.id, d.id])
        let incomplete = FixedTeam(name: "Solo", playerIds: [a.id])
        let match = completedMatch(tid, round: 1, [a, b], [c, d], 21, 10)

        let entries = Leaderboard.calculateTeams(
            teams: [teamCD, teamAB, incomplete], players: players, matches: [match]
        )
        #expect(entries.map(\.team.name) == ["AB", "CD"])
        #expect(entries[0].wins == 1)
        #expect(entries[0].pointDiff == 11)
        #expect(entries[1].losses == 1)
    }
}
