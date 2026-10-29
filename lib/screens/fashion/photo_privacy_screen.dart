import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class PhotoPrivacyScreen extends StatelessWidget {
  const PhotoPrivacyScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Photo privacy')),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          'Your photos in Vyoora',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 16),
        const Text(
          'Separate skincare features send ingredient-label photos and product type, or chat messages and recent conversation history, through Vyoora’s backend to OpenAI after your consent. The backend processes label pixels in memory. The last five completed scan results are stored on this device and can be cleared from History; chat is held in the current screen’s memory. These local skincare records are separate from your fashion account. OpenAI API abuse-monitoring retention is normally up to 30 days, with safety/legal exceptions. This project’s zero-retention status has not been verified.',
        ),
        const Text(
          'Delete account is available in Wardrobe. It requires your password again, blocks new processing, removes private media and generation/reference records, and deletes your Firebase sign-in account. If storage cleanup fails, data access stays blocked and you can retry deletion. Hashed usage counters may remain for security and budget enforcement for up to 65 days. Exported copies and Google’s independent logs are not removed by account deletion.',
        ),
        const Text(
          'Fashion photos are private to your verified account. Google Firebase handles sign-in; Google Cloud runs the authenticated backend and stores wardrobe images, reference photos, previews and job records. No public image links are created.',
        ),
        const SizedBox(height: 16),
        const Text(
          'When you explicitly choose Generate, Vyoora sends the selected adult reference photo and garment to Google’s Gemini image model on Google Cloud in the United States. No fashion photo is sent to Vercel or a social network by this flow. AI output may change details and is not a fit or sizing guarantee.',
        ),
        const SizedBox(height: 16),
        const Text(
          'Reference photos and unsaved previews become inaccessible after seven days. My Looks saves a separate private output copy for 30 days from saving, including after automatic reference expiry. Wardrobe photos remain until you delete them. Automated object cleanup can happen after the access deadline rather than at the exact expiry time.',
        ),
        const SizedBox(height: 16),
        const Text(
          'Deleting a reference photo revokes consent, cancels its work, and removes associated Vyoora previews and saved looks. Deleting a saved look removes its saved copy. It does not delete the separate original generation; delete the reference photo to remove both. If cleanup encounters an outage, revoked photos and their looks remain blocked; retry Delete to finish cleanup. Generation attempts and budget records are scheduled for cleanup within 65 days for usage control; they contain identifiers and status, not image pixels.',
        ),
        const SizedBox(height: 16),
        const Text(
          'Google may retain inputs and outputs in abuse-monitoring logs for up to 30 days under its own policies. We have not verified a zero-retention exemption for this project. Deleting in Vyoora cannot recall an in-progress provider request or erase Google’s independent logs. Google Cloud states that customer data is not used to train its models without permission.',
        ),
        const SizedBox(height: 16),
        const Text(
          'Save to Photos and Share make a watermarked copy on your device; the stored original is unchanged. iOS asks only for permission to add to Photos. Compatible sharing destinations depend on installed apps. A destination you choose receives the export under its own terms. Device backups, Photos/iCloud and shared copies are outside Vyoora’s deletion controls.',
        ),
        const SizedBox(height: 16),
        TextButton(
          onPressed: () => launchUrl(
            Uri.parse(
              'https://docs.cloud.google.com/gemini-enterprise-agent-platform/resources/zero-data-retention',
            ),
          ),
          child: const Text('Google Cloud processing policy'),
        ),
        TextButton(
          onPressed: () => launchUrl(
            Uri.parse('https://firebase.google.com/support/privacy'),
          ),
          child: const Text('Firebase privacy'),
        ),
      ],
    ),
  );
}
