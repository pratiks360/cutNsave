import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../logic/email.dart';
import '../services/members_service.dart';
import '../services/services.dart';
import '../state/app_state.dart';

class MembersScreen extends StatefulWidget {
  const MembersScreen({super.key});

  @override
  State<MembersScreen> createState() => _MembersScreenState();
}

class _MembersScreenState extends State<MembersScreen> {
  late final MembersService _svc = context.read<Services>().members;
  final _email = TextEditingController();
  List<Member> _members = [];
  bool _owner = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final list = await _svc.list();
      if (mounted) {
        setState(() {
          _members = list;
          _owner = _svc.isOwnerIn(list);
        });
      }
    } catch (_) {
      if (mounted) setState(() => _error = context.tr('error_generic'));
    }
  }

  Future<void> _add() async {
    final email = normalizeEmail(_email.text);
    if (email == null) {
      setState(() => _error = context.tr('invalid_email'));
      return;
    }
    try {
      await _svc.add(email);
      _email.clear();
      _error = null;
      await _load();
    } catch (_) {
      setState(() => _error = context.tr('error_generic'));
    }
  }

  Future<void> _remove(String email) async {
    try {
      await _svc.remove(email);
      await _load();
    } catch (_) {
      setState(() => _error = context.tr('error_generic'));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.t('members'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          for (final m in _members)
            ListTile(
              title: Text(m.email),
              subtitle: Text(m.role == 'owner'
                  ? context.t('owner')
                  : context.t(m.joined ? 'joined' : 'invited')),
              trailing: (_owner && m.role != 'owner')
                  ? IconButton(
                      icon: const Icon(Icons.close),
                      tooltip: context.t('remove'),
                      onPressed: () => _remove(m.email),
                    )
                  : null,
            ),
          if (_owner) ...[
            const Divider(),
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(labelText: context.t('member_email_hint')),
            ),
            const SizedBox(height: 12),
            FilledButton(onPressed: _add, child: Text(context.t('add_member'))),
          ],
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
        ],
      ),
    );
  }
}
