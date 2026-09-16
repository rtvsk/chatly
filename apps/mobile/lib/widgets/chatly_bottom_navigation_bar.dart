import 'dart:math' as math;

import 'package:flutter/material.dart';

class ChatlyBottomNavigationBar extends StatelessWidget {
  const ChatlyBottomNavigationBar({
    required this.selectedIndex,
    required this.onDestinationSelected,
    this.profileBadgeCount = 0,
    this.chatBadgeCount = 0,
    super.key,
  }) : assert(selectedIndex >= 0 && selectedIndex < _destinations.length),
       assert(profileBadgeCount >= 0),
       assert(chatBadgeCount >= 0);

  static const _animationDuration = Duration(milliseconds: 220);
  static const _destinations = [
    _ChatlyNavigationDestination(
      label: 'Contacts',
      icon: Icons.group_outlined,
      selectedIcon: Icons.group_rounded,
    ),
    _ChatlyNavigationDestination(
      label: 'Chats',
      icon: Icons.chat_bubble_outline_rounded,
      selectedIcon: Icons.chat_bubble_rounded,
    ),
    _ChatlyNavigationDestination(
      label: 'Profile',
      icon: Icons.account_circle_outlined,
      selectedIcon: Icons.account_circle_rounded,
    ),
  ];

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final int profileBadgeCount;
  final int chatBadgeCount;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainer,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(
            color: colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
          boxShadow: [
            BoxShadow(
              color: colorScheme.shadow.withValues(alpha: 0.12),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: SizedBox(
            height: 72,
            child: Row(
              children: [
                for (var index = 0; index < _destinations.length; index++)
                  Expanded(
                    child: _ChatlyNavigationButton(
                      destination: _destinations[index],
                      isSelected: selectedIndex == index,
                      badgeCount: switch (index) {
                        1 => chatBadgeCount,
                        2 => profileBadgeCount,
                        _ => 0,
                      },
                      badgeSemanticLabel: index == 1
                          ? 'unread messages'
                          : 'notifications',
                      animateOnBadgeIncrease: index == 1,
                      onTap: () => onDestinationSelected(index),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ChatlyNavigationButton extends StatefulWidget {
  const _ChatlyNavigationButton({
    required this.destination,
    required this.isSelected,
    required this.badgeCount,
    required this.badgeSemanticLabel,
    required this.animateOnBadgeIncrease,
    required this.onTap,
  });

  final _ChatlyNavigationDestination destination;
  final bool isSelected;
  final int badgeCount;
  final String badgeSemanticLabel;
  final bool animateOnBadgeIncrease;
  final VoidCallback onTap;

  @override
  State<_ChatlyNavigationButton> createState() =>
      _ChatlyNavigationButtonState();
}

class _ChatlyNavigationButtonState extends State<_ChatlyNavigationButton>
    with SingleTickerProviderStateMixin {
  static const _notificationAnimationDuration = Duration(milliseconds: 420);

  late final AnimationController _notificationController;

  @override
  void initState() {
    super.initState();
    _notificationController = AnimationController(
      duration: _notificationAnimationDuration,
      vsync: this,
    );
  }

  @override
  void didUpdateWidget(covariant _ChatlyNavigationButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    final animationsDisabled =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (widget.animateOnBadgeIncrease &&
        !widget.isSelected &&
        widget.badgeCount > oldWidget.badgeCount &&
        !animationsDisabled) {
      _notificationController.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _notificationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    Widget button = Semantics(
      key: ValueKey('bottom-nav-${widget.destination.label}'),
      button: true,
      selected: widget.isSelected,
      label: widget.badgeCount > 0
          ? '${widget.destination.label}, ${widget.badgeCount} ${widget.badgeSemanticLabel}'
          : widget.destination.label,
      onTap: widget.onTap,
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: widget.onTap,
              borderRadius: BorderRadius.circular(26),
              child: Center(
                child: AnimatedContainer(
                  key: ValueKey(
                    'bottom-nav-capsule-${widget.destination.label}',
                  ),
                  duration: ChatlyBottomNavigationBar._animationDuration,
                  curve: Curves.easeOutCubic,
                  width: 52,
                  height: 52,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: widget.isSelected
                        ? colorScheme.primaryContainer
                        : Colors.transparent,
                    shape: BoxShape.circle,
                  ),
                  child: AnimatedBuilder(
                    animation: _notificationController,
                    builder: (context, child) {
                      final progress = _notificationController.value;
                      final angle =
                          math.sin(progress * math.pi * 4) *
                          (1 - progress) *
                          0.11;
                      final scale = 1 + math.sin(progress * math.pi) * 0.08;
                      return Transform.scale(
                        scale: scale,
                        child: Transform.rotate(
                          key: widget.animateOnBadgeIncrease
                              ? const ValueKey(
                                  'bottom-nav-chat-notification-shake',
                                )
                              : null,
                          angle: angle,
                          child: child,
                        ),
                      );
                    },
                    child: AnimatedSwitcher(
                      duration: ChatlyBottomNavigationBar._animationDuration,
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeOutCubic,
                      child: Badge.count(
                        key: ValueKey(
                          '${widget.isSelected}-${widget.badgeCount}',
                        ),
                        count: widget.badgeCount,
                        isLabelVisible: widget.badgeCount > 0,
                        backgroundColor: Colors.red,
                        child: Icon(
                          widget.isSelected
                              ? widget.destination.selectedIcon
                              : widget.destination.icon,
                          size: widget.isSelected ? 30 : 28,
                          color: widget.isSelected
                              ? colorScheme.primary
                              : colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    return Tooltip(
      message: widget.destination.label,
      excludeFromSemantics: true,
      child: button,
    );
  }
}

class _ChatlyNavigationDestination {
  const _ChatlyNavigationDestination({
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}
