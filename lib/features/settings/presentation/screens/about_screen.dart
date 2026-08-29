import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_snack_bar.dart';
import 'changelog_screen.dart';

class AboutScreen extends ConsumerStatefulWidget {
  const AboutScreen({super.key});

  @override
  ConsumerState<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends ConsumerState<AboutScreen> {
  PackageInfo? _pkg;

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((info) {
      if (mounted) setState(() => _pkg = info);
    });
  }

  void _openChangelog() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChangelogScreen(
          currentVersion: _pkg?.version ?? '0.0.0',
        ),
      ),
    );
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) AppSnackBar.show(context, '无法打开浏览器');
    }
  }

  @override
  Widget build(BuildContext context) {
    final version = _pkg == null
        ? '--'
        : 'v${_pkg!.version}';
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 220,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      AppColors.primary.withValues(alpha: 0.12),
                      colorScheme.surface,
                    ],
                  ),
                ),
                child: SafeArea(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(height: 16),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: Image.asset(
                          'assets/icon/howtocook.png',
                          width: 80,
                          height: 80,
                          errorBuilder: (_, __, ___) => Container(
                            width: 80,
                            height: 80,
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Icon(Icons.restaurant_menu,
                                size: 40, color: AppColors.primary),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text('智能菜谱助手',
                          style: textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Chip(
                        label: Text(version,
                            style: textTheme.labelSmall?.copyWith(
                                color: AppColors.primary,
                                fontWeight: FontWeight.w600)),
                        backgroundColor:
                            AppColors.primary.withValues(alpha: 0.1),
                        side: BorderSide(
                            color: AppColors.primary.withValues(alpha: 0.4)),
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        visualDensity: VisualDensity.compact,
                      ),
                      const SizedBox(height: 4),
                      Text('基于 Flutter 构建',
                          style: textTheme.labelSmall
                              ?.copyWith(color: AppColors.textSecondary)),
                    ],
                  ),
                ),
              ),
            ),
            title: const Text('关于'),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                _SectionCard(
                  children: [
                    ListTile(
                      leading: CircleAvatar(
                        backgroundColor:
                            AppColors.primary.withValues(alpha: 0.15),
                        child: const Icon(Icons.person_outline,
                            color: AppColors.primary, size: 20),
                      ),
                      title: const Text('anlife'),
                      subtitle: const Text('独立开发者'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _openUrl('https://github.com/AnLifeX'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _SectionCard(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.history_outlined,
                          color: AppColors.primary),
                      title: const Text('更新日志'),
                      subtitle: const Text('查看版本更新内容'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: _openChangelog,
                    ),
                    const Divider(height: 1, indent: 16, endIndent: 16),
                    ListTile(
                      leading: const Icon(Icons.feedback_outlined,
                          color: AppColors.primary),
                      title: const Text('问题反馈'),
                      subtitle: const Text('在 GitHub 提交 Issue'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _openUrl(
                          'https://github.com/AnLifeX/howtocook-flutter/issues'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _SectionCard(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.article_outlined,
                          color: AppColors.primary),
                      title: const Text('开源许可证'),
                      subtitle: const Text('查看第三方库许可证信息'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => showLicensePage(
                        context: context,
                        applicationName: '智能菜谱助手',
                        applicationVersion: _pkg?.version,
                        applicationIcon: Padding(
                          padding: const EdgeInsets.all(8),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.asset('assets/icon/howtocook.png',
                                width: 48, height: 48),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerLowest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: children),
    );
  }
}
