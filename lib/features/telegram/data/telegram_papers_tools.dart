part of 'telegram_tools.dart';

// Research papers from ScholarXIV's Papers API (scholarxiv.com), with the
// person's sxv_ key (Settings → More apps → Papers). paper_search reads the
// arXiv corpus on every plan; the rest need the Go plan. The cards are in
// papers_result_cards.dart. The model gets clipped abstracts; the cards get
// every field through ToolOutput.full.

const _paperFields =
    'Each paper has id (pass it to the other paper tools), title, authors, year, venue or category, citations, a '
    'one-line TLDR when Semantic Scholar has one, the abstract, and PDF and page links.';

const _paperCardNote = 'The user sees paper cards they can open for the full abstract, links and authors, so summarise rather than list every field.';

final _papersTools = <TelegramTool>[
  TelegramTool(
    name: 'paper_search',
    label: 'Searching papers',
    category: ToolCategory.papers,
    cost: ToolCost.web,
    description:
        'Searches the arXiv corpus on ScholarXIV (millions of preprints in physics, maths, CS, biology, economics…). Use '
        'query for keywords anywhere in a paper, or narrow with title, author (comma-separated for several), abstract, '
        'category (arXiv code like cs.CL, hep-th, q-bio.NC) or arxiv_id; filters combine. Sort newest for recent work. '
        '$_paperFields $_paperCardNote',
    parameters: _obj({
      'query': {'type': 'string', 'description': 'Keywords matched against title, abstract, authors, categories, comments and DOI.'},
      'title': {'type': 'string', 'description': 'Words in the title.'},
      'author': {'type': 'string', 'description': 'An author name, or several comma-separated.'},
      'abstract': {'type': 'string', 'description': 'Words in the abstract.'},
      'category': {'type': 'string', 'description': 'arXiv category, e.g. cs.LG, cs.CV, math.AG, astro-ph.GA.'},
      'arxiv_id': {'type': 'string', 'description': 'An arXiv id like 1706.03762.'},
      'sort': {'type': 'string', 'enum': ['relevance', 'newest', 'updated'], 'description': 'Default relevance.'},
      'limit': {'type': 'integer', 'description': '1-30, default 10.'},
      'page': {'type': 'integer', 'description': 'Zero-based page, default 0.'},
    }),
  ),
  TelegramTool(
    name: 'paper_search_everywhere',
    label: 'Searching papers across sources',
    category: ToolCategory.papers,
    cost: ToolCost.web,
    description:
        'Searches eleven academic sources at once and merges duplicates: arXiv, OpenAlex, Semantic Scholar, PubMed, '
        'Europe PMC, Crossref, bioRxiv, medRxiv, ChemRxiv, ChinaXiv and ClinicalTrials.gov. Use it for published journal '
        'articles, medicine and biology, citation counts, or anything beyond arXiv; sort by citations for the most '
        'influential work. Needs the ScholarXIV Go plan. $_paperFields $_paperCardNote',
    parameters: _obj({
      'query': {'type': 'string', 'description': 'What to look for.'},
      'sources': {
        'type': 'array',
        'items': {'type': 'string', 'enum': PapersApi.sources},
        'description': 'Only these sources. Default: all eleven.',
      },
      'from_year': {'type': 'integer', 'description': 'Published in or after this year.'},
      'to_year': {'type': 'integer', 'description': 'Published in or before this year.'},
      'sort': {'type': 'string', 'enum': ['relevance', 'date', 'citations'], 'description': 'Default relevance. citations works for OpenAlex, Crossref and Semantic Scholar.'},
      'limit': {'type': 'integer', 'description': 'Results per source, 1-20, default 4 (all sources × 4 is up to ~40 papers before merging).'},
      'page': {'type': 'integer', 'description': 'Zero-based page, applied per source. Default 0.'},
    }, ['query']),
  ),
  TelegramTool(
    name: 'paper_details',
    label: 'Looking up a paper',
    category: ToolCategory.papers,
    cost: ToolCost.web,
    description:
        'One paper\'s full record from Semantic Scholar: title, authors, abstract, venue, year, citation count, '
        'open-access PDF and ids. Takes any id: a paper id from the other paper tools, an arXiv id or link, a DOI or '
        'doi.org link, a Semantic Scholar or PubMed link, PMID:…, or CorpusId:…. Needs the ScholarXIV Go plan.',
    parameters: _obj({
      'paper': {'type': 'string', 'description': 'Any paper id or link.'},
    }, ['paper']),
  ),
  TelegramTool(
    name: 'paper_recommendations',
    label: 'Finding related papers',
    category: ToolCategory.papers,
    cost: ToolCost.web,
    description:
        'Up to 20 papers Semantic Scholar recommends for one paper (similar work, with TLDRs). Use it for "papers like '
        'this" or to build a reading list. Very new papers often have none yet. Needs the ScholarXIV Go plan.',
    parameters: _obj({
      'paper': {'type': 'string', 'description': 'Any paper id or link.'},
      'limit': {'type': 'integer', 'description': '1-20, default 10.'},
    }, ['paper']),
  ),
  TelegramTool(
    name: 'paper_author',
    label: 'Looking up an author',
    category: ToolCategory.papers,
    cost: ToolCost.web,
    description:
        'A researcher\'s profile: affiliations, paper and citation counts, h-index, ORCID, homepage, papers per year, top '
        'papers and venues. Give author_id (a Semantic Scholar id from a paper\'s s2_author_ids), or paper plus index '
        '(their 0-based place in that paper\'s authors) and name. It never searches by name alone, so you get the right '
        'person or nothing. Needs the ScholarXIV Go plan.',
    parameters: _obj({
      'author_id': {'type': 'string', 'description': 'A numeric Semantic Scholar author id.'},
      'paper': {'type': 'string', 'description': 'A paper id or link the author is on.'},
      'index': {'type': 'integer', 'description': 'The author\'s 0-based place in that paper\'s authors.'},
      'name': {'type': 'string', 'description': 'The author\'s name as the paper spells it.'},
    }),
  ),
  TelegramTool(
    name: 'paper_venue',
    label: 'Looking up a journal',
    category: ToolCategory.papers,
    cost: ToolCost.web,
    description:
        'The journal or conference a paper appeared in: name, type, publisher, country, h-index, works and citations, '
        'open-access status, article charge (APC), years active and topics. Needs the ScholarXIV Go plan.',
    parameters: _obj({
      'paper': {'type': 'string', 'description': 'A paper id or link.'},
      'name': {'type': 'string', 'description': 'The venue name as the paper gives it (helps the fallback).'},
      'issn': {'type': 'string', 'description': 'Up to 4 comma-separated ISSNs, if known.'},
    }, ['paper']),
  ),
];

final _papersToolNames = {for (final t in _papersTools) t.name};

const _papersPolicies = <String, ToolPolicy>{
  'paper_search': ToolPolicy(ToolAccess.read),
  'paper_search_everywhere': ToolPolicy(ToolAccess.read),
  'paper_details': ToolPolicy(ToolAccess.read),
  'paper_recommendations': ToolPolicy(ToolAccess.read),
  'paper_author': ToolPolicy(ToolAccess.read),
  'paper_venue': ToolPolicy(ToolAccess.read),
};

const _paperOut = 'papers: id, title, authors, year, published, venue, category, citations, tldr, summary (clipped), source(s), arxiv_id, doi, pdf, url';

const _papersReferences = <String, ToolReference>{
  'paper_search': ToolReference(['query', 'count', _paperOut, 'has_more', 'next_page'], limits: ['limit: 1-30. arXiv only. Every ScholarXIV plan.']),
  'paper_search_everywhere': ToolReference(['query', 'count', _paperOut, 'by_source', 'has_more', 'next_page'], limits: ['limit: 1-20 per source. Go plan or above.']),
  'paper_details': ToolReference(['paper: every field above plus s2_author_ids, openalex_id, pmid, issn, license'], limits: ['Go plan or above.']),
  'paper_recommendations': ToolReference(['for', 'count', _paperOut], limits: ['Up to 20. Go plan or above.']),
  'paper_author': ToolReference([
    'name', 'affiliations', 'paper_count', 'citation_count', 'h_index', 'orcid', 'homepage', 'url', //
    'first_year', 'last_year', 'top_papers', 'top_venues', 'papers_by_year', 'openalex',
  ], limits: ['Go plan or above.']),
  'paper_venue': ToolReference(['name', 'type', 'publisher', 'country', 'h_index', 'works', 'citations', 'open_access', 'apc_usd', 'topics', 'url'], limits: ['Go plan or above.']),
};

/// What a paper tool still needs, for the Tools list and the model.
String? papersToolNeeds(TelegramTool t, AppSettings s) =>
    _papersToolNames.contains(t.name) && !s.hasScholarxivKey ? 'Add a ScholarXIV key in More apps → Papers.' : null;

extension _PapersToolRuns on TelegramToolRunner {
  Future<ToolOutput>? _runPapers(String name, Map<String, dynamic> args) {
    if (!_papersToolNames.contains(name)) return null;
    return _papersWrap(_papers(PapersApi(_settings.scholarxivKey), name, args));
  }

  static Future<ToolOutput> _papersWrap(Future<ToolOutput> f) async {
    try {
      return await f;
    } on PapersException catch (e) {
      return ToolOutput({'error': e.message});
    } on TimeoutException {
      return const ToolOutput({'error': 'ScholarXIV took too long to answer; try again.'});
    } on SocketException {
      return const ToolOutput({'error': 'Couldn\'t reach scholarxiv.com; check the connection.'});
    }
  }

  /// Clipped papers for the model, every field for the cards.
  static ToolOutput _paperList(Map<String, dynamic> head, List<Map<String, dynamic>> papers, {Map<String, dynamic> tail = const {}}) => ToolOutput(
    {...head, 'count': papers.length, 'papers': [for (final p in papers) PapersApi.brief(p)], ...tail},
    full: {...head, 'count': papers.length, 'papers': papers, ...tail},
  );

  static Map<String, dynamic> _page(Object? pagination) {
    final p = pagination as Map? ?? const {};
    return {'has_more': p['hasMore'] == true, 'next_page': ?p['nextPage']};
  }

  Future<ToolOutput> _papers(PapersApi api, String name, Map<String, dynamic> a) async {
    String? s(String k) {
      final v = '${a[k] ?? ''}'.trim();
      return v.isEmpty ? null : v;
    }

    int n(String k, int d, int min, int max) => ((a[k] as num?)?.toInt() ?? d).clamp(min, max);

    switch (name) {
      case 'paper_search':
        final r = await api.search(
          all: s('query'),
          title: s('title'),
          author: s('author'),
          abstract: s('abstract'),
          category: s('category'),
          arxivId: s('arxiv_id'),
          sort: s('sort') ?? 'relevance',
          limit: n('limit', 10, 1, 30),
          page: n('page', 0, 0, 1000),
        );
        final label = [
          ?s('query'),
          if (s('title') case final t?) 'title: $t',
          if (s('author') case final t?) 'by $t',
          if (s('abstract') case final t?) 'abstract: $t',
          ?s('category'),
          ?s('arxiv_id'),
        ].join(' · ');
        return _paperList(
          {'query': label, 'source': 'arXiv via ScholarXIV', 'sort': s('sort') ?? 'relevance'},
          (r['papers'] as List).cast<Map<String, dynamic>>(),
          tail: _page(r['pagination']),
        );
      case 'paper_search_everywhere':
        final q = s('query');
        if (q == null) return const ToolOutput({'error': 'query is required'});
        final chosen = [
          for (final x in (a['sources'] as List? ?? const []))
            if (PapersApi.sources.contains('$x'.trim().toLowerCase())) '$x'.trim().toLowerCase(),
        ];
        final r = await api.federated(
          query: q,
          sources: chosen,
          fromYear: (a['from_year'] as num?)?.toInt(),
          toYear: (a['to_year'] as num?)?.toInt(),
          sort: const {'relevance', 'date', 'citations'}.contains(s('sort')) ? s('sort')! : 'relevance',
          limit: n('limit', 4, 1, 20),
          page: n('page', 0, 0, 200),
        );
        final bySource = <String, dynamic>{
          for (final e in (r['by_source'] as Map? ?? const {}).entries)
            if (((e.value as Map?)?['count'] as num? ?? 0) > 0) '${e.key}': (e.value as Map)['count'],
        };
        return _paperList(
          {'query': q, 'sort': s('sort') ?? 'relevance', if (chosen.isNotEmpty) 'sources': chosen},
          (r['papers'] as List).cast<Map<String, dynamic>>(),
          tail: {'by_source': bySource, ..._page(r['pagination'])},
        );
      case 'paper_details':
        final ref = s('paper');
        if (ref == null) return const ToolOutput({'error': 'paper is required'});
        final p = await api.lookup(ref);
        return ToolOutput({'paper': PapersApi.brief(p, abstractChars: 3000)}, full: {'paper': p});
      case 'paper_recommendations':
        final ref = s('paper');
        if (ref == null) return const ToolOutput({'error': 'paper is required'});
        final list = (await api.recommendations(ref)).take(n('limit', 10, 1, 20)).toList();
        return _paperList({'for': ref}, list, tail: {if (list.isEmpty) 'note': 'Semantic Scholar has no recommendations for this paper yet (common for very new papers).'});
      case 'paper_author':
        final Map<String, dynamic> au;
        if (s('author_id') case final id?) {
          au = await api.author(id);
        } else {
          final ref = s('paper');
          final index = (a['index'] as num?)?.toInt();
          final who = s('name');
          if (ref == null || index == null || who == null) {
            return const ToolOutput({'error': 'Give author_id, or paper with index and name.'});
          }
          au = await api.paperAuthor(ref, index: index, name: who);
        }
        return ToolOutput(_authorBrief(au), full: au);
      case 'paper_venue':
        final ref = s('paper');
        if (ref == null) return const ToolOutput({'error': 'paper is required'});
        final v = await api.venue(ref, name: s('name'), issn: [for (final i in (s('issn') ?? '').split(',')) if (i.trim().isNotEmpty) i.trim()]);
        return ToolOutput(_venueBrief(v), full: v);
    }
    return ToolOutput({'error': 'Unknown paper tool $name'});
  }

  static Map<String, dynamic> _authorBrief(Map<String, dynamic> a) {
    final oa = a['openAlex'] as Map?;
    return {
      'name': a['name'],
      'source': a['source'],
      if ('${a['authorId'] ?? ''}'.isNotEmpty) 'author_id': a['authorId'],
      if ((a['affiliations'] as List?)?.isNotEmpty ?? false) 'affiliations': a['affiliations'],
      'paper_count': ?a['paperCount'],
      'citation_count': ?a['citationCount'],
      'h_index': ?a['hIndex'],
      if ('${a['orcid'] ?? ''}'.isNotEmpty) 'orcid': a['orcid'],
      if ('${a['homepage'] ?? ''}'.isNotEmpty) 'homepage': a['homepage'],
      if ('${a['url'] ?? ''}'.isNotEmpty) 'url': a['url'],
      'first_year': ?a['firstYear'],
      'last_year': ?a['lastYear'],
      'top_papers': [
        for (final p in (a['topPapers'] as List? ?? const []).take(8))
          if (p is Map) {'title': p['title'], 'year': p['year'], 'citations': p['citationCount'], 'venue': p['venue']},
      ],
      'top_venues': [for (final v in (a['topVenues'] as List? ?? const []).take(6)) if (v is Map) '${v['name']} (${v['count']})'],
      if (oa != null) 'openalex': {'institutions': oa['institutions'], 'topics': (oa['topics'] as List? ?? const []).take(8).toList(), 'i10_index': oa['i10Index']},
    };
  }

  static Map<String, dynamic> _venueBrief(Map<String, dynamic> v) {
    final oa = v['openAlex'] as Map?;
    return {
      'name': v['name'],
      'type': v['type'],
      'source': v['source'],
      if ((v['issn'] as List?)?.isNotEmpty ?? false) 'issn': v['issn'],
      if ('${v['url'] ?? ''}'.isNotEmpty) 'url': v['url'],
      'journal': ?v['journal'],
      'paper_year': ?v['paperYear'],
      if (oa != null) ...{
        'publisher': oa['publisher'],
        'country': oa['country'],
        'h_index': oa['hIndex'],
        'works': oa['worksCount'],
        'citations': oa['citedByCount'],
        'mean_citedness_2yr': oa['meanCitedness2yr'],
        'open_access': oa['isOpenAccess'],
        'in_doaj': oa['isInDoaj'],
        'apc_usd': oa['apcUsd'],
        'first_year': oa['firstYear'],
        'last_year': oa['lastYear'],
        'topics': (oa['topics'] as List? ?? const []).take(8).toList(),
      },
    };
  }
}
