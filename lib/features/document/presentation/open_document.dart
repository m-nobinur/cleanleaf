import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_routes.dart';
import '../../library/presentation/document_actions_sheet.dart';

/// Opens the document view. Resolves to [DocumentAction.delete] when the user
/// deleted the document there; the caller runs the delete so it keeps undo.
Future<DocumentAction?> openDocument(BuildContext context, String documentId) =>
    context.push<DocumentAction>(AppRoutes.document(documentId));
