import 'package:flutter/material.dart';

class TermsAndConditionsScreen extends StatelessWidget {
  final String termsText; // متنی که از API دریافت کردی رو پاس بده اینجا

  const TermsAndConditionsScreen({Key? key, required this.termsText})
    : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

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
      body: Column(
        children: [
          // بخش هدر و آیکون
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.gavel_rounded,
              // آیکون چکش قانون (میتونی به policy یا menu_book تغییرش بدی)
              size: 48,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 32),

          // بخش باکس متن قوانین
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: theme.cardColor,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(32),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: const Offset(0, -5),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(32),
                ),
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  // افکت اسکرول نرم (مثل iOS)
                  padding: const EdgeInsets.fromLTRB(24, 32, 24, 100),
                  // پدینگ پایین برای دکمه
                  child: Text(
                    termsText.trim().isNotEmpty
                        ? termsText
                        : 'در حال حاضر قانونی از سمت سرور دریافت نشد.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontSize: 14.5,
                      height: 1.8, // فاصله استاندارد خطوط برای خوانایی بهتر
                      color: theme.colorScheme.onSurface.withOpacity(0.8),
                    ),
                    textAlign: TextAlign.justify,
                    textDirection: TextDirection.rtl,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),

      // دکمه تایید پایین صفحه
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: ElevatedButton(
          onPressed: () {
            // برگشت به صفحه قبل
            Navigator.of(context).pop();
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: theme.colorScheme.primary,
            foregroundColor: theme.colorScheme.onPrimary,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            elevation: 2,
          ),
          child: const Text(
            'متوجه شدم',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ),
      ),
    );
  }
}
