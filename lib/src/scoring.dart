import 'dart:math' as math;

import 'board.dart';

/// Sign-map convention used by the scoring/estimator routines.
///
/// `+1` represents Black, `-1` represents White, `0` represents an empty
/// (or neutralised) point. This mirrors Sabaki's `@sabaki/influence` and
/// `@sabaki/go-board` conventions.
typedef SignMap = List<List<int>>;

int _signOf(Stone? s) =>
    s == null ? 0 : (s == Stone.black ? 1 : -1);

/// Builds a sign-map from a [Board].
SignMap signMapOf(Board board) {
  return List.generate(
    board.height,
    (y) => List.generate(board.width, (x) => _signOf(board.get((x: x, y: y)))),
  );
}

List<List<int>> _neighbors(int x, int y) =>
    [[x - 1, y], [x + 1, y], [x, y - 1], [x, y + 1]];

bool _inBounds(SignMap m, int x, int y) =>
    y >= 0 && y < m.length && x >= 0 && x < m[0].length;

/// Computes a settled-area map by flood-fill.
///
/// For each maximal empty region, looks at the bordering stones:
/// - if all border stones share one colour, the region is assigned that sign;
/// - otherwise it is `0` (dame).
///
/// Non-empty points keep their original sign. The result has the same shape
/// as [signMap].
///
/// Direct port of Sabaki's `@sabaki/influence/src/areaMap.js`.
SignMap areaMap(SignMap signMap) {
  final height = signMap.length;
  final width = height == 0 ? 0 : signMap[0].length;
  final map =
      List.generate(height, (_) => List<int>.filled(width, _unset));

  for (var x = 0; x < width; x++) {
    for (var y = 0; y < height; y++) {
      if (map[y][x] != _unset) continue;
      if (signMap[y][x] != 0) {
        map[y][x] = signMap[y][x];
        continue;
      }

      final chain = _emptyChain(signMap, x, y);
      var sign = 0;
      var indicator = 1;

      outer:
      for (final v in chain) {
        for (final n in _neighbors(v[0], v[1])) {
          final nx = n[0];
          final ny = n[1];
          if (!_inBounds(signMap, nx, ny)) continue;
          final s = signMap[ny][nx];
          if (s == 0) continue;

          if (sign == 0) {
            sign = s.sign;
          } else if (sign != s.sign) {
            indicator = 0;
            break outer;
          }
        }
      }

      for (final v in chain) {
        map[v[1]][v[0]] = sign * indicator;
      }
    }
  }

  return map;
}

const int _unset = -1000000;

/// Connected component of empty points starting at (x, y).
List<List<int>> _emptyChain(SignMap signMap, int x, int y) {
  final result = <List<int>>[];
  final seen = <int>{};
  final stack = <List<int>>[[x, y]];
  final width = signMap[0].length;

  while (stack.isNotEmpty) {
    final v = stack.removeLast();
    final key = v[1] * width + v[0];
    if (seen.contains(key)) continue;
    seen.add(key);
    result.add(v);

    for (final n in _neighbors(v[0], v[1])) {
      if (!_inBounds(signMap, n[0], n[1])) continue;
      if (signMap[n[1]][n[0]] != 0) continue;
      stack.add(n);
    }
  }

  return result;
}

/// Distance-from-nearest-stone-of-[sign] map.
///
/// Port of `@sabaki/influence/src/nearestNeighborMap.js`. Cells holding a
/// stone of the matching sign are `0`. Distance is measured in steps using
/// Sabaki's two-pass row-sweep algorithm.
List<List<double>> _nearestNeighborMap(SignMap data, int sign) {
  final height = data.length;
  final width = height == 0 ? 0 : data[0].length;
  final map = List.generate(
      height, (_) => List<double>.filled(width, double.infinity));
  var min = double.infinity;

  void f(int x, int y) {
    if (data[y][x] == sign) {
      min = 0;
    } else {
      min += 1;
    }
    map[y][x] = min = math.min(min, map[y][x]);
  }

  for (var y = 0; y < height; y++) {
    min = double.infinity;
    for (var x = 0; x < width; x++) {
      f(x, y);
      final old = min;

      for (var ny = y + 1; ny < height; ny++) {
        f(x, ny);
      }
      min = old;

      for (var ny = y - 1; ny >= 0; ny--) {
        f(x, ny);
      }
      min = old;
    }
  }

  for (var y = height - 1; y >= 0; y--) {
    min = double.infinity;
    for (var x = width - 1; x >= 0; x--) {
      f(x, y);
      final old = min;

      for (var ny = y + 1; ny < height; ny++) {
        f(x, ny);
      }
      min = old;

      for (var ny = y - 1; ny >= 0; ny--) {
        f(x, ny);
      }
      min = old;
    }
  }

  return map;
}

/// Radiance (influence strength) emitted by each [sign]-coloured group.
///
/// Port of `@sabaki/influence/src/radianceMap.js`. Each chain of stones casts
/// a BFS wave outward up to depth [p1]; reflections off the wall add [p3];
/// non-mirrored cells receive `p2 / (d / p1 * 6 + 1)`.
List<List<double>> _radianceMap(SignMap data, int sign,
    {double p1 = 6, double p2 = 1.5, double p3 = 2}) {
  final height = data.length;
  final width = height == 0 ? 0 : data[0].length;
  final map =
      List.generate(height, (_) => List<double>.filled(width, 0));
  final size = [width, height];
  final done = <int>{};

  List<int> mirror(List<int> v) {
    if (v[0] >= 0 && v[0] < width && v[1] >= 0 && v[1] < height) return v;
    return [
      for (var i = 0; i < 2; i++)
        v[i] < 0
            ? -v[i] - 1
            : v[i] >= size[i]
                ? 2 * size[i] - v[i] - 1
                : v[i]
    ];
  }

  void castRadiance(List<List<int>> chain) {
    final queue = [for (final v in chain) [v, 0]];
    final visited = <int>{};

    while (queue.isNotEmpty) {
      final entry = queue.removeAt(0);
      final v = entry[0] as List<int>;
      final d = entry[1] as int;
      final mv = mirror(v);

      final mirrored = !(mv[0] == v[0] && mv[1] == v[1]);
      map[mv[1]][mv[0]] +=
          mirrored ? p3 : p2 / (d / p1 * 6 + 1);

      for (final n in _neighbors(v[0], v[1])) {
        final nx = n[0];
        final ny = n[1];
        if (d >= p1) continue;
        if (_inBounds(data, nx, ny) && data[ny][nx] == -sign) continue;
        final key = ny * (width + 1) + nx + width * height;
        if (visited.contains(key)) continue;
        visited.add(key);
        queue.add([n, d + 1]);
      }
    }
  }

  for (var x = 0; x < width; x++) {
    for (var y = 0; y < height; y++) {
      final key = y * width + x;
      if (data[y][x] != sign || done.contains(key)) continue;

      final chain = _signedChain(data, x, y);
      for (final c in chain) {
        done.add(c[1] * width + c[0]);
      }

      castRadiance(chain);
    }
  }

  return map;
}

List<List<int>> _signedChain(SignMap data, int x, int y) {
  final sign = data[y][x];
  final result = <List<int>>[];
  final seen = <int>{};
  final width = data[0].length;
  final stack = <List<int>>[[x, y]];
  while (stack.isNotEmpty) {
    final v = stack.removeLast();
    final key = v[1] * width + v[0];
    if (seen.contains(key)) continue;
    seen.add(key);
    result.add(v);
    for (final n in _neighbors(v[0], v[1])) {
      if (!_inBounds(data, n[0], n[1])) continue;
      if (data[n[1]][n[0]] != sign) continue;
      stack.add(n);
    }
  }
  return result;
}

double _avg(Iterable<double> xs) {
  final list = xs.toList();
  if (list.isEmpty) return 0;
  return list.reduce((a, b) => a + b) / list.length;
}

/// Computes an influence-based estimator map.
///
/// Port of `@sabaki/influence/src/influenceMap.js`. Returns a map where the
/// sign of each entry indicates the predicted owner: `+1` Black, `-1` White,
/// `0` neutral. Stones keep their literal sign.
///
/// - [discrete]: when true (default for the estimator), output is snapped to
///   `{-1, 0, 1}`. When false, returns continuous [-1, 1] influence values.
/// - [maxDistance]: empty points farther than this from the closer colour are
///   treated as neutral.
/// - [minRadiance]: empty points with weaker radiance than this are neutral.
SignMap influenceMap(
  SignMap data, {
  bool discrete = true,
  double maxDistance = 6,
  double minRadiance = 2,
}) {
  final height = data.length;
  final width = height == 0 ? 0 : data[0].length;
  final am = areaMap(data);
  final result =
      List.generate(height, (y) => List<double>.from(am[y].map((x) => x.toDouble())));
  final pnn = _nearestNeighborMap(data, 1);
  final nnn = _nearestNeighborMap(data, -1);
  final pr = _radianceMap(data, 1);
  final nr = _radianceMap(data, -1);
  var maxV = double.negativeInfinity;
  var minV = double.infinity;

  for (var x = 0; x < width; x++) {
    for (var y = 0; y < height; y++) {
      if (result[y][x] != 0) continue;

      final s = (nnn[y][x] - pnn[y][x]).sign.toInt();
      final dist = s > 0 ? pnn[y][x] : nnn[y][x];
      final rad = s > 0 ? pr[y][x] : nr[y][x];
      final faraway = s == 0 || dist > maxDistance;
      final dim = s == 0 || rad.round() < minRadiance;

      if (faraway || dim) {
        result[y][x] = 0;
      } else {
        result[y][x] = s * rad;
      }

      if (result[y][x] > maxV) maxV = result[y][x];
      if (result[y][x] < minV) minV = result[y][x];

      if (discrete) result[y][x] = result[y][x].sign;
    }
  }

  // Postprocessing
  for (var x = 0; x < width; x++) {
    for (var y = 0; y < height; y++) {
      if (am[y][x] != 0) continue;

      var sign = result[y][x].sign.toInt();
      final neighbors = _neighbors(x, y)
          .where((n) => _inBounds(data, n[0], n[1]))
          .toList();
      final friendly = sign == 0
          ? <List<int>>[]
          : neighbors
              .where((n) => result[n[1]][n[0]].sign.toInt() == sign)
              .toList();

      // Prevent single point areas
      if (sign != 0) {
        if (neighbors.length >= 2 &&
            neighbors
                .every((n) => result[n[1]][n[0]].sign.toInt() != sign)) {
          result[y][x] = 0;
          continue;
        }
      }

      // Fix ragged areas
      if (sign != 0 && friendly.length == 1) {
        final f = friendly.first;
        if (data[f[1]][f[0]] == sign) {
          result[y][x] = 0;
          continue;
        }
      }

      // Fix empty pillars
      final distance =
          [x, y, width - x - 1, height - y - 1].reduce(math.min);

      if (distance <= 2 && sign != 0) {
        final signedNeighbors = neighbors
            .where((n) => result[n[1]][n[0]] != 0)
            .toList();

        if (signedNeighbors.length >= 2) {
          final n1 = signedNeighbors[0];
          final n2 = signedNeighbors[1];
          final s = result[n1[1]][n1[0]].sign.toInt();

          if ((signedNeighbors.length >= 3 || n1[0] == n2[0] || n1[1] == n2[1]) &&
              signedNeighbors
                  .every((n) => result[n[1]][n[0]].sign.toInt() == s)) {
            result[y][x] = !discrete
                ? _avg(signedNeighbors.map((n) => result[n[1]][n[0]]))
                : s.toDouble();
            sign = s;
          }
        }
      }

      // Blur
      if (!discrete && sign != 0) {
        final values = <double>[result[y][x]];
        for (final n in friendly) {
          values.add(result[n[1]][n[0]]);
        }
        result[y][x] = _avg(values);
      }
    }
  }

  // Normalise (continuous mode only)
  if (!discrete) {
    for (var x = 0; x < width; x++) {
      for (var y = 0; y < height; y++) {
        if (am[y][x] != 0 || result[y][x] == 0) continue;
        if (result[y][x] > 0 && maxV > 0) {
          result[y][x] = math.min(result[y][x] / maxV, 1);
        } else if (result[y][x] < 0 && minV < 0) {
          result[y][x] = math.max(-result[y][x] / minV, -1);
        }
      }
    }
  }

  // Final sweep through areaMap to clean up
  final intMap = List.generate(
      height, (y) => List<int>.generate(width, (x) => result[y][x].sign.toInt()));
  return areaMap(intMap);
}

/// Computed score for a board position.
///
/// - [areaScore] follows Chinese-style rules: `(black area) − (white area) − komi − handicap`.
/// - [territoryScore] follows Japanese-style rules: `(black territory + black captures) − (white territory + white captures) − komi`.
class Score {
  /// Total area (stones + territory) per side. `[black, white]`.
  final List<int> area;

  /// Empty territory only, per side. `[black, white]`.
  final List<int> territory;

  /// Captured stones per side. `[black, white]`.
  final List<int> captures;

  /// Komi (white compensation).
  final double komi;

  /// Handicap stones (subtracted from black under area rules).
  final int handicap;

  const Score({
    required this.area,
    required this.territory,
    required this.captures,
    required this.komi,
    required this.handicap,
  });

  int get blackArea => area[0];
  int get whiteArea => area[1];
  int get blackTerritory => territory[0];
  int get whiteTerritory => territory[1];
  int get blackCaptures => captures[0];
  int get whiteCaptures => captures[1];

  /// Chinese-style result. Positive favours Black.
  double get areaScore =>
      (area[0] - area[1]).toDouble() - komi - handicap;

  /// Japanese-style result. Positive favours Black.
  double get territoryScore =>
      (territory[0] - territory[1] + captures[0] - captures[1]).toDouble() -
          komi;

  @override
  String toString() =>
      'Score(area: B${area[0]}-W${area[1]}, territory: B${territory[0]}-W${territory[1]}, '
      'captures: B${captures[0]}-W${captures[1]}, komi: $komi, handicap: $handicap, '
      'areaScore: ${areaScore.toStringAsFixed(1)}, territoryScore: ${territoryScore.toStringAsFixed(1)})';
}

/// Computes a [Score] from a board and a settled-area / influence map.
///
/// [scoredMap] is typically the result of [areaMap] (strict, Japanese-style
/// dame handling) or [influenceMap] (estimator). Each entry must be
/// `+1` (black), `-1` (white) or `0` (neutral). Captures are read from the
/// board; pass a board where dead stones have already been removed if you
/// want them counted as captures (this matches Sabaki's flow).
///
/// Direct port of Sabaki's `getScore` in `src/modules/utils.js`.
Score score(
  Board board,
  SignMap scoredMap, {
  double komi = 0,
  int handicap = 0,
}) {
  final area = [0, 0];
  final territory = [0, 0];

  for (var x = 0; x < board.width; x++) {
    for (var y = 0; y < board.height; y++) {
      final z = scoredMap[y][x];
      if (z == 0) continue;
      final index = z > 0 ? 0 : 1;
      area[index] += 1;
      if (board.get((x: x, y: y)) == null) {
        territory[index] += 1;
      }
    }
  }

  return Score(
    area: area,
    territory: territory,
    captures: [
      board.getCaptures(Stone.black),
      board.getCaptures(Stone.white),
    ],
    komi: komi,
    handicap: handicap,
  );
}

/// Board-level facade for scoring and estimation.
///
/// Most callers want the methods on this class. Lower-level [SignMap]
/// helpers ([areaMap], [influenceMap], [score]) are also exported.
class Scorer {
  Scorer._();

  /// Strict area map (Japanese rules): only fully-enclosed empty regions
  /// are awarded as territory, neutral points stay `0`.
  static SignMap boardAreaMap(Board board) => areaMap(signMapOf(board));

  /// Influence-based estimator map (Bouzy-style heuristic).
  ///
  /// Returns a `{-1, 0, 1}` map predicting the owner of each point.
  static SignMap estimate(
    Board board, {
    double maxDistance = 6,
    double minRadiance = 2,
  }) =>
      influenceMap(
        signMapOf(board),
        discrete: true,
        maxDistance: maxDistance,
        minRadiance: minRadiance,
      );

  /// Settle the position with strict [boardAreaMap] and return a [Score].
  /// Use this once both players have agreed dead stones have been removed
  /// from the board.
  static Score finalScore(
    Board board, {
    double komi = 0,
    int handicap = 0,
  }) =>
      score(board, boardAreaMap(board), komi: komi, handicap: handicap);

  /// Estimate a [Score] mid-game using the influence map.
  static Score estimateScore(
    Board board, {
    double komi = 0,
    int handicap = 0,
    double maxDistance = 6,
    double minRadiance = 2,
  }) =>
      score(
        board,
        estimate(board, maxDistance: maxDistance, minRadiance: minRadiance),
        komi: komi,
        handicap: handicap,
      );

  /// Returns the static "floating stones" prefilter result — stones that
  /// any reasonable playout will identify as dead. Direct port of Sabaki's
  /// `getFloatingStones`; used internally by [guessDeadStones] when
  /// `finished: true`.
  static List<Vertex> findFloatingStones(Board board) {
    final pb = _PseudoBoard.fromBoard(board);
    return _toVertices(pb.getFloatingStones(), pb.width);
  }

  /// Identifies dead stones using Monte-Carlo playouts.
  ///
  /// Direct port of Sabaki's `@sabaki/deadstones` `guess` algorithm. When
  /// [finished] is true (the default) a static "floating stones" prefilter
  /// runs first, then [iterations] random playouts settle the position, and
  /// a related-chains pass refines the result. This is the recommended
  /// detector for end-of-game scoring.
  ///
  /// - [iterations]: number of random playouts (Sabaki default: 100).
  /// - [finished]: enable end-of-game refinements; pass false for mid-game.
  /// - [seed]: optional RNG seed for deterministic playouts.
  static List<Vertex> guessDeadStones(
    Board board, {
    int iterations = 100,
    bool finished = true,
    int? seed,
  }) =>
      _mctsGuessDeadStones(
        board,
        iterations: iterations,
        finished: finished,
        seed: seed,
      );

  /// End-of-game score: identifies dead stones with Monte-Carlo playouts,
  /// removes them (counted as captures), then runs the strict area count.
  static Score scoreEndgame(
    Board board, {
    double komi = 0,
    int handicap = 0,
    int iterations = 100,
    int? seed,
  }) {
    final settled = settleForScoring(
      board,
      iterations: iterations,
      seed: seed,
    );
    return scoreWithDeadStones(
      board,
      settled.dead,
      komi: komi,
      handicap: handicap,
    );
  }

  /// Removes the Monte-Carlo dead stones from [board] and credits them as
  /// captures. Returns the cleaned board plus the dead-stone list.
  static ({Board cleaned, List<Vertex> dead}) settleForScoring(
    Board board, {
    int iterations = 100,
    int? seed,
  }) {
    final dead = guessDeadStones(
      board,
      iterations: iterations,
      finished: true,
      seed: seed,
    );
    return (cleaned: _removeDeadStones(board, dead), dead: dead);
  }

  /// Returns the group of stones that should toggle when the user clicks
  /// at [vertex] in scoring mode. Mirrors Sabaki's expansion:
  ///
  /// - default (scoring mode): the chain of [vertex] plus every same-colour
  ///   chain reachable through empty cells (`Board.getRelatedChains`).
  /// - `includeRelatedChains: false` (estimator mode): just the chain
  ///   (`Board.getChain`).
  ///
  /// Returns an empty list if [vertex] is empty or off-board.
  static List<Vertex> deadStoneSelection(
    Board board,
    Vertex vertex, {
    bool includeRelatedChains = true,
  }) {
    if (board.get(vertex) == null) return const [];
    return includeRelatedChains
        ? board.getRelatedChains(vertex)
        : board.getChain(vertex);
  }

  /// Toggles the dead/alive state of the group containing [vertex] in
  /// [dead]. Returns a new set with the toggle applied. Mirrors Sabaki's
  /// click-to-mark behaviour: if [vertex] is currently in [dead], the whole
  /// group is removed; otherwise the whole group is added.
  static Set<Vertex> toggleDeadGroup(
    Set<Vertex> dead,
    Board board,
    Vertex vertex, {
    bool includeRelatedChains = true,
  }) {
    final selection = deadStoneSelection(
      board,
      vertex,
      includeRelatedChains: includeRelatedChains,
    );
    if (selection.isEmpty) return dead;
    final result = {...dead};
    if (dead.contains(vertex)) {
      result.removeAll(selection);
    } else {
      result.addAll(selection);
    }
    return result;
  }

  /// Scores [board] using a user-supplied set of dead stones. Each dead
  /// stone is removed and credited as a capture to the opposing colour,
  /// then the strict area count is applied.
  static Score scoreWithDeadStones(
    Board board,
    Iterable<Vertex> dead, {
    double komi = 0,
    int handicap = 0,
  }) {
    final cleaned = _removeDeadStones(board, dead);
    return score(
      cleaned,
      areaMap(signMapOf(cleaned)),
      komi: komi,
      handicap: handicap,
    );
  }

  /// Static dead-stone heuristic.
  ///
  /// Hypothetically removes each chain and checks whether its footprint
  /// becomes a region enclosed only by opposing stones AND the chain is
  /// outnumbered by them. Cheap and deterministic, but only catches clearly
  /// settled positions — prefer [guessDeadStones] for end-of-game scoring.
  static List<Vertex> staticGuessDeadStones(Board board) {
    final dead = <Vertex>[];
    final visited = <int>{};
    final w = board.width;

    for (var y = 0; y < board.height; y++) {
      for (var x = 0; x < w; x++) {
        final stone = board.get((x: x, y: y));
        if (stone == null) continue;
        final key = y * w + x;
        if (visited.contains(key)) continue;

        final chain = board.getChain((x: x, y: y));
        for (final c in chain) {
          visited.add(c.y * w + c.x);
        }

        final stoneSign = _signOf(stone);
        final removedSm = signMapOf(board);
        for (final c in chain) {
          removedSm[c.y][c.x] = 0;
        }

        final region = _emptyChain(removedSm, chain.first.x, chain.first.y);
        final friendlyBorder = <int>{};
        final opponentBorder = <int>{};
        for (final v in region) {
          for (final n in _neighbors(v[0], v[1])) {
            if (!_inBounds(removedSm, n[0], n[1])) continue;
            final s = removedSm[n[1]][n[0]];
            if (s == 0) continue;
            final k = n[1] * w + n[0];
            if (s == stoneSign) {
              friendlyBorder.add(k);
            } else {
              opponentBorder.add(k);
            }
          }
        }

        if (friendlyBorder.isEmpty &&
            opponentBorder.isNotEmpty &&
            chain.length < opponentBorder.length) {
          dead.addAll(chain);
        }
      }
    }
    return dead;
  }

  static Board _removeDeadStones(Board board, Iterable<Vertex> dead) {
    final cleaned = board.clone();
    for (final v in dead) {
      final s = cleaned.get(v);
      if (s == null) continue;
      final captor = s == Stone.black ? Stone.white : Stone.black;
      cleaned.setCaptures(captor, cleaned.getCaptures(captor) + 1);
      cleaned.set(v, null);
    }
    return cleaned;
  }
}

// ---------------------------------------------------------------------------
// Monte-Carlo dead-stone detection.
//
// Direct port of Sabaki's `@sabaki/deadstones` (Rust → WASM):
//   - [_PseudoBoard] mirrors `PseudoBoard` in src/pseudo_board.rs
//   - [_playTillEnd] mirrors `play_till_end` in src/deadstones.rs
//   - [_mctsGuessDeadStones] mirrors the `guess` function: a static
//     `getFloatingStones` prefilter plus N random playouts, then a
//     related-chains refinement pass.
// ---------------------------------------------------------------------------

class _PseudoBoard {
  final List<int> data;
  final int width;
  final int height;

  _PseudoBoard(this.data, this.width, this.height);

  factory _PseudoBoard.fromBoard(Board b) {
    final data = List<int>.filled(b.width * b.height, 0);
    for (var y = 0; y < b.height; y++) {
      for (var x = 0; x < b.width; x++) {
        data[y * b.width + x] = _signOf(b.get((x: x, y: y)));
      }
    }
    return _PseudoBoard(data, b.width, b.height);
  }

  _PseudoBoard clone() =>
      _PseudoBoard(List<int>.from(data), width, height);

  int? get(int v) => (v >= 0 && v < data.length) ? data[v] : null;
  void set(int v, int s) {
    data[v] = s;
  }

  /// 4 orthogonal neighbours, edge-clipped.
  List<int> getNeighbors(int v) {
    final result = <int>[];
    final x = v % width;
    final y = v ~/ width;
    if (y > 0) result.add(v - width);
    if (y < height - 1) result.add(v + width);
    if (x > 0) result.add(v - 1);
    if (x < width - 1) result.add(v + 1);
    return result;
  }

  /// Connected component reachable from [vertex] over cells whose value is in [signs].
  List<int> getConnectedComponent(int vertex, List<int> signs) {
    final result = <int>[];
    final inResult = <int>{};
    final stack = <int>[vertex];
    while (stack.isNotEmpty) {
      final v = stack.removeLast();
      if (inResult.contains(v)) continue;
      inResult.add(v);
      result.add(v);
      for (final n in getNeighbors(v)) {
        final s = get(n);
        if (s == null) continue;
        if (!signs.contains(s)) continue;
        if (inResult.contains(n)) continue;
        stack.add(n);
      }
    }
    return result;
  }

  List<int> getChain(int vertex) {
    final s = get(vertex);
    if (s == null) return [];
    return getConnectedComponent(vertex, [s]);
  }

  List<int> getRelatedChains(int vertex) {
    final s = get(vertex);
    if (s == null || s == 0) return [];
    final area = getConnectedComponent(vertex, [s, 0]);
    return area.where((v) => get(v) == s).toList();
  }

  bool hasLiberties(int vertex) {
    final sign = get(vertex);
    if (sign == null) return false;
    final visited = <int>{};
    final stack = <int>[vertex];
    while (stack.isNotEmpty) {
      final v = stack.removeLast();
      if (visited.contains(v)) continue;
      visited.add(v);
      for (final n in getNeighbors(v)) {
        final s = get(n);
        if (s == 0) return true;
        if (s == sign && !visited.contains(n)) stack.add(n);
      }
    }
    return false;
  }

  /// Plays at [vertex] for [sign] under playout-friendly rules:
  ///   - rejected if all neighbours are own colour or empty (eye/own area)
  ///   - rejected if move kills only own single point and captures nothing
  ///   - rejected if move's chain has no liberties unless it captures
  ///
  /// Returns the list of captured vertices on success, or `null` if illegal.
  List<int>? makePseudoMove(int sign, int vertex) {
    final neighbors = getNeighbors(vertex);

    if (neighbors.every((n) {
      final s = get(n);
      return s == null || s == sign;
    })) {
      return null;
    }

    set(vertex, sign);

    var checkCapture = false;
    var checkMultiDeadChains = false;

    if (!hasLiberties(vertex)) {
      final isPointChain = neighbors.every((n) => get(n) != sign);
      if (isPointChain) {
        checkMultiDeadChains = true;
      } else {
        checkCapture = true;
      }
    }

    final dead = <int>[];
    var deadChains = 0;

    for (final n in neighbors) {
      if (get(n) != -sign) continue;
      if (hasLiberties(n)) continue;

      final chain = getChain(n);
      deadChains++;
      for (final c in chain) {
        set(c, 0);
        dead.add(c);
      }
    }

    if ((checkMultiDeadChains && deadChains <= 1) ||
        (checkCapture && dead.isEmpty)) {
      for (final d in dead) {
        set(d, -sign);
      }
      set(vertex, 0);
      return null;
    }

    return dead;
  }

  /// Static "obvious dead stones" prefilter — direct port of
  /// `get_floating_stones` in src/pseudo_board.rs.
  List<int> getFloatingStones() {
    final done = <int>{};
    final result = <int>[];

    for (var v = 0; v < data.length; v++) {
      if (get(v) != 0 || done.contains(v)) continue;

      final posArea = getConnectedComponent(v, [0, -1]);
      final negArea = getConnectedComponent(v, [0, 1]);
      final posSet = {...posArea};
      final negSet = {...negArea};
      final posDead = posArea.where((w) => get(w) == -1).toList();
      final negDead = negArea.where((w) => get(w) == 1).toList();
      final posDeadSet = {...posDead};
      final negDeadSet = {...negDead};

      final posDiff = posArea
          .where((w) => !posDeadSet.contains(w) && !negSet.contains(w))
          .length;
      final negDiff = negArea
          .where((w) => !negDeadSet.contains(w) && !posSet.contains(w))
          .length;

      final favorNeg = negDiff <= 1 && negDead.length <= posDead.length;
      final favorPos = posDiff <= 1 && posDead.length <= negDead.length;

      List<int> actualArea;
      List<int> actualDead;
      if (!favorNeg && favorPos) {
        actualArea = posArea;
        actualDead = posDead;
      } else if (favorNeg && !favorPos) {
        actualArea = negArea;
        actualDead = negDead;
      } else {
        actualArea = getChain(v);
        actualDead = const [];
      }

      done.addAll(actualArea);
      result.addAll(actualDead);
    }

    return result;
  }
}

/// Plays out the position with random moves until both sides pass; then
/// "patches holes" so the final position can be area-counted. Direct port
/// of `play_till_end` in src/deadstones.rs.
_PseudoBoard _playTillEnd(_PseudoBoard board, int startSign, math.Random rand) {
  final b = board.clone();
  var sign = startSign;
  var finishedNeg = false;
  var finishedPos = false;
  final illegal = <int>[];
  final free = <int>[];
  for (var v = 0; v < b.data.length; v++) {
    if (b.get(v) == 0) free.add(v);
  }

  while (free.isNotEmpty && (!finishedNeg || !finishedPos)) {
    var madeMove = false;

    while (free.isNotEmpty) {
      final i = rand.nextInt(free.length);
      final v = free[i];
      free[i] = free[free.length - 1];
      free.removeLast();

      final captured = b.makePseudoMove(sign, v);
      if (captured != null) {
        free.addAll(captured);
        if (sign < 0) {
          finishedNeg = false;
        } else {
          finishedPos = false;
        }
        madeMove = true;
        break;
      } else {
        illegal.add(v);
      }
    }

    if (sign > 0) {
      finishedPos = !madeMove;
    } else {
      finishedNeg = !madeMove;
    }

    free.addAll(illegal);
    illegal.clear();
    sign = -sign;
  }

  for (var v = 0; v < b.data.length; v++) {
    if (b.get(v) != 0) continue;
    var fill = 0;
    for (final n in b.getNeighbors(v)) {
      final s = b.get(n);
      if (s == 1 || s == -1) {
        fill = s!;
        break;
      }
    }
    if (fill != 0) b.set(v, fill);
  }

  return b;
}

/// Per-vertex ownership probability in `[-1, 1]` after [iterations] playouts.
/// Half the iterations start with white, half with black, so first-move bias
/// cancels out (matches Sabaki).
List<double> _probabilityMap(
    _PseudoBoard board, int iterations, math.Random rand) {
  final neg = List<int>.filled(board.data.length, 0);
  final pos = List<int>.filled(board.data.length, 0);

  for (var i = 0; i < iterations; i++) {
    final startSign = i < iterations ~/ 2 ? -1 : 1;
    final result = _playTillEnd(board, startSign, rand);
    for (var v = 0; v < result.data.length; v++) {
      final s = result.get(v);
      if (s == -1) {
        neg[v] += 1;
      } else if (s == 1) {
        pos[v] += 1;
      }
    }
  }

  return List<double>.generate(board.data.length, (v) {
    final total = neg[v] + pos[v];
    if (total == 0) return 0;
    return pos[v] * 2.0 / total - 1.0;
  });
}

List<Vertex> _mctsGuessDeadStones(
  Board board, {
  required int iterations,
  required bool finished,
  required int? seed,
}) {
  final pb = _PseudoBoard.fromBoard(board);
  final rand = seed == null ? math.Random() : math.Random(seed);

  final floating = <int>[];
  if (finished) {
    floating.addAll(pb.getFloatingStones());
    for (final v in floating) {
      pb.set(v, 0);
    }
  }

  final probMap = _probabilityMap(pb, iterations, rand);
  final result = <int>[];
  final done = <int>{};

  for (var v = 0; v < probMap.length; v++) {
    final s = pb.get(v);
    if (s == null || s == 0 || done.contains(v)) continue;

    final chain = pb.getChain(v);
    final probability =
        chain.map((c) => probMap[c]).fold<double>(0, (a, b) => a + b) /
            chain.length;
    final dead = probability.sign.toInt() == -s;

    for (final c in chain) {
      done.add(c);
      if (dead) result.add(c);
    }
  }

  if (!finished) {
    return _toVertices(result, pb.width);
  }

  // Refine: a chain is dead if a majority of its related chains are flagged.
  final updated = <int>[...floating];
  final done2 = <int>{};
  final resultSet = {...result};
  for (final v in result) {
    if (done2.contains(v)) continue;
    final related = pb.getRelatedChains(v);
    if (related.isEmpty) continue;
    final deadCount = related.where(resultSet.contains).length;
    final dead = deadCount / related.length > 0.5;
    for (final r in related) {
      done2.add(r);
      if (dead) updated.add(r);
    }
  }

  final seen = <int>{};
  final uniq = <int>[];
  for (final v in updated) {
    if (seen.add(v)) uniq.add(v);
  }
  return _toVertices(uniq, pb.width);
}

List<Vertex> _toVertices(List<int> indices, int width) =>
    indices.map((i) => (x: i % width, y: i ~/ width)).toList();
