import 'dart:convert';

import 'package:http/http.dart' as http;

class PapersException implements Exception {
  const PapersException(this.message, {this.status});
  final String message;
  final int? status;
  @override
  String toString() => message;
}

/// The ScholarXIV Papers API (scholarxiv.com/developers) with the person's
/// `sxv_` key: the arXiv corpus on every plan, and on Go and above a search
/// across eleven sources, Semantic Scholar lookups, recommendations, venues
/// and author profiles.
///
/// Every paper is reshaped into one map, the same for the model and the
/// cards, whichever endpoint or source it came from (see [paper]).
class PapersApi {
  PapersApi(this.key, {http.Client? client}) : _http = client ?? http.Client();
  final String key;
  final http.Client _http;

  // The bare domain answers with a 307 to www, which POSTs don't follow.
  static const host = 'www.scholarxiv.com';

  /// Every source federated search can reach, in the order ScholarXIV lists them.
  static const sources = [
    'arxiv',
    'openalex',
    'semantic_scholar',
    'pubmed',
    'europepmc',
    'crossref',
    'biorxiv',
    'medrxiv',
    'chemrxiv',
    'chinarxiv',
    'clinicaltrials',
  ];

  static String sourceLabel(String s) => switch (s) {
    'arxiv' => 'arXiv',
    'openalex' => 'OpenAlex',
    'semantic_scholar' => 'Semantic Scholar',
    'pubmed' => 'PubMed',
    'europepmc' => 'Europe PMC',
    'crossref' => 'Crossref',
    'biorxiv' => 'bioRxiv',
    'medrxiv' => 'medRxiv',
    'chemrxiv' => 'ChemRxiv',
    'chinarxiv' => 'ChinaXiv',
    'clinicaltrials' => 'ClinicalTrials.gov',
    _ => s,
  };

  Future<Map<String, dynamic>> _send(String method, String path, {Map<String, String>? query, Object? body}) async {
    if (key.trim().isEmpty) {
      throw const PapersException('This needs a ScholarXIV API key. The user can add one in Settings → More apps → Papers (scholarxiv.com/developers).');
    }
    final uri = Uri.https(host, path, query);
    final headers = {'authorization': 'Bearer ${key.trim()}', 'accept': 'application/json', if (body != null) 'content-type': 'application/json'};
    final r = await (method == 'POST' ? _http.post(uri, headers: headers, body: jsonEncode(body)) : _http.get(uri, headers: headers))
        .timeout(const Duration(seconds: 45));
    Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(r.bodyBytes));
    } catch (_) {}
    if (r.statusCode >= 400) {
      final said = decoded is Map ? '${decoded['error'] ?? decoded['message'] ?? ''}' : '';
      final retry = r.headers['retry-after'];
      throw PapersException(switch (r.statusCode) {
        401 => 'ScholarXIV refused the API key${said.isEmpty ? '' : ' ($said)'}. Check it in Settings → More apps → Papers.',
        403 => 'This needs the ScholarXIV Go plan or above (federated search and paper details). Searching the arXiv corpus with paper_search works on every plan.',
        404 => said.isEmpty ? 'ScholarXIV found no record of that.' : said,
        429 => 'The ScholarXIV hourly limit is reached${retry == null ? '' : '; try again in about $retry seconds'}.',
        502 || 503 => 'Semantic Scholar is busy right now${retry == null ? '' : ' (retry in ${retry}s)'}; try again shortly.',
        _ => 'ScholarXIV said ${r.statusCode}${said.isEmpty ? '' : ': $said'}',
      }, status: r.statusCode);
    }
    if (decoded is! Map) throw const PapersException('ScholarXIV sent an answer this app couldn\'t read.');
    return Map<String, dynamic>.from(decoded);
  }

  static List<Map<String, dynamic>> _list(Object? v) => [
    for (final x in (v as List? ?? const []))
      if (x is Map) paper(x),
  ];

  /// The arXiv corpus: any of the fielded filters, ANDed together.
  Future<Map<String, dynamic>> search({
    String? all,
    String? title,
    String? author,
    String? abstract,
    String? category,
    String? arxivId,
    String? journal,
    String sort = 'relevance',
    int page = 0,
    int limit = 10,
  }) async {
    final filters = {
      'all': ?_clean(all),
      'ti': ?_clean(title),
      'au': ?_clean(author),
      'abs': ?_clean(abstract),
      'cat': ?_clean(category),
      'id': ?_clean(arxivId),
      'jr': ?_clean(journal),
    };
    if (filters.isEmpty) throw const PapersException('Give a query or at least one of title, author, abstract, category or arxiv_id.');
    final body = await _send('POST', '/api/v1/papers/search', body: {
      'searchFilterString': filters,
      'page': page,
      'limit': limit,
      'sortBy': switch (sort) {
        'newest' => 'submittedDate',
        'updated' => 'lastUpdatedDate',
        _ => 'relevance',
      },
      'sortOrder': sort == 'relevance' ? 'ascending' : 'descending',
    });
    return {'papers': _list(body['data']), 'pagination': body['pagination']};
  }

  /// Eleven sources at once, merged and deduplicated. [limit] is per source.
  Future<Map<String, dynamic>> federated({
    required String query,
    List<String> sources = const [],
    int? fromYear,
    int? toYear,
    String sort = 'relevance',
    int page = 0,
    int limit = 5,
  }) async {
    final body = await _send('POST', '/api/v1/papers/federated/search', body: {
      'q': query,
      'page': page,
      'limit': limit,
      if (sources.isNotEmpty) 'sources': sources,
      'fromYear': ?fromYear,
      'toYear': ?toYear,
      'sort': sort,
    });
    return {'papers': _list(body['data']), 'by_source': body['bySource'], 'pagination': body['pagination']};
  }

  Future<Map<String, dynamic>> lookup(String id) async => paper((await _send('GET', '/api/v1/papers/lookup', query: {'id': normalizeId(id)}))['data'] as Map? ?? const {});

  Future<List<Map<String, dynamic>>> recommendations(String id) async =>
      _list((await _send('GET', '/api/v1/papers/recommendations', query: {'id': normalizeId(id)}))['data']);

  Future<Map<String, dynamic>> venue(String id, {List<String> issn = const [], String? name, String? openAlexId}) async {
    final body = await _send('GET', '/api/v1/papers/venue', query: {
      'id': normalizeId(id),
      if (issn.isNotEmpty) 'issn': issn.take(4).join(','),
      'name': ?_clean(name),
      'openAlexId': ?_clean(openAlexId),
    });
    return Map<String, dynamic>.from(body['data'] as Map? ?? const {});
  }

  /// One of a paper's authors, by their place on it (never a name search).
  Future<Map<String, dynamic>> paperAuthor(String id, {required int index, required String name, String? openAlexId}) async {
    final body = await _send('GET', '/api/v1/papers/author', query: {
      'id': normalizeId(id),
      'index': '$index',
      'name': name,
      'openAlexId': ?_clean(openAlexId),
    });
    return Map<String, dynamic>.from(body['data'] as Map? ?? const {});
  }

  /// A Semantic Scholar author profile by its numeric id.
  Future<Map<String, dynamic>> author(String authorId) async {
    final id = authorId.trim().replaceAll(RegExp(r'^.*/author/(?:[^/]+/)?'), '');
    if (!RegExp(r'^\d{1,20}$').hasMatch(id)) throw const PapersException('author_id must be a numeric Semantic Scholar author id.');
    final body = await _send('GET', '/api/v1/authors/$id');
    return Map<String, dynamic>.from(body['data'] as Map? ?? const {});
  }

  /// The author of [p] at [index]: by Semantic Scholar id when the paper
  /// carries one, otherwise by place on the paper.
  Future<Map<String, dynamic>> authorOf(Map<String, dynamic> p, int index) async {
    final ids = p['s2_author_ids'] as List? ?? const [];
    final s2 = index < ids.length ? ids[index] : null;
    if (s2 != null && '$s2'.isNotEmpty) return author('$s2');
    final names = p['authors'] as List? ?? const [];
    final ref = '${p['id'] ?? ''}';
    if (ref.isEmpty || index >= names.length) throw const PapersException('This paper doesn\'t carry an id to look its authors up with.');
    return paperAuthor(ref, index: index, name: '${names[index]}', openAlexId: p['openalex_id'] as String?);
  }

  static String? _clean(String? s) {
    final t = s?.trim() ?? '';
    return t.isEmpty ? null : t;
  }

  static final _arxivNew = RegExp(r'^\d{4}\.\d{4,5}(v\d+)?$');
  static final _arxivOld = RegExp(r'^[a-z\-]+(\.[A-Z]{2})?/\d{7}(v\d+)?$');

  static bool isArxivId(String s) => _arxivNew.hasMatch(s) || _arxivOld.hasMatch(s);

  /// Any way a person or the model names a paper → an id the lookups take:
  /// links (arXiv, doi.org, Semantic Scholar, OpenAlex, PubMed, ScholarXIV),
  /// bare arXiv ids and DOIs, or an already prefixed id.
  static String normalizeId(String raw) {
    var s = raw.trim();
    if (s.isEmpty) throw const PapersException('A paper id is required.');
    final prefixed = RegExp(r'^(DOI|ARXIV|PMID|PMCID|CorpusId|OPENALEX|MAG|ACL|URL):(.+)$', caseSensitive: false).firstMatch(s);
    if (prefixed != null) {
      final kind = prefixed[1]!.toUpperCase();
      final rest = prefixed[2]!.trim();
      return switch (kind) {
        'ARXIV' => 'ARXIV:${rest.replaceAll(RegExp(r'v\d+$'), '')}',
        'CORPUSID' => 'CorpusId:$rest',
        'OPENALEX' => 'OPENALEX:${rest.split('/').last.toUpperCase()}',
        _ => '$kind:$rest',
      };
    }
    // Namespaced federated ids: arxiv:…, s2:…, openalex:…, pubmed:…
    if (s.startsWith('arxiv:')) s = s.substring(6);
    if (s.startsWith('s2:')) return s.substring(3);
    if (s.startsWith('openalex:')) return 'OPENALEX:${s.substring(9).split('/').last.toUpperCase()}';
    if (s.startsWith('pubmed:')) return 'PMID:${s.substring(7)}';
    final arxivLink = RegExp(r'(?:arxiv\.org|scholarxiv\.com)/(?:abs|pdf|html)/([^\s?#]+?)(?:\.pdf)?(?:[?#]|$)').firstMatch(s);
    if (arxivLink != null) return 'ARXIV:${arxivLink[1]!.replaceAll(RegExp(r'v\d+$'), '')}';
    final doi = RegExp(r'(10\.\d{4,9}/[^\s]+)').firstMatch(s);
    if (doi != null && (s.startsWith('10.') || s.contains('doi.org/'))) return 'DOI:${doi[1]!.replaceAll(RegExp(r'[.,;]+$'), '')}';
    final s2Link = RegExp(r'semanticscholar\.org/paper/(?:[^/]+/)?([0-9a-f]{40})').firstMatch(s);
    if (s2Link != null) return s2Link[1]!;
    final oaLink = RegExp(r'openalex\.org/(?:works/)?(W\d+)', caseSensitive: false).firstMatch(s);
    if (oaLink != null) return 'OPENALEX:${oaLink[1]!.toUpperCase()}';
    final pmLink = RegExp(r'pubmed\.ncbi\.nlm\.nih\.gov/(\d+)').firstMatch(s);
    if (pmLink != null) return 'PMID:${pmLink[1]}';
    if (isArxivId(s)) return 'ARXIV:${s.replaceAll(RegExp(r'v\d+$'), '')}';
    if (RegExp(r'^[0-9a-f]{40}$').hasMatch(s)) return s;
    if (RegExp(r'^PMC\d+$', caseSensitive: false).hasMatch(s)) return 'PMCID:${s.toUpperCase()}';
    if (RegExp(r'^W\d{2,12}$', caseSensitive: false).hasMatch(s)) return 'OPENALEX:${s.toUpperCase()}';
    return s;
  }

  // ---- shaping ------------------------------------------------------------------

  static String? _s(Object? v) {
    final t = v == null ? '' : '$v'.trim();
    return t.isEmpty || t == 'null' ? null : t;
  }

  static List<String> _strings(Object? v) => [
    for (final x in (v as List? ?? const []))
      ?_s(x),
  ];

  /// A paper from any endpoint (the arXiv corpus or a federated source) as
  /// the cards and the model read it. `id` is what the lookups take.
  static Map<String, dynamic> paper(Map raw) {
    final m = Map<String, dynamic>.from(raw);
    final external = _s(m['externalID']) ?? '';
    final source = _s(m['source']) ?? (m['extractedID'] != null ? 'arxiv' : null);
    var arxiv = _s(m['extractedID']) ?? (external.startsWith('arxiv:') ? external.substring(6) : null);
    if (arxiv != null && !isArxivId(arxiv)) arxiv = null;
    final arxivBase = arxiv?.replaceAll(RegExp(r'v\d+$'), '');
    final doi = _s(m['doi'])?.replaceFirst(RegExp(r'^https?://(dx\.)?doi\.org/'), '');
    final s2 = _s(m['s2Id']) ?? (external.startsWith('s2:') ? external.substring(3) : null);
    final openAlex = (_s(m['openAlexId']) ?? (external.startsWith('openalex:') ? external.substring(9) : null))?.split('/').last.toUpperCase();
    final pmid = _s(m['pmid']) ?? (external.startsWith('pubmed:') ? external.substring(7) : null);
    final pmcid = _s(m['pmcid']);
    final id = s2 ??
        (doi != null && doi.startsWith('10.') ? 'DOI:$doi' : null) ??
        (arxivBase != null ? 'ARXIV:$arxivBase' : null) ??
        (pmid != null ? 'PMID:$pmid' : null) ??
        (pmcid != null ? 'PMCID:$pmcid' : null) ??
        (openAlex != null && RegExp(r'^W\d+$').hasMatch(openAlex) ? 'OPENALEX:$openAlex' : null);
    final published = _s(m['published']);
    final year = (m['year'] as num?)?.toInt() ?? int.tryParse((published ?? '').length >= 4 ? published!.substring(0, 4) : '');
    final categories = _strings(m['category']);
    final s2Authors = m['s2AuthorIds'] is List ? [for (final a in m['s2AuthorIds'] as List) _s(a)] : null;
    final allSources = _strings(m['sources']);
    final summary = (_s(m['summary']) ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
    var url = _s(m['url']) ?? (arxiv != null ? 'https://arxiv.org/abs/$arxiv' : null);
    if (url == null && doi != null) url = 'https://doi.org/$doi';
    if (url == null && s2 != null) url = 'https://www.semanticscholar.org/paper/$s2';
    return {
      'id': ?id,
      'title': (_s(m['title']) ?? 'Untitled').replaceAll(RegExp(r'\s+'), ' '),
      'authors': _strings(m['authors']),
      if (summary.isNotEmpty) 'summary': summary,
      'tldr': ?_s(m['tldr']),
      'year': ?year,
      if (published != null) 'published': published.split('T').first,
      if (_s(m['updated']) case final u?) 'updated': u.split('T').first,
      'venue': ?_s(m['venue']),
      'journal_ref': ?_s(m['journalRef']),
      'category': ?_s(m['primaryCategory']),
      if (categories.isNotEmpty) 'categories': categories,
      'citations': ?(m['citationCount'] as num?)?.toInt(),
      'source': ?source,
      if (allSources.length > 1) 'sources': allSources,
      'arxiv_id': ?arxiv,
      'doi': ?doi,
      's2_id': ?s2,
      if (s2Authors != null && s2Authors.any((a) => a != null)) 's2_author_ids': s2Authors,
      if (openAlex != null && RegExp(r'^W\d+$').hasMatch(openAlex)) 'openalex_id': openAlex,
      'pmid': ?pmid,
      'pmcid': ?pmcid,
      'pdf': ?_s(m['pdfLink']),
      'url': ?url,
      if (arxiv != null) 'scholarxiv_url': 'https://scholarxiv.com/abs/$arxiv',
      'comment': ?_s(m['comment']),
      'license': ?_s(m['license']),
      'type': ?_s(m['workType']),
      if (_strings(m['issn']).isNotEmpty) 'issn': _strings(m['issn']) else if (_s(m['issn']) case final i?) 'issn': [i],
    };
  }

  /// [p] shortened for the model: the abstract clipped, ids it doesn't need
  /// dropped. The cards keep the full paper.
  static Map<String, dynamic> brief(Map<String, dynamic> p, {int abstractChars = 500}) {
    final summary = p['summary'] as String?;
    final authors = (p['authors'] as List? ?? const []);
    return {
      for (final e in p.entries)
        if (!const {'s2_author_ids', 'scholarxiv_url', 'issn', 'summary', 'authors', 'categories', 'pmcid', 'license', 'comment'}.contains(e.key)) e.key: e.value,
      'authors': authors.length > 8 ? [...authors.take(8), '+${authors.length - 8} more'] : authors,
      if (summary != null) 'summary': summary.length > abstractChars ? '${summary.substring(0, abstractChars)}…' : summary,
    };
  }
}
