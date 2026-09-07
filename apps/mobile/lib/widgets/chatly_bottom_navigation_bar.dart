import 'package:flutter/material.dart';

class ChatlyBottomNavigationBar extends StatelessWidget {
  const ChatlyBottomNavigationBar({
    required this.selectedIndex,
    required this.onDestinationSelected,
    super.key,
  }) : assert(selectedIndex >= 0 && selectedIndex < _destinations.length);

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

class _ChatlyNavigationButton extends StatelessWidget {
  const _ChatlyNavigationButton({
    required this.destination,
    required this.isSelected,
    required this.onTap,
  });

  final _ChatlyNavigationDestination destination;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    Widget button = Semantics(
      key: ValueKey('bottom-nav-${destination.label}'),
      button: true,
      selected: isSelected,
      label: destination.label,
      onTap: onTap,
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(26),
              child: Center(
                child: AnimatedContainer(
                  key: ValueKey('bottom-nav-capsule-${destination.label}'),
                  duration: ChatlyBottomNavigationBar._animationDuration,
                  curve: Curves.easeOutCubic,
                  width: 52,
                  height: 52,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: isSelected
                        ? colorScheme.primaryContainer
                        : Colors.transparent,
                    shape: BoxShape.circle,
                  ),
                  child: AnimatedSwitcher(
                    duration: ChatlyBottomNavigationBar._animationDuration,
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeOutCubic,
                    child: Icon(
                      isSelected ? destination.selectedIcon : destination.icon,
                      key: ValueKey(isSelected),
                      size: isSelected ? 30 : 28,
                      color: isSelected
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
    );

    return Tooltip(
      message: destination.label,
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
