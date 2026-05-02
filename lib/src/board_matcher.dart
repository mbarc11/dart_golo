// Pattern and shape matching for Go board positions.
//
// Direct port of Sabaki's `@sabaki/boardmatcher`:
//   https://github.com/SabakiHQ/boardmatcher
//
// Supports finding patterns by shape or by corner, and giving a human
// name to a candidate move (`Pass`, `Take`, `Atari`, `Suicide`, `Fill`,
// `Connect`, named opening shapes from the embedded library, plus
// `Tengen` / `Hoshi` / `<n>-<n> Point`).

import 'dart:convert';

import 'board.dart';
import 'board_matcher_library.dart' show defaultLibraryJson;

/// `(vertex, sign)` pair where `sign` is `-1` (white), `0` (empty) or
/// `1` (black). Used inside [Pattern] anchors and vertices.
typedef SignedVertex = ({Vertex vertex, int sign});

/// A board pattern that can be matched against any position.
///
/// - [name] / [url] are display metadata (used by [BoardMatcher.nameMove]).
/// - [size] restricts matching to square boards of that size.
/// - When [type] is `'corner'`, anchors are checked against the board's
///   corner symmetries; otherwise the pattern is translation-invariant.
/// - [vertices] lists `(vertex, sign)` requirements that must hold.
/// - [anchors] lists optional reference points used to seed [matchShape].
class Pattern {
  final String? name;
  final String? url;
  final int? size;
  final String? type;
  final List<SignedVertex> anchors;
  final List<SignedVertex> vertices;

  const Pattern({
    this.name,
    this.url,
    this.size,
    this.type,
    this.anchors = const [],
    required this.vertices,
  });

  bool get isCorner => type == 'corner';

  factory Pattern.fromJson(Map<String, dynamic> json) {
    SignedVertex parseSv(List<dynamic> sv) {
      final v = sv[0] as List<dynamic>;
      return (
        vertex: (x: v[0] as int, y: v[1] as int),
        sign: sv[1] as int,
      );
    }

    return Pattern(
      name: json['name'] as String?,
      url: json['url'] as String?,
      size: json['size'] is String
          ? int.tryParse(json['size'] as String)
          : json['size'] as int?,
      type: json['type'] as String?,
      anchors: (json['anchors'] as List<dynamic>? ?? const [])
          .map((e) => parseSv(e as List<dynamic>))
          .toList(),
      vertices: (json['vertices'] as List<dynamic>)
          .map((e) => parseSv(e as List<dynamic>))
          .toList(),
    );
  }
}

/// One match of a [Pattern] on a board.
///
/// - [symmetryIndex] is `0..7`, indicating which of the 8 dihedral
///   transforms maps the pattern onto the board.
/// - [invert] is true when the pattern colours had to be flipped.
/// - [anchors] / [vertices] are the matched board positions
///   corresponding to the pattern's anchors / vertices.
class PatternMatch {
  final int symmetryIndex;
  final bool invert;
  final List<Vertex> anchors;
  final List<Vertex> vertices;

  const PatternMatch({
    required this.symmetryIndex,
    required this.invert,
    required this.anchors,
    required this.vertices,
  });
}

/// Result of [BoardMatcher.findPatternInMove]: a [Pattern] plus the
/// specific [PatternMatch] that was found.
class FoundPattern {
  final Pattern pattern;
  final PatternMatch match;
  const FoundPattern(this.pattern, this.match);
}

// ---------------------------------------------------------------------------
// Helpers — direct port of `boardmatcher/src/helper.js`.
// ---------------------------------------------------------------------------

int _mod(int x, int m) => ((x % m) + m) % m;

int _signOf(Stone? s) =>
    s == null ? 0 : (s == Stone.black ? 1 : -1);

bool _hasVertex(Vertex v, int width, int height) =>
    v.x >= 0 && v.y >= 0 && v.x < width && v.y < height;

List<Vertex> _neighbors(Vertex v, int width, int height) {
  final result = <Vertex>[];
  for (final n in [
    (x: v.x - 1, y: v.y),
    (x: v.x + 1, y: v.y),
    (x: v.x, y: v.y - 1),
    (x: v.x, y: v.y + 1),
  ]) {
    if (_hasVertex(n, width, height)) result.add(n);
  }
  return result;
}

/// 8 dihedral symmetries of the 2-vector `(x, y)`.
List<({int x, int y})> _symmetries(int x, int y) => [
      (x: x, y: y),
      (x: -x, y: y),
      (x: x, y: -y),
      (x: -x, y: -y),
      (x: y, y: x),
      (x: -y, y: x),
      (x: y, y: -x),
      (x: -y, y: -x),
    ];

/// Board-aware symmetries of [v]: applies [_symmetries] then folds via
/// `mod(_, dim - 1)` so each result is mapped back into the board.
List<Vertex> _boardSymmetries(Vertex v, int width, int height) {
  final mx = width - 1;
  final my = height - 1;
  final result = <Vertex>[];
  for (final s in _symmetries(v.x, v.y)) {
    final mapped = (x: _mod(s.x, mx), y: _mod(s.y, my));
    if (_hasVertex(mapped, width, height)) result.add(mapped);
  }
  return result;
}

/// Counts pseudo-liberties of the chain at [v], capped at 3.
///
/// Used by [BoardMatcher.findPatternInMove] for atari/take detection.
/// Caps at 3 because the caller only needs to distinguish 1 / 2 / 3+.
int _pseudoLibertyCount(List<List<int>> data, Vertex v) {
  final result = <Vertex>{};
  final visited = <Vertex>{};
  final height = data.length;
  final width = height == 0 ? 0 : data[0].length;
  final sign = data[v.y][v.x];

  void recurse(Vertex w) {
    visited.add(w);
    for (final n in _neighbors(w, width, height)) {
      if (result.length >= 3) return;
      final s = data[n.y][n.x];
      if (s == -sign) continue;
      if (visited.contains(n)) continue;
      if (s == 0) {
        result.add(n);
        continue;
      }
      recurse(n);
    }
  }

  recurse(v);
  return result.length;
}

/// 4-4 / 3-3 hoshi positions excluding tengen and corner stars.
List<Vertex> _unnamedHoshis(int width, int height) {
  if (width < 8 || height < 8) return const [];
  final nearX = width >= 13 ? 3 : 2;
  final nearY = height >= 13 ? 3 : 2;
  final farX = width - nearX - 1;
  final farY = height - nearY - 1;
  final result = <Vertex>[];

  if (width.isOdd) {
    final mid = (width - 1) ~/ 2;
    result.add((x: mid, y: nearY));
    result.add((x: mid, y: farY));
  }
  if (height.isOdd) {
    final mid = (height - 1) ~/ 2;
    result.add((x: nearX, y: mid));
    result.add((x: farX, y: mid));
  }
  return result;
}

/// Converts a [Board] to the int sign-map representation used internally
/// (and by Sabaki's pattern format): `[y][x]` → `-1` / `0` / `1`.
List<List<int>> _signMap(Board board) {
  return List.generate(
    board.height,
    (y) => List.generate(board.width, (x) {
      return _signOf(board.get((x: x, y: y)));
    }),
  );
}

// ---------------------------------------------------------------------------
// Pattern matching — direct ports of matchCorner.js and matchPattern.js.
// ---------------------------------------------------------------------------

/// Pure-data variant of [BoardMatcher.matchShape] operating on a sign-map.
Iterable<PatternMatch> _matchShape(
    List<List<int>> data, Vertex anchor, Pattern pattern) sync* {
  final height = data.length;
  final width = height == 0 ? 0 : data[0].length;
  if (!_hasVertex(anchor, width, height)) return;
  if (pattern.size != null &&
      (width != height || width != pattern.size)) {
    return;
  }

  final sign = data[anchor.y][anchor.x];
  if (sign == 0) return;

  for (final a in pattern.anchors) {
    if (pattern.isCorner) {
      final inSymmetries = _boardSymmetries(a.vertex, width, height)
          .any((v) => v.x == anchor.x && v.y == anchor.y);
      if (!inSymmetries) continue;
    }

    // Hypothesise: `anchor` corresponds to pattern anchor `a`.
    final hypotheses = List<bool>.filled(8, true);

    for (final pv in pattern.vertices) {
      final dx = pv.vertex.x - a.vertex.x;
      final dy = pv.vertex.y - a.vertex.y;
      final symm = _symmetries(dx, dy);

      for (var k = 0; k < symm.length; k++) {
        if (!hypotheses[k]) continue;
        final wx = anchor.x + symm[k].x;
        final wy = anchor.y + symm[k].y;
        final w = (x: wx, y: wy);
        if (!_hasVertex(w, width, height) ||
            data[wy][wx] != pv.sign * sign * a.sign) {
          hypotheses[k] = false;
        }
      }

      if (!hypotheses.contains(true)) break;
    }

    for (var i = 0; i < hypotheses.length; i++) {
      if (!hypotheses[i]) continue;

      Vertex transform(Vertex v) {
        final dx = v.x - a.vertex.x;
        final dy = v.y - a.vertex.y;
        final s = _symmetries(dx, dy)[i];
        return (x: anchor.x + s.x, y: anchor.y + s.y);
      }

      yield PatternMatch(
        symmetryIndex: i,
        invert: sign != a.sign,
        anchors: pattern.anchors.map((a) => transform(a.vertex)).toList(),
        vertices: pattern.vertices.map((v) => transform(v.vertex)).toList(),
      );
    }
  }
}

/// Pure-data variant of [BoardMatcher.matchCorner].
Iterable<PatternMatch> _matchCorner(
    List<List<int>> data, Pattern pattern) sync* {
  final height = data.length;
  final width = height == 0 ? 0 : data[0].length;
  if (pattern.size != null &&
      (width != height || width != pattern.size)) {
    return;
  }

  final hypotheses = List<bool>.filled(8, true);
  final hypothesesInvert = List<bool>.filled(8, true);
  final anchors = pattern.anchors;

  for (final sv in [...anchors, ...pattern.vertices]) {
    final reps = _boardSymmetries(sv.vertex, width, height);
    for (var i = 0; i < hypotheses.length; i++) {
      if (i >= reps.length) {
        hypotheses[i] = false;
        hypothesesInvert[i] = false;
        continue;
      }
      final r = reps[i];
      final v = data[r.y][r.x];
      if (hypotheses[i] && v != sv.sign) hypotheses[i] = false;
      if (hypothesesInvert[i] && v != -sv.sign) hypothesesInvert[i] = false;
    }
    if (!hypotheses.contains(true) && !hypothesesInvert.contains(true)) {
      return;
    }
  }

  for (var invert = 0; invert <= 1; invert++) {
    for (var i = 0; i < hypotheses.length; i++) {
      final ok = invert == 0 ? hypotheses[i] : hypothesesInvert[i];
      if (!ok) continue;

      Vertex transform(Vertex v) =>
          _boardSymmetries(v, width, height)[i];

      yield PatternMatch(
        symmetryIndex: i,
        invert: invert == 1,
        anchors: anchors.map((a) => transform(a.vertex)).toList(),
        vertices:
            pattern.vertices.map((v) => transform(v.vertex)).toList(),
      );
    }
  }
}

// ---------------------------------------------------------------------------
// Public API.
// ---------------------------------------------------------------------------

/// Pattern and shape matching on a [Board].
///
/// Direct port of Sabaki's `@sabaki/boardmatcher`. Use [defaultLibrary]
/// for Sabaki's curated 58-pattern opening library, or supply your own
/// list of [Pattern]s.
class BoardMatcher {
  BoardMatcher._();

  static List<Pattern>? _defaultLibrary;

  /// The 58-pattern opening library shipped with Sabaki — Chinese, Orthodox,
  /// Kobayashi, Shusaku, sanrensei, common joseki, etc. Loaded lazily on
  /// first use.
  static List<Pattern> get defaultLibrary {
    return _defaultLibrary ??= (jsonDecode(defaultLibraryJson) as List)
        .map((e) => Pattern.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
  }

  /// Yields every match of [pattern] on [board], regardless of the
  /// pattern's `type`. Pattern is treated as a corner-style match.
  static Iterable<PatternMatch> matchCorner(Board board, Pattern pattern) =>
      _matchCorner(_signMap(board), pattern);

  /// Yields every match of [pattern] on [board] for which [anchor]
  /// corresponds to one of the pattern's anchors.
  static Iterable<PatternMatch> matchShape(
          Board board, Vertex anchor, Pattern pattern) =>
      _matchShape(_signMap(board), anchor, pattern);

  /// Names a candidate move at [vertex] played by [stone].
  ///
  /// Returns one of: `Pass`, `Take`, `Atari`, `Suicide`, `Fill`, `Connect`,
  /// any [Pattern.name] from [library] (defaults to [defaultLibrary]),
  /// `Tengen`, `Hoshi`, or `null` if the move can't be classified.
  ///
  /// Pass `vertex == null` (or [stone] == null) for a pass move.
  static String? nameMove(
    Board board,
    Stone? stone,
    Vertex? vertex, {
    List<Pattern>? library,
  }) =>
      findPatternInMove(board, stone, vertex, library: library)
          ?.pattern
          .name;

  /// Same as [nameMove] but returns the matching [Pattern] and
  /// [PatternMatch] details, or `null` if nothing matches.
  ///
  /// For built-in names (`Pass`, `Take`, ...) the returned pattern is
  /// synthetic — its `vertices` are empty and `anchors` is just the
  /// played stone.
  static FoundPattern? findPatternInMove(
    Board board,
    Stone? stone,
    Vertex? vertex, {
    List<Pattern>? library,
  }) {
    final width = board.width;
    final height = board.height;
    final sign = stone == null ? 0 : _signOf(stone);
    final isPass =
        sign == 0 || vertex == null || !_hasVertex(vertex, width, height);

    FoundPattern dummy(String name, [String? url]) {
      final anchors = isPass
          ? const <SignedVertex>[]
          : [(vertex: vertex, sign: sign)];
      final matchAnchors = isPass ? const <Vertex>[] : [vertex];
      return FoundPattern(
        Pattern(
          name: name,
          url: url,
          anchors: anchors,
          vertices: const [],
        ),
        PatternMatch(
          symmetryIndex: 0,
          invert: false,
          anchors: matchAnchors,
          vertices: const [],
        ),
      );
    }

    if (isPass) return dummy('Pass', 'https://senseis.xmp.net/?Pass');

    final v = vertex;
    final data = _signMap(board);
    if (data[v.y][v.x] != 0) return null;

    final neighbors = _neighbors(v, width, height);

    // Atari / take.
    for (final n in neighbors) {
      if (data[n.y][n.x] != -sign) continue;
      final libs = _pseudoLibertyCount(data, n);
      if (libs == 1) return dummy('Take');
      if (libs == 2) return dummy('Atari', 'https://senseis.xmp.net/?Atari');
    }

    // Suicide check on hypothetical post-move board.
    final next = data
        .map((row) => List<int>.from(row))
        .toList(growable: false);
    next[v.y][v.x] = sign;
    if (_pseudoLibertyCount(next, v) == 0) {
      return dummy('Suicide', 'https://senseis.xmp.net/?Suicide');
    }

    // Friendly connection.
    final friendly = neighbors.where((n) => data[n.y][n.x] == sign).length;
    if (friendly == neighbors.length) return dummy('Fill');
    if (friendly >= 2) return dummy('Connect');

    // Library pattern.
    final lib = library ?? defaultLibrary;
    for (final pattern in lib) {
      for (final match in _matchShape(next, v, pattern)) {
        return FoundPattern(pattern, match);
      }
    }

    // Hoshi-ish points.
    final mid = ((width - 1) / 2, (height - 1) / 2);
    if (mid.$1 == mid.$1.toInt() &&
        mid.$2 == mid.$2.toInt() &&
        v.x == mid.$1.toInt() &&
        v.y == mid.$2.toInt()) {
      return dummy('Tengen', 'https://senseis.xmp.net/?Tengen');
    }
    if (_unnamedHoshis(width, height)
        .any((h) => h.x == v.x && h.y == v.y)) {
      return dummy('Hoshi', 'https://senseis.xmp.net/?StarPoint');
    }

    return null;
  }
}
