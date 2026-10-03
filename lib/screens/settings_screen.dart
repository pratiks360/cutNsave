import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import '../services/services.dart';
import '../services/update_service.dart';
import '../state/app_state.dart';
import '../widgets/quota_card.dart';
import 'members_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _version = '';
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((i) {
      if (mounted) setState(() => _version = i.version);
    });
  }

  Future<void> _checkUpdates() async {
    final s = context.read<Services>();
    setState(() => _checking = true);
    try {
      final info = await s.updater.latestIfNewer();
      if (!mounted) return;
      if (info == null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(context.tr('up_to_date'))));
      } else {
        await _offerUpdate(s, info);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(context.tr('update_failed'))));
      }
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _offerUpdate(Services s, UpdateInfo info) async {
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.tr('update_available', {'version': info.tag})),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.tr('cancel'))),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(ctx.tr('download_install')),
          ),
        ],
      ),
    );
    if (go != true || !mounted) return;
    final progress = ValueNotifier<double>(0);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.tr('downloading')),
        content: ValueListenableBuilder<double>(
          valueListenable: progress,
          builder: (_, v, _) => LinearProgressIndicator(value: v == 0 ? null : v),
        ),
      ),
    );
    try {
      final apk = await s.updater.download(info, onProgress: (v) => progress.value = v);
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
      await s.updater.install(apk);
    } catch (_) {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(context.tr('update_failed'))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(title: Text(context.t('settings'))),
      body: ListView(
        children: [
          const QuotaCard(),
          ListTile(
            title: Text(context.t('interface_language')),
            trailing: SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'mr', label: Text('मराठी')),
                ButtonSegment(value: 'en', label: Text('English')),
              ],
              selected: {app.lang},
              onSelectionChanged: (v) => app.setLang(v.first),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.group),
            title: Text(context.t('members')),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const MembersScreen()),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.system_update),
            title: Text(context.t(_checking ? 'checking' : 'check_updates')),
            subtitle: Text(context.t('installed_version', {'version': _version})),
            onTap: _checking ? null : _checkUpdates,
          ),
          ListTile(
            leading: const Icon(Icons.logout),
            title: Text(context.t('sign_out')),
            onTap: () async {
              final nav = Navigator.of(context);
              await app.signOut();
              nav.popUntil((r) => r.isFirst);
            },
          ),
        ],
      ),
    );
  }
}
