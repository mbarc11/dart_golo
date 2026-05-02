// Pinned to Sabaki's @sabaki/boardmatcher reference fixtures.
//
// Source data + expectations:
//   https://github.com/SabakiHQ/boardmatcher/blob/master/tests/data.js
//   https://github.com/SabakiHQ/boardmatcher/blob/master/tests/nameMove.test.js
//   https://github.com/SabakiHQ/boardmatcher/blob/master/tests/matchPattern.test.js

import 'package:golo/golo.dart';
import 'package:test/test.dart';

Board _board(List<List<int>> signs) {
  return Board(signs.map((row) => row.map<Stone?>((s) {
    if (s == 0) return null;
    if (s == 1) return Stone.black;
    return Stone.white;
  }).toList()).toList());
}

Vertex _v(int x, int y) => (x: x, y: y);

void main() {
  group('BoardMatcher.nameMove (Sabaki fixtures)', () {
    final unfinished = _board(_unfinished);
    final empty = _board(_empty);

    test('passes', () {
      expect(BoardMatcher.nameMove(unfinished, Stone.black, _v(-1, -1)),
          'Pass');
      expect(BoardMatcher.nameMove(unfinished, Stone.white, _v(-1, -1)),
          'Pass');
      expect(BoardMatcher.nameMove(unfinished, null, _v(0, 0)), 'Pass');
      expect(BoardMatcher.nameMove(unfinished, Stone.black, _v(19, 19)),
          'Pass');
      expect(BoardMatcher.nameMove(unfinished, Stone.black, null), 'Pass');
    });

    test('suicides', () {
      expect(BoardMatcher.nameMove(unfinished, Stone.black, _v(0, 0)),
          'Suicide');
      expect(BoardMatcher.nameMove(unfinished, Stone.black, _v(1, 5)),
          'Suicide');
      expect(BoardMatcher.nameMove(unfinished, Stone.black, _v(0, 4)),
          'Suicide');
    });

    test('takes', () {
      expect(BoardMatcher.nameMove(unfinished, Stone.white, _v(0, 0)),
          'Take');
      expect(BoardMatcher.nameMove(unfinished, Stone.black, _v(14, 15)),
          'Take');
      expect(BoardMatcher.nameMove(unfinished, Stone.white, _v(2, 7)),
          'Take');
    });

    test('distinguishes between suicides and takes', () {
      // Same custom mutation as Sabaki's test.
      final custom = _unfinished.map((row) => List<int>.from(row)).toList();
      custom[6][12] = 1;
      custom[8][12] = 1;
      custom[7][13] = 1;
      expect(BoardMatcher.nameMove(_board(custom), Stone.white, _v(12, 7)),
          'Take');
    });

    test('ataris', () {
      expect(BoardMatcher.nameMove(unfinished, Stone.white, _v(17, 15)),
          'Atari');
      expect(BoardMatcher.nameMove(unfinished, Stone.black, _v(18, 15)),
          'Atari');
      expect(BoardMatcher.nameMove(unfinished, Stone.black, _v(15, 2)),
          'Atari');
      expect(BoardMatcher.nameMove(unfinished, Stone.black, _v(3, 3)),
          'Atari');
    });

    test('fills', () {
      expect(BoardMatcher.nameMove(unfinished, Stone.white, _v(0, 4)),
          'Fill');
      expect(BoardMatcher.nameMove(unfinished, Stone.white, _v(1, 5)),
          'Fill');
    });

    test('connections', () {
      expect(BoardMatcher.nameMove(unfinished, Stone.white, _v(1, 2)),
          'Connect');
      expect(BoardMatcher.nameMove(unfinished, Stone.white, _v(1, 12)),
          'Connect');
      expect(BoardMatcher.nameMove(unfinished, Stone.black, _v(12, 15)),
          'Connect');
    });

    test('library shapes', () {
      expect(BoardMatcher.nameMove(unfinished, Stone.black, _v(7, 1)),
          'Stretch');
      expect(BoardMatcher.nameMove(unfinished, Stone.black, _v(10, 16)),
          'Cut');
    });

    test('hoshis', () {
      expect(BoardMatcher.nameMove(empty, Stone.white, _v(9, 9)), 'Tengen');
      expect(BoardMatcher.nameMove(empty, Stone.white, _v(9, 3)), 'Hoshi');
      expect(BoardMatcher.nameMove(empty, Stone.black, _v(9, 15)), 'Hoshi');
      expect(BoardMatcher.nameMove(empty, Stone.black, _v(3, 3)),
          '4-4 Point');
      expect(BoardMatcher.nameMove(empty, Stone.black, _v(15, 15)),
          '4-4 Point');
    });
  });

  group('BoardMatcher.matchShape (Sabaki fixtures)', () {
    final unfinished = _board(_unfinished);

    final pattern = const Pattern(
      anchors: [
        (vertex: (x: 0, y: 2), sign: 1),
        (vertex: (x: 2, y: 2), sign: 1),
      ],
      vertices: [
        (vertex: (x: 1, y: 1), sign: 1),
        (vertex: (x: 2, y: 1), sign: 0),
        (vertex: (x: 1, y: 2), sign: 0),
      ],
    );

    test('matches symmetric instances at (14, 2)', () {
      final matches =
          BoardMatcher.matchShape(unfinished, _v(14, 2), pattern).toList();
      final indices = matches.map((m) => m.symmetryIndex).toList()..sort();
      expect(indices, [3, 7]);

      // First match's anchors and vertices match the JS reference.
      expect(matches[0].anchors, [_v(16, 2), _v(14, 2)]);
      expect(matches[0].vertices, [_v(15, 3), _v(14, 3), _v(15, 2)]);
    });

    test('matches symmetric instances at (0, 5)', () {
      final matches =
          BoardMatcher.matchShape(unfinished, _v(0, 5), pattern).toList();
      final indices = matches.map((m) => m.symmetryIndex).toList()..sort();
      expect(indices, [0, 1, 5, 7]);
    });

    test('respects size property', () {
      final sized = Pattern(
        size: 13,
        anchors: pattern.anchors,
        vertices: pattern.vertices,
      );
      final matches =
          BoardMatcher.matchShape(unfinished, _v(14, 2), sized).toList();
      expect(matches, isEmpty);
    });

    test('respects corner type', () {
      final corner = Pattern(
        type: 'corner',
        anchors: pattern.anchors,
        vertices: pattern.vertices,
      );
      // (0,2)/(2,2) anchors don't map to (14,2) under board symmetries
      // on a 19x19 — Sabaki expects no matches here.
      expect(
          BoardMatcher.matchShape(unfinished, _v(14, 2), corner).toList(),
          isEmpty);

      final corner2 = const Pattern(
        type: 'corner',
        anchors: [
          (vertex: (x: 2, y: 2), sign: 1),
          (vertex: (x: 4, y: 2), sign: 1),
        ],
        vertices: [
          (vertex: (x: 3, y: 3), sign: 1),
          (vertex: (x: 3, y: 2), sign: 0),
          (vertex: (x: 4, y: 3), sign: 0),
        ],
      );
      final matches =
          BoardMatcher.matchShape(unfinished, _v(14, 2), corner2).toList();
      final indices = matches.map((m) => m.symmetryIndex).toList()..sort();
      expect(indices, [1, 6]);
    });
  });

  group('BoardMatcher.defaultLibrary', () {
    test('parses Sabaki\'s 58-pattern library lazily', () {
      final lib = BoardMatcher.defaultLibrary;
      expect(lib.length, 58);
      expect(lib.first.name, 'Low Chinese Opening');
      // Caching: subsequent access returns the same instance.
      expect(identical(lib, BoardMatcher.defaultLibrary), isTrue);
    });
  });
}

// Verbatim copies of fixtures from
// https://github.com/SabakiHQ/boardmatcher/blob/master/tests/data.js

final _unfinished = <List<int>>[
  [0, -1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
  [1, -1, -1, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, -1, 0, 0],
  [-1, 0, -1, -1, 1, 1, 0, 1, 0, 1, 1, 0, -1, 0, -1, 0, -1, 1, 0],
  [-1, 0, 0, 0, -1, -1, -1, 1, 0, -1, 0, 0, 0, 0, 0, -1, 1, 0, 0],
  [0, -1, 0, -1, 1, 1, 1, -1, -1, 0, 0, -1, 0, 0, -1, 1, 1, 0, 0],
  [-1, 0, -1, -1, 0, 0, 0, -1, 0, 0, -1, 0, 0, 0, -1, 1, 0, 1, 0],
  [-1, -1, 1, -1, 1, 1, 1, -1, 0, 1, 1, -1, 0, 0, 1, 1, -1, 0, 0],
  [0, 1, 0, -1, 0, -1, 1, -1, 0, 1, -1, 1, 0, 0, 0, 0, -1, 0, 1],
  [0, 0, 0, -1, 0, -1, 1, 1, 0, 1, -1, -1, 0, 0, 0, 1, 1, -1, 0],
  [0, 0, 1, 1, 1, -1, -1, 1, 0, 0, 1, 0, -1, -1, 1, 1, -1, -1, -1],
  [0, -1, -1, -1, 1, 0, 0, 1, 0, 1, 0, 0, -1, 1, 0, 1, 1, -1, 0],
  [0, -1, 1, 1, 1, 1, 0, -1, 1, 0, 0, 0, -1, 1, 0, 0, 1, -1, 0],
  [0, 0, 0, 0, 0, -1, 0, -1, -1, 0, 0, 0, -1, 1, 0, 0, 1, -1, 0],
  [0, -1, -1, 0, -1, 0, 0, 0, 0, 0, 0, 0, -1, -1, 1, 1, -1, -1, 0],
  [0, 0, 1, -1, 0, 0, 0, 0, 0, 0, 0, 0, -1, 1, -1, -1, 1, 1, -1],
  [0, 0, 1, 0, 1, 0, 0, 0, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0, 0],
  [0, 0, 0, 0, 0, 0, 1, 0, -1, 0, 0, -1, 1, 0, 0, 1, 0, 1, 0],
  [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, -1, 1, 1, 0, 0, 0, 0, 0, 0],
  [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
];

final _empty = List.generate(19, (_) => List.filled(19, 0));
