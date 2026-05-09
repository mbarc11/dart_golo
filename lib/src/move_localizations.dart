/// Localized labels for move classifications and library shape names
/// returned by [BoardMatcher.nameMove].
///
/// Translations are keyed by the canonical English name (the value
/// returned by `nameMove` and stored on `Pattern.name`). Locale
/// coverage matches `igo-social-flutter`: `en`, `ja`, `ko`, `zh`,
/// `zh_HK`, `zh_TW`.
///
/// Source ARB files in `lib/l10n/` are the translator-facing copy of
/// the same content; the const maps below are the runtime payload.
/// Keep both in sync (see `tool/regen_move_localizations.dart`).
library;

import 'board_matcher.dart' show BoardMatcher;

/// Lookup table for translated Go move/shape names.
///
/// ```dart
/// final ja = MoveLocalizations.of('ja');
/// ja.translate('Atari');        // 'アタリ'
/// ja.translate('4-4 Point');    // '星'
///
/// // Falls back to the canonical English when a translation is
/// // missing — never throws or returns null.
/// MoveLocalizations.of('zh').translate('Some Custom Pattern');
/// // → 'Some Custom Pattern'
/// ```
class MoveLocalizations {
  /// The locale code this instance serves (e.g. `'ja'`, `'zh_HK'`).
  final String locale;

  /// Map from canonical English name → localized name.
  final Map<String, String> _terms;

  const MoveLocalizations._(this.locale, this._terms);

  /// Returns localizations for [locale], with a two-step fallback:
  ///
  /// 1. Exact match (`'zh_HK'` → Traditional Chinese for Hong Kong).
  /// 2. Base language (`'zh-Hans'`/`'zh_CN'` → Simplified Chinese
  ///    via the `'zh'` base).
  /// 3. English (canonical names — every key resolves to itself).
  ///
  /// Never throws on unknown locales.
  factory MoveLocalizations.of(String locale) {
    // Normalise BCP-47 dashes to underscores so 'zh-HK' and 'zh_HK'
    // both resolve.
    final normalised = locale.replaceAll('-', '_');
    final exact = _registry[normalised];
    if (exact != null) return exact;
    final sep = normalised.indexOf('_');
    if (sep > 0) {
      final base = _registry[normalised.substring(0, sep)];
      if (base != null) return base;
    }
    return _registry['en']!;
  }

  /// Returns the localized term for [canonicalName] (the value on
  /// [Pattern.name] / returned by [BoardMatcher.nameMove]). Falls back
  /// to [canonicalName] itself if no translation exists.
  String translate(String canonicalName) =>
      _terms[canonicalName] ?? canonicalName;

  /// Same as [translate] but returns `null` for `null` input.
  String? translateOrNull(String? canonicalName) =>
      canonicalName == null ? null : translate(canonicalName);

  /// Every canonical English term that has a translation in this
  /// locale. Useful for building term-glossary UI.
  Iterable<String> get knownTerms => _terms.keys;

  /// Locale codes shipped with the package.
  static const supportedLocales = <String>[
    'en',
    'ja',
    'ko',
    'zh',
    'zh_HK',
    'zh_TW',
  ];

  static final Map<String, MoveLocalizations> _registry = {
    'en': const MoveLocalizations._('en', _termsEn),
    'ja': const MoveLocalizations._('ja', _termsJa),
    'ko': const MoveLocalizations._('ko', _termsKo),
    'zh': const MoveLocalizations._('zh', _termsZh),
    // zh_HK and zh_TW share a Traditional Chinese set; refine here
    // when regional differences (rare for Go terminology) are needed.
    'zh_HK': const MoveLocalizations._('zh_HK', _termsZhTrad),
    'zh_TW': const MoveLocalizations._('zh_TW', _termsZhTrad),
  };
}

// ---------------------------------------------------------------------------
// Translation tables. Keep in sync with lib/l10n/app_*.arb.
//
// For terms with no widely-accepted translation in a given language,
// the canonical English string is reused so the API never returns an
// empty/garbled label.
// ---------------------------------------------------------------------------

const Map<String, String> _termsEn = {
  'Pass': 'Pass',
  'Take': 'Take',
  'Atari': 'Atari',
  'Self-Atari': 'Self-Atari',
  'Suicide': 'Suicide',
  'Fill': 'Fill',
  'Connect': 'Connect',
  'Tengen': 'Tengen',
  'Hoshi': 'Hoshi',
  'Low Chinese Opening': 'Low Chinese Opening',
  'High Chinese Opening': 'High Chinese Opening',
  'Orthodox Opening': 'Orthodox Opening',
  'Enclosure Opening': 'Enclosure Opening',
  'Kobayashi Opening': 'Kobayashi Opening',
  'Small Chinese Opening': 'Small Chinese Opening',
  'Micro Chinese Opening': 'Micro Chinese Opening',
  'Sanrensei Opening': 'Sanrensei Opening',
  'Nirensei Opening': 'Nirensei Opening',
  'Shūsaku Opening': 'Shūsaku Opening',
  'Low Approach': 'Low Approach',
  'High Approach': 'High Approach',
  'Low Enclosure': 'Low Enclosure',
  'High Enclosure': 'High Enclosure',
  'Mouth Shape': 'Mouth Shape',
  'Table Shape': 'Table Shape',
  'Tippy Table': 'Tippy Table',
  'Bamboo Joint': 'Bamboo Joint',
  'Trapezium': 'Trapezium',
  'Diamond': 'Diamond',
  'Tiger’s Mouth': 'Tiger’s Mouth',
  'Empty Triangle': 'Empty Triangle',
  'Turn': 'Turn',
  'Stretch': 'Stretch',
  'Diagonal': 'Diagonal',
  'Wedge': 'Wedge',
  'Hane': 'Hane',
  'Cut': 'Cut',
  'Square': 'Square',
  'Throwing Star': 'Throwing Star',
  'Parallelogram': 'Parallelogram',
  'Dog’s Head': 'Dog’s Head',
  'Horse’s Head': 'Horse’s Head',
  'Attachment': 'Attachment',
  'One-Point Jump': 'One-Point Jump',
  'Big Bulge': 'Big Bulge',
  'Small Knight': 'Small Knight',
  'Two-Point Jump': 'Two-Point Jump',
  'Large Knight': 'Large Knight',
  '3-3 Point Invasion': '3-3 Point Invasion',
  'Shoulder Hit': 'Shoulder Hit',
  'Diagonal Jump': 'Diagonal Jump',
  '3-4 Point': '3-4 Point',
  '4-4 Point': '4-4 Point',
  '3-3 Point': '3-3 Point',
  '3-5 Point': '3-5 Point',
  '4-5 Point': '4-5 Point',
  '6-3 Point': '6-3 Point',
  '6-4 Point': '6-4 Point',
  '5-5 Point': '5-5 Point',
  'Crosscut': 'Crosscut',
  'Monkey Jump': 'Monkey Jump',
  'Cap': 'Cap',
};

const Map<String, String> _termsJa = {
  'Pass': 'パス',
  'Take': '取り',
  'Atari': 'アタリ',
  'Self-Atari': '自アタリ',
  'Suicide': '自殺手',
  'Fill': 'ダメ詰め',
  'Connect': 'ツギ',
  'Tengen': '天元',
  'Hoshi': '星',
  'Low Chinese Opening': '低中国流',
  'High Chinese Opening': '高中国流',
  'Orthodox Opening': '正統布石',
  'Enclosure Opening': 'シマリ布石',
  'Kobayashi Opening': '小林流',
  'Small Chinese Opening': '小中国流',
  'Micro Chinese Opening': 'ミニ中国流',
  'Sanrensei Opening': '三連星',
  'Nirensei Opening': '二連星',
  'Shūsaku Opening': '秀策流',
  'Low Approach': '小ゲイマガカリ',
  'High Approach': '一間高ガカリ',
  'Low Enclosure': '小ゲイマジマリ',
  'High Enclosure': '一間高ジマリ',
  'Mouth Shape': '口型',
  'Table Shape': 'テーブル形',
  'Tippy Table': '傾きテーブル',
  'Bamboo Joint': 'タケフ',
  'Trapezium': '台形',
  'Diamond': 'ひし形',
  'Tiger’s Mouth': 'トラの口',
  'Empty Triangle': '空き三角',
  'Turn': 'マガリ',
  'Stretch': 'ノビ',
  'Diagonal': 'コスミ',
  'Wedge': 'ワリコミ',
  'Hane': 'ハネ',
  'Cut': 'キリ',
  'Square': '四角',
  'Throwing Star': '投星',
  'Parallelogram': '平行四辺形',
  'Dog’s Head': '犬の頭',
  'Horse’s Head': '馬の顔',
  'Attachment': 'ツケ',
  'One-Point Jump': '一間トビ',
  'Big Bulge': '大ブクラミ',
  'Small Knight': '小ゲイマ',
  'Two-Point Jump': '二間トビ',
  'Large Knight': '大ゲイマ',
  '3-3 Point Invasion': '三々入り',
  'Shoulder Hit': 'カタツキ',
  'Diagonal Jump': '斜トビ',
  '3-4 Point': '小目',
  '4-4 Point': '星',
  '3-3 Point': '三々',
  '3-5 Point': '目外し',
  '4-5 Point': '高目',
  '6-3 Point': '大目外し',
  '6-4 Point': '大高目',
  '5-5 Point': '五の五',
  'Crosscut': '切り違い',
  'Monkey Jump': 'サルスベリ',
  'Cap': 'ボウシ',
};

const Map<String, String> _termsKo = {
  'Pass': '패스',
  'Take': '따냄',
  'Atari': '단수',
  'Self-Atari': '자단수',
  'Suicide': '자살수',
  'Fill': '메우기',
  'Connect': '잇기',
  'Tengen': '천원',
  'Hoshi': '화점',
  'Low Chinese Opening': '저중국식 포석',
  'High Chinese Opening': '고중국식 포석',
  'Orthodox Opening': '정통 포석',
  'Enclosure Opening': '굳힘 포석',
  'Kobayashi Opening': '코바야시 포석',
  'Small Chinese Opening': '소중국식 포석',
  'Micro Chinese Opening': '미니중국식 포석',
  'Sanrensei Opening': '삼연성 포석',
  'Nirensei Opening': '이연성 포석',
  'Shūsaku Opening': '수책 포석',
  'Low Approach': '낮은 걸침',
  'High Approach': '높은 걸침',
  'Low Enclosure': '낮은 굳힘',
  'High Enclosure': '높은 굳힘',
  'Mouth Shape': '빈입 모양',
  'Table Shape': '탁자 모양',
  'Tippy Table': '기운 탁자',
  'Bamboo Joint': '쌍립',
  'Trapezium': '사다리꼴',
  'Diamond': '마름모',
  'Tiger’s Mouth': '호구',
  'Empty Triangle': '빈삼각',
  'Turn': '꼬부림',
  'Stretch': '늘기',
  'Diagonal': '마늘모',
  'Wedge': '끼움',
  'Hane': '젖힘',
  'Cut': '끊음',
  'Square': '정사각형',
  'Throwing Star': '별 모양',
  'Parallelogram': '평행사변형',
  'Dog’s Head': '개머리',
  'Horse’s Head': '말머리',
  'Attachment': '붙임',
  'One-Point Jump': '한칸뜀',
  'Big Bulge': '큰 부풀림',
  'Small Knight': '날일자',
  'Two-Point Jump': '두칸뜀',
  'Large Knight': '눈목자',
  '3-3 Point Invasion': '삼삼 침입',
  'Shoulder Hit': '어깨짚기',
  'Diagonal Jump': '대각뜀',
  '3-4 Point': '소목',
  '4-4 Point': '화점',
  '3-3 Point': '삼삼',
  '3-5 Point': '외목',
  '4-5 Point': '고목',
  '6-3 Point': '대외목',
  '6-4 Point': '대고목',
  '5-5 Point': '오오',
  'Crosscut': '십자끊음',
  'Monkey Jump': '원숭이뜀',
  'Cap': '모자',
};

const Map<String, String> _termsZh = {
  'Pass': '弃权',
  'Take': '提子',
  'Atari': '打吃',
  'Self-Atari': '自打',
  'Suicide': '自杀',
  'Fill': '填',
  'Connect': '接',
  'Tengen': '天元',
  'Hoshi': '星位',
  'Low Chinese Opening': '低中国流',
  'High Chinese Opening': '高中国流',
  'Orthodox Opening': '正统布局',
  'Enclosure Opening': '守角布局',
  'Kobayashi Opening': '小林流',
  'Small Chinese Opening': '小中国流',
  'Micro Chinese Opening': '迷你中国流',
  'Sanrensei Opening': '三连星布局',
  'Nirensei Opening': '二连星布局',
  'Shūsaku Opening': '秀策流',
  'Low Approach': '小飞挂',
  'High Approach': '一间高挂',
  'Low Enclosure': '小飞守',
  'High Enclosure': '一间高守',
  'Mouth Shape': '口字形',
  'Table Shape': '桌子形',
  'Tippy Table': '斜桌形',
  'Bamboo Joint': '双',
  'Trapezium': '梯形',
  'Diamond': '菱形',
  'Tiger’s Mouth': '虎口',
  'Empty Triangle': '空三角',
  'Turn': '拐',
  'Stretch': '长',
  'Diagonal': '尖',
  'Wedge': '挖',
  'Hane': '扳',
  'Cut': '断',
  'Square': '方形',
  'Throwing Star': '飞星形',
  'Parallelogram': '平行四边形',
  'Dog’s Head': '狗头',
  'Horse’s Head': '马头',
  'Attachment': '靠',
  'One-Point Jump': '一间跳',
  'Big Bulge': '大鼓',
  'Small Knight': '小飞',
  'Two-Point Jump': '二间跳',
  'Large Knight': '大飞',
  '3-3 Point Invasion': '三三入侵',
  'Shoulder Hit': '肩冲',
  'Diagonal Jump': '跨',
  '3-4 Point': '小目',
  '4-4 Point': '星位',
  '3-3 Point': '三三',
  '3-5 Point': '目外',
  '4-5 Point': '高目',
  '6-3 Point': '大目外',
  '6-4 Point': '大高目',
  '5-5 Point': '五五',
  'Crosscut': '扭十字',
  'Monkey Jump': '猴子跳',
  'Cap': '镇',
};

const Map<String, String> _termsZhTrad = {
  'Pass': '棄權',
  'Take': '提子',
  'Atari': '打吃',
  'Self-Atari': '自打',
  'Suicide': '自殺',
  'Fill': '填',
  'Connect': '接',
  'Tengen': '天元',
  'Hoshi': '星位',
  'Low Chinese Opening': '低中國流',
  'High Chinese Opening': '高中國流',
  'Orthodox Opening': '正統佈局',
  'Enclosure Opening': '守角佈局',
  'Kobayashi Opening': '小林流',
  'Small Chinese Opening': '小中國流',
  'Micro Chinese Opening': '迷你中國流',
  'Sanrensei Opening': '三連星佈局',
  'Nirensei Opening': '二連星佈局',
  'Shūsaku Opening': '秀策流',
  'Low Approach': '小飛掛',
  'High Approach': '一間高掛',
  'Low Enclosure': '小飛守',
  'High Enclosure': '一間高守',
  'Mouth Shape': '口字形',
  'Table Shape': '桌子形',
  'Tippy Table': '斜桌形',
  'Bamboo Joint': '雙',
  'Trapezium': '梯形',
  'Diamond': '菱形',
  'Tiger’s Mouth': '虎口',
  'Empty Triangle': '空三角',
  'Turn': '拐',
  'Stretch': '長',
  'Diagonal': '尖',
  'Wedge': '挖',
  'Hane': '扳',
  'Cut': '斷',
  'Square': '方形',
  'Throwing Star': '飛星形',
  'Parallelogram': '平行四邊形',
  'Dog’s Head': '狗頭',
  'Horse’s Head': '馬頭',
  'Attachment': '靠',
  'One-Point Jump': '一間跳',
  'Big Bulge': '大鼓',
  'Small Knight': '小飛',
  'Two-Point Jump': '二間跳',
  'Large Knight': '大飛',
  '3-3 Point Invasion': '三三入侵',
  'Shoulder Hit': '肩衝',
  'Diagonal Jump': '跨',
  '3-4 Point': '小目',
  '4-4 Point': '星位',
  '3-3 Point': '三三',
  '3-5 Point': '目外',
  '4-5 Point': '高目',
  '6-3 Point': '大目外',
  '6-4 Point': '大高目',
  '5-5 Point': '五五',
  'Crosscut': '扭十字',
  'Monkey Jump': '猴子跳',
  'Cap': '鎮',
};
