import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

Future<bool> confirmSkincareProcessing(
  BuildContext context, {
  bool chat = false,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(
          chat
              ? 'Send this conversation for AI help?'
              : 'Analyze this label with AI?',
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                chat
                    ? 'Vyoora sends your messages and recent conversation context through its backend to OpenAI. Avoid including sensitive personal details. This permission applies to this conversation.'
                    : 'Vyoora sends your selected label photo and product type through its backend to OpenAI for ingredient analysis. Only include the product label.',
              ),
              const SizedBox(height: 12),
              const Text(
                'OpenAI API data is not used for training by default. Abuse-monitoring logs may be kept for up to 30 days, with longer retention for safety or legal exceptions. Vyoora cannot erase those independent logs. Ingredient results are not medical advice.',
              ),
              TextButton(
                onPressed: () => launchUrl(
                  Uri.parse(
                    'https://developers.openai.com/api/docs/guides/your-data',
                  ),
                ),
                child: const Text('OpenAI API data policy'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('skincare-ai-consent'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Agree and continue'),
          ),
        ],
      ),
    ) ??
    false;
