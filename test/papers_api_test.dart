import 'package:flutter_test/flutter_test.dart';
import 'package:teleai/features/papers/papers_api.dart';

void main() {
  group('normalizeId', () {
    test('arXiv ids and links lose their version', () {
      expect(PapersApi.normalizeId('2005.11401v3'), 'ARXIV:2005.11401');
      expect(PapersApi.normalizeId('https://arxiv.org/abs/1706.03762v7'), 'ARXIV:1706.03762');
      expect(PapersApi.normalizeId('https://arxiv.org/pdf/1706.03762.pdf'), 'ARXIV:1706.03762');
      expect(PapersApi.normalizeId('scholarxiv.com/abs/2401.01234'), 'ARXIV:2401.01234');
      expect(PapersApi.normalizeId('arxiv:hep-th/9901001v1'), 'ARXIV:hep-th/9901001');
      expect(PapersApi.normalizeId('arXiv:2401.01234v2'), 'ARXIV:2401.01234');
    });

    test('DOIs, S2, OpenAlex and PubMed', () {
      expect(PapersApi.normalizeId('10.1038/nature14539'), 'DOI:10.1038/nature14539');
      expect(PapersApi.normalizeId('https://doi.org/10.1038/nature14539'), 'DOI:10.1038/nature14539');
      expect(PapersApi.normalizeId('doi:10.1038/nature14539'), 'DOI:10.1038/nature14539');
      const s2 = '204e3073870fae3d05bcbc2f6a8e263d9b72e776';
      expect(PapersApi.normalizeId(s2), s2);
      expect(PapersApi.normalizeId('s2:$s2'), s2);
      expect(PapersApi.normalizeId('https://www.semanticscholar.org/paper/Attention-Is-All/$s2'), s2);
      expect(PapersApi.normalizeId('openalex:W2741809807'), 'OPENALEX:W2741809807');
      expect(PapersApi.normalizeId('https://openalex.org/W2741809807'), 'OPENALEX:W2741809807');
      expect(PapersApi.normalizeId('pubmed:32511208'), 'PMID:32511208');
      expect(PapersApi.normalizeId('PMC1234567'), 'PMCID:PMC1234567');
      expect(PapersApi.normalizeId('CorpusId:215416146'), 'CorpusId:215416146');
    });
  });

  group('paper', () {
    test('an arXiv corpus result', () {
      final p = PapersApi.paper({
        'id': 'http://arxiv.org/abs/1706.03762v7',
        'extractedID': '1706.03762v7',
        'title': 'Attention Is\n  All You Need',
        'summary': 'The dominant  sequence models...',
        'authors': ['Ashish Vaswani', 'Noam Shazeer'],
        'published': '2017-06-12T17:57:34Z',
        'primaryCategory': 'cs.CL',
        'category': ['cs.CL', 'cs.LG'],
        'pdfLink': 'https://arxiv.org/pdf/1706.03762v7',
      });
      expect(p['id'], 'ARXIV:1706.03762');
      expect(p['title'], 'Attention Is All You Need');
      expect(p['summary'], 'The dominant sequence models...');
      expect(p['year'], 2017);
      expect(p['published'], '2017-06-12');
      expect(p['source'], 'arxiv');
      expect(p['url'], 'https://arxiv.org/abs/1706.03762v7');
      expect(p['scholarxiv_url'], 'https://scholarxiv.com/abs/1706.03762v7');
    });

    test('a federated result prefers the Semantic Scholar id', () {
      final p = PapersApi.paper({
        'externalID': 's2:abc',
        'source': 'semantic_scholar',
        'sources': ['semantic_scholar', 'openalex'],
        'title': 'X',
        'authors': ['A', 'B'],
        'year': 2020,
        'doi': 'https://doi.org/10.1/x',
        'citationCount': 42,
        'tldr': 'Short.',
        's2AuthorIds': ['1', null],
        'openAlexId': 'https://openalex.org/W99',
      });
      expect(p['id'], 'abc');
      expect(p['doi'], '10.1/x');
      expect(p['citations'], 42);
      expect(p['sources'], ['semantic_scholar', 'openalex']);
      expect(p['s2_author_ids'], ['1', null]);
      expect(p['openalex_id'], 'W99');
      final b = PapersApi.brief(p);
      expect(b.containsKey('s2_author_ids'), isFalse);
      expect(b['tldr'], 'Short.');
    });
  });
}
