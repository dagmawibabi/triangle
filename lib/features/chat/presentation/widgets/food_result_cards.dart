import 'package:flutter/material.dart';

import '../../../../app/theme.dart';
import '../../../../core/widgets/net_image.dart';
import '../../../info/info_api.dart';
import '../../../qr/qr.dart';
import '../../domain/chat_models.dart';
import 'info_card_kit.dart';

/// Cards for recipes and food nutrition. Null for other tools.
Widget? foodResultFor(ToolPart part, Map<String, dynamic> j) => switch (part.name) {
  'recipe_search' when maps(j['recipes']).isNotEmpty => _RecipeGrid(r: j),
  'recipe_details' when j['ingredients'] != null => _RecipeCard(m: j),
  'food_nutrition' when j['per_100g'] != null => _FoodCard(f: j),
  'food_nutrition' when maps(j['products']).isNotEmpty => _FoodList(r: j),
  _ => null,
};

const _food = Color(0xFFE8833A);

// ---- recipes ----------------------------------------------------------------------

class _RecipeGrid extends StatelessWidget {
  const _RecipeGrid({required this.r});
  final Map<String, dynamic> r;

  @override
  Widget build(BuildContext context) {
    final list = maps(r['recipes']);
    return InfoFrame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InfoHeader(Icons.restaurant_menu_rounded, 'Recipes · ${r['count']}', color: _food),
          SizedBox(
            height: 196,
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(Space.m, 0, Space.m, Space.m),
              scrollDirection: Axis.horizontal,
              itemCount: list.length,
              separatorBuilder: (_, _) => const SizedBox(width: Space.s),
              itemBuilder: (context, i) {
                final m = list[i];
                return InkWell(
                  borderRadius: BorderRadius.circular(Radii.m),
                  onTap: () => showRecipe(context, '${m['id']}'),
                  child: SizedBox(
                    width: 140,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(Radii.m),
                          child: NetImage('${m['image']}/preview', width: 140, height: 128, fit: BoxFit.cover, errorWidget: NetImage('${m['image']}', width: 140, height: 128)),
                        ),
                        const SizedBox(height: 4),
                        Text('${m['name']}', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5, height: 1.2)),
                        Text([m['cuisine'], m['category']].whereType<Object>().join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.labelSmall),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> showRecipe(BuildContext context, String id) =>
    showLoadingSheet(context, () => InfoApi.instance.recipe(id), (context, m) => _recipeBody(context, m), initialSize: 0.94);

List<Widget> _recipeBody(BuildContext context, Map<String, dynamic> m) {
  final ingredients = maps(m['ingredients']);
  final steps = strs(m['steps']);
  return [
    ClipRRect(borderRadius: BorderRadius.circular(Radii.l), child: AspectRatio(aspectRatio: 16 / 10, child: NetImage('${m['image']}', fit: BoxFit.cover))),
    const SizedBox(height: Space.m),
    SheetTitle('${m['name']}', subtitle: [m['cuisine'], m['category']].whereType<Object>().join(' · ')),
    if (strs(m['tags']).isNotEmpty) ...[
      const SizedBox(height: Space.s),
      Wrap(spacing: 6, runSpacing: 6, children: [for (final t in strs(m['tags'])) InfoPill(t)]),
    ],
    SectionLabel('Ingredients', trailing: '${ingredients.length}'),
    _Checklist(items: ingredients),
    SectionLabel('Method', trailing: '${steps.length} steps'),
    for (final (i, s) in steps.indexed)
      Padding(
        padding: const EdgeInsets.only(bottom: Space.m),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 24,
              height: 24,
              alignment: Alignment.center,
              decoration: const BoxDecoration(color: _food, shape: BoxShape.circle),
              child: Text('${i + 1}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12)),
            ),
            const SizedBox(width: Space.m),
            Expanded(child: SelectableText(s, style: const TextStyle(height: 1.45))),
          ],
        ),
      ),
    sheetButtons([
      if (m['youtube'] != null) linkButton('Watch video', '${m['youtube']}', filled: true, icon: Icons.play_circle_outline_rounded),
      linkButton('Original recipe', textOf(m['source'])),
      TextButton.icon(
        onPressed: () => copyText(
          context,
          '${m['name']}\n\nIngredients:\n${[for (final x in ingredients) '- ${x['measure']} ${x['name']}'.replaceAll('  ', ' ')].join('\n')}\n\nMethod:\n${[for (final (i, s) in steps.indexed) '${i + 1}. $s'].join('\n')}',
          'Copied the recipe',
        ),
        icon: const Icon(Icons.copy_rounded, size: 18),
        label: const Text('Copy'),
      ),
    ]),
    Padding(padding: const EdgeInsets.only(top: Space.l), child: Text('From TheMealDB.', style: TextStyle(fontSize: 11.5, color: AppColors.text3))),
  ];
}

/// Ingredients the cook can tick off while shopping or cooking.
class _Checklist extends StatefulWidget {
  const _Checklist({required this.items});
  final List<Map<String, dynamic>> items;

  @override
  State<_Checklist> createState() => _ChecklistState();
}

class _ChecklistState extends State<_Checklist> {
  final _done = <int>{};

  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (final (i, x) in widget.items.indexed)
        InkWell(
          onTap: () => setState(() => _done.contains(i) ? _done.remove(i) : _done.add(i)),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                ClipRRect(borderRadius: BorderRadius.circular(6), child: NetImage('${x['image']}', width: 34, height: 34, fit: BoxFit.contain, errorWidget: const SizedBox(width: 34))),
                const SizedBox(width: Space.m),
                Expanded(
                  child: Text(
                    '${x['name']}',
                    style: TextStyle(decoration: _done.contains(i) ? TextDecoration.lineThrough : null, color: _done.contains(i) ? AppColors.text3 : null, fontWeight: FontWeight.w500),
                  ),
                ),
                Text('${x['measure']}', style: TextStyle(color: AppColors.text2, fontSize: 13)),
                const SizedBox(width: Space.s),
                Icon(_done.contains(i) ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded, size: 18, color: _done.contains(i) ? AppColors.success : AppColors.text3),
              ],
            ),
          ),
        ),
    ],
  );
}

class _RecipeCard extends StatelessWidget {
  const _RecipeCard({required this.m});
  final Map<String, dynamic> m;

  @override
  Widget build(BuildContext context) => InfoFrame(
    onTap: () => showInfoSheet(context, initialSize: 0.94, (c) => _recipeBody(c, m)),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Stack(
          children: [
            AspectRatio(aspectRatio: 2, child: NetImage('${m['image']}', fit: BoxFit.cover)),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Colors.black.withValues(alpha: 0.7)])),
              ),
            ),
            Positioned(
              left: Space.m,
              right: Space.m,
              bottom: Space.m,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${m['name']}', style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
                  Text([m['cuisine'], m['category']].whereType<Object>().join(' · '), style: const TextStyle(color: Colors.white70, fontSize: 12.5)),
                ],
              ),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.all(Space.m),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${maps(m['ingredients']).length} ingredients · ${strs(m['steps']).length} steps', style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(maps(m['ingredients']).map((x) => x['name']).join(', '), maxLines: 2, overflow: TextOverflow.ellipsis, style: context.text.bodySmall),
            ],
          ),
        ),
      ],
    ),
  );
}

// ---- nutrition --------------------------------------------------------------------

const _nutriColors = {'A': Color(0xFF038141), 'B': Color(0xFF85BB2F), 'C': Color(0xFFFECB02), 'D': Color(0xFFEE8100), 'E': Color(0xFFE63E11)};
const _novaText = {1: 'Unprocessed or minimally processed', 2: 'Processed culinary ingredient', 3: 'Processed food', 4: 'Ultra-processed food'};
const _novaColors = {1: Color(0xFF038141), 2: Color(0xFFFECB02), 3: Color(0xFFEE8100), 4: Color(0xFFE63E11)};

class _NutriScore extends StatelessWidget {
  const _NutriScore(this.grade, {this.compact = false});
  final String? grade;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (grade == null) return const SizedBox.shrink();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final g in const ['A', 'B', 'C', 'D', 'E'])
          Container(
            width: g == grade ? (compact ? 26 : 32) : (compact ? 16 : 22),
            height: g == grade ? (compact ? 30 : 38) : (compact ? 22 : 28),
            margin: const EdgeInsets.symmetric(horizontal: 1),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: g == grade ? _nutriColors[g] : _nutriColors[g]!.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(g == grade ? 8 : 4),
              border: g == grade ? Border.all(color: Colors.white, width: 2) : null,
            ),
            child: Text(g, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: g == grade ? (compact ? 15 : 18) : 11)),
          ),
      ],
    );
  }
}

Color _levelColor(String? l) => switch (l) {
  'low' => const Color(0xFF038141),
  'moderate' => const Color(0xFFEE8100),
  'high' => const Color(0xFFE63E11),
  _ => AppColors.text3,
};

class _FoodCard extends StatelessWidget {
  const _FoodCard({required this.f});
  final Map<String, dynamic> f;

  @override
  Widget build(BuildContext context) {
    final n = mapOf(f['per_100g']);
    final levels = mapOf(f['levels']);
    return InfoFrame(
      onTap: () => showFood(context, f),
      child: Padding(
        padding: const EdgeInsets.all(Space.m),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(Radii.m),
                  child: Container(color: Colors.white, child: NetImage(textOf(f['image']), width: 72, height: 72, fit: BoxFit.contain, placeholder: Icons.fastfood_outlined)),
                ),
                const SizedBox(width: Space.m),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${f['name']}', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5)),
                      Text([f['brand'], f['quantity']].whereType<Object>().join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.bodySmall),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          _NutriScore(textOf(f['nutriscore']), compact: true),
                          if (numOf(f['nova']) != null) InfoPill('NOVA ${f['nova']}', color: _novaColors[numOf(f['nova'])!.toInt()]),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: Space.m),
            Row(
              children: [
                _Macro('kcal', numOf(n['energy_kcal']), null),
                _Macro('fat', numOf(n['fat']), levels['fat']),
                _Macro('sugar', numOf(n['sugars']), levels['sugars']),
                _Macro('salt', numOf(n['salt']), levels['salt']),
                _Macro('protein', numOf(n['protein']), null),
              ],
            ),
            const SizedBox(height: 4),
            Text('per 100 g${f['serving'] == null ? '' : ' · serving ${f['serving']}'}', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: AppColors.text3)),
            if (strs(f['allergens']).isNotEmpty) ...[
              const SizedBox(height: Space.s),
              Wrap(spacing: 6, runSpacing: 6, children: [for (final a in strs(f['allergens'])) InfoPill(a, color: AppColors.danger, icon: Icons.warning_amber_rounded)]),
            ],
          ],
        ),
      ),
    );
  }
}

class _Macro extends StatelessWidget {
  const _Macro(this.label, this.value, this.level);
  final String label;
  final num? value;
  final Object? level;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      margin: const EdgeInsets.symmetric(horizontal: 2),
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: level == null ? AppColors.surface2 : _levelColor('$level').withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(Radii.s),
        border: level == null ? null : Border.all(color: _levelColor('$level').withValues(alpha: 0.5)),
      ),
      child: Column(
        children: [
          Text(value == null ? '—' : (label == 'kcal' ? '${value!.round()}' : '${value}g'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5, fontFeatures: tabularFigures)),
          Text(label, style: TextStyle(fontSize: 10.5, color: level == null ? AppColors.text3 : _levelColor('$level'))),
        ],
      ),
    ),
  );
}

Future<void> _scanAnother(BuildContext context) async {
  final r = await Qr.scan(prompt: 'Point at the product\'s barcode');
  if (r == null || !context.mounted) return;
  final code = '${r['value'] ?? ''}';
  await showLoadingSheet(context, () => InfoApi.instance.foodByBarcode(code), (c, f) => _foodBody(c, f));
}

Future<void> showFood(BuildContext context, Map<String, dynamic> f) => showInfoSheet(context, (c) => _foodBody(c, f));

List<Widget> _foodBody(BuildContext context, Map<String, dynamic> f) {
  final n = mapOf(f['per_100g']);
  final levels = mapOf(f['levels']);
  const rows = [
    ('energy_kcal', 'Energy', 'kcal', null),
    ('fat', 'Fat', 'g', 'fat'),
    ('saturated_fat', '  of which saturated', 'g', 'saturated_fat'),
    ('carbohydrates', 'Carbohydrates', 'g', null),
    ('sugars', '  of which sugars', 'g', 'sugars'),
    ('fiber', 'Fibre', 'g', null),
    ('protein', 'Protein', 'g', null),
    ('salt', 'Salt', 'g', 'salt'),
  ];
  final nova = numOf(f['nova'])?.toInt();
  return [
    Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(Radii.m),
          child: Container(color: Colors.white, child: NetImage(textOf(f['image']), width: 96, height: 96, fit: BoxFit.contain, placeholder: Icons.fastfood_outlined)),
        ),
        const SizedBox(width: Space.m),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SelectableText('${f['name']}', style: context.text.titleLarge),
              Text([f['brand'], f['quantity']].whereType<Object>().join(' · '), style: context.text.bodySmall),
              Text('Barcode ${f['barcode']}', style: TextStyle(fontSize: 12, color: AppColors.text3, fontFamily: 'monospace')),
            ],
          ),
        ),
      ],
    ),
    const SizedBox(height: Space.l),
    if (f['nutriscore'] != null) ...[
      Row(children: [Text('Nutri-Score  ', style: context.text.labelSmall), _NutriScore(textOf(f['nutriscore']))]),
      const SizedBox(height: Space.m),
    ],
    if (nova != null)
      Row(
        children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: _novaColors[nova], borderRadius: BorderRadius.circular(6)),
            child: Text('$nova', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
          ),
          const SizedBox(width: Space.m),
          Expanded(child: Text('NOVA $nova · ${_novaText[nova] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w600))),
        ],
      ),
    if (f['ecoscore'] != null) ...[const SizedBox(height: Space.s), Text('Eco-Score ${f['ecoscore']}', style: context.text.bodySmall)],
    const SectionLabel('Nutrition', trailing: 'per 100 g'),
    for (final (k, label, unit, level) in rows)
      if (n[k] != null)
        Container(
          padding: const EdgeInsets.symmetric(vertical: 7),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.line))),
          child: Row(
            children: [
              Expanded(child: Text(label, style: TextStyle(color: label.startsWith(' ') ? AppColors.text2 : AppColors.text, fontSize: 13.5))),
              if (level != null && levels[level] != null)
                Padding(padding: const EdgeInsets.only(right: Space.s), child: InfoPill('${levels[level]}', color: _levelColor('${levels[level]}'))),
              Text('${n[k]} $unit', style: const TextStyle(fontWeight: FontWeight.w700, fontFeatures: tabularFigures)),
            ],
          ),
        ),
    if (f['per_serving_kcal'] != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text('${f['per_serving_kcal']} kcal per serving (${f['serving']})', style: context.text.bodySmall)),
    if (strs(f['allergens']).isNotEmpty || strs(f['traces']).isNotEmpty) ...[
      const SectionLabel('Allergens'),
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final a in strs(f['allergens'])) InfoPill(a, color: AppColors.danger),
        for (final a in strs(f['traces'])) InfoPill('may contain $a', color: AppColors.warning),
      ]),
    ],
    if (f['vegan'] == true || f['vegetarian'] == true || strs(f['labels']).isNotEmpty) ...[
      const SectionLabel('Labels'),
      Wrap(spacing: 6, runSpacing: 6, children: [for (final l in strs(f['labels'])) InfoPill(l)]),
    ],
    if (f['ingredients'] != null) ...[const SectionLabel('Ingredients'), SelectableText('${f['ingredients']}', style: const TextStyle(height: 1.45))],
    if (strs(f['additives']).isNotEmpty) ...[
      const SectionLabel('Additives'),
      Wrap(spacing: 6, runSpacing: 6, children: [for (final a in strs(f['additives'])) InfoPill(a)]),
    ],
    sheetButtons([
      FilledButton.icon(onPressed: () => _scanAnother(context), icon: const Icon(Icons.qr_code_scanner_rounded, size: 18), label: const Text('Scan another')),
      linkButton('Open Food Facts', textOf(f['url'])),
    ]),
    Padding(
      padding: const EdgeInsets.only(top: Space.l),
      child: Text('From Open Food Facts, a crowd-sourced database. Check the package for allergies.', style: TextStyle(fontSize: 11.5, color: AppColors.text3)),
    ),
  ];
}

class _FoodList extends StatelessWidget {
  const _FoodList({required this.r});
  final Map<String, dynamic> r;

  @override
  Widget build(BuildContext context) => InfoFrame(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InfoHeader(Icons.fastfood_outlined, 'Products · ${r['count']}', color: _food),
        for (final f in maps(r['products']).take(10))
          InkWell(
            onTap: () => showFood(context, f),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.m, vertical: 6),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(Radii.s),
                    child: Container(color: Colors.white, child: NetImage(textOf(f['image']), width: 44, height: 44, fit: BoxFit.contain, placeholder: Icons.fastfood_outlined)),
                  ),
                  const SizedBox(width: Space.m),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${f['name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                        Text(
                          [f['brand'], if (mapOf(f['per_100g'])['energy_kcal'] != null) '${mapOf(f['per_100g'])['energy_kcal']} kcal/100g'].whereType<Object>().join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.text.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  _NutriScore(textOf(f['nutriscore']), compact: true),
                ],
              ),
            ),
          ),
        const SizedBox(height: Space.xs),
      ],
    ),
  );
}
