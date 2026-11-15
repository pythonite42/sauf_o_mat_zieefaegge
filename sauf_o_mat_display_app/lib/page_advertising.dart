import 'dart:async';

import 'package:flutter/material.dart';
import 'package:sauf_o_mat_display_app/backend_connection.dart';
import 'package:sauf_o_mat_display_app/newspaper.dart';
import 'package:sauf_o_mat_display_app/theme.dart';
import 'package:sauf_o_mat_display_app/globals.dart';

class PageAdvertising extends StatelessWidget {
  const PageAdvertising({super.key});

  Future<Map> _fetchAdvertisingData() async {
    try {
      return await SalesforceService().getPageAdvertising();
    } catch (e) {
      debugPrint('Error fetching page 5 advertising image: $e');
      return {};
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map>(
      future: _fetchAdvertisingData(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting ||
            snapshot.hasError ||
            !snapshot.hasData ||
            snapshot.data!.isEmpty) {
          return Center(
            child: CircularProgressIndicator(color: defaultOnPrimary),
          );
        } else {
          SalesforceService().setPageAdvertisingVisualizedAt(
            snapshot.data!["id"],
            DateTime.now(),
          );
          final imageUrl = snapshot.data!["image"] ?? "";
          final imageWidth = MySize(context).w * 0.32;

          return Newspaper(
            content: Image.network(
              imageUrl,
              errorBuilder: (context, _, _) => Container(
                width: imageWidth,
                height: imageWidth,
                color: Colors.grey[300],
                child: Icon(Icons.image, size: MySize(context).w * 0.3 / 2),
              ),
            ),
          );
        }
      },
    );
  }
}
