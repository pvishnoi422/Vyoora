// lib/result_screen.dart
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'components/vyoora_scaffold.dart';

class ResultScreen extends StatelessWidget {
  final Map<String, dynamic> result;
  const ResultScreen({Key? key, required this.result}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final hasNew = result.containsKey('summary') && result.containsKey('concerns');

    final String summary = hasNew
        ? (result['summary'] as String? ?? 'No summary available.')
        : ((result['ingredients'] is List && (result['ingredients'] as List).isNotEmpty)
            ? 'This product contains ${(result['ingredients'] as List).length} ingredients. Key concerns, if any, are listed below.'
            : 'No ingredients found.');

    final List<Map<String, dynamic>> concerns = hasNew
        ? ((result['concerns'] as List<dynamic>? ?? [])
            .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map))
            .toList())
        : _concernsFromOld(result);

    final List<String> sources = hasNew
        ? (List<String>.from(result['sources'] ?? const []))
        : _fallbackSourcesFromOld(concerns);

    return VyooraScaffold(
      title: 'Analysis Results',
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _SummaryCard(text: summary),
          const SizedBox(height: 16),
          if (concerns.isEmpty)
            const _GoodNews()
          else
            ...concerns.map((c) => _ConcernTile(
                  ingredient: (c['ingredient'] ?? '').toString(),
                  reason: (c['reason'] ?? '').toString(),
                  references: (c['references'] is List)
                      ? List<String>.from(c['references'])
                      : const <String>[],
                  links: (c['links'] is List)
                      ? List<Map<String, dynamic>>.from(
                          (c['links'] as List).map((e) => Map<String, dynamic>.from(e as Map)))
                      : const <Map<String, dynamic>>[],
                )),
          const SizedBox(height: 12),
          _SourcesFooter(sources: sources),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  List<Map<String, dynamic>> _concernsFromOld(Map<String, dynamic> res) {
    final List items = (res['ingredients'] ?? []) as List;
    return items.where((raw) {
      final m = (raw as Map).map((k, v) => MapEntry(k.toString(), v));
      final cls = (m['classification'] ?? m['safety'] ?? '').toString().toLowerCase();
      return cls == 'irritant' || cls == 'comedogenic';
    }).map<Map<String, dynamic>>((raw) {
      final m = (raw as Map).map((k, v) => MapEntry(k.toString(), v));
      return {
        'ingredient': (m['ingredient'] ?? m['name'] ?? '').toString(),
        'reason': (m['reason'] ?? 'Flagged by classifier.').toString(),
        'references': const <String>[],
        'links': const <Map<String, dynamic>>[],
      };
    }).toList();
  }

  List<String> _fallbackSourcesFromOld(List<Map<String, dynamic>> concerns) {
    return concerns.isEmpty ? const [] : const ['Peer-reviewed literature'];
  }
}

class _SummaryCard extends StatelessWidget {
  final String text;
  const _SummaryCard({required this.text});
  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Overview',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 8),
            Text(text, style: const TextStyle(fontSize: 14)),
          ],
        ),
      ),
    );
  }
}

class _GoodNews extends StatelessWidget {
  const _GoodNews();
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.green.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.green.withOpacity(0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Icon(Icons.check_circle, color: Colors.green),
          SizedBox(width: 10),
          Expanded(
            child: Text('No major unsafe ingredients detected.',
                style: TextStyle(color: Colors.green, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

class _ConcernTile extends StatelessWidget {
  final String ingredient;
  final String reason;
  final List<String> references;
  final List<Map<String, dynamic>> links;

  const _ConcernTile({
    required this.ingredient,
    required this.reason,
    required this.references,
    required this.links,
  });

  @override
  Widget build(BuildContext context) {
    final chips = <Widget>[];

    if (links.isNotEmpty) {
      for (final m in links) {
        final src = (m['source'] ?? '').toString();
        final url = (m['url'] ?? '').toString();
        chips.add(ActionChip(
          label: Text(src),
          onPressed: url.isEmpty ? null : () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
        ));
      }
    } else {
      for (final r in references) {
        chips.add(Chip(label: Text(r)));
      }
    }

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.red.withOpacity(0.2)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: const [
              Icon(Icons.warning, color: Colors.red),
              SizedBox(width: 8),
              Text('Concern', style: TextStyle(fontWeight: FontWeight.w700)),
            ]),
            const SizedBox(height: 8),
            Text(ingredient.isEmpty ? 'Unnamed ingredient' : ingredient,
                style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(reason),
            if (chips.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(spacing: 6, runSpacing: 6, children: chips),
            ],
          ],
        ),
      ),
    );
  }
}

class _SourcesFooter extends StatelessWidget {
  final List<String> sources;
  const _SourcesFooter({required this.sources});
  @override
  Widget build(BuildContext context) {
    if (sources.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Sources referenced',
            style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: sources
              .map((s) => Chip(
                    label: Text(s),
                    side: BorderSide(color: Colors.grey.shade300),
                  ))
              .toList(),
        ),
        const SizedBox(height: 8),
        Text(
          'Taps open official ingredient monographs (CIR, EU CosIng, PubChem, IFRA, PubMed). '
          'Individual reactions vary — patch test first.',
          style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
        ),
      ],
    );
  }
}
