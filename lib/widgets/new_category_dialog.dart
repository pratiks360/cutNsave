import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/models.dart';
import '../services/services.dart';
import '../state/app_state.dart';

Future<Category?> showNewCategoryDialog(BuildContext context) async {
  final services = context.read<Services>();
  final controller = TextEditingController();
  final name = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(ctx.tr('new_category')),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: InputDecoration(labelText: ctx.tr('category_name')),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text(ctx.tr('cancel'))),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, controller.text),
          child: Text(ctx.tr('create')),
        ),
      ],
    ),
  );
  if (name == null || name.trim().isEmpty) return null;
  return services.repo.createCategory(services.libraryId, name);
}
