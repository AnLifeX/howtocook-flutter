import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../features/ai_chat/application/services/ai_chat_task_coordinator.dart';
import '../theme/app_colors.dart';

/// 悬浮导航栏的总高度（胶囊 56 + 上边距 8 + 下边距 12 = 76），
/// 子页面可通过此常量在底部留出空间。
const kFloatingNavBarHeight = 76.0;

class MainScaffold extends StatelessWidget {
  final StatefulNavigationShell navigationShell;

  const MainScaffold({super.key, required this.navigationShell});

  void _onItemTapped(int index) {
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      extendBody: true,
      resizeToAvoidBottomInset: false,
      body: navigationShell,
      bottomNavigationBar: Container(
        color: Colors.transparent,
        padding: EdgeInsets.only(
          left: 40,
          right: 40,
          top: 8,
          bottom: bottomPadding + 12,
        ),
        child: Container(
          height: 56,
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: AppColors.textPrimary.withValues(alpha: 0.1),
                blurRadius: 20,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              _buildNavItem(index: 0, icon: Icons.restaurant_menu, label: '菜谱'),
              _buildAiNavItem(),
              _buildNavItem(index: 2, icon: Icons.person_outline, label: '我的'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem({
    required int index,
    required IconData icon,
    required String label,
  }) {
    final isSelected = navigationShell.currentIndex == index;

    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _onItemTapped(index),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 22,
              color: isSelected ? AppColors.primary : AppColors.textDisabled,
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                color: isSelected ? AppColors.primary : AppColors.textDisabled,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAiNavItem() {
    return Expanded(
      child: AnimatedBuilder(
        animation: AIChatTaskCoordinator.instance,
        builder: (context, _) {
          final isSelected = navigationShell.currentIndex == 1;
          final isRunning = AIChatTaskCoordinator.instance.isRunning;
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _onItemTapped(1),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: isSelected || isRunning
                              ? [AppColors.primary, AppColors.plum]
                              : [
                                  AppColors.textDisabled,
                                  AppColors.textDisabled,
                                ],
                        ),
                        boxShadow: isSelected || isRunning
                            ? [
                                BoxShadow(
                                  color: AppColors.primary.withValues(
                                    alpha: 0.3,
                                  ),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ]
                            : null,
                      ),
                      child: const Icon(
                        Icons.auto_awesome,
                        size: 18,
                        color: AppColors.surface,
                      ),
                    ),
                    if (isRunning)
                      const Positioned(
                        right: -3,
                        top: -3,
                        child: SizedBox(
                          width: 10,
                          height: 10,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.primary,
                            backgroundColor: AppColors.surface,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  isRunning ? '回复中' : '小厨',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: isSelected || isRunning
                        ? FontWeight.w600
                        : FontWeight.w500,
                    color: isSelected || isRunning
                        ? AppColors.primary
                        : AppColors.textDisabled,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
