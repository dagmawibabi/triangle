part of 'telegram_tools.dart';

// Marketplace, Video, Books and Gallery: the sections built from channels
// and groups. The runner is in features/sections/section_tools.dart.

const _chatIds = {'type': 'array', 'items': {'type': 'integer'}, 'description': 'Telegram chat ids (channels or groups).'};
const _keys = {'type': 'array', 'items': {'type': 'string'}, 'description': 'A list of keys, ids or names.'};

const _sourceActions = {
  'type': 'string',
  'enum': ['list', 'add', 'remove', 'hide', 'show', 'reorder'],
  'description': 'list (default) shows them; add/remove/hide/show take chat_ids; reorder takes chat_ids in the order wanted.',
};

/// Every section tool, for the local-tool routing.
const sectionToolNames = {
  'market_stores', 'market_search', 'market_item', 'market_cart', 'market_wishlist', 'market_ai_settings', 'market_tidy',
  'movie_channels', 'find_videos', 'movie_library',
  'book_sources', 'find_books', 'list_books', 'add_book', 'update_book', 'book_shelves', 'book_notes', 'read_book_text', 'reading_stats', 'remove_book',
  'gallery_sources', 'gallery_items', 'gallery_albums', 'gallery_mark',
  'app_sections',
};

const sectionTools = <TelegramTool>[
  // ---- marketplace ----
  TelegramTool(
    name: 'market_stores',
    label: 'Managing marketplace stores',
    category: ToolCategory.marketplace,
    cost: ToolCost.device,
    description:
        'The Marketplace\'s stores: the channels and groups whose posts show as products. list them (with product '
        'counts), add or remove (chat_ids), hide or show them in the shop, or reorder.',
    parameters: {'type': 'object', 'properties': {'action': _sourceActions, 'chat_ids': _chatIds}},
  ),
  TelegramTool(
    name: 'market_search',
    label: 'Searching the marketplace',
    category: ToolCategory.marketplace,
    cost: ToolCost.telegram,
    description:
        'Products in the Marketplace (from its stores), with the AI listing when tidied: name, price, category, '
        'trust score (legit 0-100), rating and what buyers say. Filter by words, store, category and price; sort.',
    parameters: {
      'type': 'object',
      'properties': {
        'query': {'type': 'string', 'description': 'Words to match.'},
        'chat_id': {'type': 'integer', 'description': 'One store only.'},
        'category': {'type': 'string', 'description': 'A category from the AI listings, e.g. Phones.'},
        'min_price': {'type': 'number', 'description': 'Lowest price, in the item\'s currency.'},
        'max_price': {'type': 'number', 'description': 'Highest price, in the item\'s currency.'},
        'sort': {'type': 'string', 'enum': ['newest', 'priceLow', 'priceHigh', 'rating', 'legit', 'popular'], 'description': 'The order.'},
        'limit': {'type': 'integer', 'description': 'Default 20, at most 60.'},
        'more': {'type': 'boolean', 'description': 'Read older posts from the stores first.'},
      },
    },
  ),
  TelegramTool(
    name: 'market_item',
    label: 'Opening a product',
    category: ToolCategory.marketplace,
    cost: ToolCost.telegram,
    description: 'One product by item_key: everything known about it, its post text, and whether it is in the cart or wishlist. hide true/false hides it from the shop.',
    parameters: {
      'type': 'object',
      'properties': {'item_key': {'type': 'string', 'description': 'The item\'s key (from a search or list).'}, 'hide': {'type': 'boolean', 'description': 'Hide it (true) or show it again (false).'}},
      'required': ['item_key'],
    },
  ),
  TelegramTool(
    name: 'market_cart',
    label: 'Updating the cart',
    category: ToolCategory.marketplace,
    cost: ToolCost.device,
    description: 'The Marketplace cart: list (with totals per currency), add an item_key, remove, set_quantity, note (a note on an item), or clear.',
    parameters: {
      'type': 'object',
      'properties': {
        'action': {'type': 'string', 'enum': ['list', 'add', 'remove', 'set_quantity', 'note', 'clear'], 'description': 'What to do.'},
        'item_key': {'type': 'string', 'description': 'The item\'s key (from a search or list).'},
        'quantity': {'type': 'integer', 'description': 'How many.'},
        'note': {'type': 'string', 'description': 'A note on the item, like size or colour.'},
      },
    },
  ),
  TelegramTool(
    name: 'market_wishlist',
    label: 'Updating the wishlist',
    category: ToolCategory.marketplace,
    cost: ToolCost.device,
    description: 'The Marketplace wishlist: list, add an item_key, remove, move_to_cart, or clear.',
    parameters: {
      'type': 'object',
      'properties': {
        'action': {'type': 'string', 'enum': ['list', 'add', 'remove', 'move_to_cart', 'clear'], 'description': 'What to do.'},
        'item_key': {'type': 'string', 'description': 'The item\'s key (from a search or list).'},
      },
    },
  ),
  TelegramTool(
    name: 'market_ai_settings',
    label: 'Changing the marketplace AI',
    category: ToolCategory.marketplace,
    cost: ToolCost.device,
    description:
        'How the Marketplace tidies posts with AI: enabled, auto (as products show), model (free, cheap, main or a '
        'model id), which fields (name, description, price, legit trust check, reviews and rating), hiding posts that '
        'aren\'t products, the user\'s extra instructions, and sort/columns of the shop. Returns the settings.',
    parameters: {
      'type': 'object',
      'properties': {
        'enabled': {'type': 'boolean', 'description': 'Turn the AI tidy-up on or off.'},
        'auto': {'type': 'boolean', 'description': 'Tidy products automatically as they show.'},
        'model': {'type': 'string', 'description': 'free, cheap, main, or a model id.'},
        'name': {'type': 'boolean', 'description': 'A name.'},
        'description': {'type': 'boolean', 'description': 'Write a clean description.'},
        'price': {'type': 'boolean', 'description': 'Read the price and currency.'},
        'legit': {'type': 'boolean', 'description': 'Judge how legitimate each listing looks (0-100).'},
        'reviews': {'type': 'boolean', 'description': 'Estimate a rating and what buyers say.'},
        'hide_non_products': {'type': 'boolean', 'description': 'Leave out posts that sell nothing.'},
        'extra_instructions': {'type': 'string', 'description': 'The user\'s own instructions for the model.'},
        'sort': {'type': 'string', 'enum': ['newest', 'priceLow', 'priceHigh', 'rating', 'legit', 'popular'], 'description': 'The order.'},
        'columns': {'type': 'integer', 'description': 'Products per row in the shop (1-4).'},
      },
    },
  ),
  TelegramTool(
    name: 'market_tidy',
    label: 'Tidying products with AI',
    category: ToolCategory.marketplace,
    cost: ToolCost.web,
    description: 'Runs the Marketplace AI on products now: item_keys, or the newest of one store (chat_id) or of every store. force redoes ones already tidied.',
    parameters: {
      'type': 'object',
      'properties': {'action': {'type': 'string', 'enum': ['run', 'status', 'pause', 'resume', 'stop'], 'description': 'run (default) queues products; status, pause, resume or stop control a running tidy-up.'}, 'item_keys': _keys, 'chat_id': {'type': 'integer', 'description': 'A Telegram chat id: one channel, group or store.'}, 'limit': {'type': 'integer', 'description': 'Default 16, at most 64.'}, 'force': {'type': 'boolean', 'description': 'Redo items already tidied.'}},
    },
  ),
  // ---- movies ----
  TelegramTool(
    name: 'movie_channels',
    label: 'Managing video channels',
    category: ToolCategory.movies,
    cost: ToolCost.device,
    description: 'The Video section\'s channels (channels and groups that post videos): list with video counts, add, remove, hide or show on Home, reorder.',
    parameters: {'type': 'object', 'properties': {'action': _sourceActions, 'chat_ids': _chatIds}},
  ),
  TelegramTool(
    name: 'find_videos',
    label: 'Finding videos',
    category: ToolCategory.movies,
    cost: ToolCost.telegram,
    description: 'Videos in the Video section\'s channels: by words, one channel, length (short, medium, long), sorted; with how much the user watched.',
    parameters: {
      'type': 'object',
      'properties': {
        'query': {'type': 'string', 'description': 'Words to match.'},
        'chat_id': {'type': 'integer', 'description': 'A Telegram chat id: one channel, group or store.'},
        'length': {'type': 'string', 'enum': ['any', 'short', 'medium', 'long'], 'description': 'How long: short (under 4 min), medium (4-20), long (over 20).'},
        'sort': {'type': 'string', 'enum': ['newest', 'oldest', 'views', 'longest', 'shortest'], 'description': 'The order.'},
        'limit': {'type': 'integer', 'description': 'Most results.'},
        'more': {'type': 'boolean', 'description': 'Read older posts first.'},
      },
    },
  ),
  TelegramTool(
    name: 'movie_library',
    label: 'Managing My list',
    category: ToolCategory.movies,
    cost: ToolCost.device,
    description:
        'The user\'s Video library: my_list, history (continue watching), add or remove a video_key from My list, '
        'like/unlike, hide/unhide, forget (remove from history), clear_history, or settings (autoplay, sort).',
    parameters: {
      'type': 'object',
      'properties': {
        'action': {'type': 'string', 'enum': ['my_list', 'history', 'add', 'remove', 'like', 'unlike', 'hide', 'unhide', 'forget', 'clear_history', 'settings'], 'description': 'What to do.'},
        'video_key': {'type': 'string', 'description': 'The video\'s key (from find_videos).'},
        'autoplay': {'type': 'boolean', 'description': 'Play the next video when one ends.'},
        'sort': {'type': 'string', 'enum': ['newest', 'oldest', 'views', 'longest', 'shortest'], 'description': 'The order.'},
      },
      'required': ['action'],
    },
  ),
  // ---- books ----
  TelegramTool(
    name: 'book_sources',
    label: 'Managing book sources',
    category: ToolCategory.books,
    cost: ToolCost.device,
    description: 'The Library\'s sources: channels and groups that post books. list, add or remove (chat_ids).',
    parameters: {'type': 'object', 'properties': {'action': _sourceActions, 'chat_ids': _chatIds}},
  ),
  TelegramTool(
    name: 'find_books',
    label: 'Finding books in your channels',
    category: ToolCategory.books,
    cost: ToolCost.telegram,
    description: 'Book files (EPUB, PDF, DOCX, FB2, MOBI…) posted in the Library\'s sources, by words, one source or format; with whether each is in the library.',
    parameters: {
      'type': 'object',
      'properties': {'query': {'type': 'string', 'description': 'Words to match.'}, 'chat_id': {'type': 'integer', 'description': 'A Telegram chat id: one channel, group or store.'}, 'format': {'type': 'string', 'description': 'A file format, like epub or pdf.'}, 'limit': {'type': 'integer', 'description': 'Most results.'}},
    },
  ),
  TelegramTool(
    name: 'list_books',
    label: 'Listing your books',
    category: ToolCategory.books,
    cost: ToolCost.device,
    description: 'Books in the user\'s Library: status, progress, shelves, rating, minutes read. Filter by status, shelf, favorite or words.',
    parameters: {
      'type': 'object',
      'properties': {
        'status': {'type': 'string', 'enum': ['want', 'reading', 'finished', 'abandoned'], 'description': 'Reading status.'},
        'shelf': {'type': 'string', 'description': 'A shelf name.'},
        'favorite': {'type': 'boolean', 'description': 'Mark as favorite (true) or not (false).'},
        'query': {'type': 'string', 'description': 'Words to match.'},
        'limit': {'type': 'integer', 'description': 'Most results.'},
      },
    },
  ),
  TelegramTool(
    name: 'add_book',
    label: 'Adding a book',
    category: ToolCategory.books,
    cost: ToolCost.telegram,
    description: 'Adds a book to the Library: a post_key from find_books, a Telegram document (chat_id + message_id), or a file on the phone (file_path). download true fetches it now; shelf puts it on a shelf.',
    parameters: {
      'type': 'object',
      'properties': {
        'post_key': {'type': 'string', 'description': 'The post_key from find_books.'},
        'chat_id': {'type': 'integer', 'description': 'A Telegram chat id: one channel, group or store.'},
        'message_id': {'type': 'integer', 'description': 'The message with the book file.'},
        'file_path': {'type': 'string', 'description': 'A book file on the phone.'},
        'download': {'type': 'boolean', 'description': 'Download it now.'},
        'shelf': {'type': 'string', 'description': 'A shelf name.'},
      },
    },
  ),
  TelegramTool(
    name: 'update_book',
    label: 'Updating a book',
    category: ToolCategory.books,
    cost: ToolCost.device,
    description: 'Changes a book in the Library (book: its book_id or title): status, favorite, rating 0-5, shelves (replace) or add_shelves/remove_shelves, title, author, notes.',
    parameters: {
      'type': 'object',
      'properties': {
        'book': {'type': 'string', 'description': 'The book: its book_id or title.'},
        'status': {'type': 'string', 'enum': ['want', 'reading', 'finished', 'abandoned'], 'description': 'Reading status.'},
        'favorite': {'type': 'boolean', 'description': 'Mark as favorite (true) or not (false).'},
        'rating': {'type': 'integer', 'description': 'Stars, 0-5.'},
        'shelves': _keys,
        'add_shelves': _keys,
        'remove_shelves': _keys,
        'title': {'type': 'string', 'description': 'A new title.'},
        'author': {'type': 'string', 'description': 'A new author.'},
        'notes': {'type': 'string', 'description': 'The user\'s notes on the book.'},
      },
      'required': ['book'],
    },
  ),
  TelegramTool(
    name: 'book_shelves',
    label: 'Arranging shelves',
    category: ToolCategory.books,
    cost: ToolCost.device,
    description: 'The Library\'s shelves: list (with books), create, rename (name → new_name), delete, or reorder (order: shelf names).',
    parameters: {
      'type': 'object',
      'properties': {
        'action': {'type': 'string', 'enum': ['list', 'create', 'rename', 'delete', 'reorder'], 'description': 'What to do.'},
        'name': {'type': 'string', 'description': 'A name.'},
        'new_name': {'type': 'string', 'description': 'The shelf\'s new name.'},
        'order': _keys,
      },
    },
  ),
  TelegramTool(
    name: 'book_notes',
    label: 'Reading your highlights',
    category: ToolCategory.books,
    cost: ToolCost.device,
    description: 'Highlights, notes and bookmarks from the Library: all, or one book\'s. action delete removes one by id.',
    parameters: {
      'type': 'object',
      'properties': {'book': {'type': 'string', 'description': 'The book: its book_id or title.'}, 'action': {'type': 'string', 'enum': ['list', 'delete'], 'description': 'What to do.'}, 'id': {'type': 'string', 'description': 'The highlight or bookmark id to delete.'}},
    },
  ),
  TelegramTool(
    name: 'read_book_text',
    label: 'Reading a book',
    category: ToolCategory.books,
    cost: ToolCost.device,
    description:
        'The text of a Library book (EPUB, DOCX, FB2, TXT, HTML) to summarise it, answer questions or quote it: its '
        'contents, then a chapter (by number from the contents) or from a percent. Downloads it first if needed.',
    parameters: {
      'type': 'object',
      'properties': {
        'book': {'type': 'string', 'description': 'The book: its book_id or title.'},
        'chapter': {'type': 'integer', 'description': '1-based, from the contents.'},
        'from_percent': {'type': 'number', 'description': 'Start this far into the book, 0-100.'},
        'max_chars': {'type': 'integer', 'description': 'Default 12000, at most 40000.'},
      },
      'required': ['book'],
    },
  ),
  TelegramTool(
    name: 'reading_stats',
    label: 'Reading your reading stats',
    category: ToolCategory.books,
    cost: ToolCost.device,
    description: 'Reading time today and per day, streak, books finished, most-read books; goal_minutes sets the daily goal.',
    parameters: {'type': 'object', 'properties': {'goal_minutes': {'type': 'integer', 'description': 'Set the daily reading goal in minutes.'}}},
  ),
  TelegramTool(
    name: 'remove_book',
    label: 'Removing a book',
    category: ToolCategory.books,
    cost: ToolCost.device,
    destructive: true,
    description: 'Removes a book from the Library with its file on the phone, highlights and bookmarks. It stays in its chat. Only when the user asks.',
    parameters: {'type': 'object', 'properties': {'book': {'type': 'string', 'description': 'The book: its book_id or title.'}}, 'required': ['book']},
  ),
  // ---- gallery ----
  TelegramTool(
    name: 'gallery_sources',
    label: 'Managing gallery sources',
    category: ToolCategory.gallery,
    cost: ToolCost.device,
    description: 'The Gallery\'s sources: chats whose photos and videos gather there. list, add, remove, hide or show (chat_ids).',
    parameters: {'type': 'object', 'properties': {'action': _sourceActions, 'chat_ids': _chatIds}},
  ),
  TelegramTool(
    name: 'gallery_items',
    label: 'Looking through the gallery',
    category: ToolCategory.gallery,
    cost: ToolCost.telegram,
    description: 'Photos and videos in the Gallery: all, one source (chat_id), one type, an album, favorites or hidden ones; newest first, with item_keys.',
    parameters: {
      'type': 'object',
      'properties': {
        'chat_id': {'type': 'integer', 'description': 'A Telegram chat id: one channel, group or store.'},
        'type': {'type': 'string', 'enum': ['photo', 'video'], 'description': 'Only photos or only videos.'},
        'album': {'type': 'string', 'description': 'An album: its album_id or name.'},
        'favorites': {'type': 'boolean', 'description': 'Only favorites.'},
        'hidden': {'type': 'boolean', 'description': 'Hide (true) or unhide (false); in gallery_items, list hidden ones.'},
        'limit': {'type': 'integer', 'description': 'Most results.'},
        'more': {'type': 'boolean', 'description': 'Read older posts first.'},
      },
    },
  ),
  TelegramTool(
    name: 'gallery_albums',
    label: 'Managing albums',
    category: ToolCategory.gallery,
    cost: ToolCost.device,
    description: 'Gallery albums: list, create (name, emoji, item_keys), rename (album → name, emoji), delete, add or remove item_keys, reorder (order: album ids or names).',
    parameters: {
      'type': 'object',
      'properties': {
        'action': {'type': 'string', 'enum': ['list', 'create', 'rename', 'delete', 'add', 'remove', 'reorder'], 'description': 'What to do.'},
        'album': {'type': 'string', 'description': 'An album: its album_id or name.'},
        'name': {'type': 'string', 'description': 'A name.'},
        'emoji': {'type': 'string', 'description': 'An emoji for the album.'},
        'item_keys': _keys,
        'order': _keys,
      },
    },
  ),
  TelegramTool(
    name: 'gallery_mark',
    label: 'Marking photos',
    category: ToolCategory.gallery,
    cost: ToolCost.device,
    description: 'Favorites or hides Gallery items (item_keys): favorite true/false, hidden true/false.',
    parameters: {
      'type': 'object',
      'properties': {'item_keys': _keys, 'favorite': {'type': 'boolean', 'description': 'Mark as favorite (true) or not (false).'}, 'hidden': {'type': 'boolean', 'description': 'Hide (true) or unhide (false); in gallery_items, list hidden ones.'}},
      'required': ['item_keys'],
    },
  ),
  // ---- all ----
  TelegramTool(
    name: 'app_sections',
    label: 'Arranging the app\'s sections',
    category: ToolCategory.media,
    cost: ToolCost.device,
    description:
        'The app\'s sections (playlists, marketplace, movies, books, gallery, my folders): which show in the side '
        'drawer, and which page the app opens on (start_page: assistant, dms, channels, groups, playlists, '
        'marketplace, movies, books, gallery, files, brief, canvas, search, calls…). Returns the current setup.',
    parameters: {
      'type': 'object',
      'properties': {
        'show': _keys,
        'hide': _keys,
        'start_page': {'type': 'string', 'description': 'The page the app opens on.'},
      },
    },
  ),
];

const _sectionPolicies = <String, ToolPolicy>{
  'market_stores': ToolPolicy(ToolAccess.modify),
  'market_search': ToolPolicy(ToolAccess.read, needsTelegram: true),
  'market_item': ToolPolicy(ToolAccess.read, needsTelegram: true),
  'market_cart': ToolPolicy(ToolAccess.modify),
  'market_wishlist': ToolPolicy(ToolAccess.modify),
  'market_ai_settings': ToolPolicy(ToolAccess.modify),
  'market_tidy': ToolPolicy(ToolAccess.modify, needsTelegram: true),
  'movie_channels': ToolPolicy(ToolAccess.modify),
  'find_videos': ToolPolicy(ToolAccess.read, needsTelegram: true),
  'movie_library': ToolPolicy(ToolAccess.modify),
  'book_sources': ToolPolicy(ToolAccess.modify),
  'find_books': ToolPolicy(ToolAccess.read, needsTelegram: true),
  'list_books': ToolPolicy(ToolAccess.read),
  'add_book': ToolPolicy(ToolAccess.modify),
  'update_book': ToolPolicy(ToolAccess.modify),
  'book_shelves': ToolPolicy(ToolAccess.modify),
  'book_notes': ToolPolicy(ToolAccess.modify),
  'read_book_text': ToolPolicy(ToolAccess.read),
  'reading_stats': ToolPolicy(ToolAccess.modify),
  'remove_book': ToolPolicy(ToolAccess.destructive),
  'gallery_sources': ToolPolicy(ToolAccess.modify),
  'gallery_items': ToolPolicy(ToolAccess.read, needsTelegram: true),
  'gallery_albums': ToolPolicy(ToolAccess.modify),
  'gallery_mark': ToolPolicy(ToolAccess.modify),
  'app_sections': ToolPolicy(ToolAccess.modify),
};

const _sectionReferences = <String, ToolReference>{
  'market_stores': ToolReference(['stores: chat_id, title, hidden, products', 'added', 'removed', 'unknown']),
  'market_search': ToolReference(['products: item_key, name, price, store, category, legit_score, rating, reviews', 'total', 'categories', 'note']),
  'market_item': ToolReference(['product', 'in_cart', 'in_wishlist', 'hidden']),
  'market_cart': ToolReference(['cart: item_key, title, price, store, quantity, note', 'totals', 'count']),
  'market_wishlist': ToolReference(['wishlist: item_key, title, price, store', 'count']),
  'market_ai_settings': ToolReference(['enabled', 'auto', 'model', 'resolved_model', 'name', 'description', 'price', 'legit', 'reviews', 'hide_non_products', 'extra_instructions', 'sort', 'columns']),
  'market_tidy': ToolReference(['tidied', 'products', 'status', 'done', 'total', 'failed']),
  'movie_channels': ToolReference(['channels: chat_id, title, hidden, videos', 'added', 'removed', 'unknown']),
  'find_videos': ToolReference(['videos: video_key, title, channel, length_minutes, quality, views, watched_percent', 'total']),
  'movie_library': ToolReference(['my_list', 'history', 'done', 'autoplay', 'sort']),
  'book_sources': ToolReference(['sources: chat_id, title, books', 'added', 'removed']),
  'find_books': ToolReference(['books: post_key, title, file_name, format, size, from, in_library', 'total']),
  'list_books': ToolReference(['books: book_id, title, author, format, status, progress_percent, shelves, rating', 'shelves', 'total']),
  'add_book': ToolReference(['added: book_id, title, format, downloaded']),
  'update_book': ToolReference(['updated']),
  'book_shelves': ToolReference(['shelves: name, books']),
  'book_notes': ToolReference(['highlights: id, book, text, note', 'bookmarks: id, book, label', 'deleted']),
  'read_book_text': ToolReference(['book', 'contents', 'chapter', 'text', 'next_chapter', 'progress_percent']),
  'reading_stats': ToolReference(['today_minutes', 'goal_minutes', 'streak_days', 'last_14_days', 'books_finished', 'most_read']),
  'remove_book': ToolReference(['removed']),
  'gallery_sources': ToolReference(['sources: chat_id, title, hidden, items', 'added', 'removed']),
  'gallery_items': ToolReference(['items: item_key, type, source, date, caption', 'total']),
  'gallery_albums': ToolReference(['albums: album_id, name, items', 'album', 'added', 'removed']),
  'gallery_mark': ToolReference(['favorites', 'hidden', 'changed']),
  'app_sections': ToolReference(['in_drawer', 'start_page', 'start_pages']),
};
