/// Pattern and shape matching for Go board positions.
///
/// Adopts the matching model used by [Sabaki's @sabaki/boardmatcher][1]:
/// patterns describe sign-anchored shapes that can be matched under the 8
/// dihedral symmetries of the board, and a candidate move is classified
/// as one of `Pass`, `Take`, `Atari`, `Self-Atari`, `Suicide`, `Fill`,
/// `Connect`, a named pattern from the embedded library, `Tengen`,
/// `Hoshi`, or `<n>-<n> Point`.
///
/// The data model and embedded opening library are inherited from the
/// upstream JS project; the algorithms below have been rewritten in
/// idiomatic Dart with a few changes:
///
/// - Sign maps are stored as a single [Int8List] indexed `y * width + x`,
///   not a `List<List<int>>` of boxed integers.
/// - Symmetry hypotheses are tracked as an 8-bit bitfield instead of a
///   `List<bool>`.
/// - Liberty traversal is iterative with an explicit stack.
/// - The 8 dihedral transforms are evaluated by closed-form switch
///   instead of allocating a list of 8 records per call.
///
/// [1]: https://github.com/SabakiHQ/boardmatcher
library;

import 'dart:convert';
import 'dart:typed_data';

import 'board.dart';
import 'board_matcher_library.dart' show defaultLibraryJson;
import 'move_localizations.dart' show MoveLocalizations;

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
/// - [anchors] lists optional reference points used to seed [BoardMatcher.matchShape].
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

    final rawSize = json['size'];
    return Pattern(
      name: json['name'] as String?,
      url: json['url'] as String?,
      size: rawSize is String ? int.tryParse(rawSize) : rawSize as int?,
      type: json['type'] as String?,
      anchors: List.unmodifiable(
        (json['anchors'] as List<dynamic>? ?? const [])
            .map((e) => parseSv(e as List<dynamic>)),
      ),
      vertices: List.unmodifiable(
        (json['vertices'] as List<dynamic>)
            .map((e) => parseSv(e as List<dynamic>)),
      ),
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
// Sign map: packed Int8 representation of the board, used by every matcher.
// ---------------------------------------------------------------------------

/// Compact `(width, height)` sign map: `-1` white, `0` empty, `+1` black.
/// Stored as a flat [Int8List] indexed `y * width + x`. All matcher hot
/// paths read through this view to avoid `Stone?` boxing and `List<List>`
/// indirection.
class _SignMap {
  final Int8List data;
  final int width;
  final int height;

  _SignMap._(this.data, this.width, this.height);

  factory _SignMap.fromBoard(Board b) {
    final w = b.width;
    final h = b.height;
    final out = Int8List(w * h);
    var i = 0;
    for (var y = 0; y < h; y++) {
      final row = b.state[y];
      for (var x = 0; x < w; x++) {
        final s = row[x];
        out[i++] = s == null ? 0 : (s == Stone.black ? 1 : -1);
      }
    }
    return _SignMap._(out, w, h);
  }

  _SignMap clone() => _SignMap._(Int8List.fromList(data), width, height);

  int at(int x, int y) => data[y * width + x];
  void set(int x, int y, int v) => data[y * width + x] = v;
  bool inBounds(int x, int y) =>
      x >= 0 && y >= 0 && x < width && y < height;
}

// ---------------------------------------------------------------------------
// Dihedral symmetries — closed form, no per-call allocation.
//
// Indices, matching Sabaki's enumeration:
//   0: ( x,  y)   1: (-x,  y)   2: ( x, -y)   3: (-x, -y)
//   4: ( y,  x)   5: (-y,  x)   6: ( y, -x)   7: (-y, -x)
// ---------------------------------------------------------------------------

@pragma('vm:prefer-inline')
int _symX(int i, int x, int y) => switch (i) {
      0 || 2 => x,
      1 || 3 => -x,
      4 || 6 => y,
      5 || 7 => -y,
      _ => throw RangeError.range(i, 0, 7, 'symmetry index'),
    };

@pragma('vm:prefer-inline')
int _symY(int i, int x, int y) => switch (i) {
      0 || 1 => y,
      2 || 3 => -y,
      4 || 5 => x,
      6 || 7 => -x,
      _ => throw RangeError.range(i, 0, 7, 'symmetry index'),
    };

int _floorMod(int x, int m) => ((x % m) + m) % m;

/// Folds [v] back into the board via the 8 dihedral transforms then
/// `mod (dim - 1)`. Returns vertices in symmetry-index order, or `null`
/// at indices where the result falls off the board.
///
/// On 1×N or N×1 boards `dim - 1 == 0`; the JS reference relies on NaN
/// fall-through, we explicitly return an all-`null` list so callers can
/// short-circuit cleanly.
List<Vertex?> _boardSymmetries(int x, int y, int width, int height) {
  final mx = width - 1;
  final my = height - 1;
  if (mx == 0 || my == 0) return const [null, null, null, null, null, null, null, null];
  final out = List<Vertex?>.filled(8, null);
  for (var i = 0; i < 8; i++) {
    final wx = _floorMod(_symX(i, x, y), mx);
    final wy = _floorMod(_symY(i, x, y), my);
    if (wx >= 0 && wy >= 0 && wx < width && wy < height) {
      out[i] = (x: wx, y: wy);
    }
  }
  return out;
}

// ---------------------------------------------------------------------------
// Liberty counting — iterative DFS, capped, no per-step list allocation.
// ---------------------------------------------------------------------------

/// Counts unique liberties of the chain at `(x, y)` in [m], stopping as
/// soon as [maxCount] is reached. Returns `0` if the start cell is empty.
///
/// Uses a fixed-size `Int8List` for visit / liberty marking instead of a
/// hash set, which dominates because every traversal in this file caps
/// out at 3.
int _countLiberties(_SignMap m, int x, int y, int maxCount) {
  final width = m.width;
  final height = m.height;
  final start = y * width + x;
  final sign = m.data[start];
  if (sign == 0) return 0;

  final visited = Int8List(width * height);
  final libertyMark = Int8List(width * height);
  final stack = <int>[start];
  visited[start] = 1;
  var libCount = 0;

  while (stack.isNotEmpty) {
    final p = stack.removeLast();
    final px = p % width;
    final py = p ~/ width;

    // Unrolled neighbour visit. We deliberately don't extract a closure
    // because that allocates per call and ends up dominating the profile.
    for (var dir = 0; dir < 4; dir++) {
      int nx, ny;
      switch (dir) {
        case 0:
          nx = px - 1;
          ny = py;
          break;
        case 1:
          nx = px + 1;
          ny = py;
          break;
        case 2:
          nx = px;
          ny = py - 1;
          break;
        default:
          nx = px;
          ny = py + 1;
      }
      if (nx < 0 || ny < 0 || nx >= width || ny >= height) continue;
      final nidx = ny * width + nx;
      if (visited[nidx] != 0) continue;
      visited[nidx] = 1;
      final ns = m.data[nidx];
      if (ns == -sign) continue;
      if (ns == 0) {
        if (libertyMark[nidx] == 0) {
          libertyMark[nidx] = 1;
          libCount++;
          if (libCount >= maxCount) return libCount;
        }
        continue;
      }
      stack.add(nidx);
    }
  }
  return libCount;
}

// ---------------------------------------------------------------------------
// Star points / hoshis.
// ---------------------------------------------------------------------------

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

// ---------------------------------------------------------------------------
// Pattern matching (shape and corner).
// ---------------------------------------------------------------------------

/// Yields every match of [pattern] anchored at `(anchor)` on [m].
Iterable<PatternMatch> _matchShape(
    _SignMap m, Vertex anchor, Pattern pattern) sync* {
  final width = m.width;
  final height = m.height;
  if (!m.inBounds(anchor.x, anchor.y)) return;
  if (pattern.size != null &&
      (width != height || width != pattern.size)) {
    return;
  }

  final anchorSign = m.at(anchor.x, anchor.y);
  if (anchorSign == 0) return;

  for (final pa in pattern.anchors) {
    if (pattern.isCorner) {
      final sym = _boardSymmetries(pa.vertex.x, pa.vertex.y, width, height);
      var ok = false;
      for (var i = 0; i < 8; i++) {
        final v = sym[i];
        if (v != null && v.x == anchor.x && v.y == anchor.y) {
          ok = true;
          break;
        }
      }
      if (!ok) continue;
    }

    // Bitfield of the 8 still-viable hypotheses.
    var hypotheses = 0xFF;

    for (final pv in pattern.vertices) {
      final dx = pv.vertex.x - pa.vertex.x;
      final dy = pv.vertex.y - pa.vertex.y;
      final expected = pv.sign * anchorSign * pa.sign;

      var bit = 1;
      for (var k = 0; k < 8; k++, bit <<= 1) {
        if ((hypotheses & bit) == 0) continue;
        final wx = anchor.x + _symX(k, dx, dy);
        final wy = anchor.y + _symY(k, dx, dy);
        if (wx < 0 || wy < 0 || wx >= width || wy >= height ||
            m.data[wy * width + wx] != expected) {
          hypotheses &= ~bit;
        }
      }

      if (hypotheses == 0) break;
    }

    if (hypotheses == 0) continue;

    final invert = anchorSign != pa.sign;
    var bit = 1;
    for (var k = 0; k < 8; k++, bit <<= 1) {
      if ((hypotheses & bit) == 0) continue;
      yield PatternMatch(
        symmetryIndex: k,
        invert: invert,
        anchors: [
          for (final a in pattern.anchors)
            (
              x: anchor.x + _symX(k, a.vertex.x - pa.vertex.x,
                  a.vertex.y - pa.vertex.y),
              y: anchor.y + _symY(k, a.vertex.x - pa.vertex.x,
                  a.vertex.y - pa.vertex.y),
            ),
        ],
        vertices: [
          for (final v in pattern.vertices)
            (
              x: anchor.x + _symX(k, v.vertex.x - pa.vertex.x,
                  v.vertex.y - pa.vertex.y),
              y: anchor.y + _symY(k, v.vertex.x - pa.vertex.x,
                  v.vertex.y - pa.vertex.y),
            ),
        ],
      );
    }
  }
}

/// Yields every corner-symmetric match of [pattern] on [m].
Iterable<PatternMatch> _matchCorner(_SignMap m, Pattern pattern) sync* {
  final width = m.width;
  final height = m.height;
  if (pattern.size != null &&
      (width != height || width != pattern.size)) {
    return;
  }

  var hypotheses = 0xFF;
  var hypothesesInvert = 0xFF;

  void filter(SignedVertex sv) {
    final sym = _boardSymmetries(sv.vertex.x, sv.vertex.y, width, height);
    var bit = 1;
    for (var i = 0; i < 8; i++, bit <<= 1) {
      final v = sym[i];
      if (v == null) {
        hypotheses &= ~bit;
        hypothesesInvert &= ~bit;
        continue;
      }
      final cell = m.at(v.x, v.y);
      if ((hypotheses & bit) != 0 && cell != sv.sign) hypotheses &= ~bit;
      if ((hypothesesInvert & bit) != 0 && cell != -sv.sign) {
        hypothesesInvert &= ~bit;
      }
    }
  }

  for (final sv in pattern.anchors) {
    filter(sv);
    if (hypotheses == 0 && hypothesesInvert == 0) return;
  }
  for (final sv in pattern.vertices) {
    filter(sv);
    if (hypotheses == 0 && hypothesesInvert == 0) return;
  }

  for (var invertBit = 0; invertBit <= 1; invertBit++) {
    final mask = invertBit == 0 ? hypotheses : hypothesesInvert;
    if (mask == 0) continue;
    var bit = 1;
    for (var i = 0; i < 8; i++, bit <<= 1) {
      if ((mask & bit) == 0) continue;
      yield PatternMatch(
        symmetryIndex: i,
        invert: invertBit == 1,
        anchors: [
          for (final a in pattern.anchors)
            _boardSymmetries(a.vertex.x, a.vertex.y, width, height)[i]!,
        ],
        vertices: [
          for (final v in pattern.vertices)
            _boardSymmetries(v.vertex.x, v.vertex.y, width, height)[i]!,
        ],
      );
    }
  }
}

// ---------------------------------------------------------------------------
// Public API.
// ---------------------------------------------------------------------------

/// Pattern and shape matching on a [Board].
///
/// Built around an embedded version of Sabaki's curated 58-pattern
/// opening library (Chinese, Orthodox, Kobayashi, Shusaku, sanrensei,
/// common joseki, etc.) plus a small [extendedLibrary] of golo
/// additions (Crosscut, Monkey Jump, Cap). Use [defaultLibrary],
/// [extendedLibrary], or [combinedLibrary] (the default for
/// [nameMove] / [findPatternInMove]), or pass your own `List<Pattern>`.
class BoardMatcher {
  BoardMatcher._();

  static List<Pattern>? _defaultLibrary;
  static List<Pattern>? _combinedLibrary;

  /// The 58-pattern opening library shipped with the package, sourced
  /// verbatim from `@sabaki/boardmatcher`. Loaded lazily on first use;
  /// the returned list (and each [Pattern]'s `anchors` / `vertices`) is
  /// unmodifiable so callers can't corrupt the cached singleton.
  static List<Pattern> get defaultLibrary {
    return _defaultLibrary ??= List.unmodifiable(
      (jsonDecode(defaultLibraryJson) as List)
          .map((e) => Pattern.fromJson(e as Map<String, dynamic>)),
    );
  }

  /// Extra shape patterns that go beyond Sabaki's library but are
  /// commonly named by Go players.
  ///
  /// - `Crosscut`: two stones of each colour cutting on a 2×2 square.
  /// - `Monkey Jump`: 3-1 jump from the second line to the first line
  ///   along a corner edge (`type: 'corner'`, size 19).
  /// - `Cap`: friendly stone played one space toward the centre from
  ///   an opponent stone (one-point jump apart, opposite colours).
  static const List<Pattern> extendedLibrary = [
    Pattern(
      name: 'Crosscut',
      url: 'https://senseis.xmp.net/?Crosscut',
      anchors: [(vertex: (x: 3, y: 3), sign: 1)],
      vertices: [
        (vertex: (x: 3, y: 3), sign: 1),
        (vertex: (x: 4, y: 4), sign: 1),
        (vertex: (x: 4, y: 3), sign: -1),
        (vertex: (x: 3, y: 4), sign: -1),
      ],
    ),
    Pattern(
      name: 'Monkey Jump',
      url: 'https://senseis.xmp.net/?MonkeyJump',
      type: 'corner',
      size: 19,
      // Anchors deliberately avoid the literal corner cell (e.g.
      // (18, 0)) — under corner symmetry it folds to (0, 0) and the
      // shape becomes unmatchable. Both anchors live one off the edge.
      anchors: [
        (vertex: (x: 14, y: 1), sign: 1),
        (vertex: (x: 17, y: 0), sign: 1),
      ],
      vertices: [
        (vertex: (x: 14, y: 1), sign: 1),
        (vertex: (x: 17, y: 0), sign: 1),
        (vertex: (x: 15, y: 0), sign: 0),
        (vertex: (x: 16, y: 0), sign: 0),
        (vertex: (x: 15, y: 1), sign: 0),
        (vertex: (x: 16, y: 1), sign: 0),
        (vertex: (x: 17, y: 1), sign: 0),
      ],
    ),
    Pattern(
      name: 'Cap',
      url: 'https://senseis.xmp.net/?Boshi',
      anchors: [(vertex: (x: 3, y: 5), sign: 1)],
      vertices: [
        (vertex: (x: 3, y: 5), sign: 1),
        (vertex: (x: 3, y: 4), sign: 0),
        (vertex: (x: 3, y: 3), sign: -1),
        (vertex: (x: 2, y: 4), sign: 0),
        (vertex: (x: 4, y: 4), sign: 0),
        (vertex: (x: 2, y: 5), sign: 0),
        (vertex: (x: 4, y: 5), sign: 0),
      ],
    ),
  ];

  /// [extendedLibrary] followed by [defaultLibrary]. This is the
  /// library [nameMove] / [findPatternInMove] use unless overridden.
  ///
  /// Extensions go first so the more specific names take precedence —
  /// e.g. a corner-area `Monkey Jump` is reported as such rather than
  /// the generic `Large Knight` shape it shares geometry with, and a
  /// 2×2 alternating cut is reported as `Crosscut` rather than `Cut`.
  static List<Pattern> get combinedLibrary {
    return _combinedLibrary ??= List.unmodifiable(
      [...extendedLibrary, ...defaultLibrary],
    );
  }

  /// Yields every corner-style match of [pattern] on [board].
  static Iterable<PatternMatch> matchCorner(Board board, Pattern pattern) =>
      _matchCorner(_SignMap.fromBoard(board), pattern);

  /// Yields every match of [pattern] on [board] for which [anchor]
  /// corresponds to one of the pattern's anchors.
  static Iterable<PatternMatch> matchShape(
          Board board, Vertex anchor, Pattern pattern) =>
      _matchShape(_SignMap.fromBoard(board), anchor, pattern);

  /// Names a candidate move at [vertex] played by [stone].
  ///
  /// Returns one of: `Pass`, `Take`, `Atari`, `Self-Atari`, `Suicide`,
  /// `Fill`, `Connect`, any [Pattern.name] from [library] (defaults to
  /// [combinedLibrary]), `Tengen`, `Hoshi`, or `null` if the move can't
  /// be classified.
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
    final sign = stone == null
        ? 0
        : (stone == Stone.black ? 1 : -1);
    final isPass = sign == 0 ||
        vertex == null ||
        vertex.x < 0 ||
        vertex.y < 0 ||
        vertex.x >= width ||
        vertex.y >= height;

    FoundPattern synth(String name, [String? url]) {
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

    if (isPass) return synth('Pass', 'https://senseis.xmp.net/?Pass');

    final v = vertex;
    final m = _SignMap.fromBoard(board);
    if (m.at(v.x, v.y) != 0) return null;

    // Inspect the four neighbours once.
    final neighborSigns = <int>[];
    final friendlyNeighbors = <int>[];
    final enemyNeighbors = <int>[];
    for (var dir = 0; dir < 4; dir++) {
      final nx = v.x + (dir == 0 ? -1 : dir == 1 ? 1 : 0);
      final ny = v.y + (dir == 2 ? -1 : dir == 3 ? 1 : 0);
      if (nx < 0 || ny < 0 || nx >= width || ny >= height) continue;
      final s = m.at(nx, ny);
      neighborSigns.add(s);
      if (s == sign) friendlyNeighbors.add(ny * width + nx);
      if (s == -sign) enemyNeighbors.add(ny * width + nx);
    }

    // Take / Atari on enemy chains.
    var anyTake = false;
    for (final p in enemyNeighbors) {
      final libs = _countLiberties(m, p % width, p ~/ width, 3);
      if (libs == 1) {
        anyTake = true;
        break;
      }
    }
    if (anyTake) return synth('Take');

    var anyAtari = false;
    for (final p in enemyNeighbors) {
      final libs = _countLiberties(m, p % width, p ~/ width, 3);
      if (libs == 2) {
        anyAtari = true;
        break;
      }
    }
    if (anyAtari) return synth('Atari', 'https://senseis.xmp.net/?Atari');

    // Hypothetical post-move sign map. Captures are handled by removing
    // any enemy chain with zero liberties after the stone is placed.
    final next = m.clone();
    next.set(v.x, v.y, sign);
    var capturedAny = false;
    for (final p in enemyNeighbors) {
      final ex = p % width;
      final ey = p ~/ width;
      if (next.at(ex, ey) != -sign) continue; // already removed
      if (_countLiberties(next, ex, ey, 1) == 0) {
        capturedAny = true;
        _floodClear(next, ex, ey);
      }
    }

    final ownLibsAfter = _countLiberties(next, v.x, v.y, 3);
    if (!capturedAny && ownLibsAfter == 0) {
      return synth('Suicide', 'https://senseis.xmp.net/?Suicide');
    }
    if (ownLibsAfter == 1) {
      return synth('Self-Atari', 'https://senseis.xmp.net/?SelfAtari');
    }

    if (friendlyNeighbors.length == neighborSigns.length &&
        neighborSigns.isNotEmpty) {
      return synth('Fill');
    }
    if (friendlyNeighbors.length >= 2) return synth('Connect');

    // Library pattern.
    final lib = library ?? combinedLibrary;
    for (final pattern in lib) {
      for (final match in _matchShape(next, v, pattern)) {
        return FoundPattern(pattern, match);
      }
    }

    // Hoshi / Tengen on an empty point.
    if (width.isOdd && height.isOdd) {
      final midX = (width - 1) >> 1;
      final midY = (height - 1) >> 1;
      if (v.x == midX && v.y == midY) {
        return synth('Tengen', 'https://senseis.xmp.net/?Tengen');
      }
    }
    for (final h in _unnamedHoshis(width, height)) {
      if (h.x == v.x && h.y == v.y) {
        return synth('Hoshi', 'https://senseis.xmp.net/?StarPoint');
      }
    }

    return null;
  }

  /// Yields every match of every pattern in [library] (defaults to
  /// [defaultLibrary]) on [board], paired with the pattern that produced
  /// it. Useful for one-shot board analysis.
  static Iterable<FoundPattern> findAllPatterns(
    Board board, {
    List<Pattern>? library,
  }) sync* {
    final m = _SignMap.fromBoard(board);
    final lib = library ?? combinedLibrary;
    for (final pattern in lib) {
      if (pattern.isCorner) {
        for (final match in _matchCorner(m, pattern)) {
          yield FoundPattern(pattern, match);
        }
      } else {
        // Translation-invariant: try every non-empty cell as anchor.
        for (var y = 0; y < m.height; y++) {
          for (var x = 0; x < m.width; x++) {
            if (m.at(x, y) == 0) continue;
            for (final match in _matchShape(m, (x: x, y: y), pattern)) {
              yield FoundPattern(pattern, match);
            }
          }
        }
      }
    }
  }
}

/// Iteratively zero out the connected chain starting at `(x, y)`.
void _floodClear(_SignMap m, int x, int y) {
  final width = m.width;
  final height = m.height;
  final start = y * width + x;
  final sign = m.data[start];
  if (sign == 0) return;
  final stack = <int>[start];
  m.data[start] = 0;
  while (stack.isNotEmpty) {
    final p = stack.removeLast();
    final px = p % width;
    final py = p ~/ width;
    for (var dir = 0; dir < 4; dir++) {
      int nx, ny;
      switch (dir) {
        case 0:
          nx = px - 1;
          ny = py;
          break;
        case 1:
          nx = px + 1;
          ny = py;
          break;
        case 2:
          nx = px;
          ny = py - 1;
          break;
        default:
          nx = px;
          ny = py + 1;
      }
      if (nx < 0 || ny < 0 || nx >= width || ny >= height) continue;
      final nidx = ny * width + nx;
      if (m.data[nidx] != sign) continue;
      m.data[nidx] = 0;
      stack.add(nidx);
    }
  }
}

/// Returns [Pattern.name] translated into [locale] via
/// [MoveLocalizations]. `null` if the pattern is unnamed.
extension PatternLocalization on Pattern {
  String? localizedName(String locale) {
    final n = name;
    return n == null ? null : MoveLocalizations.of(locale).translate(n);
  }
}

/// Convenience shortcuts for [BoardMatcher] on a [Board].
extension BoardMatching on Board {
  /// See [BoardMatcher.nameMove].
  String? nameMove(Stone? stone, Vertex? vertex, {List<Pattern>? library}) =>
      BoardMatcher.nameMove(this, stone, vertex, library: library);

  /// See [BoardMatcher.findPatternInMove].
  FoundPattern? findPatternInMove(Stone? stone, Vertex? vertex,
          {List<Pattern>? library}) =>
      BoardMatcher.findPatternInMove(this, stone, vertex, library: library);

  /// See [BoardMatcher.matchShape].
  Iterable<PatternMatch> matchShape(Vertex anchor, Pattern pattern) =>
      BoardMatcher.matchShape(this, anchor, pattern);

  /// See [BoardMatcher.matchCorner].
  Iterable<PatternMatch> matchCorner(Pattern pattern) =>
      BoardMatcher.matchCorner(this, pattern);

  /// See [BoardMatcher.findAllPatterns].
  Iterable<FoundPattern> findAllPatterns({List<Pattern>? library}) =>
      BoardMatcher.findAllPatterns(this, library: library);
}
