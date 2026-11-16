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
  'movie_channels', 'find_videos', 'movie_library', 'video_stats',
  'cinema_channels', 'find_titles', 'cinema_title', 'cinema_watchlist', 'cinema_series',
  'book_sources', 'find_books', 'list_books', 'add_book', 'update_book', 'book_shelves', 'book_notes', 'read_book_text', 'reading_stats', 'remove_book',
  'gallery_sources', 'gallery_items', 'gallery_albums', 'gallery_mark', 'gallery_search', 'gallery_index',
  'podcast_discover', 'podcast_shows', 'podcast_library', 'podcast_play', 'radio',
  'opportunity_sources', 'find_events', 'event_plan', 'find_jobs', 'job_tracker', 'opportunity_settings',
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
  TelegramTool(
    name: 'video_stats',
    label: 'Reading your watch time',
    category: ToolCategory.movies,
    cost: ToolCost.device,
    description: 'Time spent watching in Video (and Cinema, which plays in the same player): today, per day, streak, most-watched videos and channels.',
    parameters: {'type': 'object', 'properties': {'days': {'type': 'integer', 'description': 'How many past days to show per day (default 14, at most 60).'}}},
  ),
  // ---- cinema ----
  TelegramTool(
    name: 'cinema_channels',
    label: 'Managing cinema channels',
    category: ToolCategory.cinema,
    cost: ToolCost.device,
    description:
        'Cinema\'s channels: the ones that post films and series, read as a catalogue. list (with video counts), add, '
        'remove, hide, show or reorder (chat_ids). poster_posts true/false also reads (or skips) poster posts: a '
        'picture with the plot, ratings and links but no video.',
    parameters: {'type': 'object', 'properties': {'action': _sourceActions, 'chat_ids': _chatIds, 'poster_posts': {'type': 'boolean', 'description': 'Also read poster posts (details and links, no video).'}}},
  ),
  TelegramTool(
    name: 'find_titles',
    label: 'Browsing the cinema',
    category: ToolCategory.cinema,
    cost: ToolCost.telegram,
    description:
        'Films and shows in Cinema: videos from its channels gathered into titles by name, year and season/episode, '
        'newest first, plus the user\'s own series. Filter by words or genre, kind, the watchlist, or only titles with '
        'a video. Returns title_keys for cinema_title.',
    parameters: {
      'type': 'object',
      'properties': {
        'query': {'type': 'string', 'description': 'Words in the title, or a genre such as Drama.'},
        'kind': {'type': 'string', 'enum': ['any', 'movie', 'show'], 'description': 'Films, shows or both (default).'},
        'watchlist': {'type': 'boolean', 'description': 'Only titles on the watchlist.'},
        'with_video': {'type': 'boolean', 'description': 'Leave out titles that only have a poster post.'},
        'limit': {'type': 'integer', 'description': 'Default 25, at most 80.'},
        'more': {'type': 'boolean', 'description': 'Read older posts from the channels first.'},
      },
    },
  ),
  TelegramTool(
    name: 'cinema_title',
    label: 'Opening a film or show',
    category: ToolCategory.cinema,
    cost: ToolCost.web,
    description:
        'One Cinema title by title_key (or its name): plot, genres, IMDb rating, cast, director and runtime looked up '
        'online; a film\'s copies, or a show\'s episodes by season with how much was watched and what is up next; '
        'and the links from its poster post. Each video_key plays in Video.',
    parameters: {
      'type': 'object',
      'properties': {
        'title_key': {'type': 'string', 'description': 'From find_titles, or the title\'s name.'},
        'season': {'type': 'integer', 'description': 'Only this season\'s episodes.'},
        'details': {'type': 'boolean', 'description': 'Look the title up online (default true).'},
      },
      'required': ['title_key'],
    },
  ),
  TelegramTool(
    name: 'cinema_watchlist',
    label: 'Updating the watchlist',
    category: ToolCategory.cinema,
    cost: ToolCost.device,
    description: 'Cinema\'s watchlist: list (default), add or remove a title_key.',
    parameters: {
      'type': 'object',
      'properties': {
        'action': {'type': 'string', 'enum': ['list', 'add', 'remove'], 'description': 'What to do.'},
        'title_key': {'type': 'string', 'description': 'From find_titles.'},
      },
    },
  ),
  TelegramTool(
    name: 'cinema_series',
    label: 'Putting a series together',
    category: ToolCategory.cinema,
    cost: ToolCost.device,
    description:
        'The user\'s own series in Cinema, made from channels: list (default); create (name, year, chat_ids whose '
        'posts are sorted into seasons by "S02E03" and the like); update (series → name, year, chat_ids); '
        'set_season (series, season, chat_ids whose videos are that season\'s episodes in posting order, season_name); '
        'remove_season; delete.',
    parameters: {
      'type': 'object',
      'properties': {
        'action': {'type': 'string', 'enum': ['list', 'create', 'update', 'set_season', 'remove_season', 'delete'], 'description': 'What to do.'},
        'series': {'type': 'string', 'description': 'The series: its series_id or name.'},
        'name': {'type': 'string', 'description': 'The series\' name.'},
        'year': {'type': 'integer', 'description': 'The year it started.'},
        'season': {'type': 'integer', 'description': 'A season number.'},
        'season_name': {'type': 'string', 'description': 'A name for the season, optional.'},
        'chat_ids': _chatIds,
      },
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
  TelegramTool(
    name: 'gallery_search',
    label: 'Searching the gallery',
    category: ToolCategory.gallery,
    cost: ToolCost.telegram,
    description:
        'Searches the Gallery\'s photos and videos by what they show and say: words in captions, source names, and '
        '(once indexed with gallery_index) what is in the picture: "receipts", "whiteboard", "beach at sunset", "cat". '
        'Narrow by type, dates, source, shape or favorites. deep true also asks Telegram for captions in older posts '
        'that aren\'t loaded. Returns item_keys the other gallery tools take.',
    parameters: {
      'type': 'object',
      'properties': {
        'query': {'type': 'string', 'description': 'What to look for.'},
        'type': {'type': 'string', 'enum': ['photo', 'video'], 'description': 'Only photos or only videos.'},
        'since': {'type': 'string', 'description': 'From this date, YYYY-MM-DD.'},
        'until': {'type': 'string', 'description': 'Up to this date, YYYY-MM-DD.'},
        'chat_id': {'type': 'integer', 'description': 'One source only.'},
        'shape': {'type': 'string', 'enum': ['portrait', 'landscape', 'square'], 'description': 'The picture\'s shape.'},
        'favorites': {'type': 'boolean', 'description': 'Only favorites.'},
        'deep': {'type': 'boolean', 'description': 'Also search Telegram for older posts\' captions.'},
        'limit': {'type': 'integer', 'description': 'Default 30, at most 100.'},
      },
    },
  ),
  TelegramTool(
    name: 'gallery_index',
    label: 'Indexing photos',
    category: ToolCategory.gallery,
    cost: ToolCost.ai,
    description:
        'Smart search for the Gallery: a vision model describes photos (objects, scene, any text in them) so '
        'gallery_search can find them by what they show. status (default) says how many are indexed; run indexes up to '
        'limit loaded photos not indexed yet (uses the model, costs tokens); stop; forget clears the index.',
    parameters: {
      'type': 'object',
      'properties': {
        'action': {'type': 'string', 'enum': ['status', 'run', 'stop', 'forget'], 'description': 'What to do.'},
        'limit': {'type': 'integer', 'description': 'For run: most photos to describe (default 60, at most 400).'},
      },
    },
  ),
  // ---- podcasts & radio ----
  TelegramTool(
    name: 'podcast_discover',
    label: 'Finding podcasts',
    category: ToolCategory.podcasts,
    cost: ToolCost.web,
    description: 'Searches Apple\'s podcast directory (query, optional genre such as Technology or History, country code), or gives today\'s top shows when there is no query. Follow one with podcast_shows.',
    parameters: {
      'type': 'object',
      'properties': {
        'query': {'type': 'string', 'description': 'Words to search.'},
        'genre': {'type': 'string', 'description': 'A genre, e.g. Technology, News, Comedy.'},
        'country': {'type': 'string', 'description': 'Two-letter chart country, e.g. us, gb, ng.'},
        'limit': {'type': 'integer', 'description': 'Most results.'},
      },
    },
  ),
  TelegramTool(
    name: 'podcast_shows',
    label: 'Managing podcast shows',
    category: ToolCategory.podcasts,
    cost: ToolCost.web,
    description: 'The user\'s podcast shows: list (default), follow (feed_url or apple_id), unfollow (show_id), add_telegram (chat_ids of channels whose audio posts become episodes), refresh.',
    parameters: {
      'type': 'object',
      'properties': {
        'action': {'type': 'string', 'enum': ['list', 'follow', 'unfollow', 'add_telegram', 'refresh'], 'description': 'What to do.'},
        'feed_url': {'type': 'string', 'description': 'An RSS feed address.'},
        'apple_id': {'type': 'string', 'description': 'From podcast_discover.'},
        'show_id': {'type': 'string', 'description': 'A followed show id.'},
        'chat_ids': _chatIds,
      },
    },
  ),
  TelegramTool(
    name: 'podcast_library',
    label: 'Listing episodes',
    category: ToolCategory.podcasts,
    cost: ToolCost.web,
    description: 'Episodes: of one show (show_id), or a list: new (default), in_progress, queue, downloaded, history, saved. query filters by words.',
    parameters: {
      'type': 'object',
      'properties': {
        'show_id': {'type': 'string', 'description': 'One show.'},
        'list': {'type': 'string', 'enum': ['new', 'in_progress', 'queue', 'downloaded', 'history', 'saved'], 'description': 'Which list.'},
        'query': {'type': 'string', 'description': 'Words in titles or notes.'},
        'limit': {'type': 'integer', 'description': 'Most results.'},
      },
    },
  ),
  TelegramTool(
    name: 'podcast_play',
    label: 'Playing a podcast',
    category: ToolCategory.podcasts,
    cost: ToolCost.device,
    description: 'Acts on an episode_id: play (resumes where the user stopped), play_next, queue, dequeue, played, unplayed, download, remove_download, favorite; or clear_queue.',
    parameters: {
      'type': 'object',
      'properties': {
        'episode_id': {'type': 'string', 'description': 'From podcast_library.'},
        'action': {'type': 'string', 'enum': ['play', 'play_next', 'queue', 'dequeue', 'played', 'unplayed', 'download', 'remove_download', 'favorite', 'clear_queue'], 'description': 'What to do.'},
      },
    },
  ),
  TelegramTool(
    name: 'radio',
    label: 'Live radio',
    category: ToolCategory.podcasts,
    cost: ToolCost.web,
    description: 'Live radio from every country: search (default; query, tag such as jazz or news, country name or code), play (station_id, or query to play the top match), favorite, unfavorite, favorites, recent.',
    parameters: {
      'type': 'object',
      'properties': {
        'action': {'type': 'string', 'enum': ['search', 'play', 'favorite', 'unfavorite', 'favorites', 'recent'], 'description': 'What to do.'},
        'query': {'type': 'string', 'description': 'A station name.'},
        'tag': {'type': 'string', 'description': 'A genre tag.'},
        'country': {'type': 'string', 'description': 'A country name or code; stays picked.'},
        'station_id': {'type': 'string', 'description': 'From a search.'},
        'limit': {'type': 'integer', 'description': 'Most results.'},
      },
    },
  ),
  // ---- events & jobs ----
  TelegramTool(
    name: 'opportunity_sources',
    label: 'Managing event and job channels',
    category: ToolCategory.opportunities,
    cost: ToolCost.device,
    description: 'The Opportunity page\'s sources: channels and groups whose posts are read as events (kind events) or jobs (kind jobs). list, add, remove, hide, show or reorder (chat_ids).',
    parameters: {
      'type': 'object',
      'properties': {
        'kind': {'type': 'string', 'enum': ['events', 'jobs'], 'description': 'Which list.'},
        'action': _sourceActions,
        'chat_ids': _chatIds,
      },
      'required': ['kind'],
    },
  ),
  TelegramTool(
    name: 'find_events',
    label: 'Finding events',
    category: ToolCategory.opportunities,
    cost: ToolCost.telegram,
    description:
        'Events from the event channels: when, where, online or not, price, registration link, organizer, in time '
        'order. Filter by words, when (upcoming, today, week, weekend, month, past), a date, online, free, category or '
        'one channel. Includes which ones the user is going to.',
    parameters: {
      'type': 'object',
      'properties': {
        'query': {'type': 'string', 'description': 'Words to match.'},
        'when': {'type': 'string', 'enum': ['upcoming', 'today', 'week', 'weekend', 'month', 'past'], 'description': 'Default upcoming.'},
        'date': {'type': 'string', 'description': 'One day, YYYY-MM-DD (overrides when).'},
        'online': {'type': 'boolean', 'description': 'true only online, false only in person.'},
        'free': {'type': 'boolean', 'description': 'Only free ones.'},
        'category': {'type': 'string', 'description': 'e.g. Tech, Music, Faith, Career.'},
        'chat_id': {'type': 'integer', 'description': 'One channel only.'},
        'limit': {'type': 'integer', 'description': 'Default 20, at most 60.'},
        'more': {'type': 'boolean', 'description': 'Read older posts first.'},
      },
    },
  ),
  TelegramTool(
    name: 'event_plan',
    label: 'Planning an event',
    category: ToolCategory.opportunities,
    cost: ToolCost.device,
    description:
        'The user\'s events: list (default) what they saved; going, interested or went for an event_key; remove; '
        'remind (minutes_before the start: makes a reminder); note (a note on it).',
    parameters: {
      'type': 'object',
      'properties': {
        'action': {'type': 'string', 'enum': ['list', 'going', 'interested', 'went', 'remove', 'remind', 'note'], 'description': 'What to do.'},
        'event_key': {'type': 'string', 'description': 'The event, from find_events.'},
        'minutes_before': {'type': 'integer', 'description': 'For remind: how long before it starts (default 60).'},
        'note': {'type': 'string', 'description': 'For note.'},
      },
    },
  ),
  TelegramTool(
    name: 'find_jobs',
    label: 'Finding jobs',
    category: ToolCategory.opportunities,
    cost: ToolCost.telegram,
    description:
        'Jobs from the job channels: role, company, place, remote or not, type, level, pay, deadline, how to apply, '
        'requirements, and a match score when the user has a profile. Filter and sort. Closed ones are left out unless '
        'include_closed.',
    parameters: {
      'type': 'object',
      'properties': {
        'query': {'type': 'string', 'description': 'Role, company or skill.'},
        'workplace': {'type': 'string', 'enum': ['remote', 'hybrid', 'onsite'], 'description': 'Where the work is.'},
        'type': {'type': 'string', 'description': 'Full-time, Part-time, Contract, Internship or Freelance.'},
        'level': {'type': 'string', 'description': 'Entry, Junior, Mid, Senior, Lead or Executive.'},
        'category': {'type': 'string', 'description': 'e.g. Engineering, Finance, NGO.'},
        'closing_within_days': {'type': 'integer', 'description': 'Only ones whose deadline is this close.'},
        'min_salary': {'type': 'number', 'description': 'Lowest pay, in the post\'s currency.'},
        'include_closed': {'type': 'boolean', 'description': 'Also ones past their deadline.'},
        'sort': {'type': 'string', 'enum': ['newest', 'deadline', 'salary', 'match'], 'description': 'The order.'},
        'chat_id': {'type': 'integer', 'description': 'One channel only.'},
        'limit': {'type': 'integer', 'description': 'Default 20, at most 60.'},
        'more': {'type': 'boolean', 'description': 'Read older posts first.'},
      },
    },
  ),
  TelegramTool(
    name: 'job_tracker',
    label: 'Tracking applications',
    category: ToolCategory.opportunities,
    cost: ToolCost.device,
    description:
        'The user\'s job applications: list (default, optionally one status); for a job_key: save, applied, '
        'interview, offer, rejected (moves it there), remove, note, or remind (a reminder the day before its deadline).',
    parameters: {
      'type': 'object',
      'properties': {
        'action': {'type': 'string', 'enum': ['list', 'save', 'applied', 'interview', 'offer', 'rejected', 'remove', 'note', 'remind'], 'description': 'What to do.'},
        'job_key': {'type': 'string', 'description': 'The job, from find_jobs.'},
        'status': {'type': 'string', 'enum': ['saved', 'applied', 'interview', 'offer', 'rejected'], 'description': 'For list: only this status.'},
        'note': {'type': 'string', 'description': 'For note.'},
      },
    },
  ),
  TelegramTool(
    name: 'opportunity_settings',
    label: 'Setting up events and jobs',
    category: ToolCategory.opportunities,
    cost: ToolCost.device,
    description:
        'The Opportunity page\'s AI tidy-up (a model turns posts into clean events and jobs, and gives job ads a trust score) and the user\'s job '
        'profile (skills, experience, what they want: used for match scores and drafted applications). Change any '
        'of: ai_enabled, auto, hide_others, model (free, cheap, main or an id), profile, city. read events or jobs '
        'reads the loaded posts now (force reads them again).',
    parameters: {
      'type': 'object',
      'properties': {
        'ai_enabled': {'type': 'boolean', 'description': 'Read posts with AI.'},
        'auto': {'type': 'boolean', 'description': 'Read new posts as they load.'},
        'hide_others': {'type': 'boolean', 'description': 'Hide posts the model says aren\'t events or jobs.'},
        'model': {'type': 'string', 'description': 'free, cheap, main, or a model id.'},
        'profile': {'type': 'string', 'description': 'The user\'s job profile; replaces the current one.'},
        'city': {'type': 'string', 'description': 'The user\'s city.'},
        'read': {'type': 'string', 'enum': ['events', 'jobs'], 'description': 'Read these posts with AI now.'},
        'action': {'type': 'string', 'enum': ['status', 'pause', 'resume', 'stop'], 'description': 'The tidy-up run: its progress and latest results, or pause, resume or stop it.'},
        'extra_instructions': {'type': 'string', 'description': 'The user\'s own instructions for the model (empty to clear).'},
        'event_summary': {'type': 'boolean', 'description': 'Tidy-up fills in: summary (events).'},
        'event_place': {'type': 'boolean', 'description': 'Tidy-up fills in: place (events).'},
        'event_price': {'type': 'boolean', 'description': 'Tidy-up fills in: price (events).'},
        'event_link': {'type': 'boolean', 'description': 'Tidy-up fills in: link (events).'},
        'event_tags': {'type': 'boolean', 'description': 'Tidy-up fills in: tags (events).'},
        'job_pay': {'type': 'boolean', 'description': 'Tidy-up fills in: pay (jobs).'},
        'job_apply': {'type': 'boolean', 'description': 'Tidy-up fills in: apply (jobs).'},
        'job_requirements': {'type': 'boolean', 'description': 'Tidy-up fills in: requirements (jobs).'},
        'job_summary': {'type': 'boolean', 'description': 'Tidy-up fills in: summary (jobs).'},
        'job_match': {'type': 'boolean', 'description': 'Tidy-up fills in: match (jobs).'},
        'job_trust': {'type': 'boolean', 'description': 'Tidy-up fills in: trust (jobs).'},
        'force': {'type': 'boolean', 'description': 'With read: read again even ones already read.'},
      },
    },
  ),
  // ---- all ----
  TelegramTool(
    name: 'app_sections',
    label: 'Arranging the app\'s sections',
    category: ToolCategory.sections,
    cost: ToolCost.device,
    description:
        'The side drawer\'s Explore pages (music, video, cinema, podcasts, books, gallery, opportunity, marketplace), '
        'the whole explore heading, and my_folders: which show; and which page the app opens on (start_page: '
        'assistant, dms, channels, groups, playlists, movies, cinema, podcasts, books, gallery, opportunity, '
        'marketplace, files, brief, canvas, search, calls…). Returns the current setup.',
    parameters: {
      'type': 'object',
      'properties': {
        'show': {'type': 'array', 'items': {'type': 'string'}, 'description': 'Pages to show in the drawer, e.g. cinema, podcasts, explore.'},
        'hide': {'type': 'array', 'items': {'type': 'string'}, 'description': 'Pages to hide from the drawer.'},
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
  'video_stats': ToolPolicy(ToolAccess.read),
  'cinema_channels': ToolPolicy(ToolAccess.modify),
  'find_titles': ToolPolicy(ToolAccess.read, needsTelegram: true),
  'cinema_title': ToolPolicy(ToolAccess.read, needsTelegram: true),
  'cinema_watchlist': ToolPolicy(ToolAccess.modify),
  'cinema_series': ToolPolicy(ToolAccess.modify),
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
  'gallery_search': ToolPolicy(ToolAccess.read, needsTelegram: true),
  'gallery_index': ToolPolicy(ToolAccess.modify, needsTelegram: true),
  'podcast_discover': ToolPolicy(ToolAccess.read),
  'podcast_shows': ToolPolicy(ToolAccess.modify),
  'podcast_library': ToolPolicy(ToolAccess.read),
  'podcast_play': ToolPolicy(ToolAccess.modify),
  'radio': ToolPolicy(ToolAccess.modify),
  'opportunity_sources': ToolPolicy(ToolAccess.modify),
  'find_events': ToolPolicy(ToolAccess.read, needsTelegram: true),
  'event_plan': ToolPolicy(ToolAccess.modify),
  'find_jobs': ToolPolicy(ToolAccess.read, needsTelegram: true),
  'job_tracker': ToolPolicy(ToolAccess.modify),
  'opportunity_settings': ToolPolicy(ToolAccess.modify),
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
  'video_stats': ToolReference(['today_minutes', 'total_hours', 'streak_days', 'per_day', 'most_watched: title, channel, minutes, times_started', 'top_channels: channel, minutes', 'since']),
  'cinema_channels': ToolReference(['channels: chat_id, title, hidden, videos_loaded', 'poster_posts', 'own_series', 'added', 'removed']),
  'find_titles': ToolReference(['titles: title_key, title, kind, year, seasons, episodes, versions, plot, ratings, genres, in_watchlist', 'total']),
  'cinema_title': ToolReference(['title_key', 'title', 'kind', 'details: overview, genres, imdb_rating, cast, director, runtime_minutes', 'versions', 'episodes: season, episode, video_key, watched_percent', 'up_next', 'links'], limits: ['episodes: at most 150; pass season for one season.']),
  'cinema_watchlist': ToolReference(['watchlist', 'count']),
  'cinema_series': ToolReference(['series: series_id, title_key, name, year, channels, seasons', 'done']),
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
  'gallery_search': ToolReference(['items: item_key, type, source, date, caption, seen', 'total', 'indexed', 'note']),
  'gallery_index': ToolReference(['indexed', 'loaded_photos', 'running', 'done', 'total', 'model']),
  'podcast_discover': ToolReference(['shows: title, author, genre, feed_url, apple_id, following']),
  'podcast_shows': ToolReference(['shows: show_id, title, episodes, latest, new', 'followed', 'unfollowed']),
  'podcast_library': ToolReference(['episodes: episode_id, title, show, published, minutes, played', 'total']),
  'podcast_play': ToolReference(['done', 'episode', 'queue']),
  'radio': ToolReference(['stations: station_id, name, country, tags, kbps, favorite', 'playing', 'country']),
  'opportunity_sources': ToolReference(['sources: chat_id, title, hidden, posts', 'added', 'removed']),
  'find_events': ToolReference(['events: event_key, title, starts, where, online, link, price, organizer', 'total', 'categories', 'note']),
  'event_plan': ToolReference(['my_events: event_key, title, starts, status', 'done']),
  'find_jobs': ToolReference(['jobs: job_key, title, company, location, salary, deadline, apply_link, match_percent', 'total', 'note']),
  'job_tracker': ToolReference(['applications: job_key, title, company, status, deadline', 'counts', 'done']),
  'opportunity_settings': ToolReference(['ai_enabled', 'auto', 'model', 'resolved_model', 'profile', 'city', 'read']),
  'app_sections': ToolReference(['in_drawer', 'start_page', 'start_pages']),
};
