import Foundation

public struct Player: Identifiable, Hashable, Sendable {
    public let id: UUID
    public var name: String
    public var active: Bool

    public init(id: UUID = UUID(), name: String, active: Bool = true) {
        self.id = id
        self.name = name
        self.active = active
    }
}

public struct FixedTeam: Identifiable, Hashable, Sendable {
    public let id: UUID
    public var name: String
    public var playerIds: [UUID]

    public init(id: UUID = UUID(), name: String, playerIds: [UUID]) {
        self.id = id
        self.name = name
        self.playerIds = playerIds
    }
}

public enum MatchStatus: String, Hashable, Sendable {
    case pending
    case completed
}

public enum TournamentFormat: String, Hashable, Sendable {
    case americano
    case mexicano
}

public struct Match: Identifiable, Hashable, Sendable {
    public let id: UUID
    public var tournamentId: UUID
    public var round: Int
    public var team1: [UUID]
    public var team2: [UUID]
    public var score1: Int?
    public var score2: Int?
    public var status: MatchStatus

    public init(
        id: UUID = UUID(),
        tournamentId: UUID,
        round: Int,
        team1: [UUID],
        team2: [UUID],
        score1: Int? = nil,
        score2: Int? = nil,
        status: MatchStatus = .pending
    ) {
        self.id = id
        self.tournamentId = tournamentId
        self.round = round
        self.team1 = team1
        self.team2 = team2
        self.score1 = score1
        self.score2 = score2
        self.status = status
    }
}
