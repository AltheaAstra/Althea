import 'package:flutter/material.dart';

class WorkspacePageFrame extends StatelessWidget {
  const WorkspacePageFrame({
    required this.title,
    required this.subtitle,
    required this.body,
    this.actions,
    super.key,
  });

  final String title;
  final String subtitle;
  final Widget body;
  final Widget? actions;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(
          MediaQuery.sizeOf(context).width < 700 ? 18 : 32,
          25,
          MediaQuery.sizeOf(context).width < 700 ? 18 : 32,
          20,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700, color: const Color(0xFF142C20))),
                      const SizedBox(height: 5),
                      Text(subtitle, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: const Color(0xFF6E8075))),
                    ],
                  ),
                ),
                if (actions != null) ...[const SizedBox(width: 10), actions!],
              ],
            ),
            const SizedBox(height: 24),
            Expanded(child: body),
          ],
        ),
      );
}
