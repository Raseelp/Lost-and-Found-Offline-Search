part of '../settings_screen.dart';

/// The notification settings: the daily memory, the stories note and the finish indexing note. The switches show what
/// the person chose, whether or not the phone allows notifications, and the banner above them says when it does not.
class _NotificationsSection extends StatelessWidget {
  const _NotificationsSection();

  @override
  Widget build(BuildContext context) {
    return GetBuilder<MemoriesController>(
      builder: (memories) {
        final s = memories.settings;

        void say(String text) => AppToast.show(text);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _NotificationsOffBanner(),
            _GroupCard(
              children: [
                _SettingsRow(
                  icon: Icons.auto_awesome_outlined,
                  title: 'Daily memory',
                  subtitle:
                      'Two a day, morning and evening, only when there is something good.',
                  trailing: Switch(
                    value: s.enabled,
                    onChanged: (on) async {
                      await memories.setEnabled(on);
                    },
                  ),
                ),
                if (s.enabled) ...[
                  _TapRow(
                    icon: Icons.send_rounded,
                    title: 'Send one now',
                    subtitle: 'See a different one each time.',
                    onTap: () async => say(await memories.sendTest()),
                  ),
                ],
                GetBuilder<StoriesController>(
                  builder: (stories) => _SettingsRow(
                    icon: Icons.web_stories_outlined,
                    title: 'Stories reminder',
                    subtitle: 'A note a day after you last use the app, when there are stories to watch.',
                    trailing: Switch(
                      value: stories.reminderEnabled,
                      onChanged: (on) async {
                        await stories.setReminder(on);
                      },
                    ),
                  ),
                ),
                GetBuilder<SettingsController>(
                  builder: (native) => _SettingsRow(
                    icon: Icons.manage_search_rounded,
                    title: 'Finish indexing reminder',
                    subtitle: 'A note if some of your photos and videos are not indexed yet.',
                    trailing: Switch(
                      value: native.indexNudgeEnabled,
                      onChanged: (on) async {
                        await native.setIndexNudgeEnabled(on);
                      },
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}
