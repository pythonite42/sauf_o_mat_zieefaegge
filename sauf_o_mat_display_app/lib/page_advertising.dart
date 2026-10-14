import 'dart:async';
import 'package:flutter/material.dart';
import 'package:sauf_o_mat_display_app/backend_connection.dart';
import 'package:sauf_o_mat_display_app/theme.dart';
import 'package:sauf_o_mat_display_app/globals.dart';
import 'package:flutter_tilt/flutter_tilt.dart';

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
          final headline = snapshot.data!["headline"] ?? "";
          final text = snapshot.data!["text"] ?? "";
          final imageUrl = snapshot.data!["image"] ?? "";
          final imageWidth = MySize(context).w * 0.32;
          return Stack(
            children: [
              Align(
                alignment: Alignment.topCenter,
                child: SizedBox(
                  child: Image.asset(
                    'assets/newspaper.png',
                    width: MySize(context).w,
                    fit: BoxFit.fitHeight,
                    alignment: Alignment.topCenter,
                  ),
                ),
              ),
              Positioned(
                left: MySize(context).w * 0.18,
                top: MySize(context).h * 0.06,
                child: Tilt(
                  disable: true,
                  tiltConfig: TiltConfig(initial: Offset(-0.4, -0.4)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        GlobalSettings.newspaperTitle,
                        style: NewspaperTextTheme.title.copyWith(fontSize: 100),
                      ),
                      Container(
                        padding: EdgeInsets.only(
                          bottom: MySize(context).h * 0.02,
                        ),
                        width: MySize(context).w * 0.6,
                        child: Divider(thickness: 4),
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.start,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: MySize(context).w * 0.25,
                            height: MySize(context).h * 0.6,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(20),
                              child: Image.network(
                                imageUrl,
                                width: imageWidth,
                                errorBuilder: (context, _, _) => Container(
                                  width: imageWidth,
                                  height: imageWidth,
                                  color: Colors.grey[300],
                                  child: Icon(
                                    Icons.image,
                                    size: MySize(context).w * 0.3 / 2,
                                  ),
                                ),
                              ),
                            ),
                          ),

                          SizedBox(
                            width: MySize(context).w * 0.02,
                          ), // spacing between image and content
                          SizedBox(
                            width: MySize(context).w * 0.34,
                            child: Builder(
                              builder: (context) {
                                final TextStyle headlineStyle =
                                    NewspaperTextTheme.headline.copyWith(
                                      height: 1,
                                      fontSize: 55,
                                    );
                                int headlineLines = 1;
                                try {
                                  final tp = TextPainter(
                                    text: TextSpan(
                                      text: headline,
                                      style: headlineStyle,
                                    ),
                                    textDirection: TextDirection.ltr,
                                    maxLines: 2,
                                  );
                                  tp.layout(maxWidth: MySize(context).w * 0.27);
                                  headlineLines = tp
                                      .computeLineMetrics()
                                      .length;
                                } catch (e) {
                                  headlineLines = 2;
                                }

                                final int bodyMaxLines = (headlineLines <= 1)
                                    ? 11
                                    : 10;

                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      headline,
                                      textAlign: TextAlign.center,
                                      style: headlineStyle,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    SizedBox(height: MySize(context).h * 0.02),
                                    Text(
                                      text,
                                      textAlign: TextAlign.left,
                                      style: NewspaperTextTheme.body.copyWith(
                                        height: 1,
                                        fontSize: 43,
                                      ),
                                      maxLines: bodyMaxLines,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        }
      },
    );
  }
}
