import 'package:flutter/material.dart';
import '../../services/wardrobe_repository.dart';

class AccountActions extends StatefulWidget {
  final WardrobeRepository repository;
  const AccountActions({super.key, required this.repository});
  @override
  State<AccountActions> createState() => _AccountActionsState();
}

class _AccountActionsState extends State<AccountActions> {
  bool busy = false;
  String? error;
  Future<void> delete() async {
    final controller = TextEditingController();
    final password = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete your account?'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Permanently delete your sign-in account, wardrobe photos, reference photos, previews and saved looks. Copies exported or shared elsewhere remain. Processing already sent to Google cannot be recalled. Hashed usage counters may remain for up to 65 days. Enter your password to confirm. If cleanup fails, your account is blocked until you retry deletion.',
              ),
              TextField(
                key: const Key('account-delete-password'),
                controller: controller,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                decoration: const InputDecoration(
                  labelText: 'Current password',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Keep account'),
          ),
          FilledButton(
            key: const Key('account-confirm-delete'),
            onPressed: () {
              if (controller.text.isNotEmpty)
                Navigator.pop(context, controller.text);
            },
            child: const Text('Delete account permanently'),
          ),
        ],
      ),
    );
    Future<void>.delayed(const Duration(seconds: 1), controller.dispose);
    if (password == null || !mounted) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.repository.deleteAccount(password);
    } catch (_) {
      if (mounted)
        setState(
          () => error =
              'Could not finish account deletion. Check your password and connection, then retry Delete account.',
        );
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      TextButton(
        key: const Key('account-delete'),
        onPressed: busy ? null : delete,
        child: Text(busy ? 'Deleting account…' : 'Delete account'),
      ),
      if (error != null) Text(error!),
    ],
  );
}
