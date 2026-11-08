public enum Side: Int, Hashable, Sendable {
    case one = 1
    case two = 2
}

public enum TennisGameStatus: Hashable, Sendable {
    case playing
    case deuce
    case advantage(Side)
    case win(Side)
}

/// Tennis-style scoring inside one game: 0, 15, 30, 40, then win by 2.
/// Winning a game gives that side one set point and resets the game to 0-0.
public enum TennisScoring {
    public static func pointLabel(_ rawPoints: Int) -> String {
        let labels = ["0", "15", "30", "40"]
        if (0...3).contains(rawPoints) { return labels[rawPoints] }
        return String(rawPoints)
    }

    /// A side wins with at least 4 points and a lead of 2.
    public static func gameStatus(_ score1: Int, _ score2: Int) -> TennisGameStatus {
        let diff = score1 - score2
        if max(score1, score2) >= 4 && abs(diff) >= 2 {
            return .win(diff > 0 ? .one : .two)
        }
        if score1 >= 3 && score2 >= 3 {
            if diff == 0 { return .deuce }
            return .advantage(diff > 0 ? .one : .two)
        }
        return .playing
    }

    public static func statusText(_ status: TennisGameStatus) -> String {
        switch status {
        case .deuce: "Deuce"
        case .advantage: "Adv"
        case .win: "Set Point"
        case .playing: ""
        }
    }

    /// Label for one side in the current game ("A" when that side has advantage).
    public static func sideLabel(rawPoints: Int, side: Side, status: TennisGameStatus) -> String {
        if case .advantage(let advantageSide) = status, advantageSide == side { return "A" }
        return pointLabel(rawPoints)
    }

    public static func isGameComplete(_ score1: Int, _ score2: Int) -> Bool {
        if case .win = gameStatus(score1, score2) { return true }
        return false
    }

    /// Adds one point. If the game just finished, game points reset to 0-0 and `wonSide` is set.
    public static func applyPoint(game1: Int, game2: Int, side: Side) -> (game1: Int, game2: Int, wonSide: Side?) {
        let next1 = side == .one ? game1 + 1 : game1
        let next2 = side == .two ? game2 + 1 : game2
        if case .win(let winner) = gameStatus(next1, next2) {
            return (0, 0, winner)
        }
        return (next1, next2, nil)
    }
}
