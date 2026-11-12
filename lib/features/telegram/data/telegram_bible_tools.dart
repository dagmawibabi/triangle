part of 'telegram_tools.dart';

// The Bible through YouVersion (youversion_sdk). The chat controller runs
// these: they need the developer token kept in Settings → Bible.

final _bibleTools = <TelegramTool>[
  TelegramTool(
    name: 'bible_passage',
    label: 'Reading the Bible',
    category: ToolCategory.bible,
    cost: ToolCost.web,
    description:
        'Bible text from YouVersion for a reference: one verse, a range or a whole chapter ("John 3:16", '
        '"1 Cor 13:4-7", "Psalm 23", "Rom 8:28-9:2"). version: an abbreviation like KJV, NIV, ESV, AMP, or a '
        'version_id; default the user\'s version (Settings → Bible). The user sees a verse card. Quote the text '
        'exactly; never invent scripture.',
    parameters: _obj({
      'reference': {'type': 'string', 'description': 'The reference, like "John 3:16" or "Psalm 23".'},
      'version': {'type': 'string', 'description': 'A version abbreviation (KJV, NIV…) or version_id; leave out for the default.'},
      'images': {'type': 'boolean', 'description': 'Include YouVersion verse artwork for single verses and short ranges; default true.'},
    }, ['reference']),
  ),
  TelegramTool(
    name: 'bible_chapter',
    label: 'Opening a chapter',
    category: ToolCategory.bible,
    cost: ToolCost.web,
    description:
        'A whole Bible chapter to read, with section headings, and what comes before and after. The user sees a '
        'reader card they can page through.',
    parameters: _obj({
      'book': {'type': 'string', 'description': 'The book, like "Genesis", "Ps" or "1 John".'},
      'chapter': {'type': 'integer', 'description': 'The chapter number.'},
      'version': {'type': 'string', 'description': 'A version abbreviation or version_id; leave out for the default.'},
    }, ['book', 'chapter']),
  ),
  TelegramTool(
    name: 'bible_compare',
    label: 'Comparing translations',
    category: ToolCategory.bible,
    cost: ToolCost.web,
    description: 'The same passage in several Bible versions side by side, e.g. John 1:1 in KJV, NIV and ESV.',
    parameters: _obj({
      'reference': {'type': 'string', 'description': 'The reference, like "John 1:1".'},
      'versions': {
        'type': 'array',
        'items': {'type': 'string', 'description': 'A version abbreviation or version_id.'},
        'description': '2-5 versions, like ["KJV", "NIV", "ESV"].',
      },
    }, ['reference', 'versions']),
  ),
  TelegramTool(
    name: 'bible_verse_of_the_day',
    label: 'Finding the verse of the day',
    category: ToolCategory.bible,
    cost: ToolCost.web,
    description: 'YouVersion\'s verse of the day (with its artwork when there is some), today\'s or another date\'s, in the user\'s version.',
    parameters: _obj({
      'date': {'type': 'string', 'description': 'A date like "2026-12-25"; default today.'},
      'version': {'type': 'string', 'description': 'A version abbreviation or version_id; leave out for the default.'},
    }),
  ),
  TelegramTool(
    name: 'bible_versions',
    label: 'Listing Bible versions',
    category: ToolCategory.bible,
    cost: ToolCost.web,
    description:
        'Bible versions (translations) in a language: id, abbreviation, title, books, copyright. By default only the '
        'versions the user\'s YouVersion app may read; include_unlicensed lists every version (marked licensed: false, '
        'such as NIV until its license is accepted on platform.youversion.com). language: en, am, es, fr, or * for all.',
    parameters: _obj({
      'language': {'type': 'string', 'description': 'A language code like en, am, es; default the user\'s.'},
      'query': {'type': 'string', 'description': 'Words to match in the title or abbreviation.'},
      'limit': {'type': 'integer', 'description': 'How many, 1-80; default 25.'},
      'include_unlicensed': {'type': 'boolean', 'description': 'Also list versions the user\'s app can\'t read yet; default false.'},
    }),
  ),
  TelegramTool(
    name: 'bible_search',
    label: 'Searching the Bible',
    category: ToolCategory.bible,
    cost: ToolCost.web,
    description:
        'Finds verses about a topic or containing words ("love your enemies", "anxiety", "faith hope love"), in a '
        'version, with their text. The user sees result cards.',
    parameters: _obj({
      'query': {'type': 'string', 'description': 'What to look for: words or a topic.'},
      'version': {'type': 'string', 'description': 'A version abbreviation or version_id; leave out for the default.'},
      'limit': {'type': 'integer', 'description': 'How many verses, 1-20; default 8.'},
    }, ['query']),
  ),
  TelegramTool(
    name: 'bible_books',
    label: 'Listing the books',
    category: ToolCategory.bible,
    cost: ToolCost.web,
    description: 'The books in a Bible version with their chapter counts, Old and New Testament.',
    parameters: _obj({
      'version': {'type': 'string', 'description': 'A version abbreviation or version_id; leave out for the default.'},
    }),
  ),
];

const _biblePolicies = <String, ToolPolicy>{
  'bible_passage': ToolPolicy(ToolAccess.read),
  'bible_chapter': ToolPolicy(ToolAccess.read),
  'bible_compare': ToolPolicy(ToolAccess.read),
  'bible_verse_of_the_day': ToolPolicy(ToolAccess.read),
  'bible_versions': ToolPolicy(ToolAccess.read),
  'bible_books': ToolPolicy(ToolAccess.read),
  'bible_search': ToolPolicy(ToolAccess.read),
};

const _bibleReferences = <String, ToolReference>{
  'bible_passage': ToolReference(['reference', 'passage_id', 'text', 'version', 'link', 'copyright', 'images', 'next', 'previous']),
  'bible_search': ToolReference(['query', 'version', 'results', 'did_you_mean'], limits: ['limit: 1-20.']),
  'bible_chapter': ToolReference(['reference', 'passage_id', 'text', 'version', 'link', 'next', 'previous', 'chapters_in_book']),
  'bible_compare': ToolReference(['reference', 'passage_id', 'translations', 'failed']),
  'bible_verse_of_the_day': ToolReference(['date', 'reference', 'passage_id', 'text', 'version', 'link', 'image']),
  'bible_versions': ToolReference(['language', 'count', 'readable', 'versions', 'default_version_id', 'note'], limits: ['limit: 1-80.']),
  'bible_books': ToolReference(['version', 'old_testament', 'new_testament', 'other']),
};
