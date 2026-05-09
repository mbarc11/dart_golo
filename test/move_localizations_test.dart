import 'dart:convert';
import 'dart:io';

import 'package:golo/golo.dart';
import 'package:test/test.dart';

void main() {
  group('MoveLocalizations.of', () {
    test('returns matching locale instance', () {
      expect(MoveLocalizations.of('ja').locale, 'ja');
      expect(MoveLocalizations.of('ko').locale, 'ko');
      expect(MoveLocalizations.of('zh').locale, 'zh');
      expect(MoveLocalizations.of('zh_HK').locale, 'zh_HK');
      expect(MoveLocalizations.of('zh_TW').locale, 'zh_TW');
    });

    test('falls back from BCP-47 dash form (zh-HK -> zh_HK)', () {
      expect(MoveLocalizations.of('zh-HK').locale, 'zh_HK');
    });

    test('falls back to base locale (zh_CN -> zh)', () {
      expect(MoveLocalizations.of('zh_CN').locale, 'zh');
    });

    test('falls back to English on unknown locale', () {
      expect(MoveLocalizations.of('xx_YY').locale, 'en');
    });
  });

  group('MoveLocalizations.translate', () {
    test('Japanese covers core moves', () {
      final ja = MoveLocalizations.of('ja');
      expect(ja.translate('Pass'), 'パス');
      expect(ja.translate('Atari'), 'アタリ');
      expect(ja.translate('Self-Atari'), '自アタリ');
      expect(ja.translate('Tengen'), '天元');
      expect(ja.translate('Hoshi'), '星');
      expect(ja.translate('4-4 Point'), '星');
      expect(ja.translate('3-3 Point'), '三々');
      expect(ja.translate('Hane'), 'ハネ');
      expect(ja.translate('Crosscut'), '切り違い');
      expect(ja.translate('Monkey Jump'), 'サルスベリ');
    });

    test('Korean covers core moves', () {
      final ko = MoveLocalizations.of('ko');
      expect(ko.translate('Pass'), '패스');
      expect(ko.translate('Atari'), '단수');
      expect(ko.translate('Self-Atari'), '자단수');
      expect(ko.translate('Tengen'), '천원');
      expect(ko.translate('4-4 Point'), '화점');
    });

    test('Simplified Chinese covers core moves', () {
      final zh = MoveLocalizations.of('zh');
      expect(zh.translate('Pass'), '弃权');
      expect(zh.translate('Atari'), '打吃');
      expect(zh.translate('Self-Atari'), '自打');
      expect(zh.translate('4-4 Point'), '星位');
    });

    test('Traditional Chinese (HK/TW) uses traditional characters', () {
      expect(MoveLocalizations.of('zh_HK').translate('Pass'), '棄權');
      expect(MoveLocalizations.of('zh_TW').translate('Pass'), '棄權');
      expect(MoveLocalizations.of('zh_HK').translate('Suicide'), '自殺');
      expect(MoveLocalizations.of('zh_TW').translate('Suicide'), '自殺');
    });

    test('falls back to canonical name for unknown keys', () {
      final ja = MoveLocalizations.of('ja');
      expect(ja.translate('Some Made Up Pattern'), 'Some Made Up Pattern');
    });

    test('translateOrNull preserves null', () {
      expect(MoveLocalizations.of('ja').translateOrNull(null), isNull);
      expect(MoveLocalizations.of('ja').translateOrNull('Atari'), 'アタリ');
    });
  });

  group('Pattern.localizedName', () {
    test('returns translated Pattern.name', () {
      final stretch =
          BoardMatcher.defaultLibrary.firstWhere((p) => p.name == 'Stretch');
      expect(stretch.localizedName('ja'), 'ノビ');
      expect(stretch.localizedName('en'), 'Stretch');
    });

    test('returns null for unnamed patterns', () {
      const unnamed = Pattern(vertices: []);
      expect(unnamed.localizedName('ja'), isNull);
    });
  });

  group('ARB ↔ Dart consistency', () {
    Map<String, String> readArb(String locale) {
      final raw = File('lib/l10n/app_$locale.arb').readAsStringSync();
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return {
        for (final entry in json.entries)
          if (!entry.key.startsWith('@'))
            entry.key: entry.value as String,
      };
    }

    for (final locale in MoveLocalizations.supportedLocales) {
      test('ARB matches MoveLocalizations for $locale', () {
        final arb = readArb(locale);
        final dart = {
          for (final key in MoveLocalizations.of(locale).knownTerms)
            key: MoveLocalizations.of(locale).translate(key),
        };
        expect(dart, equals(arb),
            reason: 'lib/l10n/app_$locale.arb has drifted from '
                'lib/src/move_localizations.dart');
      });
    }

    test('every supported locale ARB exists', () {
      for (final locale in MoveLocalizations.supportedLocales) {
        expect(File('lib/l10n/app_$locale.arb').existsSync(), isTrue,
            reason: 'missing lib/l10n/app_$locale.arb');
      }
    });
  });

  group('coverage', () {
    test('every library pattern name has an English entry', () {
      final en = MoveLocalizations.of('en');
      for (final p in BoardMatcher.combinedLibrary) {
        final name = p.name;
        if (name == null) continue;
        expect(en.knownTerms, contains(name),
            reason: 'missing English entry for "$name"');
      }
    });
  });
}
