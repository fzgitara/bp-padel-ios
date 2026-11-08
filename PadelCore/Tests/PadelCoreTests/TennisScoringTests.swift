import Testing
@testable import PadelCore

struct TennisScoringTests {
    @Test func pointLabels() {
        #expect(TennisScoring.pointLabel(0) == "0")
        #expect(TennisScoring.pointLabel(1) == "15")
        #expect(TennisScoring.pointLabel(2) == "30")
        #expect(TennisScoring.pointLabel(3) == "40")
        #expect(TennisScoring.pointLabel(5) == "5")
    }

    @Test(arguments: [
        (0, 0, TennisGameStatus.playing),
        (3, 2, .playing),
        (3, 3, .deuce),
        (4, 4, .deuce),
        (4, 3, .advantage(.one)),
        (3, 4, .advantage(.two)),
        (4, 0, .win(.one)),
        (4, 2, .win(.one)),
        (2, 4, .win(.two)),
        (5, 3, .win(.one)),
    ])
    func gameStatus(score1: Int, score2: Int, expected: TennisGameStatus) {
        #expect(TennisScoring.gameStatus(score1, score2) == expected)
    }

    @Test func statusText() {
        #expect(TennisScoring.statusText(.deuce) == "Deuce")
        #expect(TennisScoring.statusText(.advantage(.one)) == "Adv")
        #expect(TennisScoring.statusText(.win(.two)) == "Set Point")
        #expect(TennisScoring.statusText(.playing) == "")
    }

    @Test func sideLabelShowsAOnAdvantageOnly() {
        let status = TennisGameStatus.advantage(.one)
        #expect(TennisScoring.sideLabel(rawPoints: 4, side: .one, status: status) == "A")
        #expect(TennisScoring.sideLabel(rawPoints: 3, side: .two, status: status) == "40")
    }

    @Test func gameComplete() {
        #expect(TennisScoring.isGameComplete(4, 2))
        #expect(!TennisScoring.isGameComplete(4, 3))
    }

    @Test func applyPointIncrementsWithoutWinning() {
        let result = TennisScoring.applyPoint(game1: 3, game2: 3, side: .one)
        #expect(result.game1 == 4)
        #expect(result.game2 == 3)
        #expect(result.wonSide == nil)
    }

    @Test func applyPointBackToDeuce() {
        let result = TennisScoring.applyPoint(game1: 4, game2: 3, side: .two)
        #expect(result.game1 == 4)
        #expect(result.game2 == 4)
        #expect(result.wonSide == nil)
    }

    @Test func applyPointWinningResetsGame() {
        let result = TennisScoring.applyPoint(game1: 4, game2: 3, side: .one)
        #expect(result.game1 == 0)
        #expect(result.game2 == 0)
        #expect(result.wonSide == .one)

        let quick = TennisScoring.applyPoint(game1: 3, game2: 0, side: .one)
        #expect(quick.wonSide == .one)
    }
}
