import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../logic/quota.dart';
import '../services/services.dart';
import '../state/app_state.dart';

class QuotaCard extends StatefulWidget {
  const QuotaCard({super.key});

  @override
  State<QuotaCard> createState() => _QuotaCardState();
}

class _QuotaCardState extends State<QuotaCard> {
  late final Future<Quota?> _future = context.read<Services>().quota.fetch();

  @override
  Widget build(BuildContext context) {
    final nf = NumberFormat.decimalPattern();
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: FutureBuilder<Quota?>(
          future: _future,
          builder: (context, snap) {
            final q = snap.data;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(context.t('quota_title'),
                    style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 4),
                if (snap.connectionState != ConnectionState.done)
                  const LinearProgressIndicator()
                else if (snap.hasError || q == null)
                  Text(context.t('quota_unknown'))
                else ...[
                  Text(context.t('quota_ocr', {
                    'left': nf.format(q.ocrLeft),
                    'limit': nf.format(q.ocrLimit),
                  })),
                  Text(context.t('quota_translate', {
                    'left': nf.format(q.translateLeft),
                    'limit': nf.format(q.translateLimit),
                  })),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}
