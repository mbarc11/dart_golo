// Loads an SGF, walks to the final position, and prints area/estimator
// territory maps and Chinese/Japanese scores.
//
//   dart run example/score_sgf.dart [path/to/game.sgf] [--interactive]
//
// With --interactive (or -i), drops into a REPL where you can click-toggle
// dead stones by typing coordinates (e.g. `D4`) — same workflow as Sabaki's
// scoring mode.

import 'dart:io';

import 'package:golo/golo.dart';

const _defaultPath = 'example/sgf/test1.sgf';

void main(List<String> args) async {
  final positional = args.where((a) => !a.startsWith('-')).toList();
  final interactive =
      args.contains('--interactive') || args.contains('-i');
  final path = positional.isNotEmpty ? positional.first : _defaultPath;
  final file = File(path);
  if (!file.existsSync()) {
    stderr.writeln('SGF file not found: $path');
    exitCode = 2;
    return;
  }

  final text = await file.readAsString();
  late final Game game;
  try {
    game = Game.fromSgf(text);
  } catch (e) {
    stderr.writeln('Failed to parse SGF: $e');
    exitCode = 1;
    return;
  }

  final komi = double.tryParse(game.komi ?? '') ?? 0;
  final handicap = int.tryParse(game.handicap ?? '') ?? 0;
  final board = game.board;

  stdout.writeln('SGF: $path');
  if (game.playerBlack != null || game.playerWhite != null) {
    stdout.writeln('Black: ${game.playerBlack ?? '?'}'
        '   White: ${game.playerWhite ?? '?'}');
  }
  if (game.result != null) {
    stdout.writeln('SGF result: ${game.result}');
  }
  stdout.writeln('Komi: $komi   Handicap: $handicap');
  stdout.writeln();

  stdout.writeln('Final position:');
  stdout.writeln(board);

  // 1. Strict area map (Japanese-style territory, dame as 0)
  final am = Scorer.boardAreaMap(board);
  stdout.writeln('Strict area map (territory, dame as `.`):');
  _printOverlay(board, am);
  final strict = Scorer.finalScore(board, komi: komi, handicap: handicap);
  stdout.writeln(strict);
  _printResultLine('Strict (no dead-stone removal)', strict);
  stdout.writeln();

  // 2. Influence-based estimator
  final est = Scorer.estimate(board);
  stdout.writeln('Influence estimator map:');
  _printOverlay(board, est);
  final estimated =
      Scorer.estimateScore(board, komi: komi, handicap: handicap);
  stdout.writeln(estimated);
  _printResultLine('Estimator', estimated);
  stdout.writeln();

  // 3. Monte-Carlo dead-stone detection + final score.
  final settled = Scorer.settleForScoring(board, seed: 42);
  stdout.writeln('Monte-Carlo dead stones (${settled.dead.length}):');
  if (settled.dead.isEmpty) {
    stdout.writeln('  (none)');
  } else {
    final coords = settled.dead.map(board.stringifyVertex).toList()..sort();
    stdout.writeln('  ${coords.join(', ')}');
  }
  stdout.writeln();

  stdout.writeln('Board after MCTS dead-stone removal:');
  stdout.writeln(settled.cleaned);
  _printOverlay(settled.cleaned, Scorer.boardAreaMap(settled.cleaned));
  final endgame = Scorer.scoreEndgame(
    board,
    komi: komi,
    handicap: handicap,
    seed: 42,
  );
  stdout.writeln(endgame);
  _printResultLine('After MCTS dead-stone removal', endgame);

  if (interactive) {
    _runInteractive(board, settled.dead.toSet(), komi, handicap);
  }
}

/// Click-to-mark REPL. Mirrors Sabaki's scoring-mode UX in plain text.
void _runInteractive(
  Board board,
  Set<Vertex> initialDead,
  double komi,
  int handicap,
) {
  var dead = initialDead;

  void render() {
    stdout.writeln();
    stdout.writeln('--- click-to-mark mode ---');
    _printDeadOverlay(board, dead);
    final s = Scorer.scoreWithDeadStones(
      board,
      dead,
      komi: komi,
      handicap: handicap,
    );
    stdout.writeln(s);
    _printResultLine('Current score', s);
    stdout.writeln(
        '${dead.length} dead stones marked. Type a coordinate (e.g. D4) '
        'to toggle a group, "reset" to clear, "auto" to refresh from MCTS, '
        '"q" to quit.');
  }

  render();
  while (true) {
    stdout.write('> ');
    final line = stdin.readLineSync()?.trim();
    if (line == null || line.isEmpty) continue;
    if (line == 'q' || line == 'quit' || line == 'exit') break;
    if (line == 'reset') {
      dead = <Vertex>{};
      render();
      continue;
    }
    if (line == 'auto') {
      dead = Scorer.guessDeadStones(board).toSet();
      render();
      continue;
    }

    final v = board.parseVertex(line);
    if (v == null) {
      stdout.writeln('Unrecognised coordinate: "$line"');
      continue;
    }
    if (board.get(v) == null) {
      stdout.writeln('No stone at ${board.stringifyVertex(v)}.');
      continue;
    }
    dead = Scorer.toggleDeadGroup(dead, board, v);
    render();
  }
}

/// Same shape as [_printOverlay] but draws stones with `x`/`o` (lowercase)
/// when they're in the [dead] set, so the user can see what they marked.
void _printDeadOverlay(Board board, Set<Vertex> dead) {
  final width = board.width;
  final height = board.height;
  final labelWidth = height.toString().length;

  String header() {
    final buf = StringBuffer(' ' * (labelWidth + 1));
    for (var x = 0; x < width; x++) {
      buf.write(Board.alpha[x]);
      if (x != width - 1) buf.write(' ');
    }
    return buf.toString();
  }

  stdout.writeln(header());
  for (var y = 0; y < height; y++) {
    final rowLabel = (height - y).toString().padLeft(labelWidth);
    stdout.write('$rowLabel ');
    for (var x = 0; x < width; x++) {
      final v = (x: x, y: y);
      final stone = board.get(v);
      final glyph = stone == null
          ? '.'
          : dead.contains(v)
              ? (stone == Stone.black ? 'x' : 'o')
              : (stone == Stone.black ? 'X' : 'O');
      stdout.write(glyph);
      if (x != width - 1) stdout.write(' ');
    }
    stdout.writeln(' $rowLabel');
  }
  stdout.writeln(header());
}

/// Prints a board-shaped overlay where each cell shows either the original
/// stone glyph or, for empty cells, the territory sign from [overlay].
void _printOverlay(Board board, List<List<int>> overlay) {
  final width = board.width;
  final height = board.height;
  final labelWidth = height.toString().length;

  String header() {
    final buf = StringBuffer(' ' * (labelWidth + 1));
    for (var x = 0; x < width; x++) {
      buf.write(Board.alpha[x]);
      if (x != width - 1) buf.write(' ');
    }
    return buf.toString();
  }

  stdout.writeln(header());
  for (var y = 0; y < height; y++) {
    final rowLabel = (height - y).toString().padLeft(labelWidth);
    stdout.write('$rowLabel ');
    for (var x = 0; x < width; x++) {
      final stone = board.get((x: x, y: y));
      final glyph = stone == null
          ? (overlay[y][x] > 0 ? 'b' : overlay[y][x] < 0 ? 'w' : '.')
          : (stone == Stone.black ? 'X' : 'O');
      stdout.write(glyph);
      if (x != width - 1) stdout.write(' ');
    }
    stdout.writeln(' $rowLabel');
  }
  stdout.writeln(header());
}

void _printResultLine(String label, Score s) {
  String fmt(double d) {
    final sign = d > 0 ? 'B+' : d < 0 ? 'W+' : 'Jigo ';
    final mag = d.abs();
    final str = mag == mag.roundToDouble()
        ? mag.toStringAsFixed(0)
        : mag.toStringAsFixed(1);
    return d == 0 ? sign.trim() : '$sign$str';
  }

  stdout.writeln(
      '$label  → area (Chinese): ${fmt(s.areaScore)}   territory (Japanese): ${fmt(s.territoryScore)}');
}
