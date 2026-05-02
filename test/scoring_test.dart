import 'package:golo/golo.dart';
import 'package:test/test.dart';

// Shorthand to build a board from a sign-map literal:
//  1 = black, -1 = white, 0 = empty.
Board _board(List<List<int>> signs) {
  return Board(
    signs.map((row) => row.map<Stone?>((s) {
      if (s == 0) return null;
      if (s == 1) return Stone.black;
      return Stone.white;
    }).toList()).toList(),
  );
}

void main() {
  group('areaMap', () {
    test('empty board yields all zeros', () {
      final b = Board.fromDimension(5);
      final m = Scorer.boardAreaMap(b);
      for (final row in m) {
        for (final c in row) {
          expect(c, 0);
        }
      }
    });

    test('all-black board: every point is black-owned', () {
      final m = Scorer.boardAreaMap(_board([
        [1, 1, 1],
        [1, 1, 1],
        [1, 1, 1],
      ]));
      for (final row in m) {
        for (final c in row) {
          expect(c, 1);
        }
      }
    });

    test('settled corners assign territory to the surrounding colour', () {
      // 5x5: a black wall on row 2 and a white wall on column 3.
      //
      //   . . . W .
      //   . . . W .
      //   B B B W .
      //   . . B W .
      //   . . B W W
      //
      // Top-left empty region touches BOTH walls → dame (0).
      // Top-right strip touches only W → -1.
      // Bottom-left region touches only B → +1.
      final m = Scorer.boardAreaMap(_board([
        [0, 0, 0, -1, 0],
        [0, 0, 0, -1, 0],
        [1, 1, 1, -1, 0],
        [0, 0, 1, -1, 0],
        [0, 0, 1, -1, -1],
      ]));

      // Top-left empty region is dame: bordered by both colours.
      expect(m[0][0], 0);
      expect(m[1][2], 0);

      // Stones keep their sign.
      expect(m[2][2], 1);
      expect(m[4][3], -1);

      // Top-right strip enclosed by white.
      expect(m[0][4], -1);
      expect(m[1][4], -1);
      expect(m[2][4], -1);

      // Bottom-left region enclosed by black.
      expect(m[3][0], 1);
      expect(m[4][0], 1);
      expect(m[4][1], 1);
    });

    test('region bordered by both colours is dame', () {
      // Empty middle row touches both colours.
      //   B . W
      //   B . W
      //   B . W
      final m = Scorer.boardAreaMap(_board([
        [1, 0, -1],
        [1, 0, -1],
        [1, 0, -1],
      ]));
      for (var y = 0; y < 3; y++) {
        expect(m[y][1], 0, reason: 'middle column is dame');
      }
    });
  });

  group('Scorer.finalScore', () {
    test('balanced board with komi gives white the win', () {
      // Same board as the dame test: black 3 area, white 3 area, komi 6.5.
      final b = _board([
        [1, 0, -1],
        [1, 0, -1],
        [1, 0, -1],
      ]);
      final s = Scorer.finalScore(b, komi: 6.5);
      expect(s.area, [3, 3]);
      expect(s.territory, [0, 0]);
      expect(s.areaScore, -6.5);
      expect(s.territoryScore, -6.5);
    });

    test('settled position counts area = stones + territory + dame', () {
      // Same wall position as the areaMap test:
      //   Black: 5 stones + 4 empty in bottom-left = 9 area.
      //   White: 6 stones + 4 empty in right strip = 10 area.
      //   Dame:  6 empty in the top-left region (bordered by both).
      //   9 + 10 + 6 = 25 ✓.
      final b = _board([
        [0, 0, 0, -1, 0],
        [0, 0, 0, -1, 0],
        [1, 1, 1, -1, 0],
        [0, 0, 1, -1, 0],
        [0, 0, 1, -1, -1],
      ]);
      final s = Scorer.finalScore(b, komi: 0);
      expect(s.area, [9, 10]);
      expect(s.territory, [4, 4]);
      expect(s.areaScore, -1);
      expect(s.territoryScore, 0);
    });

    test('captures contribute to territory score, not area score', () {
      // Two disjoint single stones — area is 2 vs 0, but if white has 4
      // captured black stones, the territory score should dock 4.
      final b = _board([
        [1, 0, 0],
        [0, 0, 0],
        [0, 0, 0],
      ]);
      b.setCaptures(Stone.white, 4); // white captured 4 black stones.
      // The whole empty area is bordered only by black, so it is all black
      // territory: black area = 9, white area = 0.
      final s = Scorer.finalScore(b, komi: 0);
      expect(s.area, [9, 0]);
      expect(s.areaScore, 9);
      // Territory score: 8 (territory) + 0 (B captures) - 0 (W captures = 4 lost) - 0 komi.
      // captures[0] == 0 (B captured nothing), captures[1] == 4 (W captured B).
      // territoryScore = 8 - 0 + 0 - 4 - 0 = 4.
      expect(s.territoryScore, 4);
    });
  });

  group('Scorer.estimate', () {
    test('returns same shape as the board', () {
      final b = _board([
        [0, 0, 0, 0, 0],
        [0, 1, 0, -1, 0],
        [0, 1, 0, -1, 0],
        [0, 1, 0, -1, 0],
        [0, 0, 0, 0, 0],
      ]);
      final m = Scorer.estimate(b);
      expect(m.length, b.height);
      for (final row in m) {
        expect(row.length, b.width);
        for (final v in row) {
          expect(v == -1 || v == 0 || v == 1, isTrue,
              reason: 'discrete estimator should be in {-1, 0, 1}, got $v');
        }
      }
    });

    test('classifies clearly settled corners', () {
      // Black walls off the top-left; white walls off the bottom-right.
      final b = _board([
        [0, 0, 1, 0, 0, 0, 0],
        [0, 0, 1, 0, 0, 0, 0],
        [1, 1, 1, 0, 0, 0, 0],
        [0, 0, 0, 0, 0, 0, 0],
        [0, 0, 0, 0, -1, -1, -1],
        [0, 0, 0, 0, -1, 0, 0],
        [0, 0, 0, 0, -1, 0, 0],
      ]);
      final m = Scorer.estimate(b);
      expect(m[0][0], 1, reason: 'top-left is clearly black');
      expect(m[6][6], -1, reason: 'bottom-right is clearly white');
    });
  });

  group('Scorer.guessDeadStones', () {
    test('flags a single white stone surrounded by a black wall', () {
      // 7x7: white stone at (3,3) trapped inside a tight black box.
      final b = _board([
        [0, 0, 0, 0, 0, 0, 0],
        [0, 0, 0, 0, 0, 0, 0],
        [0, 1, 1, 1, 1, 1, 0],
        [0, 1, 0, -1, 0, 1, 0],
        [0, 1, 1, 1, 1, 1, 0],
        [0, 0, 0, 0, 0, 0, 0],
        [0, 0, 0, 0, 0, 0, 0],
      ]);
      final dead = Scorer.guessDeadStones(b);
      expect(dead, contains((x: 3, y: 3)),
          reason: 'lone white stone inside black wall should be flagged dead');
      // Black wall stones should not be flagged.
      expect(dead.contains((x: 1, y: 2)), isFalse);
      expect(dead.contains((x: 5, y: 4)), isFalse);
    });
  });

  group('Scorer.findFloatingStones', () {
    test('matches Sabaki @sabaki/deadstones finished-board fixture', () {
      // From SabakiHQ/deadstones tests/data.js (`exports.finished`).
      final signs = _sabakiFinishedFixture();
      final b = _board(signs);

      final floating = Scorer.findFloatingStones(b)..sort(_vertexCmp);
      final expected = <Vertex>[
        (x: 10, y: 5),
        (x: 13, y: 13),
        (x: 13, y: 14),
        (x: 14, y: 7),
        (x: 18, y: 13),
        (x: 2, y: 13),
        (x: 2, y: 14),
        (x: 5, y: 13),
        (x: 6, y: 13),
        (x: 9, y: 3),
        (x: 9, y: 5),
      ]..sort(_vertexCmp);
      expect(floating, expected);
    });
  });

  group('Scorer.guessDeadStones (Monte Carlo)', () {
    test('returns a deterministic set when seeded', () {
      final b = _board(_sabakiFinishedFixture());
      final a = Scorer.guessDeadStones(b, iterations: 50, seed: 1)
        ..sort(_vertexCmp);
      final c = Scorer.guessDeadStones(b, iterations: 50, seed: 1)
        ..sort(_vertexCmp);
      expect(a, c);
    });

    test('flagged stones are a superset of floating stones', () {
      final b = _board(_sabakiFinishedFixture());
      final floating = Scorer.findFloatingStones(b);
      final dead = Scorer.guessDeadStones(b, iterations: 50, seed: 1);
      for (final v in floating) {
        expect(dead, contains(v),
            reason: 'floating stone $v should also be flagged dead');
      }
    });
  });

  group('Scorer click-to-mark API', () {
    // 7x7 with a clearly dead white stone surrounded by a black wall, and
    // a separate live white group on the right edge.
    Board makeBoard() => _board([
          [0, 0, 0, 0, 0, 0, 0],
          [0, 0, 0, 0, 0, 0, -1],
          [0, 1, 1, 1, 1, 1, -1],
          [0, 1, 0, -1, 0, 1, -1],
          [0, 1, 1, 1, 1, 1, -1],
          [0, 0, 0, 0, 0, 0, -1],
          [0, 0, 0, 0, 0, 0, 0],
        ]);

    test('deadStoneSelection on empty/off-board returns empty', () {
      final b = makeBoard();
      expect(Scorer.deadStoneSelection(b, (x: 0, y: 0)), isEmpty);
      expect(Scorer.deadStoneSelection(b, (x: -1, y: 0)), isEmpty);
    });

    test('deadStoneSelection in scoring mode expands to related chains', () {
      final b = makeBoard();
      // Click a white stone on the right wall; the column is one chain so
      // related chains is just that chain on this board.
      final sel = Scorer.deadStoneSelection(b, (x: 6, y: 3));
      // All 5 vertically connected white stones should be in the selection.
      for (var y = 1; y <= 5; y++) {
        expect(sel.contains((x: 6, y: y)), isTrue);
      }
    });

    test('toggleDeadGroup adds and then removes the same group', () {
      final b = makeBoard();
      var dead = <Vertex>{};

      // First click: add the dead white stone in the middle.
      dead = Scorer.toggleDeadGroup(dead, b, (x: 3, y: 3));
      expect(dead.contains((x: 3, y: 3)), isTrue);

      // Second click on any stone in that group: remove.
      dead = Scorer.toggleDeadGroup(dead, b, (x: 3, y: 3));
      expect(dead.contains((x: 3, y: 3)), isFalse);
    });

    test('scoreWithDeadStones credits dead stones as captures', () {
      final b = makeBoard();
      final scored = Scorer.scoreWithDeadStones(
        b,
        [(x: 3, y: 3)],
        komi: 0,
      );
      // The white stone is now removed and credited to white's opponent
      // (black). Black has 12 wall stones + 7 (formerly held by lone W +
      // its two empty sockets) = 14? Just check the score reflects black
      // gaining that point: territoryScore should improve for black vs.
      // not removing the stone.
      final naive = Scorer.finalScore(b, komi: 0);
      expect(scored.territoryScore, greaterThan(naive.territoryScore));
      // Captures bookkeeping.
      expect(scored.blackCaptures, 1);
    });
  });

  group('low-level helpers', () {
    test('signMapOf round-trips', () {
      final b = _board([
        [1, 0, -1],
        [0, 1, 0],
      ]);
      expect(signMapOf(b), [
        [1, 0, -1],
        [0, 1, 0],
      ]);
    });

    test('areaMap on a sign-map matches Scorer.boardAreaMap', () {
      final b = _board([
        [1, 0, 0, 0, -1],
        [1, 0, 0, 0, -1],
        [1, 0, 0, 0, -1],
      ]);
      expect(areaMap(signMapOf(b)), Scorer.boardAreaMap(b));
    });
  });
}

int _vertexCmp(Vertex a, Vertex b) {
  final dx = a.x - b.x;
  if (dx != 0) return dx;
  return a.y - b.y;
}

// Verbatim copy of `exports.finished` from
// https://github.com/SabakiHQ/deadstones/blob/master/tests/data.js
List<List<int>> _sabakiFinishedFixture() => [
      [0, 0, 0, -1, -1, -1, 1, 0, 1, 1, -1, -1, 0, -1, 0, -1, -1, 1, 0],
      [0, 0, -1, 0, -1, 1, 1, 1, 0, 1, -1, 0, -1, -1, -1, -1, 1, 1, 0],
      [0, 0, -1, -1, -1, 1, 1, 0, 0, 1, 1, -1, -1, 1, -1, 1, 0, 1, 0],
      [0, 0, 0, 0, -1, -1, 1, 0, 1, -1, 1, 1, 1, 1, 1, 0, 1, 0, 0],
      [0, 0, 0, 0, -1, 0, -1, 1, 0, 0, 1, 1, 0, 0, 0, 1, 1, 1, 0],
      [0, 0, -1, 0, 0, -1, -1, 1, 0, -1, -1, 1, -1, -1, 0, 1, 0, 0, 1],
      [0, 0, 0, -1, -1, 1, 1, 1, 1, 1, 1, 1, 1, -1, -1, -1, 1, 1, 1],
      [0, 0, -1, 1, 1, 0, 1, -1, -1, 1, 0, 1, -1, 0, 1, -1, -1, -1, 1],
      [0, 0, -1, -1, 1, 1, 1, 0, -1, 1, -1, -1, 0, -1, -1, 1, 1, 1, 1],
      [0, 0, -1, 1, 1, -1, -1, -1, -1, 1, 1, 1, -1, -1, -1, -1, 1, -1, -1],
      [-1, -1, -1, -1, 1, 1, 1, -1, 0, -1, 1, -1, -1, 0, -1, 1, 1, -1, 0],
      [-1, 1, -1, 0, -1, -1, -1, -1, -1, -1, 1, -1, 0, -1, -1, 1, -1, 0, -1],
      [1, 1, 1, 1, -1, 1, 1, 1, -1, 1, 0, 1, -1, 0, -1, 1, -1, -1, 0],
      [0, 1, -1, 1, 1, -1, -1, 1, -1, 1, 1, 1, -1, 1, -1, 1, 1, -1, 1],
      [0, 0, -1, 1, 0, 0, 1, 1, -1, -1, 0, 1, -1, 1, -1, 1, -1, 0, -1],
      [0, 0, 1, 0, 1, 0, 1, 1, 1, -1, -1, 1, -1, -1, 1, -1, -1, -1, 0],
      [0, 0, 0, 0, 1, 1, 0, 1, -1, 0, -1, -1, 1, 1, 1, 1, -1, -1, -1],
      [0, 0, 1, 1, -1, 1, 1, -1, 0, -1, -1, 1, 1, 1, 1, 0, 1, -1, 1],
      [0, 0, 0, 1, -1, -1, -1, -1, -1, 0, -1, -1, 1, 1, 0, 1, 1, 1, 0],
    ];
