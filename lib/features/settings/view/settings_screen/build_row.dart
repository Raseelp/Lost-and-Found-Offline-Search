part of '../settings_screen.dart';

/// Which build this is, the way Telegram X lists it: the version, the build number and the commit it was made from
/// (a "+" after the commit means there were changes that were not committed). Tapping copies it, for a bug report.
class _BuildRow extends StatefulWidget {
  const _BuildRow();

  @override
  State<_BuildRow> createState() => _BuildRowState();
}

class _BuildRowState extends State<_BuildRow> {
  String? _text;

  @override
  void initState() {
    super.initState();
    DeviceService().buildInfo().then((info) {
      if (!mounted || info == null) return;
      final parts = [
        'Version ${info['version']} (${info['build']})',
        'commit ${info['commit']}',
        if ('${info['commitDate']}' != 'unknown') '${info['commitDate']}',
        if (info['debug'] == true || kDebugMode) 'debug build',
      ];
      setState(() => _text = parts.join(' · '));
    });
  }

  @override
  Widget build(BuildContext context) {
    final text = _text;
    return InkWell(
      onTap: text == null
          ? null
          : () async {
              await Clipboard.setData(
                ClipboardData(text: 'Lost & Found $text'),
              );
              AppToast.show('Build details copied.');
            },
      child: _SettingsRow(
        icon: Icons.info_outline_rounded,
        title: 'Lost & Found',
        subtitle: text ?? 'Version',
      ),
    );
  }
}
