import 'package:flutter/material.dart';

class ReadingCard extends StatelessWidget {
  final String title, value;
  final IconData icon;
  const ReadingCard({super.key, required this.title, required this.value, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(children: [
          Icon(icon, size: 32),
          const SizedBox(width: 12),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            Text(value, style: Theme.of(context).textTheme.headlineSmall),
          ]),
        ]),
      ),
    );
  }
}
