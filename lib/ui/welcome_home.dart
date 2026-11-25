import 'package:flutter/material.dart';

class WelcomeHome extends StatelessWidget {
  final VoidCallback onGroup;
  final VoidCallback onJoin;
  final VoidCallback onResults;
  final VoidCallback onSettings;
  final String? groupCode;
  final String? error;
  final bool hasLocation;

  const WelcomeHome({
    super.key,
    required this.onGroup,
    required this.onJoin,
    required this.onResults,
    required this.onSettings,
    this.groupCode,
    this.error,
    required this.hasLocation,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
      children: [
        Row(
          children: [
            CustomPaint(
              size: const Size(48, 36),
              painter: _BrandMark(theme.colorScheme.primary),
            ),
            const SizedBox(width: 10),
            Flexible(child: Text('Shape-ify', style: theme.textTheme.headlineMedium)),
          ],
        ),
        const SizedBox(height: 6),
        Text('Measure • Construct • Conclude', style: theme.textTheme.titleSmall),
        const SizedBox(height: 18),
        ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: AspectRatio(
            aspectRatio: 2.6,
            child: Image.asset('assets/home-sunrise.jpg', fit: BoxFit.cover,
              excludeFromSemantics: true),
          ),
        ),
        const SizedBox(height: 20),
        if (error != null) Text(error!, style: TextStyle(color: theme.colorScheme.error)),
        FilledButton.icon(
          onPressed: onGroup,
          icon: Icon(groupCode == null ? Icons.group_add_outlined : Icons.group_outlined),
          label: Text(groupCode == null ? 'Create Group' : 'Resume Group $groupCode'),
        ),
        if (groupCode == null)
          OutlinedButton.icon(
            onPressed: onJoin,
            icon: const Icon(Icons.login),
            label: const Text('Join Group'),
          ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            TextButton(onPressed: onResults, child: const Text('View Results')),
            TextButton(onPressed: onSettings, child: const Text('Settings')),
            TextButton(
              onPressed: () => showAboutDialog(
                context: context,
                applicationName: 'Shape-ify',
                children: const [
                  Text('Compare ground orientations using observations of visible stars.'),
                ],
              ),
              child: const Text('About'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          hasLocation
              ? 'GPS ready · Sensors checked at capture · Stars chosen in group'
              : 'GPS checked during setup · Sensors checked at capture · Stars chosen in group',
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _BrandMark extends CustomPainter {
  final Color accent;
  const _BrandMark(this.accent);

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    final upper = Path()
      ..moveTo(3, 25)
      ..quadraticBezierTo(22, 2, 43, 12);
    final lower = Path()
      ..moveTo(3, 29)
      ..quadraticBezierTo(24, 37, 45, 18);
    canvas.drawPath(upper, line);
    canvas.drawPath(lower, line);
    final star = Path()
      ..moveTo(31, 4)
      ..lineTo(33, 12)
      ..lineTo(41, 14)
      ..lineTo(33, 16)
      ..lineTo(31, 24)
      ..lineTo(29, 16)
      ..lineTo(21, 14)
      ..lineTo(29, 12)
      ..close();
    canvas.drawPath(star, Paint()..color = const Color(0xffffcf73));
  }

  @override
  bool shouldRepaint(covariant _BrandMark oldDelegate) => oldDelegate.accent != accent;
}
