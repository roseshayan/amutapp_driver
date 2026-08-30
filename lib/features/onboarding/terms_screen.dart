import 'package:flutter/material.dart';

class TermsAndConditionsScreen extends StatelessWidget {
  final String termsText;

  const TermsAndConditionsScreen({super.key, required this.termsText});

  List<_TermsSection> _parseSections() {
    final normalized = termsText.trim().replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    if (normalized.isEmpty) {
      return const [
        _TermsSection(
          title: 'قوانین و مقررات',
          body: 'در حال حاضر قانونی از سمت سرور دریافت نشد.',
        ),
      ];
    }

    final sections = <_TermsSection>[];
    String title = '';
    final body = <String>[];

    void flush() {
      final text = body.join('\n').trim();
      if (title.isNotEmpty || text.isNotEmpty) {
        sections.add(
          _TermsSection(
            title: title.isNotEmpty ? title : 'قوانین و مقررات',
            body: text,
          ),
        );
      }
      body.clear();
    }

    for (final line in normalized.split('\n')) {
      final trimmed = line.trimLeft();
      if (trimmed.startsWith('## ')) {
        if (title.isNotEmpty || body.isNotEmpty) flush();
        title = trimmed.substring(3).trim();
      } else {
        body.add(line);
      }
    }
    flush();
    return sections.isEmpty
        ? [_TermsSection(title: 'قوانین و مقررات', body: normalized)]
        : sections;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sections = _parseSections();

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: theme.colorScheme.onSurface,
        title: const Text(
          'قوانین و مقررات',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            const SizedBox(height: 8),
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(22),
              ),
              child: Icon(
                Icons.gavel_rounded,
                size: 36,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Text(
                'استفاده از خدمات به منزله مطالعه و پذیرش مقررات جاری سامانه است.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  height: 1.7,
                  color: theme.colorScheme.onSurface.withOpacity(.62),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Expanded(
              child: ListView.separated(
                physics: const BouncingScrollPhysics(),
                padding: EdgeInsets.fromLTRB(
                  16,
                  0,
                  16,
                  105 + MediaQuery.of(context).padding.bottom,
                ),
                itemCount: sections.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final section = sections[index];
                  return Container(
                    decoration: BoxDecoration(
                      color: theme.cardColor,
                      borderRadius: BorderRadius.circular(17),
                      border: Border.all(
                        color: theme.dividerColor.withOpacity(.11),
                      ),
                    ),
                    child: Theme(
                      data: theme.copyWith(dividerColor: Colors.transparent),
                      child: ExpansionTile(
                        initiallyExpanded: index == 0,
                        tilePadding: const EdgeInsets.symmetric(
                          horizontal: 15,
                          vertical: 3,
                        ),
                        childrenPadding: const EdgeInsets.fromLTRB(
                          17,
                          0,
                          17,
                          18,
                        ),
                        leading: Container(
                          width: 36,
                          height: 36,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary.withOpacity(.09),
                            borderRadius: BorderRadius.circular(11),
                          ),
                          child: Text(
                            '${index + 1}',
                            style: TextStyle(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        title: Text(
                          section.title,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14.5,
                            height: 1.6,
                          ),
                        ),
                        children: [
                          Align(
                            alignment: Alignment.centerRight,
                            child: SelectableText(
                              section.body,
                              textAlign: TextAlign.justify,
                              textDirection: TextDirection.rtl,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontSize: 13.5,
                                height: 1.95,
                                color: theme.colorScheme.onSurface.withOpacity(.76),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: SafeArea(
        top: false,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: ElevatedButton(
            onPressed: () => Navigator.of(context).pop(),
            style: ElevatedButton.styleFrom(
              backgroundColor: theme.colorScheme.primary,
              foregroundColor: theme.colorScheme.onPrimary,
              padding: const EdgeInsets.symmetric(vertical: 15),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
              ),
              elevation: 2,
            ),
            child: const Text(
              'متوجه شدم',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ),
    );
  }
}

class _TermsSection {
  const _TermsSection({required this.title, required this.body});

  final String title;
  final String body;
}
