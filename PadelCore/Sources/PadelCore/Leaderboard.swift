import Foundation

public enum LeaderboardSort: Sendable {
    case wins
    case points
    case diff
}

public struct LeaderboardEntry: Identifiable, Equatable, Sendable {
    public let player: Player
    public var wins = 0
    public var losses = 0
    public var matchesPlayed = 0
    public var totalPoints = 0
    public var pointDiff = 0

    public var id: UUID { player.id }
}

public struct TeamLeaderboardEntry: Identifiable, Equatable, Sendable {
    public let team: FixedTeam
    public let members: [Player]
    public var wins = 0
    public var losses = 0
    public var matchesPlayed = 0
    public var totalPoints = 0
    public var pointDiff = 0

    public var id: UUID { team.id }
}

public enum Leaderboard {
    /// Individual standings from completed matches. Players with no matches are still listed.
    public static func calculate(
        players: [Player],
        matches: [Match],
        sortBy: LeaderboardSort = .wins
    ) -> [LeaderboardEntry] {
        var entries = players.map { LeaderboardEntry(player: $0) }
        var indexOf: [UUID: Int] = [:]
        for (index, entry) in entries.enumerated() { indexOf[entry.player.id] = index }

        func record(team: [UUID], own: Int, other: Int) {
            for playerId in team {
                guard let index = indexOf[playerId] else { continue }
                entries[index].matchesPlayed += 1
                entries[index].totalPoints += own
                entries[index].pointDiff += own - other
                if own > other { entries[index].wins += 1 }
                else if own < other { entries[index].losses += 1 }
            }
        }

        for match in matches where match.status == .completed {
            guard let score1 = match.score1, let score2 = match.score2 else { continue }
            record(team: match.team1, own: score1, other: score2)
            record(team: match.team2, own: score2, other: score1)
        }

        return entries.sorted {
            sortKey(wins: $0.wins, points: $0.totalPoints, diff: $0.pointDiff, by: sortBy)
                .lexicographicallyPrecedes(
                    sortKey(wins: $1.wins, points: $1.totalPoints, diff: $1.pointDiff, by: sortBy),
                    by: >
                )
        }
    }

    /// Standings per fixed team. Partners always play together, so the first member's record is the team's.
    public static func calculateTeams(
        teams: [FixedTeam],
        players: [Player],
        matches: [Match],
        sortBy: LeaderboardSort = .wins
    ) -> [TeamLeaderboardEntry] {
        let individual = calculate(players: players, matches: matches, sortBy: sortBy)
        var byPlayer: [UUID: LeaderboardEntry] = [:]
        for entry in individual { byPlayer[entry.player.id] = entry }

        let entries = teams
            .filter { $0.playerIds.count == 2 }
            .map { team -> TeamLeaderboardEntry in
                let members = team.playerIds.compactMap { id in players.first { $0.id == id } }
                var entry = TeamLeaderboardEntry(team: team, members: members)
                if let first = members.first, let representative = byPlayer[first.id] {
                    entry.wins = representative.wins
                    entry.losses = representative.losses
                    entry.matchesPlayed = representative.matchesPlayed
                    entry.totalPoints = representative.totalPoints
                    entry.pointDiff = representative.pointDiff
                }
                return entry
            }

        return entries.sorted {
            sortKey(wins: $0.wins, points: $0.totalPoints, diff: $0.pointDiff, by: sortBy)
                .lexicographicallyPrecedes(
                    sortKey(wins: $1.wins, points: $1.totalPoints, diff: $1.pointDiff, by: sortBy),
                    by: >
                )
        }
    }

    private static func sortKey(wins: Int, points: Int, diff: Int, by sort: LeaderboardSort) -> [Int] {
        switch sort {
        case .wins: [wins, diff, points]
        case .points: [points, wins, diff]
        case .diff: [diff, wins, points]
        }
    }
}
